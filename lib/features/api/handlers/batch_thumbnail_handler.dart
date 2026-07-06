// 文件输入：ThumbnailService, HTTP Request
// 文件职责：处理批量缩略图请求，返回 MIME Multipart 格式的多个缩略图
// 文件对外接口：BatchThumbnailHandler
// 文件包含：BatchThumbnailHandler, ThumbnailResult
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import '../../../../core/storage/thumbnail_service.dart';
import '../../../../core/storage/thumbnail_concurrency_limiter.dart';
import '../../../../core/debug/server_debug_logging.dart';

class ThumbnailResult {
  ThumbnailResult({
    required this.path,
    required this.index,
    required this.success,
    this.bytes,
    this.contentType,
    this.size,
    this.error,
  });

  final String path;
  final int index;
  final bool success;
  final Uint8List? bytes;
  final String? contentType;
  final int? size;
  final String? error;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'path': path,
      'index': index,
      'success': success,
    };
    if (success) {
      json['contentType'] = contentType;
      json['size'] = size;
    } else {
      json['error'] = error;
    }
    return json;
  }
}

class BatchThumbnailHandler {
  BatchThumbnailHandler({
    required ThumbnailService thumbnailService,
    required ThumbnailConcurrencyLimiter concurrencyLimiter,
    bool mediaLibraryEnabled = false,
    bool thumbnailsEnabled = true,
  }) : _thumbnailService = thumbnailService,
       _concurrencyLimiter = concurrencyLimiter,
       _mediaLibraryEnabled = mediaLibraryEnabled,
       _thumbnailsEnabled = thumbnailsEnabled;

  final ThumbnailService _thumbnailService;
  final ThumbnailConcurrencyLimiter _concurrencyLimiter;
  final bool _mediaLibraryEnabled;
  final bool _thumbnailsEnabled;
  static const int _maxBatchSize = 50;
  static const String _boundary = '----nas_batch_thumbnails';

  Future<Response> handler(Request request) async {
    if (!_thumbnailsEnabled) {
      return _errorResponse(
        501,
        'THUMBNAILS_DISABLED',
        'Thumbnail generation is not available on this platform',
      );
    }

    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final paths = (json['paths'] as List?)?.cast<String>();
      if (paths == null || paths.isEmpty) {
        return _errorResponse(
          400,
          'INVALID_REQUEST',
          'paths array is required and cannot be empty',
        );
      }

      if (paths.length > _maxBatchSize) {
        return _errorResponse(
          400,
          'INVALID_REQUEST',
          'paths array cannot exceed $_maxBatchSize items',
        );
      }

      final typeStr = (json['type'] as String?) ?? 'grid';
      final type = typeStr == 'preview'
          ? ThumbnailType.preview
          : ThumbnailType.grid;

      final results = <ThumbnailResult>[];
      final successParts = <ThumbnailResult>[];

      final futures = paths.asMap().entries.map((entry) async {
        final index = entry.key;
        final path = entry.value;

        final libraryAllowed =
            _mediaLibraryEnabled && path.startsWith('/library/');
        if (!path.startsWith('/fs/') && !libraryAllowed) {
          return ThumbnailResult(
            path: path,
            index: index,
            success: false,
            error: 'INVALID_PATH',
          );
        }

        try {
          final bytes = await _concurrencyLimiter.run(
            () => _thumbnailService.getOrGenerateThumbnail(path, type),
          );
          if (bytes != null) {
            final contentType = _detectContentType(bytes, path);
            return ThumbnailResult(
              path: path,
              index: index,
              success: true,
              bytes: bytes,
              contentType: contentType,
              size: bytes.length,
            );
          } else {
            return ThumbnailResult(
              path: path,
              index: index,
              success: false,
              error: 'NOT_FOUND',
            );
          }
        } catch (e, stackTrace) {
          logServerDebugMessage(
            scope: 'batch_thumbnail',
            request: request,
            message: 'Thumbnail generation failed',
            error: e,
            stackTrace: stackTrace,
            details: <String, Object?>{
              'path': path,
              'type': typeStr,
              'error': 'INTERNAL_ERROR',
            },
          );
          return ThumbnailResult(
            path: path,
            index: index,
            success: false,
            error: 'INTERNAL_ERROR',
          );
        }
      });

      final thumbnails = await Future.wait(futures);

      for (final thumb in thumbnails) {
        if (thumb.success) {
          successParts.add(thumb);
        } else {
          logServerDebugMessage(
            scope: 'batch_thumbnail',
            request: request,
            message: 'Thumbnail batch item failed',
            details: <String, Object?>{
              'path': thumb.path,
              'index': thumb.index,
              'error': thumb.error ?? 'UNKNOWN',
              'type': typeStr,
            },
          );
        }
        results.add(thumb);
      }

      if (results.length - successParts.length > 0) {
        logServerDebugMessage(
          scope: 'batch_thumbnail',
          request: request,
          message: 'Thumbnail batch completed with failures',
          details: <String, Object?>{
            'total': results.length,
            'successCount': successParts.length,
            'failedCount': results.length - successParts.length,
            'type': typeStr,
          },
        );
      }

      return _buildMultipartResponse(results, successParts);
    } catch (e) {
      if (e is FormatException) {
        return _errorResponse(400, 'INVALID_REQUEST', 'Invalid JSON body');
      }
      return _errorResponse(500, 'INTERNAL_ERROR', e.toString());
    }
  }

  Response _buildMultipartResponse(
    List<ThumbnailResult> results,
    List<ThumbnailResult> successParts,
  ) {
    final buffer = <int>[];

    final indexJson = {
      'thumbnails': results.map((r) => r.toJson()).toList(),
      'total': results.length,
      'successCount': successParts.length,
      'failedCount': results.length - successParts.length,
    };

    buffer.addAll(utf8.encode('--$_boundary\r\n'));
    buffer.addAll(
      utf8.encode('Content-Type: application/json; charset=utf-8\r\n'),
    );
    buffer.addAll(
      utf8.encode('Content-Disposition: attachment; filename="index.json"\r\n'),
    );
    buffer.addAll(utf8.encode('\r\n'));
    buffer.addAll(utf8.encode(jsonEncode(indexJson)));
    buffer.addAll(utf8.encode('\r\n'));

    for (final result in successParts) {
      if (result.bytes == null) continue;

      final fileName = result.path.split('/').last;
      buffer.addAll(utf8.encode('--$_boundary\r\n'));
      buffer.addAll(utf8.encode('Content-Type: ${result.contentType}\r\n'));
      buffer.addAll(
        utf8.encode(
          'Content-Disposition: attachment; filename="$fileName"\r\n',
        ),
      );
      buffer.addAll(utf8.encode('X-Thumbnail-Index: ${result.index}\r\n'));
      buffer.addAll(utf8.encode('X-Thumbnail-Path: ${result.path}\r\n'));
      buffer.addAll(utf8.encode('\r\n'));
      buffer.addAll(result.bytes!);
      buffer.addAll(utf8.encode('\r\n'));
    }

    buffer.addAll(utf8.encode('--$_boundary--\r\n'));

    return Response.ok(
      Uint8List.fromList(buffer),
      headers: {
        'Content-Type': 'multipart/mixed; boundary=$_boundary',
        'Cache-Control': 'public, max-age=86400',
      },
    );
  }

  Response _errorResponse(int status, String code, String message) {
    return Response(
      status,
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
      headers: {'Content-Type': 'application/json'},
    );
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
