import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device_registry/device_avatar_store.dart';
import 'package:nas_server/core/storage/share_internal_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DeviceAvatarStore', () {
    late Directory avatarDirectory;
    late DeviceAvatarStore store;

    setUp(() async {
      avatarDirectory = await Directory.systemTemp.createTemp('avatar-store-');
      store = DeviceAvatarStore(avatarDirectoryPath: avatarDirectory.path);
    });

    tearDown(() async {
      if (await avatarDirectory.exists()) {
        await avatarDirectory.delete(recursive: true);
      }
    });

    test('saves and reads avatar bytes in the configured directory', () async {
      final bytes = List<int>.generate(128, (index) => index);

      final updatedAt = await store.saveAvatar(
        deviceId: 'tablet-01',
        bytes: bytes,
      );
      final readBytes = await store.readAvatarBytes('tablet-01');

      expect(readBytes, bytes);
      expect(updatedAt, isNotNull);
      expect(
        store.avatarFilePath('tablet-01'),
        p.join(avatarDirectory.path, 'tablet-01.jpg'),
      );
      expect(await File(store.avatarFilePath('tablet-01')).exists(), isTrue);
    });

    test('migrateFromLegacyStorageRoot copies missing avatars and removes legacy folder',
        () async {
      final legacyRoot = await Directory.systemTemp.createTemp('legacy-share-');
      final legacyDirectory = Directory(
        p.join(legacyRoot.path, deviceAvatarLegacyFolderName),
      );
      await legacyDirectory.create(recursive: true);
      await File(p.join(legacyDirectory.path, 'phone-01.jpg')).writeAsBytes([
        1,
        2,
        3,
      ]);
      await File(p.join(legacyDirectory.path, 'tablet-02.jpg')).writeAsBytes([
        4,
        5,
      ]);

      await store.saveAvatar(
        deviceId: 'tablet-02',
        bytes: [9, 9, 9],
      );

      await store.migrateFromLegacyStorageRoot(legacyRoot.path);

      expect(await store.readAvatarBytes('phone-01'), [1, 2, 3]);
      expect(await store.readAvatarBytes('tablet-02'), [9, 9, 9]);
      expect(await legacyDirectory.exists(), isFalse);
      expect(await legacyRoot.exists(), isTrue);

      await legacyRoot.delete(recursive: true);
    });
  });
}
