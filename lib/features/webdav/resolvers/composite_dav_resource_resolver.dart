// 文件输入：FileSystemDavResourceResolver, MediaLibraryDavResourceResolver
// 文件职责：根据请求路径将请求分发到不同资源解析器
// 文件对外接口：CompositeDavResourceResolver
// 文件包含：CompositeDavResourceResolver
import '../resources/dav_resource.dart';
import 'dav_resource_resolver.dart';
import 'file_system_dav_resource_resolver.dart';
import 'media_library_dav_resource_resolver.dart';

class CompositeDavResourceResolver implements DavResourceResolver {
  CompositeDavResourceResolver({
    required FileSystemDavResourceResolver fileSystemResolver,
    MediaLibraryDavResourceResolver? mediaLibraryResolver,
    bool mediaLibraryEnabled = true,
  }) : _fileSystemResolver = fileSystemResolver,
       _mediaLibraryResolver = mediaLibraryResolver,
       _mediaLibraryEnabled =
           mediaLibraryEnabled && mediaLibraryResolver != null;

  final FileSystemDavResourceResolver _fileSystemResolver;
  final MediaLibraryDavResourceResolver? _mediaLibraryResolver;
  final bool _mediaLibraryEnabled;

  String _normalizePath(String path) {
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    while (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  @override
  Future<DavResource?> resolve(String davPath) async {
    final normalizedPath = _normalizePath(davPath);
    final mediaLibraryResolver = _mediaLibraryResolver;

    if (_mediaLibraryEnabled && normalizedPath == '/library') {
      return DavResource.virtualDirectory(
        davPath: '/library',
        name: '媒体库',
        readable: true,
        listable: true,
      );
    }

    if (_mediaLibraryEnabled &&
        mediaLibraryResolver != null &&
        normalizedPath.startsWith('/library/')) {
      return mediaLibraryResolver.resolve(normalizedPath);
    }

    if (normalizedPath == '/fs') {
      return DavResource.virtualDirectory(
        davPath: '/fs',
        name: '铥棒文件S',
        readable: true,
        listable: true,
      );
    }

    if (normalizedPath.startsWith('/fs/')) {
      return _fileSystemResolver.resolve(normalizedPath);
    }

    return null;
  }

  @override
  Future<List<DavResource>> listChildren(String davPath) async {
    final normalizedPath = _normalizePath(davPath);
    final mediaLibraryResolver = _mediaLibraryResolver;

    if (_mediaLibraryEnabled &&
        mediaLibraryResolver != null &&
        normalizedPath == '/library') {
      return mediaLibraryResolver.listChildren('/library');
    }

    if (_mediaLibraryEnabled && normalizedPath.startsWith('/library/')) {
      return [];
    }

    if (normalizedPath == '/fs' || normalizedPath.startsWith('/fs/')) {
      return _fileSystemResolver.listChildren(normalizedPath);
    }

    if (normalizedPath == '/' || normalizedPath.isEmpty) {
      return [
        DavResource.virtualDirectory(
          davPath: '/fs',
          name: '铥棒文件S',
          readable: true,
          listable: true,
        ),
        if (_mediaLibraryEnabled)
          DavResource.virtualDirectory(
            davPath: '/library',
            name: '媒体库',
            readable: true,
            listable: true,
          ),
      ];
    }

    return [];
  }
}
