import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/path_mapper.dart';

void main() {
  group('PathMapper', () {
    const mapper = PathMapper(rootPath: r'D:\NASRoot');

    test('maps encoded fs file paths into a safe local path', () {
      final mappedPath = mapper.resolve(
        '/fs/IMG%201.jpg',
        allowRoot: false,
        allowNestedPaths: false,
      );

      expect(mappedPath.root, ServerPathRoot.fs);
      expect(mappedPath.fileName, 'IMG 1.jpg');
      expect(mappedPath.relativePath, '/IMG 1.jpg');
      expect(mappedPath.localPath, contains('IMG 1.jpg'));
    });

    test('rejects traversal segments', () {
      expect(
        () => mapper.resolve('/fs/%2e%2e/secret.txt'),
        throwsA(
          isA<PathMappingException>().having(
            (error) => error.code,
            'code',
            PathMappingErrorCode.invalidPath,
          ),
        ),
      );
    });

    test('rejects nested paths when flat mode is required', () {
      expect(
        () => mapper.resolve('/fs/folder/file.txt', allowNestedPaths: false),
        throwsA(
          isA<PathMappingException>().having(
            (error) => error.code,
            'code',
            PathMappingErrorCode.nestedPathNotAllowed,
          ),
        ),
      );
    });

    test('rejects the reserved relay storage segment', () {
      expect(
        () => mapper.resolve('/fs/.relay/payload.bin'),
        throwsA(
          isA<PathMappingException>().having(
            (error) => error.code,
            'code',
            PathMappingErrorCode.invalidPath,
          ),
        ),
      );
    });

    test('rejects reserved internal share segments', () {
      for (final path in [
        '/fs/.thumbs/preview.jpg',
        '/fs/device_avatars/tablet-01.jpg',
      ]) {
        expect(
          () => mapper.resolve(path),
          throwsA(
            isA<PathMappingException>().having(
              (error) => error.code,
              'code',
              PathMappingErrorCode.invalidPath,
            ),
          ),
        );
      }
    });

    test('parses library paths without generating a local path', () {
      const parser = PathMapper();
      final mappedPath = parser.resolve(
        '/library/cover.jpg',
        allowRoot: false,
        allowNestedPaths: false,
      );

      expect(mappedPath.root, ServerPathRoot.library);
      expect(mappedPath.fileName, 'cover.jpg');
      expect(mappedPath.localPath, isNull);
    });
  });
}
