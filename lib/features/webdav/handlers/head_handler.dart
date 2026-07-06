// 文件输入：DavResourceResolver, DavContentReader
// 文件职责：处理 WebDAV HEAD 请求，返回文件元信息（无 body）
// 文件对外接口：HeadHandler
// 文件包含：HeadHandler
import 'package:shelf/shelf.dart';
import '../resolvers/dav_resource_resolver.dart';
import '../readers/dav_content_reader.dart';
import '../utils/dav_response_header_builder.dart';

class HeadHandler {
  HeadHandler({
    required DavResourceResolver resolver,
    required DavContentReader contentReader,
  }) : _resolver = resolver,
       _contentReader = contentReader;

  final DavResourceResolver _resolver;
  final DavContentReader _contentReader;

  Future<Response> handle(Request request) async {
    final path = _normalizePath(request.url.path);

    final resource = await _resolver.resolve(path);
    if (resource == null) {
      return _buildErrorResponse(404, 'Resource not found');
    }

    if (resource.isDirectory) {
      return Response.ok(
        '',
        headers: {
          'Content-Type': 'httpd/unix-directory',
          'Accept-Ranges': 'bytes',
        },
      );
    }

    final fileSize = await _contentReader.getFileSize(resource);

    return Response.ok(
      '',
      headers: DavResponseHeaderBuilder.buildFileHeaders(
        resource: resource,
        contentLength: fileSize,
      ),
    );
  }

  String _normalizePath(String urlPath) {
    if (urlPath.isEmpty) return '/';
    return '/$urlPath';
  }

  Response _buildErrorResponse(int status, String message) {
    return Response(
      status,
      body: '',
      headers: {'Content-Type': 'application/json'},
    );
  }
}
