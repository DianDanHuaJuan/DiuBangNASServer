// 文件输入：无
// 文件职责：表达 MediaStore 原始记录的数据传输对象
// 文件对外接口：MediaStoreItemDto
// 文件包含：MediaStoreItemDto
class MediaStoreItemDto {
  final String id;
  final String contentUri;
  final String displayName;
  final String relativePath;
  final int size;
  final String mimeType;
  final int dateModified;
  final String mediaType;
  final String bucketId;
  final String bucketDisplayName;

  const MediaStoreItemDto({
    required this.id,
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

  factory MediaStoreItemDto.fromMap(Map<String, dynamic> map) {
    return MediaStoreItemDto(
      id: map['id']?.toString() ?? '',
      contentUri: map['contentUri'] ?? '',
      displayName: map['displayName'] ?? '',
      relativePath: map['relativePath'] ?? '',
      size: map['size'] ?? 0,
      mimeType: map['mimeType'] ?? '',
      dateModified: map['dateModified'] ?? 0,
      mediaType: map['mediaType'] ?? 'image',
      bucketId: map['bucketId'] ?? '',
      bucketDisplayName: map['bucketDisplayName'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'contentUri': contentUri,
      'displayName': displayName,
      'relativePath': relativePath,
      'size': size,
      'mimeType': mimeType,
      'dateModified': dateModified,
      'mediaType': mediaType,
      'bucketId': bucketId,
      'bucketDisplayName': bucketDisplayName,
    };
  }
}
