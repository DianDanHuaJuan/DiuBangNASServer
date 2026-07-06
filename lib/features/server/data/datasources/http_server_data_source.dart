// ignore_for_file: avoid_print

// 文件输入：shelf, shelf_router, AuthRouter, ApiRouter, WebdavMethodRouter
// 文件职责：创建和管理 shelf HttpServer 实例，注册路由和中间件
// 文件对外接口：HttpServerDataSource
// 文件包含：HttpServerDataSource
import 'dart:developer' as developer;
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../../../../core/debug/server_debug_logging.dart';
import '../../../../core/auth/auth_headers.dart';
import '../../../../core/transfer/server_transfer_tuning.dart';
import '../../../../features/relay/relay_contract.dart';
import 'server_activity_tracker.dart';

class HttpServerDataSource {
  HttpServerDataSource({
    required shelf.Handler authHandler,
    required shelf.Handler pairingHandler,
    required shelf.Handler apiHandler,
    required shelf.Handler? benchmarkWebdavHandler,
    required shelf.Handler relayWebdavHandler,
    required shelf.Handler webdavHandler,
    ServerActivityTracker? activityTracker,
  }) : _authHandler = authHandler,
       _pairingHandler = pairingHandler,
       _apiHandler = apiHandler,
       _benchmarkWebdavHandler = benchmarkWebdavHandler,
       _relayWebdavHandler = relayWebdavHandler,
       _webdavHandler = webdavHandler,
       _activityTracker = activityTracker;

  final shelf.Handler _authHandler;
  final shelf.Handler _pairingHandler;
  final shelf.Handler _apiHandler;
  final shelf.Handler? _benchmarkWebdavHandler;
  final shelf.Handler _relayWebdavHandler;
  final shelf.Handler _webdavHandler;
  final ServerActivityTracker? _activityTracker;

  HttpServer? _server;
  bool _isRunning = false;
  String? _boundIp;

  final List<String> _requestLogs = [];

  List<String> get requestLogs => List.unmodifiable(_requestLogs);

  void _addLog(String log) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final formatted = '[$timestamp] $log';
    _requestLogs.add(formatted);
    if (_requestLogs.length > 100) {
      _requestLogs.removeAt(0);
    }
    stdout.writeln(formatted);
  }

  Future<void> start({
    required int port,
    required String localIp,
    required SecurityContext securityContext,
  }) async {
    if (_isRunning) {
      await stop();
    }

    _requestLogs.clear();
    _addLog('Server starting on port $port...');

    final router = Router();

    router.mount('/api/v1/auth/', _authHandler);
    router.mount('/api/v1/pairing/', _pairingHandler);
    router.mount('/api/v1/', _apiHandler);
    final benchmarkWebdavHandler = _benchmarkWebdavHandler;
    if (benchmarkWebdavHandler != null) {
      router.mount('/dav/benchmark/', benchmarkWebdavHandler);
    }
    router.mount('/dav/relay/', _relayWebdavHandler);
    router.mount('/dav/', _webdavHandler);

    router.all('/<ignored|.*>', (request) {
      _addLog('${request.method} ${request.url.path} - 404 Not Found');
      return shelf.Response.notFound(
        '{"code":"PATH_NOT_FOUND","message":"Not found","details":{}}',
        headers: {'Content-Type': 'application/json'},
      );
    });

    final pipeline = const shelf.Pipeline()
        .addMiddleware(_loggingMiddleware())
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    _server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      port,
      securityContext,
      shared: true,
      backlog: 512,
    );
    _server!.autoCompress = false;
    _server!.idleTimeout = const Duration(seconds: 120);
    shelf_io.serveRequests(_server!, pipeline);

    _boundIp = localIp;
    _isRunning = true;
    _addLog('Server started on https://$localIp:${_server!.port}');
  }

  shelf.Middleware _loggingMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        final activityLease = _activityTracker?.beginRequest(request);
        final requestId = createServerDebugRequestId();
        final isHotTransferPath = ServerTransferTuning.isHotTransferPath(
          request.url.path,
        );
        final requestWithId = request.change(
          context: <String, Object?>{
            ...request.context,
            serverDebugRequestIdContextKey: requestId,
          },
        );
        if (!isHotTransferPath) {
          _addLog('[$requestId] ${request.method} ${request.url.path}');
        }
        try {
          final response = await innerHandler(requestWithId);
          final shouldAnnotateResponse =
              !isHotTransferPath || response.statusCode >= 400;
          final responseWithId = shouldAnnotateResponse
              ? response.change(
                  headers: <String, String>{
                    ...response.headers,
                    serverDebugRequestIdHeader: requestId,
                  },
                )
              : response;
          if (!isHotTransferPath || response.statusCode >= 400) {
            _addLog(
              '[$requestId] ${request.method} ${request.url.path} - ${response.statusCode}',
            );
          }
          if (response.statusCode >= 500) {
            final message =
                'Request completed with server error '
                'requestId=$requestId method=${request.method} '
                'path=${request.url.path} status=${response.statusCode}';
            developer.log(message, name: 'nas_server.http');
            print(message);
          }
          return activityLease?.bind(responseWithId) ?? responseWithId;
        } catch (e, stackTrace) {
          activityLease?.close();
          _addLog(
            '[$requestId] ${request.method} ${request.url.path} - ERROR: $e',
          );
          if (request.url.path == 'api/v1/realtime/ws') {
            final message =
                'Realtime websocket request aborted requestId=$requestId '
                'method=${request.method} path=${request.url.path}';
            developer.log(
              message,
              name: 'nas_server.http',
              level: 800,
              error: e,
              stackTrace: stackTrace,
            );
            rethrow;
          }
          final message =
              'Unhandled middleware exception requestId=$requestId '
              'method=${request.method} path=${request.url.path}';
          developer.log(
            message,
            name: 'nas_server.http',
            error: e,
            stackTrace: stackTrace,
          );
          print(message);
          rethrow;
        }
      };
    };
  }

  Future<void> stop() async {
    _addLog('Server stopping...');
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
    }
    _isRunning = false;
    _boundIp = null;
    _addLog('Server stopped');
  }

  bool get isRunning => _isRunning;

  int? get port => _server?.port;

  String? get boundIp => _boundIp;

  shelf.Middleware _corsMiddleware() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        if (request.method == 'OPTIONS') {
          _addLog('OPTIONS ${request.url.path} - CORS preflight');
          return shelf.Response.ok(
            '',
            headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods':
                  'GET, POST, PUT, DELETE, MKCOL, PROPFIND, HEAD, COPY, MOVE, OPTIONS, PROPPATCH, REPORT',
              'Access-Control-Allow-Headers':
                  'Authorization, Content-Type, Depth, Destination, Range, Host, Accept, If-Range, If-Modified-Since, $deviceIdHeaderName, $deviceNameHeaderName, $relayChunkChecksumHeader, $relayChunkStartHeader, $relayChunkEndHeader',
              'Access-Control-Allow-Credentials': 'true',
              'Access-Control-Max-Age': '86400',
            },
          );
        }
        final response = await innerHandler(request);
        return response.change(
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods':
                'GET, POST, PUT, DELETE, MKCOL, PROPFIND, HEAD, COPY, MOVE, OPTIONS, PROPPATCH, REPORT',
            'Access-Control-Allow-Headers':
                'Authorization, Content-Type, Depth, Destination, Range, Host, Accept, If-Range, If-Modified-Since, $deviceIdHeaderName, $deviceNameHeaderName, $relayChunkChecksumHeader, $relayChunkStartHeader, $relayChunkEndHeader',
            'Access-Control-Allow-Credentials': 'true',
            'Access-Control-Expose-Headers':
                'DAV, Content-Length, Content-Range, Accept-Ranges, Content-Type, Last-Modified, Content-Disposition',
          },
        );
      };
    };
  }
}
