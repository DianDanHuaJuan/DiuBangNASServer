// 文件输入：flutter_foreground_task
// 文件职责：定义 NAS 服务前台任务的后台入口和最小 TaskHandler
// 文件对外接口：NasForegroundTaskHandler
// 文件包含：NasForegroundTaskHandler
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../../app/di/service_locator.dart';
import 'nas_foreground_task_contract.dart';

/// 输入：无
/// 职责：为 flutter_foreground_task 提供后台入口，维持前台服务进程与常驻通知
/// 对外接口：startCallback(), serviceId, notificationInitialRoute
@pragma('vm:entry-point')
void nasForegroundTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(NasForegroundTaskHandler());
}

class NasForegroundTaskHandler extends TaskHandler {
  static const int serviceId = 1001;
  static const String notificationInitialRoute = '/';

  bool _isServiceLocatorReady = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final config = await _loadServerConfig();

    await _saveRuntimeState(NasForegroundTaskContract.stateStarting);
    await _clearRuntimeError();

    try {
      await ServiceLocator.setup(initializeForegroundService: false);
      _isServiceLocatorReady = true;

      await ServiceLocator.startServerRuntime(
        serverName: config.serverName,
        localIp: config.ip,
        port: config.port,
      );

      await _saveRuntimeState(NasForegroundTaskContract.stateRunning);
      await FlutterForegroundTask.updateService(
        notificationTitle: config.serverName,
        notificationText: _buildNotificationText(config.ip, config.port),
      );

      FlutterForegroundTask.sendDataToMain({
        'event': NasForegroundTaskContract.stateRunning,
        'ip': config.ip,
        'port': config.port,
      });
    } catch (error) {
      final message = error.toString();
      await _saveRuntimeState(NasForegroundTaskContract.stateError);
      await FlutterForegroundTask.saveData(
        key: NasForegroundTaskContract.runtimeErrorKey,
        value: message,
      );

      if (_isServiceLocatorReady) {
        await ServiceLocator.stopServerRuntime();
      }

      await FlutterForegroundTask.updateService(
        notificationTitle: config.serverName,
        notificationText: 'NAS server failed to start',
      );

      FlutterForegroundTask.sendDataToMain({
        'event': NasForegroundTaskContract.stateError,
        'error': message,
      });

      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    if (_isServiceLocatorReady) {
      await ServiceLocator.stopServerRuntime();
    }

    await _saveRuntimeState(NasForegroundTaskContract.stateStopped);
    await _clearRuntimeError();

    FlutterForegroundTask.sendDataToMain({
      'event': NasForegroundTaskContract.stateStopped,
      'isTimeout': isTimeout,
    });

    _isServiceLocatorReady = false;
  }

  Future<void> _saveRuntimeState(String state) async {
    await FlutterForegroundTask.saveData(
      key: NasForegroundTaskContract.runtimeStateKey,
      value: state,
    );
  }

  Future<void> _clearRuntimeError() async {
    await FlutterForegroundTask.removeData(
      key: NasForegroundTaskContract.runtimeErrorKey,
    );
  }

  Future<({String serverName, String ip, int port})> _loadServerConfig() async {
    final serverName =
        await FlutterForegroundTask.getData<String>(
          key: NasForegroundTaskContract.serverNameKey,
        ) ??
        '铥棒文件S';
    final ip =
        await FlutterForegroundTask.getData<String>(
          key: NasForegroundTaskContract.serverIpKey,
        ) ??
        '0.0.0.0';
    final port =
        await FlutterForegroundTask.getData<int>(
          key: NasForegroundTaskContract.serverPortKey,
        ) ??
        8080;

    return (serverName: serverName, ip: ip, port: port);
  }

  String _buildNotificationText(String ip, int port) {
    return ip.isNotEmpty ? 'https://$ip:$port' : 'Service running';
  }
}
