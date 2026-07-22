import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/core/device/system_status_cache.dart';
import 'package:nas_server/features/api/handlers/dashboard_payload_builder.dart';
import 'package:nas_server/features/realtime/data/realtime_connection_registry.dart';
import 'package:nas_server/features/realtime/data/realtime_event_hub.dart';
import 'package:nas_server/features/realtime/data/realtime_presence_repository.dart';
import 'package:nas_server/features/realtime/data/realtime_status_publisher.dart';
import 'package:nas_server/features/realtime/realtime_contract.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../helpers/system_status_cache_test_helper.dart';

void main() {
  group('RealtimeStatusPublisher', () {
    test('removes stale websocket connections after heartbeat timeout', () async {
      final now = DateTime.utc(2026, 4, 14, 12);
      final registry = RealtimeConnectionRegistry();
      final presenceRepository = RealtimePresenceRepository();
      final channel = _FakeWebSocketChannel();
      final connection = _buildConnection(
        channel: channel,
        connectionId: 'conn-stale',
        clientId: 'tablet-01',
        connectedAt: now.subtract(const Duration(minutes: 1)),
        lastSeenAt: now
            .subtract(realtimeHeartbeatTimeout)
            .subtract(const Duration(seconds: 1)),
      );

      registry.register(connection);
      presenceRepository.markOnline(connection);

      final publisher = RealtimeStatusPublisher(
        connectionRegistry: registry,
        eventHub: RealtimeEventHub(
          connectionRegistry: registry,
          clock: () => now,
        ),
        dashboardPayloadBuilder: await _buildDashboardPayloadBuilder(now),
        presenceRepository: presenceRepository,
        clock: () => now,
      );

      publisher.publishStatusTick();

      expect(registry.hasConnections, isFalse);
      expect(presenceRepository.snapshot(), isEmpty);
      expect(channel.closeCalls, 1);
      expect(channel.closeCode, realtimeCloseCodeHeartbeatTimeout);
    });

    test(
      'publishes presence changes to remaining clients when a peer times out',
      () async {
        final now = DateTime.utc(2026, 4, 14, 12);
        final registry = RealtimeConnectionRegistry();
        final presenceRepository = RealtimePresenceRepository();
        final activeChannel = _FakeWebSocketChannel();
        final staleChannel = _FakeWebSocketChannel();

        final activeConnection = _buildConnection(
          channel: activeChannel,
          connectionId: 'conn-active',
          clientId: 'tablet-01',
          connectedAt: now.subtract(const Duration(minutes: 1)),
          lastSeenAt: now.subtract(const Duration(seconds: 5)),
        );
        final staleConnection = _buildConnection(
          channel: staleChannel,
          connectionId: 'conn-stale',
          clientId: 'tablet-02',
          connectedAt: now.subtract(const Duration(minutes: 1)),
          lastSeenAt: now
              .subtract(realtimeHeartbeatTimeout)
              .subtract(const Duration(seconds: 1)),
        );

        registry.register(activeConnection);
        registry.register(staleConnection);
        presenceRepository.markOnline(activeConnection);
        presenceRepository.markOnline(staleConnection);

        final publisher = RealtimeStatusPublisher(
          connectionRegistry: registry,
          eventHub: RealtimeEventHub(
            connectionRegistry: registry,
            clock: () => now,
          ),
          dashboardPayloadBuilder: await _buildDashboardPayloadBuilder(now),
          presenceRepository: presenceRepository,
          clock: () => now,
        );

        publisher.publishStatusTick();
        await Future<void>.delayed(Duration.zero);

        expect(registry.findByConnectionId('conn-active'), isNotNull);
        expect(registry.findByConnectionId('conn-stale'), isNull);
        expect(staleChannel.closeCode, realtimeCloseCodeHeartbeatTimeout);

        final presenceMessages = activeChannel.messages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where(
              (message) =>
                  message['type'] == RealtimeMessageType.presenceChanged,
            )
            .toList(growable: false);
        expect(presenceMessages, hasLength(1));
        final clients =
            presenceMessages.single['payload']['clients'] as List<dynamic>;
        expect(clients, hasLength(1));
        expect(clients.single['deviceId'], 'tablet-01');
      },
    );

    test('includes enrolledDeviceIds in presence.changed payload', () async {
      final now = DateTime.utc(2026, 4, 14, 12);
      final registry = RealtimeConnectionRegistry();
      final presenceRepository = RealtimePresenceRepository();
      final channel = _FakeWebSocketChannel();
      final connection = _buildConnection(
        channel: channel,
        connectionId: 'conn-1',
        clientId: 'tablet-01',
        connectedAt: now.subtract(const Duration(minutes: 1)),
        lastSeenAt: now.subtract(const Duration(seconds: 5)),
      );
      registry.register(connection);
      presenceRepository.markOnline(connection);

      final publisher = RealtimeStatusPublisher(
        connectionRegistry: registry,
        eventHub: RealtimeEventHub(
          connectionRegistry: registry,
          clock: () => now,
        ),
        dashboardPayloadBuilder: await _buildDashboardPayloadBuilder(now),
        presenceRepository: presenceRepository,
        enrolledDeviceIdsProvider: () async =>
            const <String>['tablet-01', 'phone-01'],
        clock: () => now,
      );

      publisher.publishPresenceChanged();
      await Future<void>.delayed(Duration.zero);

      final presenceMessages = channel.messages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where(
            (message) =>
                message['type'] == RealtimeMessageType.presenceChanged,
          )
          .toList(growable: false);
      expect(presenceMessages, hasLength(1));
      expect(
        presenceMessages.single['payload']['enrolledDeviceIds'],
        <String>['tablet-01', 'phone-01'],
      );
    });
  });
}

Future<DashboardPayloadBuilder> _buildDashboardPayloadBuilder(
  DateTime now,
) async {
  final cache = await createTestSystemStatusCache(selectedIp: '192.168.1.10');
  cache
    ..deviceId = 'device-1'
    ..model = 'Pixel 7'
    ..brand = 'google'
    ..systemVersion = '14'
    ..batteryLevel = 2
    ..batteryPercent = 88.5
    ..isCharging = true
    ..totalStorage = 128000
    ..usedStorage = 64000
    ..totalMemory = 8192
    ..usedMemory = 4096
    ..cpuTemperature = 42
    ..localIp = '192.168.1.10'
    ..lastUpdated = now;

  return DashboardPayloadBuilder(
    systemStatusCache: cache,
    port: 8080,
    startedAt: now.subtract(const Duration(minutes: 5)),
  );
}

RealtimeConnection _buildConnection({
  required _FakeWebSocketChannel channel,
  required String connectionId,
  required String clientId,
  required DateTime connectedAt,
  required DateTime lastSeenAt,
}) {
  return RealtimeConnection(
    connectionId: connectionId,
    sessionId: 'sess-$connectionId',
    accountId: 'acct-$clientId',
    username: 'device-user',
    label: '客户端',
    role: AccountRole.device,
    clientId: clientId,
    deviceName: clientId,
    connectedAt: connectedAt,
    lastSeenAt: lastSeenAt,
    channel: channel,
  );
}

class _FakeWebSocketChannel implements WebSocketChannel {
  final List<String> messages = <String>[];
  int closeCalls = 0;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready async {}

  @override
  Stream get stream => const Stream.empty();

  @override
  WebSocketSink get sink => _FakeWebSocketSink(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this._channel);

  final _FakeWebSocketChannel _channel;

  @override
  Future<void> get done async {}

  @override
  void add(event) {
    _channel.messages.add(event as String);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.closeCalls += 1;
    _channel.closeCode = closeCode;
    _channel.closeReason = closeReason;
  }
}
