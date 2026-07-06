// 文件输入：MethodChannel（Android MediaStore）
// 文件职责：封装 MediaStore 查询和读取，提供媒体文件索引和内容访问
// 文件对外接口：MediaStoreService
// 文件包含：MediaStoreService, MediaReadResult
import 'dart:io';
import 'package:flutter/services.dart';
import '../../core/media_type.dart';

class MediaStoreService {
  static const _channel = MethodChannel('com.nasserver.nas_server/mediastore');

  Future<List<MediaFile>> queryImages() async {
    if (!Platform.isAndroid) return const [];
    try {
      final result = await _channel.invokeListMethod<Map>('queryImages');
      if (result == null) return [];
      return result
          .map((e) => MediaFile.fromMap(e.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaFile>> queryVideos() async {
    if (!Platform.isAndroid) return const [];
    try {
      final result = await _channel.invokeListMethod<Map>('queryVideos');
      if (result == null) return [];
      return result
          .map((e) => MediaFile.fromMap(e.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<MediaReadResult> readFile(
    String contentUri, {
    int? rangeStart,
    int? rangeEnd,
  }) async {
    if (!Platform.isAndroid) {
      return MediaReadResult(bytes: Uint8List(0), totalSize: 0);
    }
    try {
      final args = <String, Object?>{'uri': contentUri};
      if (rangeStart != null) {
        args['rangeStart'] = rangeStart;
      }
      if (rangeEnd != null) {
        args['rangeEnd'] = rangeEnd;
      }
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'readMediaFile',
        args,
      );

      if (result != null) {
        return MediaReadResult(
          bytes: Uint8List.fromList(List<int>.from(result['bytes'] ?? [])),
          totalSize: result['totalSize'] as int? ?? 0,
        );
      }
    } catch (e) {
      // Fallback
    }

    return MediaReadResult(bytes: Uint8List(0), totalSize: 0);
  }

  Future<MediaFile?> getFileInfo(String contentUri) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getMediaFileInfo',
        {'uri': contentUri},
      );

      if (result != null) {
        return MediaFile.fromMap(result);
      }
    } catch (e) {
      // Fallback
    }
    return null;
  }

  Future<int> getFileCount(MediaType type) async {
    if (!Platform.isAndroid) return 0;
    try {
      final count = await _channel.invokeMethod<int>('getMediaFileCount', {
        'type': type.name,
      });
      return count ?? 0;
    } catch (e) {
      return 0;
    }
  }
}

class MediaFile {
  final String id;
  final String contentUri;
  final String displayName;
  final String relativePath;
  final int size;
  final String mimeType;
  final DateTime dateModified;
  final MediaType mediaType;
  final String bucketId;
  final String bucketDisplayName;

  const MediaFile({
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

  factory MediaFile.fromMap(Map<String, dynamic> map) {
    return MediaFile(
      id: map['id']?.toString() ?? '',
      contentUri: map['contentUri'] ?? '',
      displayName: map['displayName'] ?? '',
      relativePath: map['relativePath'] ?? '',
      size: map['size'] ?? 0,
      mimeType: map['mimeType'] ?? '',
      dateModified: DateTime.fromMillisecondsSinceEpoch(
        map['dateModified'] ?? 0,
      ),
      mediaType: MediaType.values.firstWhere(
        (e) => e.name == map['mediaType'],
        orElse: () => MediaType.image,
      ),
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
      'dateModified': dateModified.millisecondsSinceEpoch,
      'mediaType': mediaType.name,
      'bucketId': bucketId,
      'bucketDisplayName': bucketDisplayName,
    };
  }
}

class MediaReadResult {
  final Uint8List bytes;
  final int totalSize;

  const MediaReadResult({required this.bytes, required this.totalSize});
}
