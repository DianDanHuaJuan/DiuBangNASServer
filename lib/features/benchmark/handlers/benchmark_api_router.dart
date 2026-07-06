import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'benchmark_api_handler.dart';

class BenchmarkApiRouter {
  BenchmarkApiRouter({required BenchmarkApiHandler benchmarkApiHandler})
    : _benchmarkApiHandler = benchmarkApiHandler;

  final BenchmarkApiHandler _benchmarkApiHandler;

  Handler get handler {
    final router = Router();

    router.post('/sessions', _benchmarkApiHandler.createSessionHandler);
    router.put(
      '/sessions/<sessionId>/upload',
      _benchmarkApiHandler.uploadHandler,
    );
    router.get(
      '/sessions/<sessionId>/download',
      _benchmarkApiHandler.downloadHandler,
    );
    router.head(
      '/sessions/<sessionId>/download',
      _benchmarkApiHandler.headDownloadHandler,
    );
    router.post(
      '/sessions/<sessionId>/client-report',
      _benchmarkApiHandler.reportClientHandler,
    );
    router.get('/sessions/<sessionId>', _benchmarkApiHandler.getSessionHandler);
    router.delete(
      '/sessions/<sessionId>',
      _benchmarkApiHandler.deleteSessionHandler,
    );

    router.all('/<ignored|.*>', (request) {
      return Response.notFound(
        '{"code":"PATH_NOT_FOUND","message":"Benchmark endpoint not found","details":{}}',
        headers: const <String, String>{'Content-Type': 'application/json'},
      );
    });

    return router.call;
  }
}
