import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';
import '../storage/key_value_store.dart';

typedef WindowsPowerStateReader = WindowsPowerState? Function();

class DeviceInfoService {
  DeviceInfoService({
    MethodChannel? channel,
    KeyValueStore? keyValueStore,
    bool? isAndroidOverride,
    bool? isWindowsOverride,
    String? localHostnameOverride,
    WindowsPowerStateReader? windowsPowerStateReader,
  }) : _channel =
           channel ??
           const MethodChannel('com.nasserver.nas_server/device_info'),
       _keyValueStore = keyValueStore,
       _isAndroidOverride = isAndroidOverride,
       _isWindowsOverride = isWindowsOverride,
       _localHostnameOverride = localHostnameOverride,
       _windowsPowerStateReader =
           windowsPowerStateReader ?? _queryWindowsPowerState;

  static const _deviceIdStorageKey = 'device_id';

  final MethodChannel _channel;
  final KeyValueStore? _keyValueStore;
  final bool? _isAndroidOverride;
  final bool? _isWindowsOverride;
  final String? _localHostnameOverride;
  final WindowsPowerStateReader _windowsPowerStateReader;

  bool get _isAndroid => _isAndroidOverride ?? Platform.isAndroid;
  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;

  bool get supportsBatteryTelemetry => _isAndroid || _isWindows;

  /// 仅查询电池 / 电源状态，不触及 deviceId、localHostname 等静态数据。
  Future<BatteryState?> queryBatteryState() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'getDeviceInfo',
        );
        if (result != null) {
          return BatteryState(
            batteryLevel: result['batteryLevel'] as int? ?? 1,
            batteryPercent:
                (result['batteryPercent'] as num?)?.toDouble() ?? 0.0,
            isCharging: result['isCharging'] as bool? ?? false,
          );
        }
      } catch (_) {}
    }

    if (_isWindows) {
      final powerState = _windowsPowerStateReader();
      if (powerState == null) {
        return null;
      }
      return BatteryState(
        batteryLevel: powerState.batteryLevel,
        batteryPercent: powerState.batteryPercent,
        isCharging: powerState.isCharging,
      );
    }

    return null;
  }

  Future<DeviceInfo> getDeviceInfo() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMapMethod<String, dynamic>(
          'getDeviceInfo',
        );
        if (result != null) {
          return DeviceInfo(
            deviceId: result['deviceId'] as String? ?? 'unknown',
            deviceName: result['deviceName'] as String? ?? 'Unknown Device',
            model: result['model'] as String? ?? 'Unknown',
            brand: result['brand'] as String? ?? 'Unknown',
            manufacturer: result['manufacturer'] as String? ?? 'Unknown',
            systemVersion: result['systemVersion'] as String? ?? 'Unknown',
            batteryLevel: result['batteryLevel'] as int? ?? 1,
            batteryPercent:
                (result['batteryPercent'] as num?)?.toDouble() ?? 0.0,
            isCharging: result['isCharging'] as bool? ?? false,
          );
        }
      } catch (_) {}
    }

    final windowsPowerState = _isWindows ? _windowsPowerStateReader() : null;
    final deviceId = await _loadOrCreateDeviceId();
    final deviceName = _resolveLocalHostname();
    return DeviceInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      model: deviceName,
      brand: Platform.operatingSystem,
      manufacturer: Platform.operatingSystem,
      systemVersion: Platform.operatingSystemVersion,
      batteryLevel: windowsPowerState?.batteryLevel ?? 0,
      batteryPercent: windowsPowerState?.batteryPercent ?? 0.0,
      isCharging: windowsPowerState?.isCharging ?? false,
    );
  }

  Future<String> getDeviceId() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('getAndroidId');
        if (result != null && result.trim().isNotEmpty) {
          return result;
        }
      } catch (_) {}
    }
    return _loadOrCreateDeviceId();
  }

  Future<String> getModel() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('getModel');
        return result ?? 'Unknown';
      } catch (_) {
        return 'Unknown';
      }
    }
    return _resolveLocalHostname().isEmpty
        ? Platform.operatingSystem
        : _resolveLocalHostname();
  }

  Future<String> getSystemVersion() async {
    if (_isAndroid) {
      try {
        final result = await _channel.invokeMethod<String>('getSystemVersion');
        return result ?? 'Unknown';
      } catch (_) {
        return 'Unknown';
      }
    }
    return Platform.operatingSystemVersion;
  }

  String _resolveLocalHostname() {
    final override = _localHostnameOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    final hostname = Platform.localHostname.trim();
    return hostname.isEmpty ? '铥棒文件S' : hostname;
  }

  Future<String> _loadOrCreateDeviceId() async {
    final cachedId = _keyValueStore?.getString(_deviceIdStorageKey)?.trim();
    if (cachedId != null && cachedId.isNotEmpty) {
      return cachedId;
    }

    final generatedId = 'nas-${_generateHex(16)}';
    await _keyValueStore?.setString(_deviceIdStorageKey, generatedId);
    return generatedId;
  }

  String _generateHex(int length) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }

  static WindowsPowerState? _queryWindowsPowerState() {
    final status = calloc<SYSTEM_POWER_STATUS>();
    try {
      if (GetSystemPowerStatus(status) == 0) {
        throw StateError(
          'GetSystemPowerStatus failed with error ${GetLastError()}',
        );
      }
      return WindowsPowerState.fromRawStatus(
        acLineStatus: status.ref.ACLineStatus,
        batteryFlag: status.ref.BatteryFlag,
        batteryLifePercent: status.ref.BatteryLifePercent,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to query Windows power status',
        name: 'nas_server.device_info',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    } finally {
      calloc.free(status);
    }
  }
}

class BatteryState {
  const BatteryState({
    required this.batteryLevel,
    required this.batteryPercent,
    required this.isCharging,
  });

  final int batteryLevel;
  final double batteryPercent;
  final bool isCharging;
}

class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String model;
  final String brand;
  final String manufacturer;
  final String systemVersion;
  final int batteryLevel;
  final double batteryPercent;
  final bool isCharging;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.model,
    required this.brand,
    required this.manufacturer,
    required this.systemVersion,
    required this.batteryLevel,
    required this.batteryPercent,
    required this.isCharging,
  });
}

class WindowsPowerState {
  const WindowsPowerState({
    required this.batteryLevel,
    required this.batteryPercent,
    required this.isCharging,
  });

  static const int _acLineOffline = 0;
  static const int _acLineOnline = 1;
  static const int _batteryFlagHigh = 1;
  static const int _batteryFlagLow = 2;
  static const int _batteryFlagCritical = 4;
  static const int _batteryFlagCharging = 8;
  static const int _batteryFlagNoSystemBattery = 128;
  static const int _batteryFlagUnknown = 255;
  static const int _batteryStatusUnknown = 1;
  static const int _batteryStatusCharging = 2;
  static const int _batteryStatusDischarging = 3;
  static const int _batteryStatusNotCharging = 4;
  static const int _batteryStatusFull = 5;

  final int batteryLevel;
  final double batteryPercent;
  final bool isCharging;

  factory WindowsPowerState.fromRawStatus({
    required int acLineStatus,
    required int batteryFlag,
    required int batteryLifePercent,
  }) {
    if (batteryFlag == _batteryFlagNoSystemBattery) {
      return const WindowsPowerState(
        batteryLevel: _batteryStatusCharging,
        batteryPercent: 100,
        isCharging: true,
      );
    }

    final batteryPercent = batteryLifePercent >= 0 && batteryLifePercent <= 100
        ? batteryLifePercent.toDouble()
        : _estimateBatteryPercent(
            acLineStatus: acLineStatus,
            batteryFlag: batteryFlag,
          );
    final isCharging =
        (batteryFlag != _batteryFlagUnknown &&
            (batteryFlag & _batteryFlagCharging) != 0) ||
        (acLineStatus == _acLineOnline && batteryPercent >= 100);

    return WindowsPowerState(
      batteryLevel: _resolveBatteryLevel(
        acLineStatus: acLineStatus,
        batteryFlag: batteryFlag,
        batteryPercent: batteryPercent,
        isCharging: isCharging,
      ),
      batteryPercent: batteryPercent,
      isCharging: isCharging,
    );
  }

  static double _estimateBatteryPercent({
    required int acLineStatus,
    required int batteryFlag,
  }) {
    if (batteryFlag == _batteryFlagUnknown) {
      return acLineStatus == _acLineOnline ? 100 : 0;
    }
    if ((batteryFlag & _batteryFlagCritical) != 0) {
      return 4;
    }
    if ((batteryFlag & _batteryFlagLow) != 0) {
      return 25;
    }
    if ((batteryFlag & _batteryFlagHigh) != 0) {
      return 100;
    }
    return acLineStatus == _acLineOnline ? 100 : 0;
  }

  static int _resolveBatteryLevel({
    required int acLineStatus,
    required int batteryFlag,
    required double batteryPercent,
    required bool isCharging,
  }) {
    if (isCharging) {
      return batteryPercent >= 100
          ? _batteryStatusFull
          : _batteryStatusCharging;
    }
    if (batteryFlag == _batteryFlagUnknown && batteryPercent <= 0) {
      return _batteryStatusUnknown;
    }
    if (acLineStatus == _acLineOnline) {
      return batteryPercent >= 100
          ? _batteryStatusFull
          : _batteryStatusNotCharging;
    }
    if (acLineStatus == _acLineOffline || batteryPercent > 0) {
      return _batteryStatusDischarging;
    }
    return _batteryStatusUnknown;
  }
}
