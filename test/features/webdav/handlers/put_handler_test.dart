import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/thumbnail_native_service.dart';
import 'package:nas_server/core/storage/thumbnail_service.dart';
import 'package:nas_server/features/webdav/handlers/put_handler.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

void main() {
  group('PutHandler', () {
    test(
      'returns 409 when duplicate upload has no explicit conflict policy',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'nas-put-handler',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final existingFile = File(
          '${tempDir.path}${Platform.pathSeparator}photo.jpg',
        );
        await existingFile.writeAsString('old-content');

        final handler = PutHandler(rootPath: tempDir.path);
        final response = await handler.handle(
          Request(
            'PUT',
            Uri.parse('http://localhost/fs/photo.jpg'),
            body: Stream<List<int>>.fromIterable([utf8.encode('new-content')]),
          ),
        );

        expect(response.statusCode, 409);
        expect(jsonDecode(await response.readAsString()), {
          'code': 'FILE_ALREADY_EXISTS',
          'message': 'A file with the same name already exists.',
          'file': {
            'rootId': 'fs',
            'relativePath': '/photo.jpg',
            'name': 'photo.jpg',
          },
        });
        expect(await existingFile.readAsString(), 'old-content');
      },
    );

    test(
      'overwrites existing file when overwrite policy is requested',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'nas-put-handler',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final existingFile = File(
          '${tempDir.path}${Platform.pathSeparator}photo.jpg',
        );
        await existingFile.writeAsString('old-content');

        final handler = PutHandler(rootPath: tempDir.path);
        final response = await handler.handle(
          Request(
            'PUT',
            Uri.parse('http://localhost/fs/photo.jpg'),
            headers: const {'x-nas-conflict-policy': 'overwrite'},
            body: Stream<List<int>>.fromIterable([
              utf8.encode('replacement-content'),
            ]),
          ),
        );

        final payload =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(response.statusCode, 200);
        expect(payload['file'], {
          'rootId': 'fs',
          'relativePath': '/photo.jpg',
          'name': 'photo.jpg',
        });
        expect(payload['overwritten'], isTrue);
        expect(payload['renamed'], isFalse);
        expect(await existingFile.readAsString(), 'replacement-content');
      },
    );

    test(
      'auto renames duplicate upload when rename policy is requested',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'nas-put-handler',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final existingFile = File(
          '${tempDir.path}${Platform.pathSeparator}photo.jpg',
        );
        await existingFile.writeAsString('old-content');

        final handler = PutHandler(rootPath: tempDir.path);
        final response = await handler.handle(
          Request(
            'PUT',
            Uri.parse('http://localhost/fs/photo.jpg'),
            headers: const {'x-nas-conflict-policy': 'rename'},
            body: Stream<List<int>>.fromIterable([
              utf8.encode('duplicate-content'),
            ]),
          ),
        );

        final payload =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        final renamedFile = File(
          '${tempDir.path}${Platform.pathSeparator}photo (1).jpg',
        );

        expect(response.statusCode, 201);
        expect(payload['file'], {
          'rootId': 'fs',
          'relativePath': '/photo (1).jpg',
          'name': 'photo (1).jpg',
        });
        expect(payload['overwritten'], isFalse);
        expect(payload['renamed'], isTrue);
        expect(await existingFile.readAsString(), 'old-content');
        expect(await renamedFile.readAsString(), 'duplicate-content');
      },
    );

    test('streams request body chunks to a new file', () async {
      final tempDir = await Directory.systemTemp.createTemp('nas-put-handler');
      addTearDown(() => tempDir.delete(recursive: true));

      final handler = PutHandler(rootPath: tempDir.path);
      final response = await handler.handle(
        Request(
          'PUT',
          Uri.parse('http://localhost/fs/video.mp4'),
          body: Stream<List<int>>.fromIterable([
            utf8.encode('chunk-1'),
            utf8.encode('-chunk-2'),
            utf8.encode('-chunk-3'),
          ]),
        ),
      );

      final payload =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final uploadedFile = File(
        '${tempDir.path}${Platform.pathSeparator}video.mp4',
      );

      expect(response.statusCode, 201);
      expect(payload['file'], {
        'rootId': 'fs',
        'relativePath': '/video.mp4',
        'name': 'video.mp4',
      });
      expect(await uploadedFile.readAsString(), 'chunk-1-chunk-2-chunk-3');
    });

    test('rejects nested upload paths', () async {
      final tempDir = await Directory.systemTemp.createTemp('nas-put-handler');
      addTearDown(() => tempDir.delete(recursive: true));

      final handler = PutHandler(rootPath: tempDir.path);
      final response = await handler.handle(
        Request(
          'PUT',
          Uri.parse('http://localhost/fs/folder/video.mp4'),
          body: Stream<List<int>>.fromIterable([utf8.encode('content')]),
        ),
      );

      expect(response.statusCode, 400);
      expect(
        await response.readAsString(),
        'Bad Request: Subdirectories are not allowed',
      );
    });

    test('cleans stale thumbnails before overwrite uploads', () async {
      final tempDir = await Directory.systemTemp.createTemp('nas-put-handler');
      addTearDown(() => tempDir.delete(recursive: true));

      final existingFile = File(
        '${tempDir.path}${Platform.pathSeparator}photo.jpg',
      );
      await existingFile.writeAsString('old-content');

      final thumbnailService = ThumbnailService(
        rootPath: tempDir.path,
        nativeService: _FakePutThumbnailNativeService(),
      );
      await thumbnailService.getOrGenerateThumbnail(
        '/fs/photo.jpg',
        ThumbnailType.grid,
      );

      final cacheDir = Directory(p.join(tempDir.path, '.thumbs', 'grid'));
      expect(cacheDir.listSync().whereType<File>(), hasLength(1));

      final handler = PutHandler(
        rootPath: tempDir.path,
        thumbnailService: thumbnailService,
      );
      final response = await handler.handle(
        Request(
          'PUT',
          Uri.parse('http://localhost/fs/photo.jpg'),
          headers: const {'x-nas-conflict-policy': 'overwrite'},
          body: Stream<List<int>>.fromIterable([
            utf8.encode('replacement-content'),
          ]),
        ),
      );

      expect(response.statusCode, 200);
      expect(cacheDir.listSync().whereType<File>(), isEmpty);
    });
  });
}

class _FakePutThumbnailNativeService extends ThumbnailNativeService {
  @override
  Future<Uint8List?> generateThumbnail(
    String filePath,
    int size, {
    bool cropSquare = false,
  }) async {
    return Uint8List.fromList([1, 2, 3]);
  }
}
