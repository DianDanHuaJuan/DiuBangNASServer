import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/bearer_auth_middleware.dart';
import 'package:nas_server/core/device_registry/device_store.dart';
import 'package:nas_server/features/relay/domain/relay_models.dart';
import 'package:nas_server/features/relay/data/relay_realtime_publisher.dart';
import 'package:nas_server/features/relay/data/relay_service.dart';
import 'package:nas_server/features/relay/data/relay_temp_storage_manager.dart';
import 'package:nas_server/features/relay/data/sqlite_relay_transfer_repository.dart';
import 'package:nas_server/features/relay/handlers/relay_api_handler.dart';
import 'package:nas_server/features/relay/handlers/relay_webdav_handler.dart';
import 'package:nas_server/features/realtime/data/realtime_connection_registry.dart';
import 'package:nas_server/features/realtime/data/realtime_event_hub.dart';
import 'package:nas_server/features/realtime/data/realtime_presence_repository.dart';
import 'package:nas_server/features/realtime/realtime_contract.dart';
import 'package:shelf/shelf.dart';

import '../../../test_support/device_store_harness.dart';

void main() {
  group('Relay HTTP control plane + WebDAV data plane', () {
    test(
      'creates, uploads, heads, downloads and retries a relay transfer',
      () async {
        final rig = await _RelayTestRig.create();
        addTearDown(rig.dispose);
        final apiHandler = RelayApiHandler(relayService: rig.relayService);
        final webdavHandler = RelayWebdavHandler(
          relayService: rig.relayService,
        );
        const payload = 'relay demo payload';
        final payloadBytes = utf8.encode(payload);

        final createResponse = await apiHandler.createTransferHandler(
          rig.request(
            'POST',
            'http://localhost/api/v1/relay/transfers',
            authContext: rig.senderContext,
            body: jsonEncode({
              'targetClientIds': [rig.receiverClientId],
              'fileName': 'demo.txt',
              'fileSize': payloadBytes.length,
              'mimeType': 'text/plain',
            }),
            headers: const {'Content-Type': 'application/json'},
          ),
        );
        final createdBody =
            jsonDecode(await createResponse.readAsString())
                as Map<String, dynamic>;
        final transfer = createdBody['transfer'] as Map<String, dynamic>;
        final transferId = transfer['transferId'] as String;

        expect(createResponse.statusCode, 201);
        expect(transfer['status'], RelayTransferStatus.created.name);
        expect(transfer['transport'], {
          'protocol': 'webdav',
          'upload': {'method': 'PUT', 'path': '/dav/relay/$transferId/payload'},
          'download': {
            'method': 'GET',
            'path': '/dav/relay/$transferId/payload',
            'supportsRange': false,
          },
          'thumbnailUpload': {
            'method': 'PUT',
            'path': '/dav/relay/$transferId/thumbnail',
          },
          'thumbnailDownload': {
            'method': 'GET',
            'path': '/dav/relay/$transferId/thumbnail',
          },
        });

        final uploadResponse = await webdavHandler.putTransferHandler(
          rig.request(
            'PUT',
            'http://localhost/dav/relay/$transferId/payload',
            authContext: rig.senderContext,
            body: payloadBytes,
            headers: {
              'Content-Length': '${payloadBytes.length}',
              'Content-Type': 'text/plain',
            },
          ),
          transferId,
          'payload',
        );
        final uploadedBody =
            jsonDecode(await uploadResponse.readAsString())
                as Map<String, dynamic>;
        expect(uploadResponse.statusCode, 201);
        expect(
          uploadedBody['transfer']['status'],
          RelayTransferStatus.ready.name,
        );
        expect(
          uploadedBody['transfer']['transport']['download']['supportsRange'],
          isTrue,
        );

        final headResponse = await webdavHandler.headTransferHandler(
          rig.request(
            'HEAD',
            'http://localhost/dav/relay/$transferId/payload',
            authContext: rig.receiverContext,
          ),
          transferId,
          'payload',
        );
        expect(headResponse.statusCode, 200);
        expect(
          headResponse.headers['Content-Length'],
          '${payloadBytes.length}',
        );
        expect(headResponse.headers['Accept-Ranges'], 'bytes');

        final historyBeforeDownload = await apiHandler.listHistoryHandler(
          rig.request(
            'GET',
            'http://localhost/api/v1/relay/transfers/history',
            authContext: rig.receiverContext,
          ),
        );
        final historyBeforeDownloadBody =
            jsonDecode(await historyBeforeDownload.readAsString())
                as Map<String, dynamic>;
        final transfersBeforeDownload =
            historyBeforeDownloadBody['transfers'] as List<dynamic>;
        expect(historyBeforeDownload.statusCode, 200);
        expect(transfersBeforeDownload, hasLength(1));
        expect(
          transfersBeforeDownload.single['status'],
          RelayTransferStatus.ready.name,
        );

        final downloadResponse = await webdavHandler.getTransferHandler(
          rig.request(
            'GET',
            'http://localhost/dav/relay/$transferId/payload',
            authContext: rig.receiverContext,
          ),
          transferId,
          'payload',
        );
        final downloadedText = await downloadResponse.readAsString();
        expect(downloadResponse.statusCode, 200);
        expect(downloadedText, payload);
        expect(
          downloadResponse.headers['Content-Disposition'],
          contains("filename*=UTF-8''demo.txt"),
        );

        final transfersAfterDownload = await _awaitRelayHistoryStatus(
          apiHandler: apiHandler,
          rig: rig,
          expectedStatus: RelayTransferStatus.completed,
        );
        expect(
          transfersAfterDownload.single['status'],
          RelayTransferStatus.completed.name,
        );

        final retryResponse = await apiHandler.retryTransferHandler(
          rig.request(
            'POST',
            'http://localhost/api/v1/relay/transfers/$transferId/retry',
            authContext: rig.senderContext,
          ),
          transferId,
        );
        final retryBody =
            jsonDecode(await retryResponse.readAsString())
                as Map<String, dynamic>;
        final retriedTransfer = retryBody['transfer'] as Map<String, dynamic>;

        expect(retryResponse.statusCode, 201);
        expect(retriedTransfer['retryOfTransferId'], transferId);
        expect(retriedTransfer['status'], RelayTransferStatus.created.name);

        final receiverMessageTypes = rig.receiverChannel.messages
            .map(_messageType)
            .toList(growable: false);
        expect(
          receiverMessageTypes,
          containsAllInOrder([
            RealtimeMessageType.transferCreated,
            RealtimeMessageType.transferUploadProgress,
            RealtimeMessageType.transferReady,
            RealtimeMessageType.transferDownloadProgress,
            RealtimeMessageType.transferCompleted,
          ]),
        );
      },
    );

    test(
      'listHistory with peerClientId returns paginated peer conversation',
      () async {
        final rig = await _RelayTestRig.create();
        addTearDown(rig.dispose);
        final apiHandler = RelayApiHandler(relayService: rig.relayService);
        final webdavHandler = RelayWebdavHandler(
          relayService: rig.relayService,
        );
        const payload = 'relay peer page payload';
        final payloadBytes = utf8.encode(payload);

        for (var index = 0; index < 3; index++) {
          final createResponse = await apiHandler.createTransferHandler(
            rig.request(
              'POST',
              'http://localhost/api/v1/relay/transfers',
              authContext: rig.senderContext,
              body: jsonEncode({
                'targetClientIds': [rig.receiverClientId],
                'fileName': 'peer-$index.txt',
                'fileSize': payloadBytes.length,
              }),
              headers: const {'Content-Type': 'application/json'},
            ),
          );
          final createdBody =
              jsonDecode(await createResponse.readAsString())
                  as Map<String, dynamic>;
          final transferId =
              (createdBody['transfer'] as Map<String, dynamic>)['transferId']
                  as String;

          await webdavHandler.putTransferHandler(
            rig.request(
              'PUT',
              'http://localhost/dav/relay/$transferId/payload',
              authContext: rig.senderContext,
              body: payloadBytes,
            ),
            transferId,
            'payload',
          );
        }

        final firstPageResponse = await apiHandler.listHistoryHandler(
          rig.request(
            'GET',
            Uri.parse(
              'http://localhost/api/v1/relay/transfers/history',
            ).replace(
              queryParameters: <String, String>{
                'peerClientId': rig.senderClientId,
                'limit': '2',
              },
            ).toString(),
            authContext: rig.receiverContext,
          ),
        );
        final firstPageBody =
            jsonDecode(await firstPageResponse.readAsString())
                as Map<String, dynamic>;
        final firstPageTransfers = firstPageBody['transfers'] as List<dynamic>;

        expect(firstPageResponse.statusCode, 200);
        expect(firstPageBody['hasMore'], isTrue);
        expect(firstPageTransfers, hasLength(2));
        expect(
          firstPageTransfers.map(
            (transfer) => (transfer as Map<String, dynamic>)['fileName'],
          ),
          containsAll(<String>['peer-2.txt', 'peer-1.txt']),
        );

        final oldestCreatedAt =
            (firstPageTransfers.last as Map<String, dynamic>)['createdAt']
                as String;
        final secondPageResponse = await apiHandler.listHistoryHandler(
          rig.request(
            'GET',
            Uri.parse(
              'http://localhost/api/v1/relay/transfers/history',
            ).replace(
              queryParameters: <String, String>{
                'peerClientId': rig.senderClientId,
                'limit': '2',
                'before': oldestCreatedAt,
              },
            ).toString(),
            authContext: rig.receiverContext,
          ),
        );
        final secondPageBody =
            jsonDecode(await secondPageResponse.readAsString())
                as Map<String, dynamic>;
        final secondPageTransfers =
            secondPageBody['transfers'] as List<dynamic>;

        expect(secondPageResponse.statusCode, 200);
        expect(secondPageBody['hasMore'], isFalse);
        expect(secondPageTransfers, hasLength(1));
        expect(
          (secondPageTransfers.single as Map<String, dynamic>)['fileName'],
          'peer-0.txt',
        );
      },
    );

    test(
      'blocks unrelated clients from uploading or downloading relay data',
      () async {
        final rig = await _RelayTestRig.create();
        addTearDown(rig.dispose);
        final apiHandler = RelayApiHandler(relayService: rig.relayService);
        final webdavHandler = RelayWebdavHandler(
          relayService: rig.relayService,
        );
        const payload = 'relay demo payload';
        final payloadBytes = utf8.encode(payload);

        final createResponse = await apiHandler.createTransferHandler(
          rig.request(
            'POST',
            'http://localhost/api/v1/relay/transfers',
            authContext: rig.senderContext,
            body: jsonEncode({
              'targetClientIds': [rig.receiverClientId],
              'fileName': 'demo.txt',
              'fileSize': payloadBytes.length,
            }),
            headers: const {'Content-Type': 'application/json'},
          ),
        );
        final createdBody =
            jsonDecode(await createResponse.readAsString())
                as Map<String, dynamic>;
        final transferId =
            (createdBody['transfer'] as Map<String, dynamic>)['transferId']
                as String;

        final unauthorizedUpload = await webdavHandler.putTransferHandler(
          rig.request(
            'PUT',
            'http://localhost/dav/relay/$transferId/payload',
            authContext: rig.otherContext,
            body: payloadBytes,
          ),
          transferId,
          'payload',
        );
        final unauthorizedUploadBody =
            jsonDecode(await unauthorizedUpload.readAsString())
                as Map<String, dynamic>;

        expect(unauthorizedUpload.statusCode, 403);
        expect(unauthorizedUploadBody['code'], 'AUTH_FORBIDDEN');

        await webdavHandler.putTransferHandler(
          rig.request(
            'PUT',
            'http://localhost/dav/relay/$transferId/payload',
            authContext: rig.senderContext,
            body: payloadBytes,
          ),
          transferId,
          'payload',
        );

        final unauthorizedDownload = await webdavHandler.getTransferHandler(
          rig.request(
            'GET',
            'http://localhost/dav/relay/$transferId/payload',
            authContext: rig.otherContext,
          ),
          transferId,
          'payload',
        );
        final unauthorizedDownloadBody =
            jsonDecode(await unauthorizedDownload.readAsString())
                as Map<String, dynamic>;

        expect(unauthorizedDownload.statusCode, 403);
        expect(unauthorizedDownloadBody['code'], 'AUTH_FORBIDDEN');
      },
    );

    test('supports ranged relay downloads and explicit completion ack', () async {
      final rig = await _RelayTestRig.create();
      addTearDown(rig.dispose);
      final apiHandler = RelayApiHandler(relayService: rig.relayService);
      final webdavHandler = RelayWebdavHandler(relayService: rig.relayService);
      const payload = 'abcdef';
      final payloadBytes = utf8.encode(payload);

      final createResponse = await apiHandler.createTransferHandler(
        rig.request(
          'POST',
          'http://localhost/api/v1/relay/transfers',
          authContext: rig.senderContext,
          body: jsonEncode({
            'targetClientIds': [rig.receiverClientId],
            'fileName': 'demo.txt',
            'fileSize': payloadBytes.length,
          }),
          headers: const {'Content-Type': 'application/json'},
        ),
      );
      final createBody =
          jsonDecode(await createResponse.readAsString())
              as Map<String, dynamic>;
      final transferId =
          (createBody['transfer'] as Map<String, dynamic>)['transferId']
              as String;

      await webdavHandler.putTransferHandler(
        rig.request(
          'PUT',
          'http://localhost/dav/relay/$transferId/payload',
          authContext: rig.senderContext,
          body: payloadBytes,
        ),
        transferId,
        'payload',
      );

      final partialDownload = await webdavHandler.getTransferHandler(
        rig.request(
          'GET',
          'http://localhost/dav/relay/$transferId/payload',
          authContext: rig.receiverContext,
          headers: const {'Range': 'bytes=1-3'},
        ),
        transferId,
        'payload',
      );
      final partialBody = await partialDownload.readAsString();

      expect(partialDownload.statusCode, 206);
      expect(partialBody, 'bcd');
      expect(partialDownload.headers['Content-Range'], 'bytes 1-3/6');

      final historyAfterRangeOnly = await apiHandler.listHistoryHandler(
        rig.request(
          'GET',
          'http://localhost/api/v1/relay/transfers/history',
          authContext: rig.receiverContext,
        ),
      );
      final historyAfterRangeOnlyBody =
          jsonDecode(await historyAfterRangeOnly.readAsString())
              as Map<String, dynamic>;
      final transfersAfterRangeOnly =
          historyAfterRangeOnlyBody['transfers'] as List<dynamic>;
      expect(
        transfersAfterRangeOnly.single['status'],
        RelayTransferStatus.downloading.name,
      );

      final acknowledgeResponse = await apiHandler
          .acknowledgeDownloadCompletedHandler(
            rig.request(
              'POST',
              'http://localhost/api/v1/relay/transfers/$transferId/download-complete',
              authContext: rig.receiverContext,
              body: '{}',
              headers: const {'Content-Type': 'application/json'},
            ),
            transferId,
          );
      final acknowledgeBody =
          jsonDecode(await acknowledgeResponse.readAsString())
              as Map<String, dynamic>;
      expect(acknowledgeResponse.statusCode, 200);
      expect(
        (acknowledgeBody['transfer'] as Map<String, dynamic>)['status'],
        RelayTransferStatus.completed.name,
      );
    });
  });
}

String _messageType(String payload) {
  final json = jsonDecode(payload) as Map<String, dynamic>;
  return json['type'] as String;
}

Future<List<dynamic>> _awaitRelayHistoryStatus({
  required RelayApiHandler apiHandler,
  required _RelayTestRig rig,
  required RelayTransferStatus expectedStatus,
}) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final historyResponse = await apiHandler.listHistoryHandler(
      rig.request(
        'GET',
        'http://localhost/api/v1/relay/transfers/history',
        authContext: rig.receiverContext,
      ),
    );
    final body =
        jsonDecode(await historyResponse.readAsString())
            as Map<String, dynamic>;
    final transfers = body['transfers'] as List<dynamic>;
    if (transfers.isNotEmpty &&
        transfers.single['status'] == expectedStatus.name) {
      return transfers;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Timed out waiting for relay transfer status ${expectedStatus.name}');
}

class _RelayTestRig {
  _RelayTestRig._({
    required this.rootDirectory,
    required this.deviceHarness,
    required this.deviceStore,
    required this.relayService,
    required this.senderContext,
    required this.receiverContext,
    required this.otherContext,
    required this.senderClientId,
    required this.receiverClientId,
    required this.otherClientId,
    required this.senderChannel,
    required this.receiverChannel,
    required this.otherChannel,
  });

  final Directory rootDirectory;
  final TestDeviceStoreHarness deviceHarness;
  final DeviceStore deviceStore;
  final RelayService relayService;
  final AuthenticatedRequestContext senderContext;
  final AuthenticatedRequestContext receiverContext;
  final AuthenticatedRequestContext otherContext;
  final String senderClientId;
  final String receiverClientId;
  final String otherClientId;
  final _FakeWebSocketChannel senderChannel;
  final _FakeWebSocketChannel receiverChannel;
  final _FakeWebSocketChannel otherChannel;

  static Future<_RelayTestRig> create() async {
    final rootDirectory = await Directory.systemTemp.createTemp(
      'nas_server_relay_',
    );
    final deviceHarness = await TestDeviceStoreHarness.create();
    final deviceStore = deviceHarness.createDeviceStore();
    final authSessionStore = await deviceHarness.createAuthSessionStore(
      deviceStore: deviceStore,
    );

    const senderClientId = 'phone-01';
    const receiverClientId = 'tablet-02';
    const otherClientId = 'tv-03';

    final senderContext = await _enrollDeviceContext(
      deviceStore: deviceStore,
      authSessionStore: authSessionStore,
      deviceId: senderClientId,
      deviceName: 'Phone 1',
    );
    final receiverContext = await _enrollDeviceContext(
      deviceStore: deviceStore,
      authSessionStore: authSessionStore,
      deviceId: receiverClientId,
      deviceName: 'Tablet 2',
    );
    final otherContext = await _enrollDeviceContext(
      deviceStore: deviceStore,
      authSessionStore: authSessionStore,
      deviceId: otherClientId,
      deviceName: 'TV 3',
    );

    final connectionRegistry = RealtimeConnectionRegistry();
    final presenceRepository = RealtimePresenceRepository();
    final eventHub = RealtimeEventHub(connectionRegistry: connectionRegistry);
    final senderChannel = _FakeWebSocketChannel();
    final receiverChannel = _FakeWebSocketChannel();
    final otherChannel = _FakeWebSocketChannel();
    final now = DateTime.utc(2026, 4, 15, 12);

    final senderConnection = _buildConnection(
      context: senderContext,
      clientId: senderClientId,
      channel: senderChannel,
      connectionId: 'conn-sender',
      now: now,
    );
    final receiverConnection = _buildConnection(
      context: receiverContext,
      clientId: receiverClientId,
      channel: receiverChannel,
      connectionId: 'conn-receiver',
      now: now,
    );
    final otherConnection = _buildConnection(
      context: otherContext,
      clientId: otherClientId,
      channel: otherChannel,
      connectionId: 'conn-other',
      now: now,
    );
    connectionRegistry.register(senderConnection);
    connectionRegistry.register(receiverConnection);
    connectionRegistry.register(otherConnection);
    presenceRepository.markOnline(senderConnection);
    presenceRepository.markOnline(receiverConnection);
    presenceRepository.markOnline(otherConnection);

    final relayService = RelayService(
      repository: SqliteRelayTransferRepository(
        databasePath: p.join(
          rootDirectory.path,
          '.relay',
          'relay_transfers.db',
        ),
      ),
      storageManager: RelayTempStorageManager(rootPath: rootDirectory.path),
      deviceStore: deviceStore,
      realtimePublisher: RelayRealtimePublisher(
        eventHub: eventHub,
        presenceRepository: presenceRepository,
      ),
    );
    await relayService.initialize();

    return _RelayTestRig._(
      rootDirectory: rootDirectory,
      deviceHarness: deviceHarness,
      deviceStore: deviceStore,
      relayService: relayService,
      senderContext: senderContext,
      receiverContext: receiverContext,
      otherContext: otherContext,
      senderClientId: senderClientId,
      receiverClientId: receiverClientId,
      otherClientId: otherClientId,
      senderChannel: senderChannel,
      receiverChannel: receiverChannel,
      otherChannel: otherChannel,
    );
  }

  Request request(
    String method,
    String url, {
    required AuthenticatedRequestContext authContext,
    Object? body,
    Map<String, String> headers = const <String, String>{},
  }) {
    return Request(
      method,
      Uri.parse(url),
      headers: headers,
      body: body,
      context: {authenticatedRequestContextKey: authContext},
    );
  }

  Future<void> dispose() async {
    await relayService.close();
    await deviceHarness.dispose();
    if (await rootDirectory.exists()) {
      await rootDirectory.delete(recursive: true);
    }
  }
}

Future<AuthenticatedRequestContext> _enrollDeviceContext({
  required DeviceStore deviceStore,
  required AuthSessionStore authSessionStore,
  required String deviceId,
  required String deviceName,
}) async {
  final enrolled = await deviceStore.enrollDevice(
    deviceId: deviceId,
    deviceName: deviceName,
  );
  expect(enrolled.isSuccess, isTrue);
  final authentication = await authSessionStore.authenticateAccessToken(
    enrolled.tokens!.accessToken,
    deviceStore: deviceStore,
  );
  expect(authentication.isSuccess, isTrue);
  return authentication.context!;
}

RealtimeConnection _buildConnection({
  required AuthenticatedRequestContext context,
  required String clientId,
  required _FakeWebSocketChannel channel,
  required String connectionId,
  required DateTime now,
}) {
  return RealtimeConnection(
    connectionId: connectionId,
    sessionId: context.sessionId,
    accountId: context.deviceId ?? '',
    username: context.deviceName ?? '',
    label: context.deviceName ?? '',
    role: context.role,
    clientId: clientId,
    deviceName: context.deviceName ?? '',
    connectedAt: now,
    lastSeenAt: now,
    channel: channel,
  );
}

class _FakeWebSocketChannel implements WebSocketChannel {
  final List<String> messages = <String>[];

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Stream get stream => const Stream.empty();

  @override
  WebSocketSink get sink => _FakeWebSocketSink(messages);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink(this._messages);

  final List<String> _messages;

  @override
  void add(data) {
    if (data is String) {
      _messages.add(data);
    }
  }

  @override
  void addError(error, [StackTrace? stackTrace]) {}

  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
