import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'relay_webdav_handler.dart';

class RelayWebdavRouter {
  RelayWebdavRouter({required RelayWebdavHandler relayWebdavHandler})
    : _relayWebdavHandler = relayWebdavHandler;

  final RelayWebdavHandler _relayWebdavHandler;

  Handler get handler {
    final router = Router();

    router.put(
      '/<transferId>/<resource>',
      _relayWebdavHandler.putTransferHandler,
    );
    router.get(
      '/<transferId>/<resource>',
      _relayWebdavHandler.getTransferHandler,
    );
    router.head(
      '/<transferId>/<resource>',
      _relayWebdavHandler.headTransferHandler,
    );
    router.all('/<ignored|.*>', (request) {
      return Response.notFound(
        '{"code":"PATH_NOT_FOUND","message":"Relay WebDAV endpoint not found","details":{}}',
        headers: const {'Content-Type': 'application/json'},
      );
    });

    return router.call;
  }
}
