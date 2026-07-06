import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/thumbnail_service.dart';
import 'package:nas_server/features/api/handlers/thumbnail_handler.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('ThumbnailHandler', () {
    test(
      'uses the generated thumbnail bytes to determine content type',
      () async {
        final handler = ThumbnailHandler(
          thumbnailService: _FakeThumbnailService(
            bytesByPath: <String, Uint8List>{
              '/fs/photos/cover.png': Uint8List.fromList(
                <int>[0xFF, 0xD8, 0xFF, 0xE0],
              ),
            },
          ),
        );

        final response = await handler.handler(
          Request(
            'GET',
            Uri.parse(
              'http://10.0.0.8:9090/api/v1/thumbnail?path=%2Ffs%2Fphotos%2Fcover.png&type=preview',
            ),
          ),
        );

        expect(response.statusCode, 200);
        expect(response.headers['Content-Type'], 'image/jpeg');
      },
    );
  });
}

class _FakeThumbnailService extends ThumbnailService {
  _FakeThumbnailService({required this.bytesByPath}) : super(rootPath: 'C:\\');

  final Map<String, Uint8List> bytesByPath;

  @override
  Future<Uint8List?> getOrGenerateThumbnail(
    String filePath,
    ThumbnailType type,
  ) async {
    return bytesByPath[filePath];
  }
}
