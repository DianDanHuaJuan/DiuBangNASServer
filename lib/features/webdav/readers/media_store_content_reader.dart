// 文件输入：MediaStoreService
// 文件职责：负责 MediaStore 内容读取和 Range 支持
// 文件对外接口：MediaStoreContentReader
// 文件包含：MediaStoreContentReader
import 'dart:math' as math;
import '../../../core/storage/media_store_service.dart';
import '../resources/dav_resource.dart';
import 'dav_content_reader.dart';

class MediaStoreContentReader implements DavContentReader {
  MediaStoreContentReader({required MediaStoreService mediaStoreService})
    : _mediaStoreService = mediaStoreService;

  final MediaStoreService _mediaStoreService;
  static const int _chunkSize = 1024 * 1024;

  @override
  Stream<List<int>> openRead(
    DavResource resource, {
    int? rangeStart,
    int? rangeEnd,
  }) async* {
    if (resource.sourceRef == null) {
      return;
    }

    final totalSize = resource.size ?? await getFileSize(resource);
    if (totalSize <= 0) {
      return;
    }

    final end = math.min(rangeEnd ?? (totalSize - 1), totalSize - 1);
    var start = rangeStart ?? 0;

    while (start <= end) {
      final chunkEnd = math.min(start + _chunkSize - 1, end);
      final result = await _mediaStoreService.readFile(
        resource.sourceRef!,
        rangeStart: start,
        rangeEnd: chunkEnd,
      );

      if (result.bytes.isEmpty) {
        break;
      }

      yield result.bytes;
      start += result.bytes.length;
    }
  }

  @override
  Future<int> getFileSize(DavResource resource) async {
    if (resource.sourceRef == null) return 0;
    final info = await _mediaStoreService.getFileInfo(resource.sourceRef!);
    return info?.size ?? 0;
  }
}
