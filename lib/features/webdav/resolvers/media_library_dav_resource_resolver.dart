// 文件输入：MediaLibraryRepository
// 文件职责：负责 /dav/library/* 资源解析，平铺所有媒体文件
// 文件对外接口：MediaLibraryDavResourceResolver
// 文件包含：MediaLibraryDavResourceResolver
import '../../../../core/media_type.dart';
import '../../../../core/storage/path_mapper.dart';
import '../../../features/media_library/domain/repositories/media_library_repository.dart';
import '../resources/dav_resource.dart';
import 'dav_resource_resolver.dart';

class MediaLibraryDavResourceResolver implements DavResourceResolver {
  MediaLibraryDavResourceResolver({required MediaLibraryRepository repository})
    : _repository = repository;

  final MediaLibraryRepository _repository;
  static const PathMapper _pathMapper = PathMapper();

  @override
  Future<DavResource?> resolve(String davPath) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = _pathMapper.resolve(
        davPath,
        allowedRoots: const {ServerPathRoot.library},
        allowNestedPaths: false,
      );
    } on PathMappingException {
      return null;
    }

    if (mappedPath.isRoot) {
      return DavResource.virtualDirectory(
        davPath: '/library',
        name: '媒体库',
        readable: true,
        listable: true,
      );
    }

    return _resolveMediaFile(
      fileName: mappedPath.fileName!,
      davPath: mappedPath.normalizedPath,
    );
  }

  Future<DavResource?> _resolveMediaFile({
    required String fileName,
    required String davPath,
  }) async {
    final imageAssets = await _repository.listAll(MediaType.image);
    final videoAssets = await _repository.listAll(MediaType.video);

    final allAssets = [...imageAssets, ...videoAssets];
    final asset = allAssets.where((a) => a.displayName == fileName).firstOrNull;

    if (asset != null) {
      return DavResource.mediaStoreFile(
        davPath: davPath,
        name: asset.displayName,
        contentUri: asset.contentUri,
        size: asset.size,
        contentType: asset.mimeType,
        lastModified: asset.dateModified,
      );
    }

    return null;
  }

  @override
  Future<List<DavResource>> listChildren(String davPath) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = _pathMapper.resolve(
        davPath,
        allowedRoots: const {ServerPathRoot.library},
        allowNestedPaths: false,
      );
    } on PathMappingException {
      return [];
    }

    if (!mappedPath.isRoot) {
      return [];
    }

    final imageAssets = await _repository.listAll(MediaType.image);
    final videoAssets = await _repository.listAll(MediaType.video);

    final allAssets = [...imageAssets, ...videoAssets];

    return allAssets.map((asset) {
      return DavResource.mediaStoreFile(
        davPath: '/library/${asset.displayName}',
        name: asset.displayName,
        contentUri: asset.contentUri,
        size: asset.size,
        contentType: asset.mimeType,
        lastModified: asset.dateModified,
      );
    }).toList();
  }
}
