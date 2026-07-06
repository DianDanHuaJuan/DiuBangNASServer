import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'application/benchmark_service.dart';
import 'benchmark_feature_flags.dart';
import 'handlers/benchmark_api_handler.dart';
import 'handlers/benchmark_api_router.dart';
import 'handlers/benchmark_webdav_handler.dart';
import 'handlers/benchmark_webdav_router.dart';

class BenchmarkFeatureBundle {
  const BenchmarkFeatureBundle({
    required this.apiRouter,
    required this.webdavRouter,
    required this.benchmarkService,
  });

  final BenchmarkApiRouter apiRouter;
  final BenchmarkWebdavRouter webdavRouter;
  final BenchmarkService benchmarkService;
}

abstract final class BenchmarkFeature {
  static const bool enabled = BenchmarkFeatureFlags.enabled;

  static BenchmarkFeatureBundle? _bundle;
  static HttpServer? _httpServer;

  static Future<BenchmarkFeatureBundle?> createBundle({
    required String rootPath,
    int? httpPort,
  }) async {
    if (!enabled) {
      return null;
    }
    final benchmarkService = BenchmarkService(rootPath: rootPath);
    await benchmarkService.initialize();
    final benchmarkApiHandler = BenchmarkApiHandler(
      benchmarkService: benchmarkService,
      httpPort: httpPort,
    );
    final benchmarkWebdavHandler = BenchmarkWebdavHandler(
      benchmarkService: benchmarkService,
    );
    final bundle = BenchmarkFeatureBundle(
      apiRouter: BenchmarkApiRouter(benchmarkApiHandler: benchmarkApiHandler),
      webdavRouter: BenchmarkWebdavRouter(
        benchmarkWebdavHandler: benchmarkWebdavHandler,
      ),
      benchmarkService: benchmarkService,
    );
    _bundle = bundle;
    return bundle;
  }

  static Future<int> startHttpServer({required int port}) async {
    final bundle = _bundle;
    if (bundle == null) return 0;

    await stopHttpServer();

    final router = Router();
    router.mount('/api/v1/debug/benchmark/', bundle.apiRouter.handler);
    router.mount('/dav/benchmark/', bundle.webdavRouter.handler);
    router.all('/<ignored|.*>', (request) {
      return Response.notFound(
        '{"code":"PATH_NOT_FOUND","message":"Benchmark HTTP endpoint not found","details":{}}',
        headers: const {'Content-Type': 'application/json'},
      );
    });

    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    shelf_io.serveRequests(_httpServer!, router.call);
    return _httpServer!.port;
  }

  static Future<void> stopHttpServer() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
  }
}
