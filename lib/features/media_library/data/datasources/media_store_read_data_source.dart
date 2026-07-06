// 文件输入：MethodChannel（Android ContentResolver）
// 文件职责：使用 ContentResolver 打开媒体内容，提供只读和区间读取能力
// 文件对外接口：MediaStoreReadDataSource
// 文件包含：MediaStoreReadDataSource
import '../../../../core/storage/media_store_service.dart';

class MediaStoreReadDataSource {
  MediaStoreReadDataSource({required MediaStoreService mediaStoreService})
    : _mediaStoreService = mediaStoreService;

  final MediaStoreService _mediaStoreService;

  Future<MediaReadResult> readFile(
    String contentUri, {
    int? rangeStart,
    int? rangeEnd,
  }) {
    return _mediaStoreService.readFile(
      contentUri,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }

  Future<int> getFileSize(String contentUri) async {
    final info = await _mediaStoreService.getFileInfo(contentUri);
    return info?.size ?? 0;
  }
}
