// 文件输入：连接注册表、事件类型、事件负载
// 文件职责：向一个或多个 websocket 连接发送统一 envelope 的 realtime 消息
// 文件对外接口：RealtimeEventHub
// 文件包含：RealtimeEventHub
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'realtime_connection_registry.dart';

typedef RealtimeEventClock = DateTime Function();

class RealtimeEventHub {
  RealtimeEventHub({
    required RealtimeConnectionRegistry connectionRegistry,
    RealtimeEventClock? clock,
  }) : _connectionRegistry = connectionRegistry,
       _clock = clock ?? DateTime.now;

  final RealtimeConnectionRegistry _connectionRegistry;
  final RealtimeEventClock _clock;

  void broadcast({
    required String type,
    required Map<String, dynamic> payload,
  }) {
    for (final connection in _connectionRegistry.connections) {
      sendToConnection(connection, type: type, payload: payload);
    }
  }

  void broadcastToSession({
    required String sessionId,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    for (final connection in _connectionRegistry.findBySessionId(sessionId)) {
      sendToConnection(connection, type: type, payload: payload);
    }
  }

  void sendToConnectionId(
    String connectionId, {
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final connection = _connectionRegistry.findByConnectionId(connectionId);
    if (connection == null) {
      return;
    }
    sendToConnection(connection, type: type, payload: payload);
  }

  void broadcastToClientId(
    String clientId, {
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final connection = _connectionRegistry.findByClientId(clientId);
    if (connection == null) {
      return;
    }
    sendToConnection(connection, type: type, payload: payload);
  }

  void broadcastToClientIds(
    Iterable<String> clientIds, {
    required String type,
    required Map<String, dynamic> payload,
  }) {
    for (final connection in _connectionRegistry.findByClientIds(clientIds)) {
      sendToConnection(connection, type: type, payload: payload);
    }
  }

  void sendToConnection(
    RealtimeConnection connection, {
    required String type,
    required Map<String, dynamic> payload,
  }) {
    sendRawMessage(connection.channel, type: type, payload: payload);
  }

  void sendRawMessage(
    WebSocketChannel channel, {
    required String type,
    required Map<String, dynamic> payload,
  }) {
    try {
      channel.sink.add(
        jsonEncode({
          'type': type,
          'payload': payload,
          'sentAt': _clock().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Ignore write failures here; the disconnect path will clean up the state.
    }
  }

  Future<void> closeConnection(
    String connectionId, {
    int closeCode = WebSocketStatus.normalClosure,
    String reason = 'connection closed',
  }) async {
    final connection = _connectionRegistry.findByConnectionId(connectionId);
    if (connection == null) {
      return;
    }
    await connection.channel.sink.close(closeCode, reason);
  }

  Future<void> closeAllConnections({
    int closeCode = WebSocketStatus.normalClosure,
    String reason = 'connection closed',
  }) async {
    final connectionIds = _connectionRegistry.connections
        .map((connection) => connection.connectionId)
        .toList(growable: false);
    for (final connectionId in connectionIds) {
      await closeConnection(
        connectionId,
        closeCode: closeCode,
        reason: reason,
      );
    }
  }
}
