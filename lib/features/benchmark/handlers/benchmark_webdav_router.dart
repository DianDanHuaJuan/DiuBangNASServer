import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'benchmark_webdav_handler.dart';

class BenchmarkWebdavRouter {
  BenchmarkWebdavRouter({
    required BenchmarkWebdavHandler benchmarkWebdavHandler,
  }) : _benchmarkWebdavHandler = benchmarkWebdavHandler;

  final BenchmarkWebdavHandler _benchmarkWebdavHandler;

  Handler get handler {
    final router = Router();

    router.put(
      '/<sessionId>/<resource>',
      _benchmarkWebdavHandler.putSessionHandler,
    );
    router.get(
      '/<sessionId>/<resource>',
      _benchmarkWebdavHandler.getSessionHandler,
    );
    router.head(
      '/<sessionId>/<resource>',
      _benchmarkWebdavHandler.headSessionHandler,
    );
    router.all('/<ignored|.*>', (request) {
      return Response.notFound(
        '{"code":"PATH_NOT_FOUND","message":"Benchmark WebDAV endpoint not found","details":{}}',
        headers: const {'Content-Type': 'application/json'},
      );
    });

    return router.call;
  }
}
