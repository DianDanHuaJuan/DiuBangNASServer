import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'relay_api_handler.dart';

class RelayApiRouter {
  RelayApiRouter({required RelayApiHandler relayApiHandler})
    : _relayApiHandler = relayApiHandler;

  final RelayApiHandler _relayApiHandler;

  Handler get handler {
    final router = Router();

    router.post('/transfers', _relayApiHandler.createTransferHandler);
    router.post(
      '/transfers/<transferId>/cancel',
      _relayApiHandler.cancelTransferHandler,
    );
    router.get('/transfers/history', _relayApiHandler.listHistoryHandler);
    router.post(
      '/transfers/<transferId>/download-complete',
      _relayApiHandler.acknowledgeDownloadCompletedHandler,
    );
    router.post(
      '/transfers/<transferId>/retry',
      _relayApiHandler.retryTransferHandler,
    );
    router.get(
      '/transfers/<transferId>/thumbnail',
      _relayApiHandler.getTransferThumbnailHandler,
    );
    router.all('/<ignored|.*>', (request) {
      return Response.notFound(
        '{"code":"PATH_NOT_FOUND","message":"Relay endpoint not found","details":{}}',
        headers: const {'Content-Type': 'application/json'},
      );
    });

    return router.call;
  }
}
