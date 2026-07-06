// 文件输入：DavResourceResolver
// 文件职责：处理 WebDAV PROPFIND 请求，返回目录内容或文件属性
// 文件对外接口：PropfindHandler
// 文件包含：PropfindHandler
import 'package:shelf/shelf.dart';
import '../resolvers/dav_resource_resolver.dart';
import '../resources/dav_resource.dart';
import '../utils/dav_xml_response_builder.dart';

class PropfindHandler {
  PropfindHandler({required DavResourceResolver resolver})
    : _resolver = resolver,
      _xmlBuilder = const DavXmlResponseBuilder();

  final DavResourceResolver _resolver;
  final DavXmlResponseBuilder _xmlBuilder;

  Future<Response> handle(Request request) async {
    final path = _normalizePath(request.url.path);

    if (path.isEmpty || path == '/') {
      final resources = await _resolver.listChildren('/');
      return _buildMultiStatusResponse('/', resources);
    }

    final resource = await _resolver.resolve(path);
    if (resource == null) {
      return _buildErrorResponse(404, 'Resource not found');
    }

    if (resource.isDirectory) {
      final children = await _resolver.listChildren(path);
      return _buildMultiStatusResponse(path, children);
    }

    return _buildMultiStatusResponse(path, [resource]);
  }

  String _normalizePath(String urlPath) {
    if (urlPath.isEmpty) return '/';
    return '/$urlPath';
  }

  Response _buildMultiStatusResponse(
    String requestPath,
    List<DavResource> resources,
  ) {
    final xml = _xmlBuilder.buildMultiStatus('/dav$requestPath', resources);
    return Response.ok(xml, headers: {'Content-Type': 'application/xml'});
  }

  Response _buildErrorResponse(int status, String message) {
    return Response(
      status,
      body: '{"code":"PATH_NOT_FOUND","message":"$message","details":{}}',
      headers: {'Content-Type': 'application/json'},
    );
  }
}
