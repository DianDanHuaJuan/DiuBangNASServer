// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';

const serverDebugRequestIdContextKey = 'nasServerDebugRequestId';
const serverDebugRequestIdHeader = 'x-nas-debug-request-id';

final Random _serverDebugRandom = Random.secure();

String createServerDebugRequestId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final suffix = _serverDebugRandom.nextInt(1 << 20).toRadixString(16);
  return 'req-$timestamp-$suffix';
}

String? readServerDebugRequestId(Request request) {
  final value = request.context[serverDebugRequestIdContextKey];
  return value is String && value.isNotEmpty ? value : null;
}

void logServerDebugMessage({
  required String scope,
  required Request request,
  required String message,
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  final payload = <String, Object?>{
    'scope': scope,
    'requestId': readServerDebugRequestId(request),
    'method': request.method,
    'uri': request.requestedUri.toString(),
    ...details,
  };
  final renderedMessage = '$message details=${jsonEncode(payload)}';

  developer.log(
    renderedMessage,
    name: 'nas_server.http',
    error: error,
    stackTrace: stackTrace,
  );
  print(renderedMessage);
  _appendToFile(renderedMessage);
}

void _appendToFile(String message) {
  try {
    final logFile = File('server_debug.log');
    final timestamp = DateTime.now().toIso8601String();
    logFile.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
  } catch (_) {}
}

Response buildServerInternalErrorResponse({
  required Request request,
  required String scope,
  required Object error,
  required StackTrace stackTrace,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  logServerDebugMessage(
    scope: scope,
    request: request,
    message: 'Unhandled request error',
    error: error,
    stackTrace: stackTrace,
    details: details,
  );

  return Response(
    500,
    body: jsonEncode(<String, dynamic>{
      'code': 'INTERNAL_ERROR',
      'message': 'Internal Server Error',
      'details': <String, dynamic>{
        'requestId': readServerDebugRequestId(request),
        'scope': scope,
        'error': '$error',
      },
    }),
    headers: const <String, String>{'Content-Type': 'application/json'},
  );
}
