// 文件输入：KeyValueStore
// 文件职责：从本地存储读写服务器设置数据
// 文件对外接口：SettingsLocalDataSource
// 文件包含：SettingsLocalDataSource
import '../../../../core/platform/app_platform.dart';
import '../../../../core/platform/app_storage_paths.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../domain/entities/server_settings_entity.dart';

class SettingsLocalDataSource {
  SettingsLocalDataSource({required KeyValueStore keyValueStore})
    : _keyValueStore = keyValueStore;

  final KeyValueStore _keyValueStore;

  static const _keyPort = 'server_port';
  static const _keyServerName = 'server_name';
  static const _keyStoragePath = 'storage_path';
  static const _keyLaunchAtStartupEnabled = 'launch_at_startup_enabled';
  static const _keyHideToTrayOnClose = 'hide_to_tray_on_close';
  static const _keyMinimizeToTray = 'minimize_to_tray';
  static const _keyLaunchMinimizedToTray = 'launch_minimized_to_tray';
  static const _defaultPort = 8080;
  static const _defaultServerName = '铥棒文件S';
  static const _defaultHideToTrayOnClose = true;
  static const _defaultMinimizeToTray = true;

  Future<ServerSettingsEntity> loadSettings() async {
    final port = _keyValueStore.getInt(_keyPort) ?? _defaultPort;
    final serverName =
        _keyValueStore.getString(_keyServerName) ?? _defaultServerName;
    final storedStoragePath = _keyValueStore.getString(_keyStoragePath)?.trim();
    final storagePath = (storedStoragePath == null || storedStoragePath.isEmpty)
        ? await AppStoragePaths.resolveDefaultStoragePath()
        : storedStoragePath;

    if (!AppPlatform.supportsDesktopTray) {
      return ServerSettingsEntity(
        port: port,
        serverName: serverName,
        storagePath: storagePath,
      );
    }

    return ServerSettingsEntity(
      port: port,
      serverName: serverName,
      storagePath: storagePath,
      launchAtStartupEnabled:
          _keyValueStore.getBool(_keyLaunchAtStartupEnabled) ?? false,
      hideToTrayOnClose:
          _keyValueStore.getBool(_keyHideToTrayOnClose) ??
          _defaultHideToTrayOnClose,
      minimizeToTray:
          _keyValueStore.getBool(_keyMinimizeToTray) ?? _defaultMinimizeToTray,
      launchMinimizedToTray:
          _keyValueStore.getBool(_keyLaunchMinimizedToTray) ?? false,
    );
  }

  Future<void> saveSettings(ServerSettingsEntity settings) async {
    await _keyValueStore.setInt(_keyPort, settings.port);
    await _keyValueStore.setString(_keyServerName, settings.serverName);
    await _keyValueStore.setString(_keyStoragePath, settings.storagePath);
    if (AppPlatform.supportsDesktopTray) {
      await _keyValueStore.setBool(
        _keyLaunchAtStartupEnabled,
        settings.launchAtStartupEnabled,
      );
      await _keyValueStore.setBool(
        _keyHideToTrayOnClose,
        settings.hideToTrayOnClose,
      );
      await _keyValueStore.setBool(_keyMinimizeToTray, settings.minimizeToTray);
      await _keyValueStore.setBool(
        _keyLaunchMinimizedToTray,
        settings.launchMinimizedToTray,
      );
    }
  }
}
