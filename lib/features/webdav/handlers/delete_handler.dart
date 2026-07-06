// 文件输入：DavResourceResolver, FileSystemService
// 文件职责：处理 WebDAV DELETE 请求，删除文件或目录
// 文件对外接口：DeleteHandler
// 文件包含：DeleteHandler
import 'dart:io';
import 'package:shelf/shelf.dart';
import '../../../core/storage/backup_catalog_service.dart';
import '../../../core/storage/path_mapper.dart';
import '../../../core/storage/thumbnail_service.dart';

class DeleteHandler {
  DeleteHandler({
    required String rootPath,
    void Function()? onFilesChanged,
    Future<void> Function(String relativePath)? onPathDeleted,
    BackupCatalogService? backupCatalogService,
    ThumbnailService? thumbnailService,
  }) : _pathMapper = PathMapper(rootPath: rootPath),
       _onFilesChanged = onFilesChanged,
       _onPathDeleted = onPathDeleted,
       _backupCatalogService = backupCatalogService,
       _thumbnailService = thumbnailService;

  final PathMapper _pathMapper;
  final void Function()? _onFilesChanged;
  final Future<void> Function(String relativePath)? _onPathDeleted;
  final BackupCatalogService? _backupCatalogService;
  final ThumbnailService? _thumbnailService;

  Future<Response> handle(Request request) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = _pathMapper.resolve(
        request.url.path,
        allowRoot: true,
        allowNestedPaths: true,
      );
    } on PathMappingException catch (error) {
      return _buildPathErrorResponse(error);
    }

    if (mappedPath.root == ServerPathRoot.library) {
      return Response(405, body: 'Method Not Allowed');
    }

    if (mappedPath.isRoot) {
      return Response(400, body: 'Bad Request: Cannot delete directory');
    }

    final localPath = mappedPath.localPath!;

    try {
      final entity = await FileSystemEntity.type(localPath);

      if (entity == FileSystemEntityType.notFound) {
        return Response(404, body: 'Not Found');
      }

      if (entity == FileSystemEntityType.file) {
        final file = File(localPath);
        final stat = await file.stat();
        await _thumbnailService?.deleteThumbnails(
          '/fs${mappedPath.relativePath}',
          sourceModifiedMs: stat.modified.millisecondsSinceEpoch,
          sourceSizeBytes: stat.size,
        );
        await file.delete();
        await _backupCatalogService?.deleteEntriesForRelativePath(
          mappedPath.relativePath,
        );
        _onFilesChanged?.call();
        final onPathDeleted = _onPathDeleted;
        if (onPathDeleted != null) {
          await onPathDeleted(mappedPath.relativePath);
        }
        return Response(204, headers: {'Content-Length': '0'});
      }

      if (entity == FileSystemEntityType.directory) {
        return Response(
          405,
          body: 'Method Not Allowed: Directories are not supported in /fs/',
        );
      }

      return Response(403, body: 'Cannot delete this type of resource');
    } catch (e) {
      return Response(500, body: 'Internal Server Error: $e');
    }
  }

  Response _buildPathErrorResponse(PathMappingException error) {
    return switch (error.code) {
      PathMappingErrorCode.unsupportedRoot => Response(403, body: 'Forbidden'),
      PathMappingErrorCode.rootPathNotAllowed => Response(
        400,
        body: 'Bad Request: Cannot delete directory',
      ),
      PathMappingErrorCode.nestedPathNotAllowed => Response(
        400,
        body: 'Bad Request: Subdirectories are not allowed',
      ),
      _ => Response(400, body: 'Bad Request: ${error.message}'),
    };
  }
}
