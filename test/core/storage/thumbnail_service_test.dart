import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/thumbnail_native_service.dart';
import 'package:nas_server/core/storage/thumbnail_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ThumbnailService', () {
    late Directory rootDir;
    late ThumbnailService service;
    late _FakeThumbnailNativeService nativeService;

    tearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    test(
      'supports nested fs paths for thumbnail generation and cache hits',
      () async {
        rootDir = await Directory.systemTemp.createTemp(
          'thumb-service-nested-',
        );
        final nestedFile = File(
          p.join(rootDir.path, 'albums', 'trip', 'cover.jpg'),
        );
        await nestedFile.parent.create(recursive: true);
        await nestedFile.writeAsBytes([1, 2, 3]);

        nativeService = _FakeThumbnailNativeService();
        service = ThumbnailService(
          rootPath: rootDir.path,
          nativeService: nativeService,
        );

        final generated = await service.getOrGenerateThumbnail(
          '/fs/albums/trip/cover.jpg',
          ThumbnailType.grid,
        );
        final cached = await service.getThumbnail(
          '/fs/albums/trip/cover.jpg',
          ThumbnailType.grid,
        );

        expect(generated, Uint8List.fromList([1]));
        expect(cached, Uint8List.fromList([1]));
        expect(nativeService.calls, [
          (
            filePath: p.join(rootDir.path, 'albums', 'trip', 'cover.jpg'),
            size: 200,
            cropSquare: true,
          ),
        ]);
      },
    );

    test(
      'keeps same-name files in different subdirectories isolated',
      () async {
        rootDir = await Directory.systemTemp.createTemp(
          'thumb-service-collision-',
        );
        final firstFile = File(
          p.join(rootDir.path, 'albums', 'a', 'cover.jpg'),
        );
        final secondFile = File(
          p.join(rootDir.path, 'albums', 'b', 'cover.jpg'),
        );
        await firstFile.parent.create(recursive: true);
        await secondFile.parent.create(recursive: true);
        await firstFile.writeAsBytes([1]);
        await secondFile.writeAsBytes([2]);

        nativeService = _FakeThumbnailNativeService();
        service = ThumbnailService(
          rootPath: rootDir.path,
          nativeService: nativeService,
        );

        final firstGenerated = await service.getOrGenerateThumbnail(
          '/fs/albums/a/cover.jpg',
          ThumbnailType.grid,
        );
        final secondGenerated = await service.getOrGenerateThumbnail(
          '/fs/albums/b/cover.jpg',
          ThumbnailType.grid,
        );
        final firstCached = await service.getThumbnail(
          '/fs/albums/a/cover.jpg',
          ThumbnailType.grid,
        );
        final secondCached = await service.getThumbnail(
          '/fs/albums/b/cover.jpg',
          ThumbnailType.grid,
        );

        expect(firstGenerated, Uint8List.fromList([1]));
        expect(secondGenerated, Uint8List.fromList([2]));
        expect(firstCached, Uint8List.fromList([1]));
        expect(secondCached, Uint8List.fromList([2]));

        final cacheFiles = Directory(
          p.join(rootDir.path, '.thumbs', 'grid'),
        ).listSync().whereType<File>().toList();
        expect(cacheFiles, hasLength(2));
      },
    );

    test('deletes cached thumbnails by nested file path', () async {
      rootDir = await Directory.systemTemp.createTemp('thumb-service-delete-');
      final nestedFile = File(
        p.join(rootDir.path, 'albums', 'trip', 'cover.jpg'),
      );
      await nestedFile.parent.create(recursive: true);
      await nestedFile.writeAsBytes([1, 2, 3]);

      nativeService = _FakeThumbnailNativeService();
      service = ThumbnailService(
        rootPath: rootDir.path,
        nativeService: nativeService,
      );

      await service.getOrGenerateThumbnail(
        '/fs/albums/trip/cover.jpg',
        ThumbnailType.grid,
      );
      await service.getOrGenerateThumbnail(
        '/fs/albums/trip/cover.jpg',
        ThumbnailType.preview,
      );

      await service.deleteThumbnails('/fs/albums/trip/cover.jpg');

      expect(
        await service.getThumbnail(
          '/fs/albums/trip/cover.jpg',
          ThumbnailType.grid,
        ),
        isNull,
      );
      expect(
        await service.getThumbnail(
          '/fs/albums/trip/cover.jpg',
          ThumbnailType.preview,
        ),
        isNull,
      );
      expect(nativeService.calls, [
        (
          filePath: p.join(rootDir.path, 'albums', 'trip', 'cover.jpg'),
          size: 200,
          cropSquare: true,
        ),
        (
          filePath: p.join(rootDir.path, 'albums', 'trip', 'cover.jpg'),
          size: 800,
          cropSquare: false,
        ),
      ]);
    });

    test(
      'uses source version in cache key so overwritten files miss old cache',
      () async {
        rootDir = await Directory.systemTemp.createTemp(
          'thumb-service-versioned-',
        );
        final nestedFile = File(
          p.join(rootDir.path, 'albums', 'trip', 'cover.jpg'),
        );
        await nestedFile.parent.create(recursive: true);
        await nestedFile.writeAsBytes([1, 2, 3]);

        nativeService = _FakeThumbnailNativeService();
        service = ThumbnailService(
          rootPath: rootDir.path,
          nativeService: nativeService,
        );

        await service.getOrGenerateThumbnail(
          '/fs/albums/trip/cover.jpg',
          ThumbnailType.grid,
        );
        final firstStat = await nestedFile.stat();
        final gridDir = Directory(p.join(rootDir.path, '.thumbs', 'grid'));
        expect(gridDir.listSync().whereType<File>(), hasLength(1));

        await nestedFile.writeAsBytes([9, 8, 7, 6]);
        await nestedFile.setLastModified(
          firstStat.modified.add(const Duration(seconds: 2)),
        );

        expect(
          await service.getThumbnail(
            '/fs/albums/trip/cover.jpg',
            ThumbnailType.grid,
          ),
          isNull,
        );

        await service.deleteThumbnails(
          '/fs/albums/trip/cover.jpg',
          sourceModifiedMs: firstStat.modified.millisecondsSinceEpoch,
          sourceSizeBytes: firstStat.size,
        );

        expect(gridDir.listSync().whereType<File>(), isEmpty);
      },
    );

    test(
      'serializes concurrent generation for the same thumbnail target',
      () async {
        rootDir = await Directory.systemTemp.createTemp('thumb-service-race-');
        final nestedFile = File(
          p.join(rootDir.path, 'albums', 'trip', 'cover.jpg'),
        );
        await nestedFile.parent.create(recursive: true);
        await nestedFile.writeAsBytes([1, 2, 3]);

        final gate = Completer<void>();
        final blockingService = _BlockingThumbnailNativeService(gate);
        service = ThumbnailService(
          rootPath: rootDir.path,
          nativeService: blockingService,
        );

        final firstFuture = service.getOrGenerateThumbnail(
          '/fs/albums/trip/cover.jpg',
          ThumbnailType.grid,
        );
        final secondFuture = service.getOrGenerateThumbnail(
          '/fs/albums/trip/cover.jpg',
          ThumbnailType.grid,
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(blockingService.calls, hasLength(1));

        gate.complete();
        final results = await Future.wait([firstFuture, secondFuture]);
        expect(results[0], Uint8List.fromList([9]));
        expect(results[1], Uint8List.fromList([9]));
      },
    );
  });
}

class _FakeThumbnailNativeService extends ThumbnailNativeService {
  final List<({String filePath, int size, bool cropSquare})> calls =
      <({String filePath, int size, bool cropSquare})>[];

  @override
  Future<Uint8List?> generateThumbnail(
    String filePath,
    int size, {
    bool cropSquare = false,
  }) async {
    calls.add((filePath: filePath, size: size, cropSquare: cropSquare));
    if (filePath.contains('${p.separator}a${p.separator}')) {
      return Uint8List.fromList([1]);
    }
    if (filePath.contains('${p.separator}b${p.separator}')) {
      return Uint8List.fromList([2]);
    }
    return Uint8List.fromList([1]);
  }
}

class _BlockingThumbnailNativeService extends ThumbnailNativeService {
  _BlockingThumbnailNativeService(this._gate);

  final Completer<void> _gate;
  final List<({String filePath, int size, bool cropSquare})> calls =
      <({String filePath, int size, bool cropSquare})>[];

  @override
  Future<Uint8List?> generateThumbnail(
    String filePath,
    int size, {
    bool cropSquare = false,
  }) async {
    calls.add((filePath: filePath, size: size, cropSquare: cropSquare));
    await _gate.future;
    return Uint8List.fromList([9]);
  }
}
