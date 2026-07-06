// 文件输入：realtime 连接上下文与 WebSocketChannel
// 文件职责：跟踪当前在线连接，并保证同一 clientId 只保留一个主连接
// 文件对外接口：RealtimeConnection, RealtimeConnectionRegistry
// 文件包含：RealtimeConnection, RealtimeConnectionRegistrationResult, RealtimeConnectionRegistry
import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/auth/account_models.dart';

class RealtimeConnection {
  const RealtimeConnection({
    required this.connectionId,
    required this.sessionId,
    required this.accountId,
    required this.username,
    required this.label,
    required this.role,
    required this.clientId,
    required this.deviceName,
    required this.connectedAt,
    required this.lastSeenAt,
    required this.channel,
    this.platform,
    this.brand,
    this.model,
    this.appVersion,
    this.reportedRouteIp,
    this.observedRemoteIp,
  });

  final String connectionId;
  final String sessionId;
  final String accountId;
  final String username;
  final String label;
  final AccountRole role;
  final String clientId;
  final String deviceName;
  final String? platform;
  final String? brand;
  final String? model;
  final String? appVersion;
  final String? reportedRouteIp;
  final String? observedRemoteIp;
  final DateTime connectedAt;
  final DateTime lastSeenAt;
  final WebSocketChannel channel;

  RealtimeConnection copyWith({DateTime? lastSeenAt}) {
    return RealtimeConnection(
      connectionId: connectionId,
      sessionId: sessionId,
      accountId: accountId,
      username: username,
      label: label,
      role: role,
      clientId: clientId,
      deviceName: deviceName,
      platform: platform,
      brand: brand,
      model: model,
      appVersion: appVersion,
      reportedRouteIp: reportedRouteIp,
      observedRemoteIp: observedRemoteIp,
      connectedAt: connectedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      channel: channel,
    );
  }
}

class RealtimeConnectionRegistrationResult {
  const RealtimeConnectionRegistrationResult({this.replacedConnection});

  final RealtimeConnection? replacedConnection;
}

class RealtimeConnectionRegistry {
  final Map<String, RealtimeConnection> _connectionsById =
      <String, RealtimeConnection>{};
  final Map<String, String> _connectionIdByClientId = <String, String>{};
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  bool get hasConnections => _connectionsById.isNotEmpty;

  Iterable<RealtimeConnection> get connections =>
      _connectionsById.values.toList(growable: false);

  Stream<bool> get onConnectionStateChanged =>
      _connectionStateController.stream;

  RealtimeConnectionRegistrationResult register(RealtimeConnection connection) {
    final wasEmpty = _connectionsById.isEmpty;
    final replacedConnectionId = _connectionIdByClientId[connection.clientId];
    final replacedConnection = replacedConnectionId == null
        ? null
        : _connectionsById.remove(replacedConnectionId);

    _connectionsById[connection.connectionId] = connection;
    _connectionIdByClientId[connection.clientId] = connection.connectionId;

    if (wasEmpty) {
      _connectionStateController.add(true);
    }

    return RealtimeConnectionRegistrationResult(
      replacedConnection: replacedConnection,
    );
  }

  RealtimeConnection? findByConnectionId(String connectionId) {
    return _connectionsById[connectionId];
  }

  RealtimeConnection? findByClientId(String clientId) {
    final connectionId = _connectionIdByClientId[clientId];
    if (connectionId == null) {
      return null;
    }
    return _connectionsById[connectionId];
  }

  Iterable<RealtimeConnection> findByClientIds(
    Iterable<String> clientIds,
  ) sync* {
    final seenConnectionIds = <String>{};
    for (final clientId in clientIds) {
      final connectionId = _connectionIdByClientId[clientId];
      if (connectionId == null || !seenConnectionIds.add(connectionId)) {
        continue;
      }

      final connection = _connectionsById[connectionId];
      if (connection != null) {
        yield connection;
      }
    }
  }

  Iterable<RealtimeConnection> findBySessionId(String sessionId) sync* {
    for (final connection in _connectionsById.values) {
      if (connection.sessionId == sessionId) {
        yield connection;
      }
    }
  }

  Iterable<RealtimeConnection> findTimedOut(
    DateTime now,
    Duration inactivityTimeout,
  ) sync* {
    for (final connection in _connectionsById.values) {
      final expiresAt = connection.lastSeenAt.add(inactivityTimeout);
      if (!expiresAt.isAfter(now)) {
        yield connection;
      }
    }
  }

  RealtimeConnection? touch(String connectionId, DateTime lastSeenAt) {
    final currentConnection = _connectionsById[connectionId];
    if (currentConnection == null) {
      return null;
    }

    final updatedConnection = currentConnection.copyWith(
      lastSeenAt: lastSeenAt,
    );
    _connectionsById[connectionId] = updatedConnection;
    return updatedConnection;
  }

  RealtimeConnection? unregister(String connectionId) {
    final removedConnection = _connectionsById.remove(connectionId);
    if (removedConnection == null) {
      return null;
    }

    if (_connectionIdByClientId[removedConnection.clientId] == connectionId) {
      _connectionIdByClientId.remove(removedConnection.clientId);
    }

    if (_connectionsById.isEmpty) {
      _connectionStateController.add(false);
    }

    return removedConnection;
  }

  void clear() {
    final hadConnections = _connectionsById.isNotEmpty;
    _connectionsById.clear();
    _connectionIdByClientId.clear();
    if (hadConnections) {
      _connectionStateController.add(false);
    }
  }

  void dispose() {
    _connectionStateController.close();
  }
}
