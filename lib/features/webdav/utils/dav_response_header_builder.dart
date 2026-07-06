// 文件输入：DavResource、字节范围上下文
// 文件职责：统一构建 WebDAV 文件响应头，供 GET / HEAD 复用
// 文件对外接口：DavResponseHeaderBuilder
// 文件包含：DavResponseHeaderBuilder
import 'dart:io';

import '../resources/dav_resource.dart';

class DavResponseHeaderBuilder {
  const DavResponseHeaderBuilder._();

  static Map<String, String> buildFileHeaders({
    required DavResource resource,
    required int contentLength,
    String? contentRange,
  }) {
    final headers = <String, String>{
      'Content-Type': resource.contentType ?? 'application/octet-stream',
      'Content-Length': contentLength.toString(),
      'Accept-Ranges': 'bytes',
      'Content-Disposition': _buildContentDisposition(resource.name),
    };

    final lastModified = resource.lastModified;
    if (lastModified != null) {
      headers['Last-Modified'] = HttpDate.format(lastModified.toUtc());
    }
    if (contentRange != null) {
      headers['Content-Range'] = contentRange;
    }

    return headers;
  }

  static String _buildContentDisposition(String fileName) {
    final safeFallback = _buildAsciiFallback(fileName);
    final encodedFileName = Uri.encodeComponent(fileName);
    return 'inline; filename="$safeFallback"; filename*=UTF-8\'\'$encodedFileName';
  }

  static String _buildAsciiFallback(String fileName) {
    final sanitized = fileName.replaceAll('\\', '_').replaceAll('"', '\'');
    final asciiOnly = sanitized.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
    return asciiOnly.isEmpty ? 'download' : asciiOnly;
  }
}
