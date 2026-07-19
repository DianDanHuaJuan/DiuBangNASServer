// 文件输入：WebDAV PUT 请求、目标根目录
// 文件职责：处理 WebDAV PUT 上传，支持冲突策略与流式写入
// 文件对外接口：PutHandler
// 文件包含：PutHandler
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import '../../../core/auth/auth_headers.dart';
import '../../../core/auth/request_authorization.dart';
import '../../../core/debug/server_debug_logging.dart';
import '../../../core/streams/buffered_byte_stream_transformer.dart';
import '../../../core/storage/backup_catalog_service.dart';
import '../../../core/storage/path_mapper.dart';
import '../../../core/storage/thumbnail_service.dart';
import '../../../core/transfer/server_transfer_tuning.dart';

class PutHandler {
  PutHandler({
    required String rootPath,
    void Function()? onFilesChanged,
    Future<void> Function(String relativePath)? onPathChanged,
    BackupCatalogService? backupCatalogService,
    ThumbnailService? thumbnailService,
  }) : _rootPath = rootPath,
       _pathMapper = PathMapper(rootPath: rootPath),
       _random = Random(),
       _onFilesChanged = onFilesChanged,
       _onPathChanged = onPathChanged,
       _backupCatalogService = backupCatalogService,
       _thumbnailService = thumbnailService;

  static const String _conflictPolicyHeader = 'x-nas-conflict-policy';
  static const String _backupMetadataHeader = 'x-nas-backup-metadata';

  final String _rootPath;
  final PathMapper _pathMapper;
  final Random _random;
  final void Function()? _onFilesChanged;
  final Future<void> Function(String relativePath)? _onPathChanged;
  final BackupCatalogService? _backupCatalogService;
  final ThumbnailService? _thumbnailService;

  Future<Response> handle(Request request) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = _pathMapper.resolve(
        request.url.path,
        allowRoot: true,
        allowNestedPaths: false,
      );
    } on PathMappingException catch (error) {
      return _buildPathErrorResponse(error);
    }

    if (mappedPath.root == ServerPathRoot.library) {
      return Response(405, body: 'Method Not Allowed');
    }

    if (mappedPath.isRoot || mappedPath.fileName == null) {
      return Response(400, body: 'Bad Request: Cannot upload to directory');
    }

    final requestedRelativePath = mappedPath.relativePath;
    final requestedFileName = mappedPath.fileName!;
    final requestedLocalPath = mappedPath.localPath!;
    final requestedFile = File(requestedLocalPath);
    final conflictPolicy = _parseConflictPolicy(
      request.headers[_conflictPolicyHeader],
    );
    final backupMetadataHeaderValue = request.headers[_backupMetadataHeader];
    final deviceId = request.headers[deviceIdHeaderName]?.trim();
    final deviceName = request.headers[deviceNameHeaderName]?.trim();
    final authContext = requireAuthenticatedRequestContext(request);
    if (authContext?.isDevice == true) {
      final boundDeviceId = authContext!.deviceId;
      if (boundDeviceId == null || boundDeviceId.isEmpty) {
        return Response(
          403,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': 'AUTH_FORBIDDEN',
            'message': 'Device uploads require a bound deviceId',
            'details': {},
          }),
        );
      }
      if (deviceId != null &&
          deviceId.isNotEmpty &&
          deviceId != boundDeviceId) {
        return Response(
          403,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': 'DEVICE_ID_MISMATCH',
            'message': 'X-NAS-Device-Id does not match the authenticated device',
            'details': {},
          }),
        );
      }
    }
    final backupMetadataHeaderPresent =
        backupMetadataHeaderValue != null &&
        backupMetadataHeaderValue.trim().isNotEmpty;
    final backupMetadata = _parseBackupMetadata(backupMetadataHeaderValue);
    if (backupMetadataHeaderPresent && backupMetadata == null) {
      logServerDebugMessage(
        scope: 'PutHandler',
        request: request,
        message: 'Backup upload metadata header ignored',
        details: <String, Object?>{
          'relativePath': requestedRelativePath,
          'contentLength': request.headers['content-length'],
          'deviceId': deviceId,
          'deviceName': deviceName,
        },
      );
    }

    try {
      final rootDir = Directory(_rootPath);
      if (!await rootDir.exists()) {
        await rootDir.create(recursive: true);
      }

      if (conflictPolicy == _UploadConflictPolicy.fail &&
          await _pathExists(requestedLocalPath)) {
        return _buildConflictResponse(
          fileName: requestedFileName,
          relativePath: requestedRelativePath,
        );
      }

      final stagingFile = File(await _buildStagingFilePath(rootDir.path));
      if (backupMetadata != null &&
          authContext?.isDevice == true &&
          authContext!.deviceId != null &&
          backupMetadata.deviceId != authContext.deviceId) {
        return Response(
          403,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': 'DEVICE_ID_MISMATCH',
            'message':
                'Backup metadata deviceId does not match the authenticated device',
            'details': {},
          }),
        );
      }
      if (backupMetadata != null) {
        logServerDebugMessage(
          scope: 'PutHandler',
          request: request,
          message: 'Backup upload request started',
          details: <String, Object?>{
            'relativePath': requestedRelativePath,
            'contentLength': request.headers['content-length'],
            'deviceId': deviceId,
            'deviceName': deviceName,
            'sourceFingerprint': backupMetadata.sourceFingerprint,
            'contentHash': backupMetadata.contentHash,
          },
        );
      }

      try {
        await _streamRequestToFile(request.read(), stagingFile);
        final result = await _finalizeUpload(
          stagingFile: stagingFile,
          requestedFile: requestedFile,
          requestedRelativePath: requestedRelativePath,
          conflictPolicy: conflictPolicy,
        );
        if (backupMetadata != null) {
          await _backupCatalogService?.registerUpload(
            BackupCatalogRegistration(
              sourceFingerprint: backupMetadata.sourceFingerprint,
              contentHash: backupMetadata.contentHash,
              deviceId: backupMetadata.deviceId,
              sourceId: backupMetadata.sourceId,
              sizeBytes: backupMetadata.sizeBytes,
              modifiedMs: backupMetadata.modifiedMs,
              relativePath: result.relativePath,
              deviceName: deviceName,
            ),
          );
        }
        if (backupMetadata != null) {
          logServerDebugMessage(
            scope: 'PutHandler',
            request: request,
            message: 'Backup upload request completed',
            details: <String, Object?>{
              'requestedRelativePath': requestedRelativePath,
              'resolvedRelativePath': result.relativePath,
              'statusCode': result.statusCode,
              'overwritten': result.overwritten,
              'renamed': result.renamed,
              'deviceId': deviceId,
              'deviceName': deviceName,
              'sourceFingerprint': backupMetadata.sourceFingerprint,
              'contentHash': backupMetadata.contentHash,
            },
          );
        }
        _onFilesChanged?.call();
        final onPathChanged = _onPathChanged;
        if (onPathChanged != null) {
          await onPathChanged(result.relativePath);
        }
        return _buildSuccessResponse(result);
      } on _UploadConflictException catch (error) {
        await _deleteIfExists(stagingFile);
        return _buildConflictResponse(
          fileName: error.fileName,
          relativePath: error.relativePath,
        );
      } catch (_) {
        await _deleteIfExists(stagingFile);
        rethrow;
      }
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'PutHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'relativePath': requestedRelativePath,
          'contentLength': request.headers['content-length'],
          'conflictPolicy': '$conflictPolicy',
        },
      );
    }
  }

  Future<void> _streamRequestToFile(
    Stream<List<int>> source,
    File targetFile,
  ) async {
    final sink = targetFile.openWrite();
    try {
      await for (final chunk in bufferByteStream(
        source,
        ServerTransferTuning.uploadStreamBufferSize,
      )) {
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
  }

  Future<_PutResult> _finalizeUpload({
    required File stagingFile,
    required File requestedFile,
    required String requestedRelativePath,
    required _UploadConflictPolicy conflictPolicy,
  }) async {
    final requestedFileName = p.basename(requestedFile.path);
    final requestedEntityExists = await _pathExists(requestedFile.path);

    switch (conflictPolicy) {
      case _UploadConflictPolicy.fail:
        if (requestedEntityExists) {
          throw _UploadConflictException(
            fileName: requestedFileName,
            relativePath: requestedRelativePath,
          );
        }
        final finalFile = await _moveStagingFile(
          stagingFile,
          requestedFile.path,
          conflictPath: requestedRelativePath,
        );
        return _PutResult(
          statusCode: 201,
          relativePath: requestedRelativePath,
          fileName: p.basename(finalFile.path),
        );
      case _UploadConflictPolicy.overwrite:
        if (requestedEntityExists && !await requestedFile.exists()) {
          throw _UploadConflictException(
            fileName: requestedFileName,
            relativePath: requestedRelativePath,
          );
        }
        if (requestedEntityExists) {
          await _deleteCachedThumbnailsForFile(
            requestedFile,
            requestedRelativePath,
          );
        }
        final finalFile = await _moveStagingFileWithOverwrite(
          stagingFile,
          requestedFile.path,
        );
        return _PutResult(
          statusCode: requestedEntityExists ? 200 : 201,
          relativePath: requestedRelativePath,
          fileName: p.basename(finalFile.path),
          overwritten: requestedEntityExists,
        );
      case _UploadConflictPolicy.rename:
        final finalFile = await _moveStagingFileToAvailablePath(
          stagingFile,
          requestedFile.path,
        );
        final finalRelativePath = '/${p.basename(finalFile.path)}';
        return _PutResult(
          statusCode: requestedEntityExists ? 201 : 201,
          relativePath: finalRelativePath,
          fileName: p.basename(finalFile.path),
          renamed: finalRelativePath != requestedRelativePath,
        );
    }
  }

  Future<File> _moveStagingFile(
    File stagingFile,
    String destinationPath, {
    required String conflictPath,
  }) async {
    try {
      return await stagingFile.rename(destinationPath);
    } on FileSystemException {
      if (await _pathExists(destinationPath)) {
        throw _UploadConflictException(
          fileName: p.basename(destinationPath),
          relativePath: conflictPath,
        );
      }
      rethrow;
    }
  }

  Future<File> _moveStagingFileWithOverwrite(
    File stagingFile,
    String destinationPath,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final destinationFile = File(destinationPath);
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }

      try {
        return await stagingFile.rename(destinationPath);
      } on FileSystemException {
        if (attempt == 2) {
          rethrow;
        }
      }
    }

    throw StateError('Failed to move staging file to $destinationPath');
  }

  Future<File> _moveStagingFileToAvailablePath(
    File stagingFile,
    String requestedPath,
  ) async {
    String candidatePath = requestedPath;
    var counter = 1;

    while (true) {
      if (await _pathExists(candidatePath)) {
        candidatePath = _buildRenamedPath(requestedPath, counter);
        counter += 1;
        continue;
      }

      try {
        return await stagingFile.rename(candidatePath);
      } on FileSystemException {
        if (await _pathExists(candidatePath)) {
          candidatePath = _buildRenamedPath(requestedPath, counter);
          counter += 1;
          continue;
        }
        rethrow;
      }
    }
  }

  String _buildRenamedPath(String originalPath, int counter) {
    final dir = p.dirname(originalPath);
    final extension = p.extension(originalPath);
    final baseName = extension.isEmpty
        ? p.basename(originalPath)
        : p.basenameWithoutExtension(originalPath);
    final renamedFileName = '$baseName ($counter)$extension';
    return p.join(dir, renamedFileName);
  }

  Future<String> _buildStagingFilePath(String rootPath) async {
    while (true) {
      final candidateName =
          '.nas-upload-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}.part';
      final candidatePath = p.join(rootPath, candidateName);
      if (!await _pathExists(candidatePath)) {
        return candidatePath;
      }
    }
  }

  Future<bool> _pathExists(String path) async {
    return await File(path).exists() || await Directory(path).exists();
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _deleteCachedThumbnailsForFile(
    File file,
    String relativePath,
  ) async {
    final thumbnailService = _thumbnailService;
    if (thumbnailService == null) {
      return;
    }

    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      return;
    }

    await thumbnailService.deleteThumbnails(
      '/fs$relativePath',
      sourceModifiedMs: stat.modified.millisecondsSinceEpoch,
      sourceSizeBytes: stat.size,
    );
  }

  _UploadConflictPolicy _parseConflictPolicy(String? headerValue) {
    return switch (headerValue?.trim().toLowerCase()) {
      'overwrite' => _UploadConflictPolicy.overwrite,
      'rename' || 'auto-rename' || 'autorename' => _UploadConflictPolicy.rename,
      _ => _UploadConflictPolicy.fail,
    };
  }

  _UploadBackupMetadata? _parseBackupMetadata(String? headerValue) {
    if (headerValue == null || headerValue.trim().isEmpty) {
      return null;
    }

    try {
      final normalized = base64Url.normalize(headerValue.trim());
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded);
      if (payload is! Map) {
        return null;
      }
      final item = payload.map((key, value) => MapEntry('$key', value));
      final sourceFingerprint = item['sourceFingerprint'] as String?;
      final contentHash = item['contentHash'] as String?;
      final deviceId = item['deviceId'] as String?;
      final sourceId = item['sourceId'] as String?;
      final sizeBytes = item['sizeBytes'];
      final modifiedMs = item['modifiedMs'];
      if (sourceFingerprint == null ||
          contentHash == null ||
          deviceId == null ||
          sourceId == null ||
          sizeBytes is! num ||
          modifiedMs is! num) {
        return null;
      }

      return _UploadBackupMetadata(
        sourceFingerprint: sourceFingerprint,
        contentHash: contentHash.toLowerCase(),
        deviceId: deviceId,
        sourceId: sourceId,
        sizeBytes: sizeBytes.toInt(),
        modifiedMs: modifiedMs.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  Response _buildSuccessResponse(_PutResult result) {
    return Response(
      result.statusCode,
      body: jsonEncode({
        'success': true,
        'file': {
          'rootId': 'fs',
          'relativePath': result.relativePath,
          'name': result.fileName,
        },
        'overwritten': result.overwritten,
        'renamed': result.renamed,
      }),
      headers: _buildSuccessHeaders(result),
    );
  }

  /// HTTP headers must be US-ASCII. Keep Unicode in the JSON body;
  /// percent-encode custom headers (omit if encoded value is too large).
  Map<String, String> _buildSuccessHeaders(_PutResult result) {
    const maxEncodedHeaderChars = 2048;
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final encodedPath = Uri.encodeComponent(result.relativePath);
    final encodedName = Uri.encodeComponent(result.fileName);
    if (encodedPath.length <= maxEncodedHeaderChars) {
      headers['X-NAS-Resolved-Path'] = encodedPath;
    }
    if (encodedName.length <= maxEncodedHeaderChars) {
      headers['X-NAS-Resolved-Name'] = encodedName;
    }
    return headers;
  }

  Response _buildConflictResponse({
    required String fileName,
    required String relativePath,
  }) {
    return Response(
      409,
      body: jsonEncode({
        'code': 'FILE_ALREADY_EXISTS',
        'message': 'A file with the same name already exists.',
        'file': {
          'rootId': 'fs',
          'relativePath': relativePath,
          'name': fileName,
        },
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Response _buildPathErrorResponse(PathMappingException error) {
    return switch (error.code) {
      PathMappingErrorCode.unsupportedRoot => Response(403, body: 'Forbidden'),
      PathMappingErrorCode.rootPathNotAllowed => Response(
        400,
        body: 'Bad Request: Cannot upload to directory',
      ),
      PathMappingErrorCode.nestedPathNotAllowed => Response(
        400,
        body: 'Bad Request: Subdirectories are not allowed',
      ),
      _ => Response(400, body: 'Bad Request: ${error.message}'),
    };
  }
}

enum _UploadConflictPolicy { fail, overwrite, rename }

class _PutResult {
  final int statusCode;
  final String relativePath;
  final String fileName;
  final bool overwritten;
  final bool renamed;

  const _PutResult({
    required this.statusCode,
    required this.relativePath,
    required this.fileName,
    this.overwritten = false,
    this.renamed = false,
  });
}

class _UploadConflictException implements Exception {
  final String fileName;
  final String relativePath;

  const _UploadConflictException({
    required this.fileName,
    required this.relativePath,
  });
}

class _UploadBackupMetadata {
  const _UploadBackupMetadata({
    required this.sourceFingerprint,
    required this.contentHash,
    required this.deviceId,
    required this.sourceId,
    required this.sizeBytes,
    required this.modifiedMs,
  });

  final String sourceFingerprint;
  final String contentHash;
  final String deviceId;
  final String sourceId;
  final int sizeBytes;
  final int modifiedMs;
}
