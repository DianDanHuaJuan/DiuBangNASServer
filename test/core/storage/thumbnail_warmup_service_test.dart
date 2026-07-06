import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/file_index_service.dart';
import 'package:nas_server/core/storage/thumbnail_native_service.dart';
import 'package:nas_server/core/storage/thumbnail_service.dart';
import 'package:nas_server/core/storage/thumbnail_warmup_service.dart';
import 'package:nas_server/features/realtime/data/realtime_connection_registry.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ThumbnailWarmupService', () {
    Directory? rootDir;
    FileIndexService? fileIndexService;
    late ThumbnailService thumbnailService;
    ThumbnailWarmupService? warmupService;
    late _FakeWarmupThumbnailNativeService nativeService;

    tearDown(() async {
      await warmupService?.close();
      await fileIndexService?.close();
      if (rootDir != null && await rootDir!.exists()) {
        await rootDir!.delete(recursive: true);
      }
    });

    test(
      'warms both grid and preview thumbnails for dirty media files',
      () async {
        rootDir = await Directory.systemTemp.createTemp('thumb-warmup-');
        final file = File(p.join(rootDir!.path, 'album.jpg'));
        await file.writeAsBytes([1, 2, 3]);

        nativeService = _FakeWarmupThumbnailNativeService();
        thumbnailService = ThumbnailService(
          rootPath: rootDir!.path,
          nativeService: nativeService,
        );
        fileIndexService = FileIndexService(
          rootPath: rootDir!.path,
          databasePath: p.join(rootDir!.path, '.relay', 'file_index.db'),
          recursiveScan: true,
          watchChanges: false,
        );
        await fileIndexService!.initialize(enableWatching: false);
        await fileIndexService!.refreshIndex();

        warmupService = ThumbnailWarmupService(
          rootPath: rootDir!.path,
          databasePath: p.join(rootDir!.path, '.relay', 'thumbnail_warmup.db'),
          thumbnailService: thumbnailService,
          fileIndexService: fileIndexService!,
          realtimeConnectionRegistry: RealtimeConnectionRegistry(),
          pollInterval: const Duration(days: 1),
        );
        await warmupService!.initialize(deferInitialScan: false);

        await warmupService!.markPathDirty('/album.jpg', reason: 'test');
        await warmupService!.processPendingNow();

        expect(
          await thumbnailService.getThumbnail(
            '/fs/album.jpg',
            ThumbnailType.grid,
          ),
          isNotNull,
        );
        expect(
          await thumbnailService.getThumbnail(
            '/fs/album.jpg',
            ThumbnailType.preview,
          ),
          isNotNull,
        );
        expect(nativeService.calls, [
          (
            filePath: p.join(rootDir!.path, 'album.jpg'),
            size: 200,
            cropSquare: true,
          ),
          (
            filePath: p.join(rootDir!.path, 'album.jpg'),
            size: 800,
            cropSquare: false,
          ),
        ]);
      },
    );
  });
}

class _FakeWarmupThumbnailNativeService extends ThumbnailNativeService {
  final List<({String filePath, int size, bool cropSquare})> calls =
      <({String filePath, int size, bool cropSquare})>[];

  @override
  Future<Uint8List?> generateThumbnail(
    String filePath,
    int size, {
    bool cropSquare = false,
  }) async {
    calls.add((filePath: filePath, size: size, cropSquare: cropSquare));
    return Uint8List.fromList([size == 200 ? 1 : 2]);
  }
}
