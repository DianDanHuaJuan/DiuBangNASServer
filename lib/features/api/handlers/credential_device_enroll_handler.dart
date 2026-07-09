import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/auth/owner_credential_store.dart';
import '../../../core/device_registry/device_store.dart';
import '../../../core/tls/server_tls_manager.dart';

class CredentialDeviceEnrollHandler {
  CredentialDeviceEnrollHandler({
    required OwnerCredentialStore ownerCredentialStore,
    required DeviceStore deviceStore,
    required Future<ServerTlsMaterial> Function() tlsMaterialProvider,
  }) : _ownerCredentialStore = ownerCredentialStore,
       _deviceStore = deviceStore,
       _tlsMaterialProvider = tlsMaterialProvider;

  final OwnerCredentialStore _ownerCredentialStore;
  final DeviceStore _deviceStore;
  final Future<ServerTlsMaterial> Function() _tlsMaterialProvider;

  Handler get handler {
    return (Request request) async {
      if (request.method != 'POST') {
        return Response(405, body: 'Method Not Allowed');
      }

      try {
        final authHeader = request.headers['Authorization'];
        if (authHeader == null || !authHeader.startsWith('Basic ')) {
          return _buildBasicAuthErrorResponse(
            code: 'AUTH_REQUIRED',
            message: 'Authorization header is required',
          );
        }

        final credentials = _ownerCredentialStore.decodeBasicAuth(authHeader);
        if (credentials == null) {
          return _buildBasicAuthErrorResponse(
            code: 'AUTH_INVALID',
            message: 'Invalid authorization header format',
          );
        }

        final (username, password) = credentials;
        final authentication = await _ownerCredentialStore.authenticate(
          username: username,
          password: password,
        );
        if (!authentication.isSuccess) {
          return _buildBasicAuthErrorResponse(
            code: authentication.failureCode ?? 'AUTH_INVALID',
            message:
                authentication.failureMessage ?? 'Invalid username or password',
          );
        }

        final payload = jsonDecode(await request.readAsString());
        if (payload is! Map) {
          return _error(400, 'INVALID_BODY', 'Request body must be JSON');
        }

        final deviceId = payload['device_id'] as String?;
        final deviceName = payload['device_name'] as String?;
        final physicalDeviceId = payload['physical_device_id'] as String?;
        final devicePlatform = payload['device_platform'] as String?;
        final deviceBrand = payload['device_brand'] as String?;
        final deviceModel = payload['device_model'] as String?;

        if (deviceId == null || deviceId.trim().isEmpty) {
          return _error(400, 'MISSING_DEVICE_ID', '缺少设备标识');
        }
        if (deviceName == null || deviceName.trim().isEmpty) {
          return _error(400, 'MISSING_DEVICE_NAME', '缺少设备名称');
        }

        final tlsMaterial = await _tlsMaterialProvider();
        final enrollResult = await _deviceStore.enrollDevice(
          deviceId: deviceId.trim(),
          deviceName: deviceName.trim(),
          physicalDeviceId: physicalDeviceId?.trim(),
          platform: devicePlatform?.trim(),
          brand: deviceBrand?.trim(),
          model: deviceModel?.trim(),
        );

        if (!enrollResult.isSuccess) {
          return _error(
            400,
            enrollResult.failureCode ?? 'DEVICE_ENROLL_ERROR',
            enrollResult.failureMessage ?? '设备注册失败',
          );
        }

        final tokens = enrollResult.tokens!;
        return Response.ok(
          jsonEncode({
            'serverId': tlsMaterial.serverId,
            'serverName': tlsMaterial.serverName,
            'baseUrl': tlsMaterial.baseUrl,
            'rootCaPem': tlsMaterial.rootCaPem,
            'caSha256': tlsMaterial.caSha256,
            'deviceId': tokens.device.deviceId,
            'accessToken': tokens.accessToken,
            'refreshToken': tokens.refreshToken,
            'sessionId': tokens.sessionId,
            'accessExpiresAt': tokens.accessExpiresAt.toUtc().toIso8601String(),
            'refreshExpiresAt': tokens.refreshExpiresAt.toUtc().toIso8601String(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (error) {
        return Response.internalServerError(
          body: jsonEncode({
            'code': 'CREDENTIAL_DEVICE_ENROLL_ERROR',
            'message': '设备注册失败: $error',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  }

  Response _buildBasicAuthErrorResponse({
    required String code,
    required String message,
    int statusCode = 401,
  }) {
    return Response(
      statusCode,
      headers: {
        'Content-Type': 'application/json',
        'WWW-Authenticate': 'Basic realm="DiuBangFileS"',
      },
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
    );
  }

  Response _error(int statusCode, String code, String message) {
    return Response(
      statusCode,
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
