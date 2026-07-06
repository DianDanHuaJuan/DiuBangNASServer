import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/features/webdav/resolvers/file_system_dav_resource_resolver.dart';
import 'package:nas_server/features/webdav/utils/content_type_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileSystemDavResourceResolver', () {
    late Directory rootDir;
    late FileSystemDavResourceResolver resolver;

    setUp(() async {
      rootDir = await Directory.systemTemp.createTemp('dav-fs-root-');
      await File(p.join(rootDir.path, 'visible.jpg')).writeAsBytes([1]);
      final avatarDir = Directory(p.join(rootDir.path, 'device_avatars'));
      await avatarDir.create(recursive: true);
      await File(p.join(avatarDir.path, 'tablet-01.jpg')).writeAsBytes([2]);
      await Directory(p.join(rootDir.path, '.thumbs')).create();
      await File(
        p.join(rootDir.path, '.nas-upload-abc.part'),
      ).writeAsBytes([3]);

      resolver = FileSystemDavResourceResolver(
        rootPath: rootDir.path,
        contentTypeResolver: ContentTypeResolver(),
      );
    });

    tearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });

    test('listChildren hides internal share resources', () async {
      final children = await resolver.listChildren('/fs');
      final names = children.map((resource) => resource.name).toList();

      expect(names, ['visible.jpg']);
    });

    test('resolve rejects direct access to hidden avatar paths', () async {
      final resource = await resolver.resolve('/fs/device_avatars/tablet-01.jpg');
      expect(resource, isNull);
    });
  });
}
