import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../platform/app_platform.dart';
import 'device_models.dart';
import 'device_store.dart';

/// Cross-isolate command names for device registry mutations.
abstract final class DeviceRegistryCommand {
  static const String event = 'deviceRegistryCommand';
  static const String resultEvent = 'deviceRegistryCommandResult';
  static const String actionDelete = 'delete';
  static const String actionSetStatus = 'setStatus';
}

/// Device registry writes that must run where WebSocket presence lives.
///
/// - Runtime isolate ([ownsServerRuntime] true): mutate [DeviceStore] directly.
/// - Android UI isolate while FGS runs: forward to the task handler.
/// - Otherwise: mutate the local store (server stopped / offline edit).
class DeviceRegistryAdmin {
  DeviceRegistryAdmin({
    required DeviceStore deviceStore,
    required bool Function() ownsServerRuntime,
    required Future<bool> Function() isForegroundServiceRunning,
    bool Function()? supportsForegroundService,
    void Function(Object data)? sendDataToTask,
    void Function(void Function(Object data) callback)? addTaskDataCallback,
    void Function(void Function(Object data) callback)? removeTaskDataCallback,
    String Function()? requestIdFactory,
    Duration commandTimeout = const Duration(seconds: 15),
  }) : _deviceStore = deviceStore,
       _ownsServerRuntime = ownsServerRuntime,
       _isForegroundServiceRunning = isForegroundServiceRunning,
       _supportsForegroundService =
           supportsForegroundService ??
           (() => AppPlatform.supportsForegroundService),
       _sendDataToTask = sendDataToTask ?? FlutterForegroundTask.sendDataToTask,
       _addTaskDataCallback =
           addTaskDataCallback ?? FlutterForegroundTask.addTaskDataCallback,
       _removeTaskDataCallback =
           removeTaskDataCallback ??
           FlutterForegroundTask.removeTaskDataCallback,
       _requestIdFactory =
           requestIdFactory ??
           (() => DateTime.now().toUtc().microsecondsSinceEpoch.toString()),
       _commandTimeout = commandTimeout;

  final DeviceStore _deviceStore;
  final bool Function() _ownsServerRuntime;
  final Future<bool> Function() _isForegroundServiceRunning;
  final bool Function() _supportsForegroundService;
  final void Function(Object data) _sendDataToTask;
  final void Function(void Function(Object data) callback) _addTaskDataCallback;
  final void Function(void Function(Object data) callback)
  _removeTaskDataCallback;
  final String Function() _requestIdFactory;
  final Duration _commandTimeout;

  Future<void> deleteDevice(String deviceId) {
    return _run(
      action: DeviceRegistryCommand.actionDelete,
      deviceId: deviceId,
      local: () => _deviceStore.deleteDevice(deviceId),
    );
  }

  Future<void> updateDeviceStatus({
    required String deviceId,
    required DeviceStatus status,
  }) {
    return _run(
      action: DeviceRegistryCommand.actionSetStatus,
      deviceId: deviceId,
      status: status,
      local: () => _deviceStore.updateDeviceStatus(
        deviceId: deviceId,
        status: status,
      ),
    );
  }

  Future<void> _run({
    required String action,
    required String deviceId,
    required Future<void> Function() local,
    DeviceStatus? status,
  }) async {
    final normalizedId = deviceId.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError('deviceId is required');
    }

    if (_ownsServerRuntime() || !_supportsForegroundService()) {
      await local();
      return;
    }

    if (!await _isForegroundServiceRunning()) {
      await local();
      return;
    }

    await _dispatchToForeground(
      action: action,
      deviceId: normalizedId,
      status: status,
    );
  }

  Future<void> _dispatchToForeground({
    required String action,
    required String deviceId,
    DeviceStatus? status,
  }) async {
    final requestId = _requestIdFactory();
    final completer = Completer<void>();

    void onData(Object data) {
      final map = _asStringKeyedMap(data);
      if (map == null) {
        return;
      }
      if (map['event'] != DeviceRegistryCommand.resultEvent) {
        return;
      }
      if ('${map['requestId']}' != requestId) {
        return;
      }
      if (completer.isCompleted) {
        return;
      }
      if (map['ok'] == true) {
        completer.complete();
        return;
      }
      final error = '${map['error'] ?? 'Device registry command failed'}';
      completer.completeError(StateError(error));
    }

    _addTaskDataCallback(onData);
    try {
      _sendDataToTask(<String, dynamic>{
        'event': DeviceRegistryCommand.event,
        'requestId': requestId,
        'action': action,
        'deviceId': deviceId,
        if (status != null) 'status': status.name,
      });
      await completer.future.timeout(_commandTimeout);
    } on TimeoutException {
      throw StateError(
        'Timed out waiting for foreground service to apply device registry change',
      );
    } finally {
      _removeTaskDataCallback(onData);
    }
  }

  static Map<String, dynamic>? _asStringKeyedMap(Object data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }
}
