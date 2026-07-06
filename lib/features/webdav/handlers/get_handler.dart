// 文件输入：DavResourceResolver, DavContentReader
// 文件职责：处理 WebDAV GET 请求，支持完整文件下载和 Range 部分下载
// 文件对外接口：GetHandler
// 文件包含：GetHandler
import 'package:shelf/shelf.dart';
import '../../../core/debug/server_debug_logging.dart';
import '../../../core/streams/buffered_byte_stream_transformer.dart';
import '../../../core/transfer/server_transfer_tuning.dart';
import '../resolvers/dav_resource_resolver.dart';
import '../readers/dav_content_reader.dart';
import '../resources/dav_resource.dart';
import '../utils/dav_response_header_builder.dart';
import '../utils/range_parser.dart';

class GetHandler {
  GetHandler({
    required DavResourceResolver resolver,
    required DavContentReader contentReader,
    RangeParser rangeParser = const RangeParser(),
  }) : _resolver = resolver,
       _contentReader = contentReader,
       _rangeParser = rangeParser;

  final DavResourceResolver _resolver;
  final DavContentReader _contentReader;
  final RangeParser _rangeParser;

  Future<Response> handle(Request request) async {
    final path = _normalizePath(request.url.path);
    final rangeHeader = request.headers['Range'];
    try {
      final resource = await _resolver.resolve(path);
      if (resource == null) {
        return _buildErrorResponse(404, 'Resource not found');
      }

      if (resource.isDirectory) {
        return _buildErrorResponse(403, 'Cannot GET directory');
      }

      if (rangeHeader != null) {
        return _handleRangeRequest(resource, rangeHeader);
      }

      return _handleFullRequest(resource);
    } catch (error, stackTrace) {
      return buildServerInternalErrorResponse(
        request: request,
        scope: 'GetHandler',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{'path': path, 'range': rangeHeader},
      );
    }
  }

  Future<Response> _handleFullRequest(DavResource resource) async {
    final fileSize =
        resource.size ?? await _contentReader.getFileSize(resource);

    final headers = DavResponseHeaderBuilder.buildFileHeaders(
      resource: resource,
      contentLength: fileSize,
    );

    return Response.ok(
      fileSize <= 0
          ? Stream<List<int>>.empty()
          : _bufferStream(
              _contentReader.openRead(resource),
              contentLength: fileSize,
            ),
      headers: headers,
    );
  }

  Future<Response> _handleRangeRequest(
    DavResource resource,
    String rangeHeader,
  ) async {
    final fileSize =
        resource.size ?? await _contentReader.getFileSize(resource);
    final range = _rangeParser.parse(rangeHeader, fileSize);

    if (range == null) {
      return Response(
        416,
        body: 'Invalid range',
        headers: {'Content-Range': 'bytes */$fileSize'},
      );
    }

    final contentLength = range.end - range.start + 1;

    final headers = DavResponseHeaderBuilder.buildFileHeaders(
      resource: resource,
      contentLength: contentLength,
      contentRange: 'bytes ${range.start}-${range.end}/${range.totalSize}',
    );

    return Response(
      206,
      body: contentLength <= 0
          ? Stream<List<int>>.empty()
          : _bufferStream(
              _contentReader.openRead(
                resource,
                rangeStart: range.start,
                rangeEnd: range.end,
              ),
              contentLength: contentLength,
            ),
      headers: headers,
    );
  }

  Stream<List<int>> _bufferStream(
    Stream<List<int>> source, {
    required int contentLength,
  }) {
    if (contentLength < ServerTransferTuning.downloadBufferingThresholdBytes) {
      return source;
    }
    return bufferByteStream(
      source,
      ServerTransferTuning.downloadStreamBufferSize,
    );
  }

  String _normalizePath(String urlPath) {
    if (urlPath.isEmpty) return '/';
    return '/$urlPath';
  }

  Response _buildErrorResponse(int status, String message) {
    return Response(
      status,
      body: '{"code":"PATH_NOT_FOUND","message":"$message","details":{}}',
      headers: {'Content-Type': 'application/json'},
    );
  }
}
