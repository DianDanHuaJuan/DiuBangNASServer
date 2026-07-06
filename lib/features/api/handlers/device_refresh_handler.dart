import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/device_registry/device_store.dart';

class DeviceRefreshHandler {
  DeviceRefreshHandler({required DeviceStore deviceStore})
    : _deviceStore = deviceStore;

  final DeviceStore _deviceStore;

  Handler get handler {
    return (Request request) async {
      if (request.method != 'POST') {
        return Response(405, body: 'Method Not Allowed');
      }

      try {
        final payload = jsonDecode(await request.readAsString());
        if (payload is! Map) {
          return _error(400, 'INVALID_BODY', 'Request body must be JSON');
        }

        final refreshToken = payload['refreshToken'] as String?;
        if (refreshToken == null || refreshToken.trim().isEmpty) {
          return _error(400, 'INVALID_PARAMS', 'refreshToken is required');
        }

        final result = await _deviceStore.refreshAccessToken(refreshToken);
        if (!result.isSuccess) {
          return _error(
            401,
            result.failureCode ?? 'AUTH_INVALID',
            result.failureMessage ?? 'Invalid refresh token',
          );
        }

        final tokens = result.tokens!;
        return Response.ok(
          jsonEncode({
            'deviceId': tokens.deviceId,
            'accessToken': tokens.accessToken,
            'tokenType': 'Device',
            'expiresAt': tokens.accessExpiresAt.toUtc().toIso8601String(),
            'sessionId': tokens.sessionId,
            'serverTime': DateTime.now().toUtc().toIso8601String(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } on FormatException catch (error) {
        return _error(400, 'INVALID_BODY', error.message);
      }
    };
  }

  Response _error(int statusCode, String code, String message) {
    return Response(
      statusCode,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
    );
  }
}
