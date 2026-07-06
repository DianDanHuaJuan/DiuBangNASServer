import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/thumbnail_service.dart';
import 'package:nas_server/features/api/handlers/batch_thumbnail_handler.dart';
import 'package:nas_server/core/storage/thumbnail_concurrency_limiter.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('BatchThumbnailHandler', () {
    test('returns multipart 200 with per-item errors when all paths fail', () async {
      final handler = BatchThumbnailHandler(
        thumbnailService: _FakeThumbnailService(bytesByPath: const {}),
        concurrencyLimiter: ThumbnailConcurrencyLimiter(maxConcurrent: 2),
      );

      final response = await handler.handler(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1:9090/api/v1/thumbnails/batch'),
          body: jsonEncode(<String, dynamic>{
            'paths': <String>['/fs/photos/a.jpg', '/fs/photos/b.jpg'],
            'type': 'grid',
          }),
          headers: const <String, String>{'Content-Type': 'application/json'},
        ),
      );

      expect(response.statusCode, 200);
      expect(
        response.headers['Content-Type'],
        contains('multipart/mixed'),
      );

      final body = await response.read().fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      final bodyText = utf8.decode(body);
      expect(bodyText, contains('"successCount":0'));
      expect(bodyText, contains('"failedCount":2'));
      expect(bodyText, contains('"error":"NOT_FOUND"'));
      expect(bodyText, contains('/fs/photos/a.jpg'));
      expect(bodyText, contains('/fs/photos/b.jpg'));
    });

    test('marks invalid paths without calling thumbnail service', () async {
      final service = _FakeThumbnailService(
        bytesByPath: <String, Uint8List>{
          '/fs/photos/ok.jpg': Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF]),
        },
      );
      final handler = BatchThumbnailHandler(
        thumbnailService: service,
        concurrencyLimiter: ThumbnailConcurrencyLimiter(maxConcurrent: 2),
      );

      final response = await handler.handler(
        Request(
          'POST',
          Uri.parse('http://127.0.0.1:9090/api/v1/thumbnails/batch'),
          body: jsonEncode(<String, dynamic>{
            'paths': <String>['bad-path', '/fs/photos/ok.jpg'],
            'type': 'grid',
          }),
          headers: const <String, String>{'Content-Type': 'application/json'},
        ),
      );

      expect(response.statusCode, 200);
      expect(service.requestedPaths, <String>['/fs/photos/ok.jpg']);

      final body = await response.read().fold<List<int>>(
        <int>[],
        (previous, element) => previous..addAll(element),
      );
      final bodyText = utf8.decode(body, allowMalformed: true);
      expect(bodyText, contains('"error":"INVALID_PATH"'));
      expect(bodyText, contains('"successCount":1'));
      expect(bodyText, contains('"failedCount":1'));
    });
  });
}

class _FakeThumbnailService extends ThumbnailService {
  _FakeThumbnailService({required this.bytesByPath}) : super(rootPath: 'C:\\');

  final Map<String, Uint8List> bytesByPath;
  final List<String> requestedPaths = <String>[];

  @override
  Future<Uint8List?> getOrGenerateThumbnail(
    String filePath,
    ThumbnailType type,
  ) async {
    requestedPaths.add(filePath);
    return bytesByPath[filePath];
  }
}
