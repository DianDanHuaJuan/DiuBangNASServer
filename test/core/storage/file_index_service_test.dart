import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/file_index_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileIndexService', () {
    late Directory rootDir;
    late FileIndexService service;

    tearDown(() async {
      await service.close();
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    test(
      'recursively indexes nested files and excludes internal folders',
      () async {
        rootDir = await Directory.systemTemp.createTemp('file-index-win-');
        final nestedDir = Directory(p.join(rootDir.path, 'albums', 'trip'));
        await nestedDir.create(recursive: true);
        await File(p.join(nestedDir.path, 'cover.jpg')).writeAsBytes([1, 2, 3]);
        await File(p.join(rootDir.path, 'note.pdf')).writeAsBytes([1]);
        await Directory(
          p.join(rootDir.path, '.thumbs'),
        ).create(recursive: true);
        await File(
          p.join(rootDir.path, '.thumbs', 'skip.jpg'),
        ).writeAsBytes([1, 2, 3]);
        final avatarDir = Directory(
          p.join(rootDir.path, 'device_avatars'),
        );
        await avatarDir.create(recursive: true);
        await File(
          p.join(avatarDir.path, 'tablet-01.jpg'),
        ).writeAsBytes([1, 2, 3]);

        service = FileIndexService(
          rootPath: rootDir.path,
          databasePath: p.join(rootDir.path, '.relay', 'file_index.db'),
          recursiveScan: true,
        );
        await service.initialize(startBackgroundIndex: false);
        await service.refreshIndex();

        final photoPage = await service.listFiles(limit: 10, category: 'photo');
        final documentPage = await service.listFiles(
          limit: 10,
          category: 'document',
        );

        expect(photoPage.items.map((item) => item.path), [
          '/albums/trip/cover.jpg',
        ]);
        expect(documentPage.items.map((item) => item.path), ['/note.pdf']);
      },
    );

    test('paginates with cursor offsets', () async {
      rootDir = await Directory.systemTemp.createTemp('file-index-page-');
      await File(p.join(rootDir.path, 'a.jpg')).writeAsBytes([1]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await File(p.join(rootDir.path, 'b.jpg')).writeAsBytes([1]);

      service = FileIndexService(
        rootPath: rootDir.path,
        databasePath: p.join(rootDir.path, '.relay', 'file_index.db'),
        recursiveScan: true,
      );
      await service.initialize(startBackgroundIndex: false);
      await service.refreshIndex();

      final firstPage = await service.listFiles(limit: 1, category: 'photo');
      final secondPage = await service.listFiles(
        limit: 1,
        category: 'photo',
        cursor: firstPage.nextCursor,
      );

      expect(firstPage.items, hasLength(1));
      expect(firstPage.hasMore, isTrue);
      expect(secondPage.items, hasLength(1));
      expect(secondPage.hasMore, isFalse);
      expect(firstPage.items.single.path, isNot(secondPage.items.single.path));
    });

    test('repairs stale rows before returning a page', () async {
      rootDir = await Directory.systemTemp.createTemp('file-index-stale-');
      final staleFile = File(p.join(rootDir.path, 'stale.jpg'));
      final liveFile = File(p.join(rootDir.path, 'live.jpg'));
      await staleFile.writeAsBytes([1]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await liveFile.writeAsBytes([1]);

      service = FileIndexService(
        rootPath: rootDir.path,
        databasePath: p.join(rootDir.path, '.relay', 'file_index.db'),
        recursiveScan: true,
      );
      await service.initialize(startBackgroundIndex: false);
      await service.refreshIndex();

      await staleFile.delete();

      final page = await service.listFiles(limit: 10, category: 'photo');

      expect(page.items.map((item) => item.path), ['/live.jpg']);
      expect(page.hasMore, isFalse);
    });

    test('listFiles returns immediately while background indexing completes', () async {
      rootDir = await Directory.systemTemp.createTemp('file-index-bg-');
      await File(p.join(rootDir.path, 'cover.jpg')).writeAsBytes([1, 2, 3]);

      service = FileIndexService(
        rootPath: rootDir.path,
        databasePath: p.join(rootDir.path, '.relay', 'file_index.db'),
        recursiveScan: true,
      );
      await service.initialize();

      await service.waitForInitialIndex();

      final indexedPage = await service.listFiles(limit: 10, category: 'photo');
      expect(indexedPage.items.map((item) => item.path), ['/cover.jpg']);
      expect(service.isIndexing, isFalse);
    });

    test('cancels refresh without committing partial index results', () async {
      rootDir = await Directory.systemTemp.createTemp('file-index-cancel-');
      service = FileIndexService(
        rootPath: rootDir.path,
        databasePath: p.join(rootDir.path, '.relay', 'file_index.db'),
        recursiveScan: true,
      );
      await service.initialize(startBackgroundIndex: false);

      await File(p.join(rootDir.path, 'cover.jpg')).writeAsBytes([1, 2, 3]);
      var checks = 0;

      await expectLater(
        service.refreshIndexWithCancellation(
          shouldContinue: () async {
            checks += 1;
            return checks < 2;
          },
        ),
        throwsA(isA<FileIndexRefreshCancelled>()),
      );

      final page = await service.listFiles(limit: 10, category: 'photo');
      expect(page.items, isEmpty);
    });
  });
}
