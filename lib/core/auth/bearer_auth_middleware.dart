import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../device_registry/device_store.dart';
import 'auth_session_store.dart';

const String authenticatedRequestContextKey = 'authenticatedRequestContext';

Middleware bearerAuthMiddleware(
  AuthSessionStore authSessionStore, {
  DeviceStore? deviceStore,
}) {
  return (Handler innerHandler) {
    return (Request request) async {
      final authentication = await authSessionStore.authenticate(
        request.headers['Authorization'],
        deviceStore: deviceStore,
      );

      if (!authentication.isSuccess) {
        return buildBearerAuthErrorResponse(
          code: authentication.failureCode ?? 'AUTH_INVALID',
          message: authentication.failureMessage ?? 'Invalid bearer token',
        );
      }

      final deviceHeader = request.headers['x-nas-device-id']?.trim();
      final context = authentication.context!;
      if (context.isDevice &&
          deviceHeader != null &&
          deviceHeader.isNotEmpty &&
          deviceHeader != context.deviceId) {
        return buildBearerAuthErrorResponse(
          code: 'DEVICE_ID_MISMATCH',
          message: 'X-NAS-Device-Id does not match the authenticated device',
          statusCode: 403,
        );
      }

      return innerHandler(
        request.change(
          context: {authenticatedRequestContextKey: context},
        ),
      );
    };
  };
}

Response buildBearerAuthErrorResponse({
  required String code,
  required String message,
  int statusCode = 401,
}) {
  return Response(
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'WWW-Authenticate': 'Bearer realm="DiuBangFileS"',
    },
    body: jsonEncode({'code': code, 'message': message, 'details': {}}),
  );
}

AuthenticatedRequestContext? authenticatedRequestContextFromRequest(
  Request request,
) {
  final context = request.context[authenticatedRequestContextKey];
  return context is AuthenticatedRequestContext ? context : null;
}
