import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/features/realtime/data/realtime_connection_registry.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('RealtimeConnectionRegistry', () {
    test('keeps only the latest primary connection for the same clientId', () {
      final registry = RealtimeConnectionRegistry();
      final oldConnection = _buildConnection(
        connectionId: 'conn-1',
        clientId: 'tablet-01',
      );
      final newConnection = _buildConnection(
        connectionId: 'conn-2',
        clientId: 'tablet-01',
      );

      final firstRegistration = registry.register(oldConnection);
      final secondRegistration = registry.register(newConnection);

      expect(firstRegistration.replacedConnection, isNull);
      expect(secondRegistration.replacedConnection?.connectionId, 'conn-1');
      expect(registry.findByConnectionId('conn-1'), isNull);
      expect(registry.findByConnectionId('conn-2')?.clientId, 'tablet-01');
    });

    test(
      'does not let an old disconnect remove a newer replacement connection',
      () {
        final registry = RealtimeConnectionRegistry();
        registry.register(
          _buildConnection(connectionId: 'conn-1', clientId: 'tablet-01'),
        );
        registry.register(
          _buildConnection(connectionId: 'conn-2', clientId: 'tablet-01'),
        );

        final removedOldConnection = registry.unregister('conn-1');
        final removedNewConnection = registry.unregister('conn-2');

        expect(removedOldConnection, isNull);
        expect(removedNewConnection?.connectionId, 'conn-2');
        expect(registry.hasConnections, isFalse);
      },
    );

    test('finds the latest connection by client id', () {
      final registry = RealtimeConnectionRegistry();
      registry.register(
        _buildConnection(connectionId: 'conn-1', clientId: 'tablet-01'),
      );
      registry.register(
        _buildConnection(connectionId: 'conn-2', clientId: 'tablet-01'),
      );
      registry.register(
        _buildConnection(connectionId: 'conn-3', clientId: 'phone-02'),
      );

      expect(registry.findByClientId('tablet-01')?.connectionId, 'conn-2');
      expect(
        registry
            .findByClientIds(['tablet-01', 'phone-02'])
            .map((connection) => connection.connectionId)
            .toList(),
        ['conn-2', 'conn-3'],
      );
    });
  });
}

RealtimeConnection _buildConnection({
  required String connectionId,
  required String clientId,
}) {
  final now = DateTime.utc(2024, 4, 1, 12);
  return RealtimeConnection(
    connectionId: connectionId,
    sessionId: 'sess-1',
    accountId: 'acct-1',
    username: 'device-user',
    label: '客厅平板',
    role: AccountRole.device,
    clientId: clientId,
    deviceName: 'Living Room Tablet',
    connectedAt: now,
    lastSeenAt: now,
    channel: _FakeWebSocketChannel(),
  );
}

class _FakeWebSocketChannel implements WebSocketChannel {
  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready async {}

  @override
  WebSocketSink get sink => _FakeWebSocketSink();

  @override
  Stream get stream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  @override
  Future<void> get done async {}

  @override
  void add(event) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close([int? closeCode, String? closeReason]) async {}
}
