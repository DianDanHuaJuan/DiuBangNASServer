// 文件输入：MediaLibraryRepository, MediaStoreQueryDataSource, MediaStoreReadDataSource
// 文件职责：实现 MediaLibraryRepository 接口，聚合数据源、路径映射和缓存
// 文件对外接口：MediaLibraryRepositoryImpl
// 文件包含：MediaLibraryRepositoryImpl
import '../../../../core/media_type.dart';
import '../../domain/entities/media_asset.dart';
import '../../domain/repositories/media_library_repository.dart';
import '../datasources/media_store_query_data_source.dart';
import '../models/media_store_item_dto.dart';

class MediaLibraryRepositoryImpl implements MediaLibraryRepository {
  MediaLibraryRepositoryImpl({
    required MediaStoreQueryDataSource queryDataSource,
  }) : _queryDataSource = queryDataSource;

  final MediaStoreQueryDataSource _queryDataSource;

  final Map<MediaType, List<MediaStoreItemDto>> _cache = {};
  final Map<MediaType, Set<String>> _bucketCache = {};

  @override
  Future<List<MediaAsset>> listAll(MediaType type) async {
    if (!_cache.containsKey(type)) {
      final items = await _queryDataSource.queryByType(type);
      _cache[type] = items;
      _buildBucketCache(type, items);
    }

    return _cache[type]!.map(_toMediaAsset).toList();
  }

  @override
  Future<List<String>> listBuckets(MediaType type) async {
    await listAll(type);
    return _bucketCache[type]?.toList() ?? [];
  }

  @override
  Future<List<MediaAsset>> listByBucket(MediaType type, String bucketId) async {
    await listAll(type);
    return _cache[type]
            ?.where((item) => item.bucketId == bucketId)
            .map(_toMediaAsset)
            .toList() ??
        [];
  }

  @override
  Future<MediaAsset?> getAsset(String contentUri) async {
    for (final type in MediaType.values) {
      await listAll(type);
      final item = _cache[type]?.firstWhere(
        (item) => item.contentUri == contentUri,
        orElse: () => MediaStoreItemDto(
          id: '',
          contentUri: '',
          displayName: '',
          relativePath: '',
          size: 0,
          mimeType: '',
          dateModified: 0,
          mediaType: '',
          bucketId: '',
          bucketDisplayName: '',
        ),
      );
      if (item != null && item.contentUri.isNotEmpty) {
        return _toMediaAsset(item);
      }
    }
    return null;
  }

  @override
  Future<void> invalidateCache() async {
    _cache.clear();
    _bucketCache.clear();
  }

  MediaAsset _toMediaAsset(MediaStoreItemDto dto) {
    return MediaAsset(
      contentUri: dto.contentUri,
      displayName: dto.displayName,
      relativePath: dto.relativePath,
      size: dto.size,
      mimeType: dto.mimeType,
      dateModified: DateTime.fromMillisecondsSinceEpoch(dto.dateModified),
      mediaType: _parseMediaType(dto.mediaType),
      bucketId: dto.bucketId,
      bucketDisplayName: dto.bucketDisplayName,
    );
  }

  MediaType _parseMediaType(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      default:
        return MediaType.image;
    }
  }

  void _buildBucketCache(MediaType type, List<MediaStoreItemDto> items) {
    final buckets = items.map((e) => e.bucketDisplayName).toSet();
    _bucketCache[type] = buckets;
  }
}
