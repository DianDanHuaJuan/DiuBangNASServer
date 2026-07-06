// 文件输入：无
// 文件职责：定义更新服务器设置的入参对象
// 文件对外接口：UpdateServerSettingsParams
// 文件包含：UpdateServerSettingsParams
class UpdateServerSettingsParams {
  final int port;
  final String? serverName;
  final String? storagePath;
  final bool? launchAtStartupEnabled;
  final bool? hideToTrayOnClose;
  final bool? minimizeToTray;
  final bool? launchMinimizedToTray;

  const UpdateServerSettingsParams({
    required this.port,
    this.serverName,
    this.storagePath,
    this.launchAtStartupEnabled,
    this.hideToTrayOnClose,
    this.minimizeToTray,
    this.launchMinimizedToTray,
  });
}
