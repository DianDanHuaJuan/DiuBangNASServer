import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/debug/server_debug_logging.dart';
import '../application/benchmark_service.dart';
import '../domain/benchmark_models.dart';

class BenchmarkApiHandler {
  BenchmarkApiHandler({
    required BenchmarkService benchmarkService,
    this.httpPort,
  }) : _benchmarkService = benchmarkService;

  final BenchmarkService _benchmarkService;
  final int? httpPort;

  Future<Response> createSessionHandler(Request request) async {
    try {
      final body = await _readJsonBody(request);
      final mode = BenchmarkTransferMode.parse(
        body['mode']?.toString() ?? 'upload',
      );
      final transportType = BenchmarkTransportType.parse(
        body['transportType']?.toString() ?? 'direct',
      );
      final fileSizeBytes = _readRequiredInt(
        body['fileSizeBytes'],
        field: 'fileSizeBytes',
      );
      final session = await _benchmarkService.createSession(
        mode: mode,
        fileSizeBytes: fileSizeBytes,
        transportType: transportType,
      );
      final endpoints = <String, dynamic>{
        'uploadPath':
            '/api/v1/debug/benchmark/sessions/${session.sessionId}/upload',
        'downloadPath':
            '/api/v1/debug/benchmark/sessions/${session.sessionId}/download',
        'davUploadPath': '/dav/benchmark/${session.sessionId}/payload',
        'davDownloadPath': '/dav/benchmark/${session.sessionId}/payload',
        'reportPath':
            '/api/v1/debug/benchmark/sessions/${session.sessionId}/client-report',
        'resultPath': '/api/v1/debug/benchmark/sessions/${session.sessionId}',
        if (httpPort != null) 'httpPort': httpPort,
      };
      return _jsonResponse(200, <String, dynamic>{
        'session': session.toJson(),
        'endpoints': endpoints,
      });
    } on FormatException catch (error) {
      return _errorResponse(400, 'BENCHMARK_REQUEST_INVALID', error.message);
    } on BenchmarkServiceException catch (error) {
      return _errorResponse(error.statusCode, error.code, error.message);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'BenchmarkApiHandler.createSessionHandler',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Response> uploadHandler(Request request, String sessionId) async {
    try {
      final session = await _benchmarkService.acceptUpload(
        sessionId: sessionId,
        source: request.read(),
      );
      return _jsonResponse(200, <String, dynamic>{'session': session.toJson()});
    } on BenchmarkServiceException catch (error) {
      return _errorResponse(error.statusCode, error.code, error.message);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'BenchmarkApiHandler.uploadHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{'sessionId': sessionId},
      );
    }
  }

  Future<Response> downloadHandler(Request request, String sessionId) async {
    try {
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
        scope: 'BenchmarkApiHandler.downloadHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{'sessionId': sessionId},
      );
    }
  }

  Future<Response> headDownloadHandler(
    Request request,
    String sessionId,
  ) async {
    try {
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
        scope: 'BenchmarkApiHandler.headDownloadHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{'sessionId': sessionId},
      );
    }
  }

  Future<Response> reportClientHandler(
    Request request,
    String sessionId,
  ) async {
    try {
      final body = await _readJsonBody(request);
      final report = body['clientReport'];
      if (report is! Map) {
        throw const FormatException('clientReport must be a JSON object');
      }
      final session = await _benchmarkService.reportClientMetrics(
        sessionId: sessionId,
        clientReport: report.map((key, value) => MapEntry('$key', value)),
      );
      return _jsonResponse(200, <String, dynamic>{'session': session.toJson()});
    } on FormatException catch (error) {
      return _errorResponse(400, 'BENCHMARK_REQUEST_INVALID', error.message);
    } on BenchmarkServiceException catch (error) {
      return _errorResponse(error.statusCode, error.code, error.message);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'BenchmarkApiHandler.reportClientHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{'sessionId': sessionId},
      );
    }
  }

  Future<Response> getSessionHandler(Request request, String sessionId) async {
    try {
      final session = await _benchmarkService.getSessionResult(sessionId);
      return _jsonResponse(200, <String, dynamic>{'session': session.toJson()});
    } on BenchmarkServiceException catch (error) {
      return _errorResponse(error.statusCode, error.code, error.message);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'BenchmarkApiHandler.getSessionHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{'sessionId': sessionId},
      );
    }
  }

  Future<Response> deleteSessionHandler(
    Request request,
    String sessionId,
  ) async {
    await _benchmarkService.deleteSession(sessionId);
    return Response(
      204,
      headers: const <String, String>{'Content-Length': '0'},
    );
  }

  Future<Map<String, dynamic>> _readJsonBody(Request request) async {
    final rawBody = (await request.readAsString()).trim();
    if (rawBody.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(rawBody);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry('$key', value));
    }
    throw const FormatException('Request body must be a JSON object');
  }

  int _readRequiredInt(dynamic value, {required String field}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw FormatException('$field must be an integer');
  }

  Response _jsonResponse(int statusCode, Map<String, dynamic> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: const <String, String>{'Content-Type': 'application/json'},
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
