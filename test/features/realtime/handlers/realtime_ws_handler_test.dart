import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/bearer_auth_middleware.dart';
import 'package:nas_server/core/device/system_status_cache.dart';
import 'package:nas_server/core/device_registry/device_store.dart';
import 'package:nas_server/features/api/handlers/dashboard_payload_builder.dart';
import 'package:nas_server/features/realtime/data/realtime_connection_registry.dart';
import 'package:nas_server/features/realtime/data/realtime_event_hub.dart';
import 'package:nas_server/features/realtime/data/realtime_presence_repository.dart';
import 'package:nas_server/features/realtime/data/realtime_snapshot_builder.dart';
import 'package:nas_server/features/realtime/data/realtime_status_publisher.dart';
import 'package:nas_server/features/realtime/handlers/realtime_ws_handler.dart';
import 'package:nas_server/features/realtime/realtime_contract.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../test_support/device_store_harness.dart';
import '../../../helpers/system_status_cache_test_helper.dart';

void main() {
  group('RealtimeWsHandler', () {
    test(
      'accepts hello and heartbeat after bearer-authenticated websocket upgrade',
      () async {
        final harness = await _RealtimeTestHarness.start();
        addTearDown(harness.close);

        final socket = await harness.connect();
        addTearDown(() async {
          await socket.close();
        });
        final messages = StreamIterator<Map<String, dynamic>>(
          socket.map(
            (event) => jsonDecode(event as String) as Map<String, dynamic>,
          ),
        );
        addTearDown(messages.cancel);

        socket.add(
          jsonEncode({
            'type': RealtimeMessageType.hello,
            'payload': {
              'sessionId': harness.issuedSession.context.sessionId,
              'deviceId': harness.issuedSession.context.deviceId,
              'deviceName': 'Living Room Tablet',
              'platform': 'android',
              'brand': 'Google',
              'model': 'Pixel 7',
              'appVersion': '1.0.0',
              'reportedRouteIp': '192.168.1.25',
            },
          }),
        );

        expect(await messages.moveNext(), isTrue);
        final helloAck = messages.current;
        expect(helloAck['type'], RealtimeMessageType.helloAck);
        expect(
          helloAck['payload']['sessionId'],
          harness.issuedSession.context.sessionId,
        );
        expect(
          helloAck['payload']['snapshot']['dashboard']['server']['status'],
          'online',
        );

        expect(await messages.moveNext(), isTrue);
        final presenceChanged = messages.current;
        expect(presenceChanged['type'], RealtimeMessageType.presenceChanged);
        final clients = presenceChanged['payload']['clients'] as List<dynamic>;
        expect(clients, hasLength(1));
        expect(
          clients.single['deviceId'],
          harness.issuedSession.context.deviceId,
        );
        expect(clients.single['platform'], 'android');
        expect(clients.single['brand'], 'Google');
        expect(clients.single['model'], 'Pixel 7');
        expect(clients.single['appVersion'], '1.0.0');
        expect(clients.single['reportedRouteIp'], '192.168.1.25');
        expect(clients.single['observedRemoteIp'], '127.0.0.1');

        socket.add(
          jsonEncode({
            'type': RealtimeMessageType.heartbeat,
            'payload': {'sessionId': harness.issuedSession.context.sessionId},
          }),
        );

        expect(await messages.moveNext(), isTrue);
        final heartbeatAck = messages.current;
        expect(heartbeatAck['type'], RealtimeMessageType.heartbeatAck);
        expect(
          heartbeatAck['payload']['sessionId'],
          harness.issuedSession.context.sessionId,
        );
      },
    );

    test('emits session.revoked when heartbeat revalidation fails', () async {
      final harness = await _RealtimeTestHarness.start();
      addTearDown(harness.close);

      final socket = await harness.connect();
      addTearDown(() async {
        await socket.close();
      });
      final messages = StreamIterator<Map<String, dynamic>>(
        socket.map(
          (event) => jsonDecode(event as String) as Map<String, dynamic>,
        ),
      );
      addTearDown(messages.cancel);

      socket.add(
        jsonEncode({
          'type': RealtimeMessageType.hello,
          'payload': {
            'sessionId': harness.issuedSession.context.sessionId,
            'deviceId': harness.issuedSession.context.deviceId,
            'deviceName': 'Living Room Tablet',
            'platform': 'android',
            'brand': 'Google',
            'model': 'Pixel 7',
            'appVersion': '1.0.0',
            'reportedRouteIp': '192.168.1.25',
          },
        }),
      );

      expect(await messages.moveNext(), isTrue);
      expect(messages.current['type'], RealtimeMessageType.helloAck);
      expect(await messages.moveNext(), isTrue);
      expect(messages.current['type'], RealtimeMessageType.presenceChanged);

      await harness.deviceStore.rotateDeviceCredential('tablet-01');
      socket.add(
        jsonEncode({
          'type': RealtimeMessageType.heartbeat,
          'payload': {'sessionId': harness.issuedSession.context.sessionId},
        }),
      );

      expect(await messages.moveNext(), isTrue);
      final revoked = messages.current;
      expect(revoked['type'], RealtimeMessageType.sessionRevoked);
      expect(revoked['payload']['code'], 'AUTH_REVOKED');
    });
  });
}

class _RealtimeTestHarness {
  _RealtimeTestHarness({
    required this.server,
    required this.issuedSession,
    required this.deviceStore,
  });

  final HttpServer server;
  final IssuedAuthSession issuedSession;
  final DeviceStore deviceStore;

  String get _url =>
      'ws://${server.address.address}:${server.port}$realtimeWebSocketPath';

  static Future<_RealtimeTestHarness> start() async {
    final testHarness = await TestDeviceStoreHarness.create();
    final deviceStore = testHarness.createDeviceStore();
    final authSessionStore = await testHarness.createAuthSessionStore(
      deviceStore: deviceStore,
    );
    final enrolled = await deviceStore.enrollDevice(
      deviceId: 'tablet-01',
      deviceName: 'Living Room Tablet',
    );
    expect(enrolled.isSuccess, isTrue);
    final authentication = await authSessionStore.authenticateAccessToken(
      enrolled.tokens!.accessToken,
      deviceStore: deviceStore,
    );
    expect(authentication.isSuccess, isTrue);
    final issuedSession = IssuedAuthSession(
      context: authentication.context!,
      accessToken: enrolled.tokens!.accessToken,
      issuedAt: DateTime.now().toUtc(),
      expiresAt: enrolled.tokens!.accessExpiresAt,
    );

    final systemStatusCache = await createTestSystemStatusCache(
      selectedIp: '127.0.0.1',
    )
      ..deviceId = 'device-1'
      ..model = 'Pixel 7'
      ..brand = 'google'
      ..systemVersion = '14'
      ..batteryLevel = 2
      ..batteryPercent = 90
      ..isCharging = true
      ..totalStorage = 128000
      ..usedStorage = 64000
      ..totalMemory = 8192
      ..usedMemory = 4096
      ..cpuTemperature = 42
      ..localIp = '127.0.0.1'
      ..lastUpdated = DateTime.utc(2024, 4, 1, 12);

    final connectionRegistry = RealtimeConnectionRegistry();
    final presenceRepository = RealtimePresenceRepository();
    final eventHub = RealtimeEventHub(connectionRegistry: connectionRegistry);
    final dashboardPayloadBuilder = DashboardPayloadBuilder(
      systemStatusCache: systemStatusCache,
      port: 8080,
      startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    );
    final snapshotBuilder = RealtimeSnapshotBuilder(
      dashboardPayloadBuilder: dashboardPayloadBuilder,
      presenceRepository: presenceRepository,
    );
    final statusPublisher = RealtimeStatusPublisher(
      connectionRegistry: connectionRegistry,
      eventHub: eventHub,
      dashboardPayloadBuilder: dashboardPayloadBuilder,
      presenceRepository: presenceRepository,
      publishInterval: const Duration(days: 1),
    );
    final realtimeHandler = RealtimeWsHandler(
      authSessionStore: authSessionStore,
      connectionRegistry: connectionRegistry,
      presenceRepository: presenceRepository,
      eventHub: eventHub,
      snapshotBuilder: snapshotBuilder,
      statusPublisher: statusPublisher,
      deviceStore: deviceStore,
    );

    final router = Router()
      ..get(realtimeWebSocketPath, realtimeHandler.handler)
      ..all('/<ignored|.*>', (_) => Response.notFound('not found'));
    final pipeline = Pipeline()
        .addMiddleware(
          bearerAuthMiddleware(authSessionStore, deviceStore: deviceStore),
        )
        .addHandler(router.call);

    final server = await shelf_io.serve(
      pipeline,
      InternetAddress.loopbackIPv4,
      0,
    );

    return _RealtimeTestHarness(
      server: server,
      issuedSession: issuedSession,
      deviceStore: deviceStore,
    );
  }

  Future<WebSocket> connect() {
    return WebSocket.connect(
      _url,
      headers: {'Authorization': 'Bearer ${issuedSession.accessToken}'},
    );
  }

  Future<void> close() async {
    await server.close(force: true);
    await deviceStore.dispose();
  }
}
