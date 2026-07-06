// 文件输入：shelf, 各 WebDAV Handler
// 文件职责：根据 HTTP 方法（PROPFIND/GET/HEAD/PUT/DELETE/MKCOL/COPY/MOVE）分发到对应 Handler
// 文件对外接口：WebdavMethodRouter
// 文件包含：WebdavMethodRouter
import 'package:shelf/shelf.dart';
import '../../../core/storage/backup_catalog_service.dart';
import '../../../core/storage/thumbnail_service.dart';
import '../handlers/propfind_handler.dart';
import '../handlers/get_handler.dart';
import '../handlers/head_handler.dart';
import '../handlers/put_handler.dart';
import '../handlers/delete_handler.dart';
import '../handlers/mkcol_handler.dart';
import '../handlers/copy_handler.dart';
import '../handlers/move_handler.dart';
import '../resolvers/dav_resource_resolver.dart';
import '../readers/composite_content_reader.dart';

class WebdavMethodRouter {
  WebdavMethodRouter({
    required DavResourceResolver resolver,
    required CompositeContentReader contentReader,
    required String rootPath,
    void Function()? onFilesChanged,
    Future<void> Function(String relativePath)? onPathChanged,
    Future<void> Function(String relativePath)? onPathDeleted,
    BackupCatalogService? backupCatalogService,
    ThumbnailService? thumbnailService,
  }) {
    _propfindHandler = PropfindHandler(resolver: resolver);
    _getHandler = GetHandler(resolver: resolver, contentReader: contentReader);
    _headHandler = HeadHandler(
      resolver: resolver,
      contentReader: contentReader,
    );
    _putHandler = PutHandler(
      rootPath: rootPath,
      onFilesChanged: onFilesChanged,
      onPathChanged: onPathChanged,
      backupCatalogService: backupCatalogService,
      thumbnailService: thumbnailService,
    );
    _deleteHandler = DeleteHandler(
      rootPath: rootPath,
      onFilesChanged: onFilesChanged,
      onPathDeleted: onPathDeleted,
      backupCatalogService: backupCatalogService,
      thumbnailService: thumbnailService,
    );
    _mkcolHandler = MkcolHandler(rootPath: rootPath);
    _copyHandler = CopyHandler(rootPath: rootPath);
    _moveHandler = MoveHandler(rootPath: rootPath);
  }

  late final PropfindHandler _propfindHandler;
  late final GetHandler _getHandler;
  late final HeadHandler _headHandler;
  late final PutHandler _putHandler;
  late final DeleteHandler _deleteHandler;
  late final MkcolHandler _mkcolHandler;
  late final CopyHandler _copyHandler;
  late final MoveHandler _moveHandler;

  Handler get handler {
    return (Request request) async {
      final method = request.method;

      switch (method) {
        case 'PROPFIND':
          return await _propfindHandler.handle(request);
        case 'GET':
          return await _getHandler.handle(request);
        case 'HEAD':
          return await _headHandler.handle(request);
        case 'PUT':
          return await _putHandler.handle(request);
        case 'DELETE':
          return await _deleteHandler.handle(request);
        case 'MKCOL':
          return await _mkcolHandler.handle(request);
        case 'COPY':
          return await _copyHandler.handle(request);
        case 'MOVE':
          return await _moveHandler.handle(request);
        default:
          return Response(405, body: 'Method Not Allowed');
      }
    };
  }
}
