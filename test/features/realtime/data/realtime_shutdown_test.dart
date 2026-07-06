import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/features/realtime/data/realtime_connection_registry.dart';
import 'package:nas_server/features/realtime/data/realtime_event_hub.dart';
import 'package:nas_server/features/realtime/realtime_contract.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('RealtimeEventHub shutdown', () {
    test('closeAllConnections closes every registered websocket', () async {
      final now = DateTime.utc(2026, 6, 13, 12);
      final registry = RealtimeConnectionRegistry();
      final channelA = _FakeWebSocketChannel();
      final channelB = _FakeWebSocketChannel();

      registry.register(
        _buildConnection(
          channel: channelA,
          connectionId: 'conn-a',
          clientId: 'client-a',
          connectedAt: now,
          lastSeenAt: now,
        ),
      );
      registry.register(
        _buildConnection(
          channel: channelB,
          connectionId: 'conn-b',
          clientId: 'client-b',
          connectedAt: now,
          lastSeenAt: now,
        ),
      );

      final hub = RealtimeEventHub(
        connectionRegistry: registry,
        clock: () => now,
      );

      await hub.closeAllConnections(
        closeCode: realtimeCloseCodeServerShutdown,
        reason: 'server stopping',
      );

      expect(channelA.closeCalls, 1);
      expect(channelA.closeCode, realtimeCloseCodeServerShutdown);
      expect(channelA.closeReason, 'server stopping');
      expect(channelB.closeCalls, 1);
      expect(channelB.closeCode, realtimeCloseCodeServerShutdown);
      expect(channelB.closeReason, 'server stopping');
    });

    test(
      'broadcasts server.state.changed offline before closing connections',
      () async {
        final now = DateTime.utc(2026, 6, 13, 12);
        final registry = RealtimeConnectionRegistry();
        final channel = _FakeWebSocketChannel();
        registry.register(
          _buildConnection(
            channel: channel,
            connectionId: 'conn-1',
            clientId: 'tablet-01',
            connectedAt: now,
            lastSeenAt: now,
          ),
        );

        final hub = RealtimeEventHub(
          connectionRegistry: registry,
          clock: () => now,
        );

        hub.broadcast(
          type: RealtimeMessageType.serverStateChanged,
          payload: {
            'server': {'status': 'offline'},
            'reason': 'server_stopping',
          },
        );
        await hub.closeAllConnections(
          closeCode: realtimeCloseCodeServerShutdown,
          reason: 'server stopping',
        );

        expect(channel.messages, hasLength(1));
        final message =
            jsonDecode(channel.messages.single) as Map<String, dynamic>;
        expect(message['type'], RealtimeMessageType.serverStateChanged);
        expect(message['payload'], {
          'server': {'status': 'offline'},
          'reason': 'server_stopping',
        });
        expect(channel.closeCalls, 1);
        expect(channel.closeCode, realtimeCloseCodeServerShutdown);
      },
    );
  });
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
