import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/auth/request_authorization.dart';
import '../../../core/debug/server_debug_logging.dart';
import '../../../core/storage/backup_catalog_service.dart';

class BackupPreflightHandler {
  BackupPreflightHandler({required BackupCatalogService backupCatalogService})
    : _backupCatalogService = backupCatalogService;

  final BackupCatalogService _backupCatalogService;

  Future<Response> handle(Request request) async {
    final deviceId = request.headers['x-nas-device-id']?.trim();
    final deviceName = request.headers['x-nas-device-name']?.trim();
    final authContext = requireAuthenticatedRequestContext(request);
    if (authContext?.isDevice == true) {
      final boundDeviceId = authContext!.deviceId;
      if (boundDeviceId == null || boundDeviceId.isEmpty) {
        return _errorResponse(
          403,
          'AUTH_FORBIDDEN',
          'Device backup requests require a bound deviceId',
        );
      }
      if (deviceId != null &&
          deviceId.isNotEmpty &&
          deviceId != boundDeviceId) {
        return _errorResponse(
          403,
          'DEVICE_ID_MISMATCH',
          'X-NAS-Device-Id does not match the authenticated device',
        );
      }
    }
    try {
      final payload = jsonDecode(await request.readAsString());
      if (payload is! Map) {
        return _errorResponse(400, 'INVALID_BODY', 'Request body must be JSON');
      }

      final rootId = payload['rootId'] as String? ?? 'fs';
      if (rootId != 'fs') {
        return _errorResponse(
          400,
          'INVALID_PARAMS',
          'Only the /fs root is supported',
        );
      }

      final rawItems = payload['items'];
      if (rawItems is! List) {
        return _errorResponse(
          400,
          'INVALID_PARAMS',
          'items must be an array of backup candidates',
        );
      }

      final items = rawItems.map(_parseItem).toList(growable: false);
      logServerDebugMessage(
        scope: 'BackupPreflightHandler',
        request: request,
        message: 'Backup preflight request received',
        details: <String, Object?>{
          'rootId': rootId,
          'itemCount': items.length,
          'deviceId': deviceId,
          'deviceName': deviceName,
        },
      );
      final decisions = await _backupCatalogService.preflight(items);
      final uploadCount = decisions
          .where((decision) => decision.action == 'upload')
          .length;
      final skipCount = decisions
          .where((decision) => decision.action == 'skip')
          .length;
      final needHashCount = decisions
          .where((decision) => decision.action == 'need_hash')
          .length;
      logServerDebugMessage(
        scope: 'BackupPreflightHandler',
        request: request,
        message: 'Backup preflight request completed',
        details: <String, Object?>{
          'rootId': rootId,
          'itemCount': items.length,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'uploadCount': uploadCount,
          'skipCount': skipCount,
          'needHashCount': needHashCount,
        },
      );

      return Response.ok(
        jsonEncode({
          'items': decisions
              .map(
                (decision) => {
                  'id': decision.id,
                  'action': decision.action,
                  'relativePath': decision.relativePath,
                  'reason': decision.reason,
                },
              )
              .toList(growable: false),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on FormatException catch (error) {
      logServerDebugMessage(
        scope: 'BackupPreflightHandler',
        request: request,
        message: 'Backup preflight request rejected',
        error: error,
        details: <String, Object?>{
          'deviceId': deviceId,
          'deviceName': deviceName,
          'reason': error.message,
        },
      );
      return _errorResponse(400, 'INVALID_PARAMS', error.message);
    } catch (error, stackTrace) {
      logServerDebugMessage(
        scope: 'BackupPreflightHandler',
        request: request,
        message: 'Backup preflight request failed',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'deviceId': deviceId,
          'deviceName': deviceName,
        },
      );
      return _errorResponse(500, 'INTERNAL_ERROR', error.toString());
    }
  }

  BackupPreflightItem _parseItem(dynamic rawItem) {
    if (rawItem is! Map) {
      throw const FormatException('Each preflight item must be an object');
    }
    final item = rawItem.map((key, value) => MapEntry('$key', value));
    final id = item['id'] as String?;
    final sourceFingerprint = item['sourceFingerprint'] as String?;
    final contentHash = item['contentHash'] as String?;
    final extension = item['extension'] as String? ?? '';
    final sizeBytes = item['sizeBytes'];
    final modifiedMs = item['modifiedMs'];

    if (id == null || id.trim().isEmpty) {
      throw const FormatException('Item id is required');
    }
    if (sourceFingerprint == null || sourceFingerprint.trim().isEmpty) {
      throw const FormatException('sourceFingerprint is required');
    }
    if (sizeBytes is! num || sizeBytes < 0) {
      throw const FormatException('sizeBytes must be a non-negative number');
    }
    if (modifiedMs is! num || modifiedMs < 0) {
      throw const FormatException('modifiedMs must be a non-negative number');
    }

    return BackupPreflightItem(
      id: id,
      sourceFingerprint: sourceFingerprint,
      contentHash: contentHash?.trim().isEmpty ?? true
          ? null
          : contentHash!.toLowerCase(),
      extension: extension,
      sizeBytes: sizeBytes.toInt(),
      modifiedMs: modifiedMs.toInt(),
    );
  }

  Response _errorResponse(int status, String code, String message) {
    return Response(
      status,
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
