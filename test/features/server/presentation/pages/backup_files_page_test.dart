import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/app/di/service_locator.dart';
import 'package:nas_server/core/storage/backup_catalog_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupFilesPage readiness', () {
    Directory? tempDir;
    BackupCatalogService? catalog;

    tearDown(() async {
      await catalog?.close();
      catalog = null;
      ServiceLocator.backupCatalogService = null;
      ServiceLocator.localFileServicesReady.value = false;
      final dir = tempDir;
      tempDir = null;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('does not contain stale service-not-started copy', () {
      final source = File(
        'lib/features/server/presentation/pages/backup_files_page.dart',
      ).readAsStringSync();
      expect(source.contains('服务未启动'), isFalse);
      expect(source.contains('正在准备备份目录'), isTrue);
    });

    test('page lists files via fileIndexService not backup catalog only', () {
      final source = File(
        'lib/features/server/presentation/pages/backup_files_page.dart',
      ).readAsStringSync();
      expect(source.contains('indexService.listFiles'), isTrue);
      expect(source.contains('_loadFilePage'), isTrue);
    });

    test('areLocalFileServicesReady follows fileIndexService', () async {
      tempDir = await Directory.systemTemp.createTemp('backup-files-page-');
      catalog = BackupCatalogService(
        rootPath: tempDir!.path,
        databasePath: p.join(tempDir!.path, '.relay', 'backup_catalog_flag.db'),
      );
      await catalog!.initialize();
      ServiceLocator.backupCatalogService = catalog;
      ServiceLocator.localFileServicesReady.value = false;

      expect(ServiceLocator.areLocalFileServicesReady, isFalse);
    });

    test('media preview supports gallery navigation with arrows and keyboard', () {
      final source = File(
        'lib/features/server/presentation/pages/backup_files_page.dart',
      ).readAsStringSync();
      expect(source.contains('MediaPreviewPage'), isTrue);
      expect(source.contains('PageView.builder'), isTrue);
      expect(source.contains('chevron_left_rounded'), isTrue);
      expect(source.contains('chevron_right_rounded'), isTrue);
      expect(source.contains('LogicalKeyboardKey.arrowLeft'), isTrue);
      expect(source.contains('LogicalKeyboardKey.arrowRight'), isTrue);
      expect(source.contains('mediaItems'), isTrue);
      expect(source.contains('BackupImagePreviewPage'), isFalse);
    });

    test('localFileServicesReady listener can trigger reload contract', () {
      var reloadCount = 0;
      void onReady() {
        if (ServiceLocator.localFileServicesReady.value) {
          reloadCount += 1;
        }
      }

      ServiceLocator.localFileServicesReady.addListener(onReady);
      ServiceLocator.localFileServicesReady.value = true;
      ServiceLocator.localFileServicesReady.removeListener(onReady);

      expect(reloadCount, 1);
    });
  });
}
