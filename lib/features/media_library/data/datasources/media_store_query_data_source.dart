// 文件输入：MethodChannel（Android MediaStore）
// 文件职责：直接查询 MediaStore，返回媒体记录 DTO
// 文件对外接口：MediaStoreQueryDataSource
// 文件包含：MediaStoreQueryDataSource
import '../../../../core/media_type.dart';
import '../../../../core/storage/media_store_service.dart';
import '../../domain/entities/media_type.dart';
import '../models/media_store_item_dto.dart';

class MediaStoreQueryDataSource {
  MediaStoreQueryDataSource({required MediaStoreService mediaStoreService})
    : _mediaStoreService = mediaStoreService;

  final MediaStoreService _mediaStoreService;

  Future<List<MediaStoreItemDto>> queryImages() async {
    final files = await _mediaStoreService.queryImages();
    return files
        .map(
          (f) => MediaStoreItemDto(
            id: f.id,
            contentUri: f.contentUri,
            displayName: f.displayName,
            relativePath: f.relativePath,
            size: f.size,
            mimeType: f.mimeType,
            dateModified: f.dateModified.millisecondsSinceEpoch,
            mediaType: f.mediaType.name,
            bucketId: f.bucketId,
            bucketDisplayName: f.bucketDisplayName,
          ),
        )
        .toList();
  }

  Future<List<MediaStoreItemDto>> queryVideos() async {
    final files = await _mediaStoreService.queryVideos();
    return files
        .map(
          (f) => MediaStoreItemDto(
            id: f.id,
            contentUri: f.contentUri,
            displayName: f.displayName,
            relativePath: f.relativePath,
            size: f.size,
            mimeType: f.mimeType,
            dateModified: f.dateModified.millisecondsSinceEpoch,
            mediaType: f.mediaType.name,
            bucketId: f.bucketId,
            bucketDisplayName: f.bucketDisplayName,
          ),
        )
        .toList();
  }

  Future<List<MediaStoreItemDto>> queryByType(MediaType type) async {
    switch (type) {
      case MediaType.image:
        return queryImages();
      case MediaType.video:
        return queryVideos();
      case MediaType.audio:
        return [];
    }
  }
}
