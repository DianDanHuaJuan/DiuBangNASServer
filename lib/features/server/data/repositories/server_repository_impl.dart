// 文件输入：ServerRepository, ServiceLocator
// 文件职责：实现 ServerRepository 接口，委托 ServiceLocator 管理前台 Service 与后台运行时
// 文件对外接口：ServerRepositoryImpl
// 文件包含：ServerRepositoryImpl
import 'package:nas_server/features/server/domain/repositories/server_repository.dart';
import 'package:nas_server/app/di/service_locator.dart';

class ServerRepositoryImpl implements ServerRepository {
  @override
  Future<void> startServer() async {
    await ServiceLocator.startServer();
  }

  @override
  Future<void> stopServer() async {
    await ServiceLocator.stopServer();
  }

  @override
  bool get isRunning => ServiceLocator.isServerRunning;

  @override
  String? get ipAddress => ServiceLocator.serverIp;

  @override
  int? get port => ServiceLocator.serverPort;
}
