// 文件输入：无
// 文件职责：定义服务器设置的业务实体
// 文件对外接口：ServerSettingsEntity
// 文件包含：ServerSettingsEntity
class ServerSettingsEntity {
  final int port;
  final String serverName;
  final String storagePath;
  final bool launchAtStartupEnabled;
  final bool hideToTrayOnClose;
  final bool minimizeToTray;
  final bool launchMinimizedToTray;

  const ServerSettingsEntity({
    required this.port,
    required this.serverName,
    required this.storagePath,
    this.launchAtStartupEnabled = false,
    this.hideToTrayOnClose = true,
    this.minimizeToTray = true,
    this.launchMinimizedToTray = false,
  });

  ServerSettingsEntity copyWith({
    int? port,
    String? serverName,
    String? storagePath,
    bool? launchAtStartupEnabled,
    bool? hideToTrayOnClose,
    bool? minimizeToTray,
    bool? launchMinimizedToTray,
  }) {
    return ServerSettingsEntity(
      port: port ?? this.port,
      serverName: serverName ?? this.serverName,
      storagePath: storagePath ?? this.storagePath,
      launchAtStartupEnabled:
          launchAtStartupEnabled ?? this.launchAtStartupEnabled,
      hideToTrayOnClose: hideToTrayOnClose ?? this.hideToTrayOnClose,
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      launchMinimizedToTray:
          launchMinimizedToTray ?? this.launchMinimizedToTray,
    );
  }
}
