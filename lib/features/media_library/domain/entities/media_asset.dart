// 文件输入：无
// 文件职责：描述媒体文件实体
// 文件对外接口：MediaAsset
// 文件包含：MediaAsset
import '../../../../core/media_type.dart';

class MediaAsset {
  final String contentUri;
  final String displayName;
  final String relativePath;
  final int size;
  final String mimeType;
  final DateTime dateModified;
  final MediaType mediaType;
  final String bucketId;
  final String bucketDisplayName;

  const MediaAsset({
    required this.contentUri,
    required this.displayName,
    required this.relativePath,
    required this.size,
    required this.mimeType,
    required this.dateModified,
    required this.mediaType,
    required this.bucketId,
    required this.bucketDisplayName,
  });
}
