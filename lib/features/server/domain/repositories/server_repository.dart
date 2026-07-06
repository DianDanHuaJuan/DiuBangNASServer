// 文件输入：无
// 文件职责：定义服务管理的抽象仓库接口
// 文件对外接口：ServerRepository
// 文件包含：ServerRepository 抽象类
abstract class ServerRepository {
  Future<void> startServer();
  Future<void> stopServer();
  bool get isRunning;
  String? get ipAddress;
  int? get port;
}
