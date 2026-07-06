// 文件输入：flutter_foreground_task
// 文件职责：管理 Android 前台 Service 的启停和常驻通知
// 文件对外接口：ForegroundServiceDataSource
// 文件包含：ForegroundServiceDataSource
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'nas_foreground_task_contract.dart';
import 'nas_foreground_task_handler.dart';

/// 输入：String serverName, String ip, int port
/// 职责：通过 flutter_foreground_task 启停前台服务，并配置 WakeLock/WifiLock
/// 对外接口：initialize(), startForegroundService(), stopForegroundService(), isForegroundServiceRunning()
class ForegroundServiceDataSource {
  static const _channelId = 'nas_server_foreground_service';
  static const _channelName = '铥棒文件S';
  static const _channelDescription =
      'Keeps the NAS server reachable while the app is in the background.';
  static const _serviceTypes = [ForegroundServiceTypes.specialUse];
  static const _runtimeStatePollInterval = Duration(milliseconds: 200);
  static const _runtimeStartTimeout = Duration(seconds: 30);

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid || _isInitialized) {
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _isInitialized = true;
  }

  String _buildNotificationText({required String ip, required int port}) {
    return ip.isNotEmpty ? 'https://$ip:$port' : 'Service running';
  }

  Never _throwServiceFailure(String action, Object error) {
    throw Exception('Failed to $action foreground service: $error');
  }

  void _handleServiceResult({
    required String action,
    required ServiceRequestResult result,
  }) {
    switch (result) {
      case ServiceRequestSuccess():
        return;
      case ServiceRequestFailure():
        _throwServiceFailure(action, result.error);
    }
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) {
      return;
    }
    await initialize();
  }

  Future<bool> _isRunning() async {
    return Platform.isAndroid && await FlutterForegroundTask.isRunningService;
  }

  Future<bool> _updateRunningService({
    required String serverName,
    required String notificationText,
  }) async {
    final result = await FlutterForegroundTask.updateService(
      notificationTitle: serverName,
      notificationText: notificationText,
    );
    _handleServiceResult(action: 'update', result: result);
    return true;
  }

  Future<bool> _startNewService({
    required String serverName,
    required String notificationText,
  }) async {
    _ensureStartCallbackHandle();
    final result = await FlutterForegroundTask.startService(
      serviceId: NasForegroundTaskHandler.serviceId,
      serviceTypes: _serviceTypes,
      notificationTitle: serverName,
      notificationText: notificationText,
      notificationInitialRoute:
          NasForegroundTaskHandler.notificationInitialRoute,
      callback: nasForegroundTaskStartCallback,
    );
    _handleServiceResult(action: 'start', result: result);
    return true;
  }

  ui.CallbackHandle _ensureStartCallbackHandle() {
    final callbackHandle = ui.PluginUtilities.getCallbackHandle(
      nasForegroundTaskStartCallback,
    );
    if (callbackHandle == null) {
      throw Exception(
        'Foreground task callback handle could not be resolved before startup.',
      );
    }
    return callbackHandle;
  }

  Future<bool> _stopRunningService() async {
    final result = await FlutterForegroundTask.stopService();
    _handleServiceResult(action: 'stop', result: result);
    return true;
  }

  Future<void> _saveLaunchConfig({
    required String serverName,
    required String ip,
    required int port,
  }) async {
    await Future.wait([
      FlutterForegroundTask.saveData(
        key: NasForegroundTaskContract.serverNameKey,
        value: serverName,
      ),
      FlutterForegroundTask.saveData(
        key: NasForegroundTaskContract.serverIpKey,
        value: ip,
      ),
      FlutterForegroundTask.saveData(
        key: NasForegroundTaskContract.serverPortKey,
        value: port,
      ),
    ]);
  }

  Future<void> _prepareRuntimeLaunch({
    required String serverName,
    required String ip,
    required int port,
  }) async {
    await _saveLaunchConfig(serverName: serverName, ip: ip, port: port);
    await Future.wait([
      FlutterForegroundTask.saveData(
        key: NasForegroundTaskContract.runtimeStateKey,
        value: NasForegroundTaskContract.stateStarting,
      ),
      FlutterForegroundTask.removeData(
        key: NasForegroundTaskContract.runtimeErrorKey,
      ),
    ]);
  }

  Future<String?> _getRuntimeState() {
    return FlutterForegroundTask.getData<String>(
      key: NasForegroundTaskContract.runtimeStateKey,
    );
  }

  Future<String?> _getRuntimeError() {
    return FlutterForegroundTask.getData<String>(
      key: NasForegroundTaskContract.runtimeErrorKey,
    );
  }

  Future<void> _waitForRuntimeState(String targetState) async {
    final deadline = DateTime.now().add(_runtimeStartTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final runtimeState = await _getRuntimeState();
      if (runtimeState == targetState) {
        return;
      }

      final runtimeError = await _getRuntimeError();
      if (runtimeError != null && runtimeError.isNotEmpty) {
        throw Exception(runtimeError);
      }

      if (!await _isRunning()) {
        throw Exception(
          'Foreground service stopped before the NAS server finished starting. '
          'Last runtime state: ${runtimeState ?? 'unknown'}.',
        );
      }

      await Future.delayed(_runtimeStatePollInterval);
    }

    final runtimeState = await _getRuntimeState();
    final runtimeError = await _getRuntimeError();
    final serviceRunning = await _isRunning();
    throw Exception(
      'Timed out while waiting for the NAS server to start. '
      'runtimeState=${runtimeState ?? 'unknown'}, '
      'serviceRunning=$serviceRunning, '
      'runtimeError=${runtimeError ?? 'none'}.',
    );
  }

  Future<void> _markRuntimeStopped() async {
    await Future.wait([
      FlutterForegroundTask.saveData(
        key: NasForegroundTaskContract.runtimeStateKey,
        value: NasForegroundTaskContract.stateStopped,
      ),
      FlutterForegroundTask.removeData(
        key: NasForegroundTaskContract.runtimeErrorKey,
      ),
    ]);
  }

  Future<void> _stopServiceSilently() async {
    if (!await _isRunning()) {
      return;
    }

    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  Future<bool> startForegroundService({
    required String serverName,
    required String ip,
    required int port,
  }) async {
    if (!Platform.isAndroid) {
      return true;
    }

    await _ensureInitialized();
    final notificationText = _buildNotificationText(ip: ip, port: port);

    if (await _isRunning()) {
      await _saveLaunchConfig(serverName: serverName, ip: ip, port: port);
      await _updateRunningService(
        serverName: serverName,
        notificationText: notificationText,
      );
      await _waitForRuntimeState(NasForegroundTaskContract.stateRunning);
      return true;
    }

    await _prepareRuntimeLaunch(serverName: serverName, ip: ip, port: port);

    try {
      await _startNewService(
        serverName: serverName,
        notificationText: notificationText,
      );
      await _waitForRuntimeState(NasForegroundTaskContract.stateRunning);
      return true;
    } catch (error) {
      await _stopServiceSilently();
      await _markRuntimeStopped();
      rethrow;
    }
  }

  Future<bool> stopForegroundService() async {
    if (!await _isRunning()) {
      await _markRuntimeStopped();
      return true;
    }

    final result = await _stopRunningService();
    await _markRuntimeStopped();
    return result;
  }

  Future<bool> isForegroundServiceRunning() async {
    return _isRunning();
  }
}
