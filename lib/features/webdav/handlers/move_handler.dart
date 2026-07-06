// 文件输入：DavResourceResolver, FileSystemService
// 文件职责：处理 WebDAV MOVE 请求，移动或重命名文件/目录
// 文件对外接口：MoveHandler
// 文件包含：MoveHandler
import 'package:shelf/shelf.dart';

class MoveHandler {
  MoveHandler({required String rootPath});

  Future<Response> handle(Request request) async {
    final path = _normalizePath(request.url.path);
    final destination = request.headers['Destination'];

    if (path.startsWith('/dav/library') ||
        (destination?.contains('/dav/library') ?? false)) {
      return Response(405, body: 'Method Not Allowed');
    }

    return Response(501, body: 'Not Implemented');
  }

  String _normalizePath(String urlPath) {
    if (urlPath.isEmpty) return '/';
    return '/$urlPath';
  }
}
