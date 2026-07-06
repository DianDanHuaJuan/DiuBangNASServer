import 'dart:io';

import 'package:path/path.dart' as p;

import '../storage/share_internal_paths.dart';

class DeviceAvatarStore {
  DeviceAvatarStore({required String avatarDirectoryPath})
    : _avatarDirectoryPath = avatarDirectoryPath;

  static const maxAvatarBytes = 512 * 1024;

  final String _avatarDirectoryPath;

  Directory get avatarDirectory => Directory(_avatarDirectoryPath);

  String avatarFilePath(String deviceId) {
    return p.join(_avatarDirectoryPath, '${deviceId.trim()}.jpg');
  }

  Future<DateTime?> readUpdatedAt(String deviceId) async {
    final file = File(avatarFilePath(deviceId));
    if (!await file.exists()) {
      return null;
    }
    return (await file.lastModified()).toUtc();
  }

  DateTime? readUpdatedAtSync(String deviceId) {
    final file = File(avatarFilePath(deviceId));
    if (!file.existsSync()) {
      return null;
    }
    return file.lastModifiedSync().toUtc();
  }

  Future<bool> hasAvatar(String deviceId) async {
    return File(avatarFilePath(deviceId)).exists();
  }

  Future<List<int>?> readAvatarBytes(String deviceId) async {
    final file = File(avatarFilePath(deviceId));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<DateTime> saveAvatar({
    required String deviceId,
    required List<int> bytes,
  }) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Avatar bytes must not be empty');
    }
    if (bytes.length > maxAvatarBytes) {
      throw ArgumentError('Avatar exceeds maximum size of 512KB');
    }
    final directory = avatarDirectory;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final file = File(avatarFilePath(deviceId));
    await file.writeAsBytes(bytes, flush: true);
    return (await file.lastModified()).toUtc();
  }

  Future<void> deleteAvatar(String deviceId) async {
    final file = File(avatarFilePath(deviceId));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> migrateFromLegacyStorageRoot(String legacyStorageRoot) async {
    final legacyDirectory = Directory(
      p.join(legacyStorageRoot, deviceAvatarLegacyFolderName),
    );
    if (!await legacyDirectory.exists()) {
      return;
    }

    if (!await avatarDirectory.exists()) {
      await avatarDirectory.create(recursive: true);
    }

    await for (final entity in legacyDirectory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final fileName = p.basename(entity.path);
      if (!fileName.toLowerCase().endsWith('.jpg')) {
        continue;
      }
      final targetFile = File(p.join(_avatarDirectoryPath, fileName));
      if (await targetFile.exists()) {
        continue;
      }
      await entity.copy(targetFile.path);
    }

    await for (final entity in legacyDirectory.list(followLinks: false)) {
      if (entity is File) {
        await entity.delete();
      }
    }
    if (await legacyDirectory.exists()) {
      await legacyDirectory.delete(recursive: true);
    }
  }
}
