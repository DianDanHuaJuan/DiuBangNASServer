import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/backup_catalog_service.dart';
import 'package:nas_server/features/api/handlers/backup_preflight_handler.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

void main() {
  group('BackupPreflightHandler', () {
    late Directory rootDir;
    late BackupCatalogService catalogService;
    late BackupPreflightHandler handler;

    setUp(() async {
      rootDir = await Directory.systemTemp.createTemp(
        'backup-preflight-handler-',
      );
      final existingFile = File(p.join(rootDir.path, 'abc123.jpg'));
      await existingFile.writeAsBytes([1, 2, 3]);
      catalogService = BackupCatalogService(
        rootPath: rootDir.path,
        databasePath: p.join(rootDir.path, '.relay', 'backup_catalog.db'),
      );
      await catalogService.initialize();
      await catalogService.registerUpload(
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
      handler = BackupPreflightHandler(backupCatalogService: catalogService);
    });

    tearDown(() async {
      await catalogService.close();
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    test(
      'returns need_hash when exact source does not match and content hash is absent',
      () async {
        final response = await handler.handle(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/backup/preflight'),
            body: jsonEncode({
              'rootId': 'fs',
              'items': [
                {
                  'id': 'first',
                  'sourceFingerprint': 'device|asset-2|3|2000',
                  'extension': '.jpg',
                  'sizeBytes': 3,
                  'modifiedMs': 2000,
                },
              ],
            }),
            headers: const {'content-type': 'application/json'},
          ),
        );

        final payload =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        final items = payload['items'] as List<dynamic>;

        expect(response.statusCode, 200);
        expect(items.single['action'], 'need_hash');
        expect(items.single['reason'], 'hash_required');
      },
    );
  });
}
