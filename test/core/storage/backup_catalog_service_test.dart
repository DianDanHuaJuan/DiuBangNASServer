import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/backup_catalog_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BackupCatalogService', () {
    late Directory rootDir;
    late BackupCatalogService service;

    tearDown(() async {
      await service.close();
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    test(
      'returns need_hash before content checks, then skip/upload after hashes arrive',
      () async {
        rootDir = await Directory.systemTemp.createTemp('backup-catalog-win-');
        final existingFile = File(p.join(rootDir.path, 'abc123.jpg'));
        await existingFile.writeAsBytes([1, 2, 3]);

        service = BackupCatalogService(
          rootPath: rootDir.path,
          databasePath: p.join(rootDir.path, '.relay', 'backup_catalog.db'),
        );
        await service.initialize();
        await service.registerUpload(
          const BackupCatalogRegistration(
            sourceFingerprint: 'device|asset-1|3|1000',
            contentHash: 'abc123',
            deviceId: 'device',
            sourceId: 'asset-1',
            sizeBytes: 3,
            modifiedMs: 1000,
            relativePath: '/abc123.jpg',
          ),
        );

        final initialDecisions = await service.preflight(const [
          BackupPreflightItem(
            id: 'first',
            sourceFingerprint: 'device|asset-1|3|1000',
            extension: '.jpg',
            sizeBytes: 3,
            modifiedMs: 1000,
          ),
          BackupPreflightItem(
            id: 'second',
            sourceFingerprint: 'device|asset-2|3|2000',
            extension: '.jpg',
            sizeBytes: 3,
            modifiedMs: 2000,
          ),
        ]);

        expect(initialDecisions[0].action, 'skip');
        expect(initialDecisions[0].relativePath, '/abc123.jpg');
        expect(initialDecisions[1].action, 'need_hash');
        expect(initialDecisions[1].reason, 'hash_required');

        final finalDecisions = await service.preflight(const [
          BackupPreflightItem(
            id: 'second',
            sourceFingerprint: 'device|asset-2|3|2000',
            contentHash: 'abc123',
            extension: '.jpg',
            sizeBytes: 3,
            modifiedMs: 2000,
          ),
          BackupPreflightItem(
            id: 'third',
            sourceFingerprint: 'device|asset-3|4|3000',
            contentHash: 'def456',
            extension: '.jpg',
            sizeBytes: 4,
            modifiedMs: 3000,
          ),
        ]);

        expect(finalDecisions[0].action, 'skip');
        expect(finalDecisions[0].reason, 'content_match');
        expect(finalDecisions[1].action, 'upload');
        expect(finalDecisions[1].relativePath, '/def456.jpg');
      },
    );
  });
}
