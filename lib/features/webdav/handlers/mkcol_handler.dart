// 文件输入：DavResourceResolver, FileSystemService
// 文件职责：处理 WebDAV MKCOL 请求，创建目录
// 文件对外接口：MkcolHandler
// 文件包含：MkcolHandler
import 'package:shelf/shelf.dart';

class MkcolHandler {
  MkcolHandler({required String rootPath});

  Future<Response> handle(Request request) async {
    final path = _normalizePath(request.url.path);

    if (path.startsWith('/library')) {
      return Response(405, body: 'Method Not Allowed');
    }

    if (!path.startsWith('/fs')) {
      return Response(403, body: 'Forbidden');
    }

    return Response(
      405,
      body:
          'Method Not Allowed: Directory creation is not allowed. All files are stored flat in /fs/',
    );
  }

  String _normalizePath(String urlPath) {
    if (urlPath.isEmpty) return '/';
    return '/$urlPath';
  }
}
