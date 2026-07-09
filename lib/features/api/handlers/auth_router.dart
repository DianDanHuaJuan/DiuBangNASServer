import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_session_handler.dart';
import 'credential_device_enroll_handler.dart';
import 'device_refresh_handler.dart';

class AuthRouter {
  AuthRouter({
    required AuthSessionHandler authSessionHandler,
    required DeviceRefreshHandler deviceRefreshHandler,
    required CredentialDeviceEnrollHandler credentialDeviceEnrollHandler,
  }) : _authSessionHandler = authSessionHandler,
       _deviceRefreshHandler = deviceRefreshHandler,
       _credentialDeviceEnrollHandler = credentialDeviceEnrollHandler;

  final AuthSessionHandler _authSessionHandler;
  final DeviceRefreshHandler _deviceRefreshHandler;
  final CredentialDeviceEnrollHandler _credentialDeviceEnrollHandler;

  Handler get handler {
    final router = Router();

    router.post('/session', _authSessionHandler.createSessionHandler);
    router.post(
      '/credential-device-enroll',
      _credentialDeviceEnrollHandler.handler,
    );
    router.post('/device/refresh', _deviceRefreshHandler.handler);
    router.all('/<ignored|.*>', (request) {
      return Response.notFound(
        '{"code":"PATH_NOT_FOUND","message":"Auth endpoint not found","details":{}}',
        headers: {'Content-Type': 'application/json'},
      );
    });

    return router.call;
  }
}
