// 文件输入：FileSystemService
// 文件职责：负责 /dav/fs/* 资源解析
// 文件对外接口：FileSystemDavResourceResolver
// 文件包含：FileSystemDavResourceResolver
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../core/storage/path_mapper.dart';
import '../../../core/storage/share_internal_paths.dart';
import '../../../features/webdav/resources/dav_capability.dart';
import '../../../features/webdav/resources/dav_resource.dart';
import '../../../features/webdav/resources/dav_resource_kind.dart';
import '../../../features/webdav/utils/content_type_resolver.dart';
import 'dav_resource_resolver.dart';

class FileSystemDavResourceResolver implements DavResourceResolver {
  FileSystemDavResourceResolver({
    required String rootPath,
    required ContentTypeResolver contentTypeResolver,
  }) : _pathMapper = PathMapper(rootPath: rootPath),
       _contentTypeResolver = contentTypeResolver;

  final PathMapper _pathMapper;
  final ContentTypeResolver _contentTypeResolver;

  @override
  Future<DavResource?> resolve(String davPath) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = _pathMapper.resolve(
        davPath,
        allowedRoots: const {ServerPathRoot.fs},
      );
    } on PathMappingException {
      return null;
    }

    final localPath = mappedPath.localPath;
    if (localPath == null) {
      return null;
    }

    final entity = await _getEntity(localPath);
    if (entity == null) return null;

    if (entity is Directory) {
      if (!mappedPath.isRoot) {
        return null;
      }

      return DavResource(
        davPath: mappedPath.normalizedPath,
        name: _getName(mappedPath.normalizedPath),
        kind: DavResourceKind.collection,
        capability: DavCapability.fullAccess,
        sourceType: DavSourceType.local,
      );
    }

    final file = entity as File;
    final stat = await file.stat();

    return DavResource(
      davPath: mappedPath.normalizedPath,
      name: _getName(mappedPath.normalizedPath),
      kind: DavResourceKind.file,
      capability: DavCapability.fullAccess,
      sourceType: DavSourceType.local,
      sourceRef: localPath,
      size: stat.size,
      contentType: _contentTypeResolver.resolve(_getExtension(localPath)),
      lastModified: stat.modified,
    );
  }

  @override
  Future<List<DavResource>> listChildren(String davPath) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = _pathMapper.resolve(
        davPath,
        allowedRoots: const {ServerPathRoot.fs},
      );
    } on PathMappingException {
      return [];
    }

    if (!mappedPath.isRoot) {
      return [];
    }

    final localPath = mappedPath.localPath;
    if (localPath == null) {
      return [];
    }

    final dir = Directory(localPath);

    if (!await dir.exists()) {
      return [];
    }

    final entities = await dir.list().toList();
    final resources = <DavResource>[];

    for (final entity in entities) {
      final name = _getName(entity.path);
      if (name.isEmpty || shouldHideFromShareListing(name)) continue;

      if (entity is File) {
        final stat = await entity.stat();
        resources.add(
          DavResource(
            davPath: '${mappedPath.normalizedPath}/${Uri.encodeComponent(name)}',
            name: name,
            kind: DavResourceKind.file,
            capability: DavCapability.fullAccess,
            sourceType: DavSourceType.local,
            sourceRef: entity.path,
            size: stat.size,
            contentType: _contentTypeResolver.resolve(
              _getExtension(entity.path),
            ),
            lastModified: stat.modified,
          ),
        );
      }
    }

    return resources;
  }

  String _getName(String path) {
    return p.basename(path);
  }

  String _getExtension(String path) {
    return p.extension(path);
  }

  Future<FileSystemEntity?> _getEntity(String path) async {
    if (await File(path).exists()) return File(path);
    if (await Directory(path).exists()) return Directory(path);
    return null;
  }
}
