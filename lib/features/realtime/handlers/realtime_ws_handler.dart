// 文件输入：鉴权后的 websocket upgrade 请求、实时连接基础设施
// 文件职责：处理 websocket 连接、hello 握手、heartbeat 续期与会话踢线
// 文件对外接口：RealtimeWsHandler
// 文件包含：RealtimeWsHandler
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/auth/account_models.dart';
import '../../../core/auth/auth_session_store.dart';
import '../../../core/auth/request_authorization.dart';
import '../../../core/device_registry/device_models.dart';
import '../../../core/device_registry/device_store.dart';
import '../data/realtime_connection_registry.dart';
import '../data/realtime_event_hub.dart';
import '../data/realtime_presence_repository.dart';
import '../data/realtime_snapshot_builder.dart';
import '../data/realtime_status_publisher.dart';
import '../realtime_contract.dart';

typedef RealtimeConnectionClock = DateTime Function();

class RealtimeWsHandler {
  RealtimeWsHandler({
    required AuthSessionStore authSessionStore,
    required RealtimeConnectionRegistry connectionRegistry,
    required RealtimePresenceRepository presenceRepository,
    required RealtimeEventHub eventHub,
    required RealtimeSnapshotBuilder snapshotBuilder,
    required RealtimeStatusPublisher statusPublisher,
    DeviceStore? deviceStore,
    Random? random,
    RealtimeConnectionClock? clock,
    Duration helloTimeout = realtimeHelloTimeout,
  }) : _authSessionStore = authSessionStore,
       _connectionRegistry = connectionRegistry,
       _presenceRepository = presenceRepository,
       _eventHub = eventHub,
       _snapshotBuilder = snapshotBuilder,
       _statusPublisher = statusPublisher,
       _deviceStore = deviceStore,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now,
       _helloTimeout = helloTimeout;

  final AuthSessionStore _authSessionStore;
  final RealtimeConnectionRegistry _connectionRegistry;
  final RealtimePresenceRepository _presenceRepository;
  final RealtimeEventHub _eventHub;
  final RealtimeSnapshotBuilder _snapshotBuilder;
  final RealtimeStatusPublisher _statusPublisher;
  final DeviceStore? _deviceStore;
  final Random _random;
  final RealtimeConnectionClock _clock;
  final Duration _helloTimeout;

  Handler get handler {
    return (Request request) {
      final authError = ensureRequestHasAnyRole(
        request,
        allowedRoles: {AccountRole.owner, AccountRole.device},
      );
      if (authError != null) {
        return authError;
      }

      final authContext = requireAuthenticatedRequestContext(request)!;
      final connectionInfo = request.context['shelf.io.connection_info'];
      final observedRemoteIp = _normalizeIpAddress(
        connectionInfo is HttpConnectionInfo
            ? connectionInfo.remoteAddress.address
            : null,
      );
      final upgradeHandler = webSocketHandler((channel, _) {
        _handleConnection(
          channel,
          authContext,
          observedRemoteIp: observedRemoteIp,
        );
      });

      return upgradeHandler(request);
    };
  }

  void _handleConnection(
    WebSocketChannel channel,
    AuthenticatedRequestContext authContext, {
    String? observedRemoteIp,
  }) {
    String? activeConnectionId;
    var isChannelClosing = false;
    late final Timer helloTimer;

    Future<void> closeSocket({
      required int closeCode,
      required String closeReason,
      String? errorCode,
      String? errorMessage,
    }) async {
      if (errorCode != null && errorMessage != null) {
        _eventHub.sendRawMessage(
          channel,
          type: RealtimeMessageType.error,
          payload: {'code': errorCode, 'message': errorMessage},
        );
      }

      if (isChannelClosing) {
        return;
      }
      isChannelClosing = true;
      await channel.sink.close(closeCode, closeReason);
    }

    Future<void> completeDisconnect() async {
      helloTimer.cancel();

      final connectionId = activeConnectionId;
      if (connectionId == null) {
        return;
      }

      final removedConnection = _connectionRegistry.unregister(connectionId);
      if (removedConnection == null) {
        return;
      }

      _presenceRepository.markOffline(
        clientId: removedConnection.clientId,
        connectionId: removedConnection.connectionId,
      );
      _statusPublisher.publishPresenceChanged();
    }

    Future<void> handleHello(Map<String, dynamic> payload) async {
      if (activeConnectionId != null) {
        _eventHub.sendRawMessage(
          channel,
          type: RealtimeMessageType.error,
          payload: {
            'code': 'HELLO_ALREADY_ACCEPTED',
            'message': 'Hello has already been accepted for this connection',
          },
        );
        return;
      }

      final requestedSessionId = _readTrimmedString(payload['sessionId']);
      if (requestedSessionId == null ||
          requestedSessionId != authContext.sessionId) {
        await closeSocket(
          closeCode: realtimeCloseCodePolicyViolation,
          closeReason: 'session mismatch',
          errorCode: 'SESSION_MISMATCH',
          errorMessage:
              'Hello sessionId does not match the authenticated websocket session',
        );
        return;
      }

      final requestedDeviceId = _readTrimmedString(payload['deviceId']);
      final boundDeviceId = _readTrimmedString(authContext.deviceId);

      if (authContext.isOwner) {
        if (requestedDeviceId != null) {
          await closeSocket(
            closeCode: realtimeCloseCodePolicyViolation,
            closeReason: 'device id not allowed',
            errorCode: 'DEVICE_ID_NOT_ALLOWED',
            errorMessage:
                'Owner websocket sessions cannot register device presence',
          );
          return;
        }

        final now = _now();
        final connection = RealtimeConnection(
          connectionId: _nextConnectionId(now),
          sessionId: authContext.sessionId,
          accountId: authContext.ownerId ?? '',
          username: authContext.username ?? '',
          label: authContext.label ?? authContext.username ?? 'owner',
          role: authContext.role,
          clientId: 'owner:${authContext.sessionId}',
          deviceName: authContext.username ?? 'owner',
          platform: _readTrimmedString(payload['platform']),
          brand: _readTrimmedString(payload['brand']),
          model: _readTrimmedString(payload['model']),
          appVersion: _readTrimmedString(payload['appVersion']),
          reportedRouteIp: _normalizeIpAddress(
            _readTrimmedString(payload['reportedRouteIp']),
          ),
          observedRemoteIp: observedRemoteIp,
          connectedAt: now,
          lastSeenAt: now,
          channel: channel,
        );

        final registration = _connectionRegistry.register(connection);
        activeConnectionId = connection.connectionId;
        helloTimer.cancel();

        if (registration.replacedConnection != null) {
          final replacedConnection = registration.replacedConnection!;
          await _eventHub.closeConnection(
            replacedConnection.connectionId,
            closeCode: realtimeCloseCodeConnectionReplaced,
            reason: 'connection replaced',
          );
        }

        _eventHub.sendToConnection(
          connection,
          type: RealtimeMessageType.helloAck,
          payload: {
            'sessionId': connection.sessionId,
            'role': connection.role.name,
            'heartbeatIntervalSec': realtimeHeartbeatInterval.inSeconds,
            'heartbeatTimeoutSec': realtimeHeartbeatTimeout.inSeconds,
            'snapshot': await _snapshotBuilder.buildForClient(),
          },
        );
        _statusPublisher.publishPresenceChanged();
        return;
      }

      final deviceId = boundDeviceId ?? requestedDeviceId;
      if (deviceId == null) {
        await closeSocket(
          closeCode: realtimeCloseCodePolicyViolation,
          closeReason: 'device id required',
          errorCode: 'DEVICE_ID_REQUIRED',
          errorMessage: 'A deviceId is required to establish realtime presence',
        );
        return;
      }

      if (boundDeviceId != null &&
          requestedDeviceId != null &&
          requestedDeviceId != boundDeviceId) {
        await closeSocket(
          closeCode: realtimeCloseCodePolicyViolation,
          closeReason: 'device id mismatch',
          errorCode: 'DEVICE_ID_MISMATCH',
          errorMessage:
              'Hello deviceId does not match the authenticated client session',
        );
        return;
      }

      final now = _now();
      final connection = RealtimeConnection(
        connectionId: _nextConnectionId(now),
        sessionId: authContext.sessionId,
        accountId: authContext.ownerId ?? '',
        username: authContext.username ?? authContext.deviceName ?? '',
        label: authContext.label ?? authContext.deviceName ?? '',
        role: authContext.role,
        clientId: deviceId,
        deviceName:
            _readTrimmedString(payload['deviceName']) ??
            authContext.deviceName ??
            '',
        platform: _readTrimmedString(payload['platform']),
        brand: _readTrimmedString(payload['brand']),
        model: _readTrimmedString(payload['model']),
        appVersion: _readTrimmedString(payload['appVersion']),
        reportedRouteIp: _normalizeIpAddress(
          _readTrimmedString(payload['reportedRouteIp']),
        ),
        observedRemoteIp: observedRemoteIp,
        connectedAt: now,
        lastSeenAt: now,
        channel: channel,
      );

      final registration = _connectionRegistry.register(connection);
      activeConnectionId = connection.connectionId;
      _presenceRepository.markOnline(connection);
      helloTimer.cancel();

      if (registration.replacedConnection != null) {
        final replacedConnection = registration.replacedConnection!;
        _eventHub.sendToConnection(
          replacedConnection,
          type: RealtimeMessageType.connectionReplaced,
          payload: {
            'deviceId': replacedConnection.clientId,
            'message': 'A newer websocket connection replaced this client',
          },
        );
        await _eventHub.closeConnection(
          replacedConnection.connectionId,
          closeCode: realtimeCloseCodeConnectionReplaced,
          reason: 'connection replaced',
        );
      }

      _eventHub.sendToConnection(
        connection,
        type: RealtimeMessageType.helloAck,
        payload: {
          'sessionId': connection.sessionId,
          'deviceId': connection.clientId,
          'role': connection.role.name,
          'heartbeatIntervalSec': realtimeHeartbeatInterval.inSeconds,
          'heartbeatTimeoutSec': realtimeHeartbeatTimeout.inSeconds,
          'snapshot': await _snapshotBuilder.buildForClient(clientId: deviceId),
        },
      );
      _statusPublisher.publishPresenceChanged();
    }

    Future<void> handleHeartbeat(Map<String, dynamic> payload) async {
      final connectionId = activeConnectionId;
      if (connectionId == null) {
        await closeSocket(
          closeCode: realtimeCloseCodePolicyViolation,
          closeReason: 'hello required',
          errorCode: 'HELLO_REQUIRED',
          errorMessage: 'Hello must be completed before heartbeat messages',
        );
        return;
      }

      final requestedSessionId =
          _readTrimmedString(payload['sessionId']) ?? authContext.sessionId;
      if (requestedSessionId != authContext.sessionId) {
        await closeSocket(
          closeCode: realtimeCloseCodePolicyViolation,
          closeReason: 'session mismatch',
          errorCode: 'SESSION_MISMATCH',
          errorMessage:
              'Heartbeat sessionId does not match the authenticated websocket session',
        );
        return;
      }

      if (authContext.isDevice) {
        final deviceId = authContext.deviceId;
        if (deviceId == null || deviceId.isEmpty) {
          await closeSocket(
            closeCode: realtimeCloseCodeSessionRevoked,
            closeReason: 'device id required',
          );
          return;
        }
        final deviceStore = _deviceStore;
        final device = deviceStore == null
            ? null
            : await deviceStore.findDeviceById(deviceId);
        if (device == null ||
            device.status != DeviceStatus.active ||
            device.credentialVersion != authContext.credentialVersion) {
          _eventHub.sendToConnectionId(
            connectionId,
            type: RealtimeMessageType.sessionRevoked,
            payload: {
              'code': 'AUTH_REVOKED',
              'message': 'Device credential has been revoked',
              'sessionId': authContext.sessionId,
            },
          );
          await closeSocket(
            closeCode: realtimeCloseCodeSessionRevoked,
            closeReason: 'AUTH_REVOKED',
          );
          return;
        }
      } else {
        final authResult = await _authSessionStore.authenticateSessionId(
          requestedSessionId,
          refreshExpiration: true,
        );
        final refreshedContext = authResult.context;
        if (!authResult.isSuccess ||
            refreshedContext == null ||
            refreshedContext.sessionId != authContext.sessionId ||
            refreshedContext.ownerId != authContext.ownerId) {
          _eventHub.sendToConnectionId(
            connectionId,
            type: RealtimeMessageType.sessionRevoked,
            payload: {
              'code': authResult.failureCode ?? 'AUTH_REVOKED',
              'message':
                  authResult.failureMessage ?? 'Session has been revoked',
              'sessionId': authContext.sessionId,
            },
          );
          await closeSocket(
            closeCode: realtimeCloseCodeSessionRevoked,
            closeReason: authResult.failureCode ?? 'session revoked',
          );
          return;
        }
      }

      final updatedConnection = _connectionRegistry.touch(connectionId, _now());
      if (updatedConnection != null) {
        _presenceRepository.touch(updatedConnection);
      }

      _eventHub.sendToConnectionId(
        connectionId,
        type: RealtimeMessageType.heartbeatAck,
        payload: {
          'sessionId': authContext.sessionId,
          'receivedAt': _now().toUtc().toIso8601String(),
        },
      );
    }

    helloTimer = Timer(_helloTimeout, () {
      unawaited(
        closeSocket(
          closeCode: realtimeCloseCodeHelloTimeout,
          closeReason: 'hello timeout',
          errorCode: 'HELLO_REQUIRED',
          errorMessage: 'Hello message was not received in time',
        ),
      );
    });

    channel.stream.listen(
      (message) {
        unawaited(() async {
          final envelope = _parseMessage(message);
          if (envelope == null) {
            await closeSocket(
              closeCode: realtimeCloseCodeInvalidMessage,
              closeReason: 'invalid payload',
              errorCode: 'INVALID_MESSAGE',
              errorMessage: 'Realtime messages must be valid JSON objects',
            );
            return;
          }

          final type = _readTrimmedString(envelope['type']);
          final payload =
              envelope['payload'] as Map<String, dynamic>? ?? const {};
          if (type == RealtimeMessageType.hello) {
            await handleHello(payload);
            return;
          }
          if (type == RealtimeMessageType.heartbeat) {
            await handleHeartbeat(payload);
            return;
          }

          _eventHub.sendRawMessage(
            channel,
            type: RealtimeMessageType.error,
            payload: {
              'code': 'MESSAGE_UNSUPPORTED',
              'message': 'Realtime message type "$type" is not supported',
            },
          );
        }());
      },
      onDone: () {
        unawaited(completeDisconnect());
      },
      onError: (_) {
        unawaited(completeDisconnect());
      },
    );
  }

  Map<String, dynamic>? _parseMessage(Object? message) {
    if (message is! String || message.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(message);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String? _readTrimmedString(Object? value) {
    final rawValue = value as String?;
    if (rawValue == null) {
      return null;
    }
    final normalizedValue = rawValue.trim();
    return normalizedValue.isEmpty ? null : normalizedValue;
  }

  String? _normalizeIpAddress(String? value) {
    final normalizedValue = value?.trim() ?? '';
    if (normalizedValue.isEmpty) {
      return null;
    }
    if (normalizedValue.startsWith('::ffff:')) {
      return normalizedValue.substring(7);
    }
    return normalizedValue;
  }

  DateTime _now() => _clock().toUtc();

  String _nextConnectionId(DateTime now) {
    return 'conn_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }
}
