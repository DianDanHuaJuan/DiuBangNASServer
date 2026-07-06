// 文件输入：MediaAsset, MediaType
// 文件职责：定义媒体聚合查询和只读访问接口
// 文件对外接口：MediaLibraryRepository（抽象类）
// 文件包含：MediaLibraryRepository 抽象类
import '../../../../core/media_type.dart';
import '../entities/media_asset.dart';

abstract class MediaLibraryRepository {
  Future<List<MediaAsset>> listAll(MediaType type);
  Future<List<String>> listBuckets(MediaType type);
  Future<List<MediaAsset>> listByBucket(MediaType type, String bucketId);
  Future<MediaAsset?> getAsset(String contentUri);
  Future<void> invalidateCache();
}
