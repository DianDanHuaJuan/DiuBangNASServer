import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/auth/auth_session_store.dart';
import '../../../core/auth/request_authorization.dart';
import '../data/relay_service.dart';

class RelayApiHandler {
  RelayApiHandler({required RelayService relayService})
    : _relayService = relayService;

  final RelayService _relayService;

  Future<Response> createTransferHandler(Request request) async {
    try {
      final authContext = _requireAuthContext(request);
      final body = await _readJsonObject(request);
      final targetClientIds = _readStringList(body['targetClientIds']);
      final fileName = _readRequiredString(body['fileName'], field: 'fileName');
      final fileSize = _readRequiredInt(body['fileSize'], field: 'fileSize');
      final transfer = await _relayService.createTransfer(
        authContext: authContext,
        targetClientIds: targetClientIds,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: body['mimeType'] as String?,
        checksum: body['checksum'] as String?,
        chunkSize: _readOptionalInt(body['chunkSize'], field: 'chunkSize'),
        senderClientId: body['senderClientId'] as String?,
      );
      return Response(
        201,
        body: jsonEncode({'transfer': transfer.toJson()}),
        headers: _jsonHeaders(),
      );
    } on RelayApiRequestException catch (error) {
      return _errorResponse(400, 'INVALID_REQUEST', error.message);
    } on FormatException {
      return _errorResponse(400, 'INVALID_REQUEST', 'Invalid JSON body');
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    }
  }

  Future<Response> cancelTransferHandler(
    Request request,
    String transferId,
  ) async {
    try {
      final authContext = _requireAuthContext(request);
      final transfer = await _relayService.cancelTransfer(
        authContext: authContext,
        transferId: transferId,
      );
      return Response.ok(
        jsonEncode({'transfer': transfer.toJson()}),
        headers: _jsonHeaders(),
      );
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    }
  }

  Future<Response> listHistoryHandler(Request request) async {
    try {
      final authContext = _requireAuthContext(request);
      final peerClientId = request.url.queryParameters['peerClientId']?.trim();
      if (peerClientId != null && peerClientId.isNotEmpty) {
        final limit = _readHistoryLimit(request.url.queryParameters['limit']);
        final before = _readOptionalDateTime(
          request.url.queryParameters['before'],
          field: 'before',
        );
        final page = await _relayService.listPeerHistory(
          authContext: authContext,
          peerClientId: peerClientId,
          limit: limit,
          beforeCreatedAt: before,
        );
        return Response.ok(
          jsonEncode({
            'transfers': page.transfers
                .map((transfer) => transfer.toJson())
                .toList(),
            'hasMore': page.hasMore,
          }),
          headers: _jsonHeaders(),
        );
      }

      final transfers = await _relayService.listHistory(
        authContext: authContext,
      );
      return Response.ok(
        jsonEncode({
          'transfers': transfers.map((transfer) => transfer.toJson()).toList(),
        }),
        headers: _jsonHeaders(),
      );
    } on RelayApiRequestException catch (error) {
      return _errorResponse(400, 'INVALID_REQUEST', error.message);
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    }
  }

  Future<Response> acknowledgeDownloadCompletedHandler(
    Request request,
    String transferId,
  ) async {
    try {
      final authContext = _requireAuthContext(request);
      final transfer = await _relayService.acknowledgeDownloadCompleted(
        authContext: authContext,
        transferId: transferId,
      );
      return Response.ok(
        jsonEncode({'transfer': transfer.toJson()}),
        headers: _jsonHeaders(),
      );
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    }
  }

  Future<Response> retryTransferHandler(
    Request request,
    String transferId,
  ) async {
    try {
      final authContext = _requireAuthContext(request);
      final transfer = await _relayService.retryTransfer(
        authContext: authContext,
        transferId: transferId,
      );
      return Response(
        201,
        body: jsonEncode({'transfer': transfer.toJson()}),
        headers: _jsonHeaders(),
      );
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    }
  }

  Future<Response> getTransferThumbnailHandler(
    Request request,
    String transferId,
  ) async {
    try {
      final authContext = _requireAuthContext(request);
      final payload = await _relayService.openThumbnailDownload(
        authContext: authContext,
        transferId: transferId,
      );
      return Response(
        payload.statusCode,
        body: payload.stream,
        headers: payload.headers,
      );
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    }
  }

  AuthenticatedRequestContext _requireAuthContext(Request request) {
    final authError = ensureAuthenticatedRequestContext(request);
    if (authError != null) {
      throw const RelayServiceException(
        statusCode: 401,
        code: 'AUTH_REQUIRED',
        message: 'Bearer token is required',
      );
    }
    return requireAuthenticatedRequestContext(request)!;
  }

  Future<Map<String, dynamic>> _readJsonObject(Request request) async {
    final body = await request.readAsString();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const RelayApiRequestException(
        'Request body must be a JSON object',
      );
    }
    return decoded;
  }

  List<String> _readStringList(Object? value) {
    if (value is! List) {
      throw const RelayApiRequestException(
        'targetClientIds must be an array of deviceId strings',
      );
    }
    final strings = value.whereType<String>().toList(growable: false);
    if (strings.length != value.length) {
      throw const RelayApiRequestException(
        'targetClientIds must only contain strings',
      );
    }
    return strings;
  }

  String _readRequiredString(Object? value, {required String field}) {
    if (value is! String || value.trim().isEmpty) {
      throw RelayApiRequestException('$field must be a non-empty string');
    }
    return value;
  }

  int _readRequiredInt(Object? value, {required String field}) {
    final parsed = _readOptionalInt(value, field: field);
    if (parsed == null) {
      throw RelayApiRequestException('$field must be an integer');
    }
    return parsed;
  }

  int? _readOptionalInt(Object? value, {required String field}) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw RelayApiRequestException('$field must be an integer');
  }

  int _readHistoryLimit(String? rawLimit) {
    if (rawLimit == null || rawLimit.trim().isEmpty) {
      return 20;
    }
    final parsed = int.tryParse(rawLimit.trim());
    if (parsed == null) {
      throw RelayApiRequestException('limit must be an integer');
    }
    return parsed.clamp(1, 100);
  }

  DateTime? _readOptionalDateTime(String? value, {required String field}) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) {
      throw RelayApiRequestException('$field must be an ISO8601 timestamp');
    }
    return parsed.toUtc();
  }

  Response _relayServiceErrorResponse(RelayServiceException error) {
    return Response(
      error.statusCode,
      body: jsonEncode({
        'code': error.code,
        'message': error.message,
        'details': error.details,
      }),
      headers: <String, String>{..._jsonHeaders(), ...error.headers},
    );
  }

  Response _errorResponse(int status, String code, String message) {
    return Response(
      status,
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
      headers: _jsonHeaders(),
    );
  }

  Map<String, String> _jsonHeaders() {
    return const <String, String>{'Content-Type': 'application/json'};
  }
}

class RelayApiRequestException implements Exception {
  const RelayApiRequestException(this.message);

  final String message;
}
