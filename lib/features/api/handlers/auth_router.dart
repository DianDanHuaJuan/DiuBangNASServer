import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_session_handler.dart';
import 'device_refresh_handler.dart';

class AuthRouter {
  AuthRouter({
    required AuthSessionHandler authSessionHandler,
    required DeviceRefreshHandler deviceRefreshHandler,
  }) : _authSessionHandler = authSessionHandler,
       _deviceRefreshHandler = deviceRefreshHandler;

  final AuthSessionHandler _authSessionHandler;
  final DeviceRefreshHandler _deviceRefreshHandler;

  Handler get handler {
    final router = Router();

    router.post('/session', _authSessionHandler.createSessionHandler);
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
