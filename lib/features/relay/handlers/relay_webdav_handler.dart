import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/auth/auth_session_store.dart';
import '../../../core/auth/request_authorization.dart';
import '../../../core/debug/server_debug_logging.dart';
import '../data/relay_service.dart';
import '../relay_contract.dart';

class RelayWebdavHandler {
  RelayWebdavHandler({required RelayService relayService})
    : _relayService = relayService;

  final RelayService _relayService;

  Future<Response> putTransferHandler(
    Request request,
    String transferId,
    String resource,
  ) async {
    final isThumbnail = resource == relayWebdavThumbnailSegment;
    try {
      final authContext = _requireAuthContext(request);
      if (isThumbnail) {
        await _relayService.uploadThumbnail(
          authContext: authContext,
          transferId: transferId,
          body: request.read(),
        );
        return Response.ok(
          '{"status":"ok"}',
          headers: _jsonHeaders(),
        );
      }
      _requirePayloadResource(resource);
      final transfer = await _relayService.uploadTransfer(
        authContext: authContext,
        transferId: transferId,
        body: request.read(),
      );
      return Response(
        201,
        body: jsonEncode({'transfer': transfer.toJson()}),
        headers: _jsonHeaders(),
      );
    } on RelayWebdavRequestException catch (error) {
      return _errorResponse(404, 'PATH_NOT_FOUND', error.message);
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'RelayWebdavHandler.putTransferHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'transferId': transferId,
          'resource': resource,
          'contentLength': request.headers['content-length'],
        },
      );
    }
  }

  Future<Response> getTransferHandler(
    Request request,
    String transferId,
    String resource,
  ) async {
    final isThumbnail = resource == relayWebdavThumbnailSegment;
    try {
      final authContext = _requireAuthContext(request);
      if (isThumbnail) {
        final payload = await _relayService.openThumbnailDownload(
          authContext: authContext,
          transferId: transferId,
        );
        return Response(
          payload.statusCode,
          body: payload.stream,
          headers: payload.headers,
        );
      }
      _requirePayloadResource(resource);
      final payload = await _relayService.openDownload(
        authContext: authContext,
        transferId: transferId,
        rangeHeader: request.headers['Range'],
      );
      return Response(
        payload.statusCode,
        body: payload.stream,
        headers: payload.headers,
      );
    } on RelayWebdavRequestException catch (error) {
      return _errorResponse(404, 'PATH_NOT_FOUND', error.message);
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'RelayWebdavHandler.getTransferHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'transferId': transferId,
          'resource': resource,
          'range': request.headers['Range'],
        },
      );
    }
  }

  Future<Response> headTransferHandler(
    Request request,
    String transferId,
    String resource,
  ) async {
    final isThumbnail = resource == relayWebdavThumbnailSegment;
    try {
      final authContext = _requireAuthContext(request);
      if (isThumbnail) {
        final payload = await _relayService.describeThumbnailDownload(
          authContext: authContext,
          transferId: transferId,
        );
        return Response(payload.statusCode, body: '', headers: payload.headers);
      }
      _requirePayloadResource(resource);
      final payload = await _relayService.describeDownload(
        authContext: authContext,
        transferId: transferId,
        rangeHeader: request.headers['Range'],
      );
      return Response(payload.statusCode, body: '', headers: payload.headers);
    } on RelayWebdavRequestException catch (error) {
      return _errorResponse(404, 'PATH_NOT_FOUND', error.message);
    } on RelayServiceException catch (error) {
      return _relayServiceErrorResponse(error);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'RelayWebdavHandler.headTransferHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'transferId': transferId,
          'resource': resource,
          'range': request.headers['Range'],
        },
      );
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

  void _requirePayloadResource(String resource) {
    if (resource == relayWebdavPayloadSegment) {
      return;
    }
    throw RelayWebdavRequestException(
      'Relay resource "$resource" was not found',
    );
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

class RelayWebdavRequestException implements Exception {
  const RelayWebdavRequestException(this.message);

  final String message;
}
