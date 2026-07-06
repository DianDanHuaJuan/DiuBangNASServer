// 文件输入：无
// 文件职责：定义服务配置的数据传输对象
// 文件对外接口：ServerConfigDto
// 文件包含：ServerConfigDto
class ServerConfigDto {
  final int port;
  final String serverName;
  const ServerConfigDto({required this.port, required this.serverName});
}
