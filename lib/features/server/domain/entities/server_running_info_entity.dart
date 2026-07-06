// 文件输入：无
// 文件职责：定义服务运行时信息实体
// 文件对外接口：ServerRunningInfoEntity
// 文件包含：ServerRunningInfoEntity
class ServerRunningInfoEntity {
  final String ip;
  final int port;
  final String serverName;
  final DateTime startedAt;
  const ServerRunningInfoEntity({
    required this.ip,
    required this.port,
    required this.serverName,
    required this.startedAt,
  });
}
