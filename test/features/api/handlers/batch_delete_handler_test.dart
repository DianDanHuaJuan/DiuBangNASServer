import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/file_system_service.dart';
import 'package:nas_server/features/api/handlers/batch_delete_handler.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('BatchDeleteHandler', () {
    late Directory tempDir;
    late FileSystemService fileSystemService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'nas_server_batch_delete_',
      );
      fileSystemService = FileSystemService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes encoded fs file paths successfully', () async {
      final file = File('${tempDir.path}\\IMG 1 (2).jpg');
      await file.writeAsString('demo');
      final handler = BatchDeleteHandler(
        fileSystemService: fileSystemService,
        rootPath: tempDir.path,
      );

      final response = await handler.handle(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/files/batch-delete'),
          body: jsonEncode({
            'paths': ['/fs/IMG%201%20(2).jpg'],
          }),
          headers: const {'Content-Type': 'application/json'},
        ),
      );

      expect(response.statusCode, 200);
      expect(await file.exists(), isFalse);

      final json =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['deleted'], 1);
      final results = json['results'] as List<dynamic>;
      expect(results, hasLength(1));
      expect(results.single['path'], '/fs/IMG%201%20(2).jpg');
      expect(results.single['success'], isTrue);
    });

    test(
      'reports not found as per-item failure instead of 404 response',
      () async {
        final handler = BatchDeleteHandler(
          fileSystemService: fileSystemService,
          rootPath: tempDir.path,
        );

        final response = await handler.handle(
          Request(
            'POST',
            Uri.parse('http://localhost/api/v1/files/batch-delete'),
            body: jsonEncode({
              'paths': ['/fs/missing.jpg'],
            }),
            headers: const {'Content-Type': 'application/json'},
          ),
        );

        expect(response.statusCode, 200);
        final json =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(json['success'], isFalse);
        expect(json['deleted'], 0);
        expect(json['failed'], 1);
        final results = json['results'] as List<dynamic>;
        expect(results.single['success'], isFalse);
        expect(results.single['error'], contains('NOT_FOUND'));
      },
    );

    test('rejects traversal paths as item-level failures', () async {
      final handler = BatchDeleteHandler(
        fileSystemService: fileSystemService,
        rootPath: tempDir.path,
      );

      final response = await handler.handle(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/files/batch-delete'),
          body: jsonEncode({
            'paths': ['/fs/%2e%2e/secret.jpg'],
          }),
          headers: const {'Content-Type': 'application/json'},
        ),
      );

      expect(response.statusCode, 200);
      final json =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>;
      expect(results.single['success'], isFalse);
      expect(results.single['error'], contains('INVALID_PATH'));
    });
  });
}
