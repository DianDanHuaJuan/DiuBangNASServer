import 'dart:io';

class AppPlatform {
  static bool get isAndroid => Platform.isAndroid;
  static bool get isWindows => Platform.isWindows;
  static String get identifier {
    if (isWindows) {
      return 'windows';
    }
    if (isAndroid) {
      return 'android';
    }
    return Platform.operatingSystem.toLowerCase();
  }

  static bool get supportsSharedDirectoryAccess => isAndroid || isWindows;
  static bool get supportsForegroundService => isAndroid;
  static bool get requiresRuntimePermissions => isAndroid;
  static bool get supportsBatteryOptimizationControl => isAndroid;
  static bool get supportsMediaLibrary => isAndroid;
  static bool get supportsMediaChangeObserver => isAndroid;
  static bool get supportsMdnsRegistration => isAndroid || isWindows;
  static bool get supportsImagePreview => supportsSharedDirectoryAccess;
  static bool get supportsVideoPreview => supportsSharedDirectoryAccess;
  static bool get supportsProgressiveVideoPreview => supportsVideoPreview;
  static bool get supportsThumbnails => isAndroid || isWindows;
  static bool get supportsDesktopTray => isWindows;
  static bool get supportsVideoTranscoding => isWindows;
}
