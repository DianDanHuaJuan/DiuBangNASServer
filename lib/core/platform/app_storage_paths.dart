import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStoragePaths {
  static const String windowsDefaultRootFolderName = 'NASServer';
  static const String internalDataFolderName = 'nas_internal';
  static const String deviceAvatarFolderName = 'device_avatars';

  static String? _cachedDefaultStoragePath;
  static String? _cachedInternalDataDirectory;
  static String? _cachedDeviceAvatarDirectory;

  /// Resolves and caches the default storage root once per process.
  static Future<String> warmDefaultStoragePath() {
    return resolveDefaultStoragePath();
  }

  static Future<String> resolveDefaultStoragePath() async {
    final cached = _cachedDefaultStoragePath;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final resolved = await _resolveDefaultStoragePathUncached();
    _cachedDefaultStoragePath = resolved;
    return resolved;
  }

  static Future<String> _resolveDefaultStoragePathUncached() async {
    if (Platform.isAndroid) {
      return '/sdcard/NASServer';
    }

    if (Platform.isWindows) {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      return p.join(documentsDirectory.path, windowsDefaultRootFolderName);
    }

    final supportDirectory = await getApplicationSupportDirectory();
    return p.join(supportDirectory.path, windowsDefaultRootFolderName);
  }

  static Future<String> warmDeviceAvatarDirectory() {
    return resolveDeviceAvatarDirectory();
  }

  static Future<String> resolveInternalDataDirectory() async {
    final cached = _cachedInternalDataDirectory;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final resolved = p.join(supportDirectory.path, internalDataFolderName);
    _cachedInternalDataDirectory = resolved;
    return resolved;
  }

  static Future<String> resolveDeviceAvatarDirectory() async {
    final cached = _cachedDeviceAvatarDirectory;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final internalDirectory = await resolveInternalDataDirectory();
    final resolved = p.join(internalDirectory, deviceAvatarFolderName);
    _cachedDeviceAvatarDirectory = resolved;
    return resolved;
  }

  static String? get cachedDeviceAvatarDirectory => _cachedDeviceAvatarDirectory;

  /// Test-only helper to seed the cache without touching platform APIs.
  static void seedDefaultStoragePathForTests(String path) {
    _cachedDefaultStoragePath = path;
  }

  static void seedDeviceAvatarDirectoryForTests(String path) {
    _cachedDeviceAvatarDirectory = path;
  }

  static void resetCachedDefaultStoragePathForTests() {
    _cachedDefaultStoragePath = null;
  }

  static void resetCachedDeviceAvatarDirectoryForTests() {
    _cachedInternalDataDirectory = null;
    _cachedDeviceAvatarDirectory = null;
  }
}
