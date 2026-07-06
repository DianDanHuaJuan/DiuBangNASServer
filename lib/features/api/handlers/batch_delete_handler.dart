// 文件输入：FileSystemService
// 文件职责：处理批量文件删除请求
// 文件对外接口：BatchDeleteHandler
// 文件包含：BatchDeleteHandler, DeleteResult
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../../../core/storage/backup_catalog_service.dart';
import '../../../core/storage/file_system_service.dart';
import '../../../core/storage/path_mapper.dart';
import '../../../core/storage/thumbnail_service.dart';

class DeleteResult {
  DeleteResult({required this.path, required this.success, this.error});

  final String path;
  final bool success;
  final String? error;

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'success': success,
      if (error != null) 'error': error,
    };
  }
}

class BatchDeleteHandler {
  static const int maxBatchSize = 100;

  BatchDeleteHandler({
    required FileSystemService fileSystemService,
    required String rootPath,
    void Function()? onFilesChanged,
    Future<void> Function(String relativePath)? onPathDeleted,
    BackupCatalogService? backupCatalogService,
    ThumbnailService? thumbnailService,
  }) : _fileSystemService = fileSystemService,
       _pathMapper = PathMapper(rootPath: rootPath),
       _onFilesChanged = onFilesChanged,
       _onPathDeleted = onPathDeleted,
       _backupCatalogService = backupCatalogService,
       _thumbnailService = thumbnailService;

  final FileSystemService _fileSystemService;
  final PathMapper _pathMapper;
  final void Function()? _onFilesChanged;
  final Future<void> Function(String relativePath)? _onPathDeleted;
  final BackupCatalogService? _backupCatalogService;
  final ThumbnailService? _thumbnailService;
  static const int _maxBatchSize = maxBatchSize;

  Future<Response> handle(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final paths = (json['paths'] as List?)?.cast<String>();
      if (paths == null || paths.isEmpty) {
        return _errorResponse(
          400,
          'INVALID_REQUEST',
          'paths array is required and cannot be empty',
        );
      }

      if (paths.length > _maxBatchSize) {
        return _errorResponse(
          400,
          'INVALID_REQUEST',
          'paths array cannot exceed $_maxBatchSize items',
        );
      }

      final results = <DeleteResult>[];

      for (final path in paths) {
        final result = await _deletePath(path);
        results.add(result);
      }

      final successCount = results.where((r) => r.success).length;
      final failedCount = results.length - successCount;

      return Response.ok(
        jsonEncode({
          'success': failedCount == 0,
          'deleted': successCount,
          'failed': failedCount,
          'results': results.map((r) => r.toJson()).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      if (e is FormatException) {
        return _errorResponse(400, 'INVALID_REQUEST', 'Invalid JSON body');
      }
      return _errorResponse(500, 'INTERNAL_ERROR', e.toString());
    }
  }

  Future<DeleteResult> _deletePath(String path) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = _pathMapper.resolve(
        path,
        allowRoot: true,
        allowNestedPaths: true,
      );
    } on PathMappingException catch (error) {
      return DeleteResult(
        path: path,
        success: false,
        error: 'INVALID_PATH: ${error.message}',
      );
    }

    if (mappedPath.root == ServerPathRoot.library) {
      return DeleteResult(
        path: path,
        success: false,
        error: 'NOT_SUPPORTED: Delete from library is not supported yet',
      );
    }

    if (mappedPath.isRoot) {
      return DeleteResult(
        path: path,
        success: false,
        error: 'INVALID_PATH: Path must target a file inside /fs/',
      );
    }

    try {
      final localPath = mappedPath.localPath!;
      final entity = await FileSystemEntity.type(localPath);

      if (entity == FileSystemEntityType.notFound) {
        return DeleteResult(
          path: path,
          success: false,
          error: 'NOT_FOUND: File or directory does not exist',
        );
      }

      if (entity == FileSystemEntityType.file) {
        final stat = await File(localPath).stat();
        await _thumbnailService?.deleteThumbnails(
          '/fs${mappedPath.relativePath}',
          sourceModifiedMs: stat.modified.millisecondsSinceEpoch,
          sourceSizeBytes: stat.size,
        );
        await _fileSystemService.deleteFile(localPath);
        await _backupCatalogService?.deleteEntriesForRelativePath(
          mappedPath.relativePath,
        );
        _onFilesChanged?.call();
        final onPathDeleted = _onPathDeleted;
        if (onPathDeleted != null) {
          await onPathDeleted(mappedPath.relativePath);
        }
        return DeleteResult(path: path, success: true);
      }

      if (entity == FileSystemEntityType.directory) {
        return DeleteResult(
          path: path,
          success: false,
          error: 'NOT_SUPPORTED: Directories are not supported in /fs/',
        );
      }

      return DeleteResult(
        path: path,
        success: false,
        error: 'UNSUPPORTED_TYPE: Cannot delete this type of resource',
      );
    } catch (e) {
      return DeleteResult(
        path: path,
        success: false,
        error: 'DELETE_ERROR: $e',
      );
    }
  }

  Response _errorResponse(int status, String code, String message) {
    return Response(
      status,
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
