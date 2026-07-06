// 文件输入：DavResource 列表
// 文件职责：构造 WebDAV PROPFIND 的 207 Multi-Status XML 响应体
// 文件对外接口：DavXmlResponseBuilder
// 文件包含：DavXmlResponseBuilder
import '../resources/dav_resource.dart';
import '../resources/dav_resource_kind.dart';

class DavXmlResponseBuilder {
  const DavXmlResponseBuilder();

  String buildMultiStatus(String requestPath, List<DavResource> resources) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    buffer.write('<D:multistatus xmlns:D="DAV:">\n');

    String href;
    if (requestPath == '/' || requestPath.isEmpty) {
      href = '/dav/';
    } else if (requestPath.endsWith('/')) {
      href = requestPath;
    } else {
      href = '$requestPath/';
    }

    buffer.write(
      _buildResourceXml(href, _getSelfResource(requestPath), isDir: true),
    );

    for (final resource in resources) {
      buffer.write(_buildResourceXml(href, resource));
    }

    buffer.write('</D:multistatus>');
    return buffer.toString();
  }

  DavResource _getSelfResource(String path) {
    final name = _getFileName(path);
    return DavResource.virtualDirectory(
      davPath: path,
      name: name.isEmpty ? '' : name,
    );
  }

  String _buildResourceXml(
    String parentHref,
    DavResource resource, {
    bool isDir = false,
  }) {
    final buffer = StringBuffer();
    String resourceHref;
    if (isDir) {
      resourceHref = parentHref;
    } else {
      final segments = resource.davPath
          .split('/')
          .where((s) => s.isNotEmpty)
          .map((s) {
            try {
              return Uri.encodeComponent(Uri.decodeComponent(s));
            } on FormatException {
              return Uri.encodeComponent(s);
            }
          })
          .join('/');
      resourceHref = '/dav/$segments';
      if (resource.kind == DavResourceKind.collection) {
        resourceHref = '$resourceHref/';
      }
    }
    final displayName = resource.name;
    final isCollection = isDir || resource.kind == DavResourceKind.collection;

    buffer.write('  <D:response>\n');
    buffer.write('    <D:href>$resourceHref</D:href>\n');
    buffer.write('    <D:propstat>\n');
    buffer.write('      <D:prop>\n');
    buffer.write('        <D:displayname>$displayName</D:displayname>\n');

    if (isCollection) {
      buffer.write(
        '        <D:resourcetype><D:collection/></D:resourcetype>\n',
      );
    } else {
      buffer.write('        <D:resourcetype/>\n');
      if (resource.size != null) {
        buffer.write(
          '        <D:getcontentlength>${resource.size}</D:getcontentlength>\n',
        );
      }
      if (resource.contentType != null) {
        buffer.write(
          '        <D:getcontenttype>${resource.contentType}</D:getcontenttype>\n',
        );
      }
    }

    if (resource.lastModified != null) {
      buffer.write(
        '        <D:getlastmodified>${_formatDate(resource.lastModified!)}</D:getlastmodified>\n',
      );
    }

    buffer.write('      </D:prop>\n');
    buffer.write('      <D:status>HTTP/1.1 200 OK</D:status>\n');
    buffer.write('    </D:propstat>\n');
    buffer.write('  </D:response>\n');

    return buffer.toString();
  }

  String _getFileName(String path) {
    if (path == '/' || path.isEmpty) return '';
    return path.split('/').lastWhere((e) => e.isNotEmpty, orElse: () => '');
  }

  String _formatDate(DateTime dt) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = days[(dt.weekday - 1) % 7];
    final month = months[dt.month - 1];
    return '$day, ${dt.day.toString().padLeft(2, '0')} $month ${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')} GMT';
  }
}
