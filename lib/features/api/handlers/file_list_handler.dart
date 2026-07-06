import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../../core/storage/file_index_service.dart';

class FileListHandler {
  FileListHandler({required FileIndexService fileIndexService})
    : _fileIndexService = fileIndexService;

  final FileIndexService _fileIndexService;

  Future<Response> handle(Request request) async {
    try {
      final rootId = request.url.queryParameters['rootId'] ?? 'fs';
      final path = request.url.queryParameters['path'] ?? '/';
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '120');
      if (rootId != 'fs') {
        return _errorResponse(
          400,
          'INVALID_PARAMS',
          'Only the /fs root is supported',
        );
      }
      if (path != '/') {
        return _errorResponse(
          400,
          'INVALID_PARAMS',
          'Only the root path is supported for flat file listing',
        );
      }
      if (limit == null || limit <= 0) {
        return _errorResponse(
          400,
          'INVALID_PARAMS',
          'limit must be a positive integer',
        );
      }

      final page = await _fileIndexService.listFiles(
        cursor: request.url.queryParameters['cursor'],
        limit: limit,
        category: request.url.queryParameters['category'],
      );

      return Response.ok(
        jsonEncode({
          'items': page.items
              .map(
                (item) => {
                  'name': item.name,
                  'path': item.path,
                  'type': 'file',
                  'category': item.category,
                  'size': item.size,
                  'modifiedAt': item.modifiedAt.toIso8601String(),
                },
              )
              .toList(growable: false),
          'hasMore': page.hasMore,
          'nextCursor': page.nextCursor,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } on FormatException catch (error) {
      return _errorResponse(400, 'INVALID_PARAMS', error.message);
    } catch (error) {
      return _errorResponse(500, 'INTERNAL_ERROR', error.toString());
    }
  }

  Response _errorResponse(int status, String code, String message) {
    return Response(
      status,
      body: jsonEncode({'code': code, 'message': message, 'details': {}}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
