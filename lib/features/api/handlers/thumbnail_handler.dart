// 文件输入：ThumbnailService, 文件路径
// 文件职责：处理缩略图请求，懒加载生成缩略图
// 文件对外接口：ThumbnailHandler
// 文件包含：ThumbnailHandler
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import '../../../../core/storage/thumbnail_service.dart';

class ThumbnailHandler {
  ThumbnailHandler({
    required ThumbnailService thumbnailService,
    bool mediaLibraryEnabled = false,
    bool thumbnailsEnabled = true,
  }) : _thumbnailService = thumbnailService,
       _mediaLibraryEnabled = mediaLibraryEnabled,
       _thumbnailsEnabled = thumbnailsEnabled;

  final ThumbnailService _thumbnailService;
  final bool _mediaLibraryEnabled;
  final bool _thumbnailsEnabled;

  Future<Response> handler(Request request) async {
    if (!_thumbnailsEnabled) {
      return Response(
        501,
        body:
            '{"code":"THUMBNAILS_DISABLED","message":"Thumbnail generation is not available on this platform","details":{}}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    final path = request.url.queryParameters['path'];
    final typeStr = request.url.queryParameters['type'] ?? 'grid';

    if (path == null || path.isEmpty) {
      return Response(
        400,
        body:
            '{"code":"INVALID_REQUEST","message":"Missing path parameter","details":{}}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    final libraryAllowed = _mediaLibraryEnabled && path.startsWith('/library/');
    if (!path.startsWith('/fs/') && !libraryAllowed) {
      return Response(
        400,
        body:
            '{"code":"INVALID_REQUEST","message":"Path must start with /fs/ or /library/","details":{}}',
        headers: {'Content-Type': 'application/json'},
      );
    }

    final type = typeStr == 'preview'
        ? ThumbnailType.preview
        : ThumbnailType.grid;

    try {
      Uint8List? bytes = await _thumbnailService.getOrGenerateThumbnail(
        path,
        type,
      );

      if (bytes == null) {
        return Response(
          404,
          body:
              '{"code":"NOT_FOUND","message":"Thumbnail not available","details":{}}',
          headers: {'Content-Type': 'application/json'},
        );
      }

      final contentType = _detectContentType(bytes, path);

      return Response.ok(
        bytes,
        headers: {
          'Content-Type': contentType,
          'Content-Length': bytes.length.toString(),
          'Cache-Control': 'public, max-age=86400',
        },
      );
    } catch (e) {
      return Response(
        500,
        body: '{"code":"INTERNAL_ERROR","message":"$e","details":{}}',
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  String _detectContentType(Uint8List bytes, String path) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }

    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }
}
