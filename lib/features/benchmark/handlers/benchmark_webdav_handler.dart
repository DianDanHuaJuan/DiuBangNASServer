import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/debug/server_debug_logging.dart';
import '../application/benchmark_service.dart';

class BenchmarkWebdavHandler {
  BenchmarkWebdavHandler({required BenchmarkService benchmarkService})
    : _benchmarkService = benchmarkService;

  final BenchmarkService _benchmarkService;

  Future<Response> putSessionHandler(
    Request request,
    String sessionId,
    String resource,
  ) async {
    try {
      _requirePayloadResource(resource);
      final session = await _benchmarkService.acceptUpload(
        sessionId: sessionId,
        source: request.read(),
      );
      return Response(
        200,
        body: jsonEncode(<String, dynamic>{'session': session.toJson()}),
        headers: const <String, String>{'Content-Type': 'application/json'},
      );
    } on BenchmarkServiceException catch (error) {
      return _errorResponse(error.statusCode, error.code, error.message);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'BenchmarkWebdavHandler.putSessionHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'sessionId': sessionId,
          'resource': resource,
        },
      );
    }
  }

  Future<Response> getSessionHandler(
    Request request,
    String sessionId,
    String resource,
  ) async {
    try {
      _requirePayloadResource(resource);
      final payload = await _benchmarkService.openDownload(
        sessionId,
        rangeHeader: request.headers['Range'],
      );
      return Response(
        payload.statusCode,
        body: payload.stream,
        headers: payload.headers,
      );
    } on BenchmarkServiceException catch (error) {
      return _errorResponse(
        error.statusCode,
        error.code,
        error.message,
        headers: error.headers,
      );
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'BenchmarkWebdavHandler.getSessionHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'sessionId': sessionId,
          'resource': resource,
          'range': request.headers['Range'],
        },
      );
    }
  }

  Future<Response> headSessionHandler(
    Request request,
    String sessionId,
    String resource,
  ) async {
    try {
      _requirePayloadResource(resource);
      final payload = await _benchmarkService.describeDownload(
        sessionId,
        rangeHeader: request.headers['Range'],
      );
      return Response(payload.statusCode, body: '', headers: payload.headers);
    } on BenchmarkServiceException catch (error) {
      return _errorResponse(
        error.statusCode,
        error.code,
        error.message,
        headers: error.headers,
      );
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'BenchmarkWebdavHandler.headSessionHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'sessionId': sessionId,
          'resource': resource,
          'range': request.headers['Range'],
        },
      );
    }
  }

  void _requirePayloadResource(String resource) {
    if (resource == 'payload') {
      return;
    }
    throw const BenchmarkServiceException(
      statusCode: 404,
      code: 'BENCHMARK_RESOURCE_NOT_FOUND',
      message: 'Benchmark WebDAV resource was not found',
    );
  }

  Response _errorResponse(
    int statusCode,
    String code,
    String message, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return Response(
      statusCode,
      body: jsonEncode(<String, dynamic>{
        'code': code,
        'message': message,
        'details': <String, dynamic>{},
      }),
      headers: <String, String>{'Content-Type': 'application/json', ...headers},
    );
  }
}
