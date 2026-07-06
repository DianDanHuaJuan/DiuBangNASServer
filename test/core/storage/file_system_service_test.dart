import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/file_system_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileSystemService.validateSharedRootPath', () {
    late Directory tempDirectory;
    late FileSystemService service;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('nas_shared_root_');
      service = FileSystemService(
        environment: {
          'SystemDrive': p.rootPrefix(tempDirectory.path),
          'USERPROFILE': p.join(
            p.rootPrefix(tempDirectory.path),
            'Users',
            'tester',
          ),
        },
        isWindowsPlatform: true,
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test(
      'accepts an existing writable directory and normalizes trailing slashes',
      () async {
        final validatedPath = await service.validateSharedRootPath(
          '${tempDirectory.path}\\',
        );

        expect(validatedPath, tempDirectory.path);
      },
    );

    test('rejects drive roots', () async {
      final driveRoot = p.rootPrefix(tempDirectory.path);

      await expectLater(
        () => service.validateSharedRootPath(driveRoot),
        throwsA(
          isA<SharedRootPathException>().having(
            (error) => error.code,
            'code',
            SharedRootPathErrorCode.driveRootUnsupported,
          ),
        ),
      );
    });

    test(
      'rejects Windows protected directories before touching the filesystem',
      () async {
        final protectedPath = p.join(
          p.rootPrefix(tempDirectory.path),
          'Windows',
          'System32',
        );

        await expectLater(
          () => service.validateSharedRootPath(protectedPath),
          throwsA(
            isA<SharedRootPathException>().having(
              (error) => error.code,
              'code',
              SharedRootPathErrorCode.systemDirectoryUnsupported,
            ),
          ),
        );
      },
    );

    test(
      'rejects missing directories when auto creation is disabled',
      () async {
        final missingDirectoryPath = p.join(tempDirectory.path, 'missing');

        await expectLater(
          () => service.validateSharedRootPath(missingDirectoryPath),
          throwsA(
            isA<SharedRootPathException>().having(
              (error) => error.code,
              'code',
              SharedRootPathErrorCode.missingDirectory,
            ),
          ),
        );
      },
    );

    test('creates the directory when auto creation is allowed', () async {
      final missingDirectoryPath = p.join(tempDirectory.path, 'created-by-app');

      final validatedPath = await service.validateSharedRootPath(
        missingDirectoryPath,
        createIfMissing: true,
      );

      expect(validatedPath, missingDirectoryPath);
      expect(await Directory(missingDirectoryPath).exists(), isTrue);
    });
  });
}
