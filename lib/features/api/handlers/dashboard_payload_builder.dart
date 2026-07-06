// 文件输入：SystemStatusCache、服务端口、启动时间
// 文件职责：构建 dashboard 的统一 JSON 负载，供 HTTP 与 realtime 复用
// 文件对外接口：DashboardPayloadBuilder
// 文件包含：DashboardPayloadBuilder
import '../../../core/device/system_status_cache.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/runtime/runtime_build_info.dart';

class DashboardPayloadBuilder {
  DashboardPayloadBuilder({
    required SystemStatusCache systemStatusCache,
    required int port,
    required DateTime startedAt,
  }) : _systemStatusCache = systemStatusCache,
       _port = port,
       _startedAt = startedAt;

  final SystemStatusCache _systemStatusCache;
  final int _port;
  final DateTime _startedAt;

  Map<String, dynamic> build() {
    final now = DateTime.now();

    return {
      'device': {
        'deviceId': _systemStatusCache.deviceId,
        'model': _systemStatusCache.model,
        'brand': _systemStatusCache.brand,
        'platform': AppPlatform.identifier,
        'systemVersion': _systemStatusCache.systemVersion,
        'batteryLevel': _systemStatusCache.batteryLevel,
        'batteryPercent': _systemStatusCache.batteryPercent,
        'isCharging': _systemStatusCache.isCharging,
      },
      'system': {
        'storage': {
          'totalBytes': _systemStatusCache.totalStorage,
          'usedBytes': _systemStatusCache.usedStorage,
          'freeBytes': _systemStatusCache.freeStorage,
          'usagePercent': _systemStatusCache.storageUsagePercent,
        },
        'memory': {
          'totalBytes': _systemStatusCache.totalMemory,
          'usedBytes': _systemStatusCache.usedMemory,
          'freeBytes': _systemStatusCache.freeMemory,
          'usagePercent': _systemStatusCache.memoryUsagePercent,
        },
        'cpuTemperature': {
          'value': _systemStatusCache.cpuTemperature,
          'level': _getTemperatureLevel(_systemStatusCache.cpuTemperature),
        },
        'uptime': now.difference(_startedAt).inSeconds,
      },
      'network': {
        'localIp': _systemStatusCache.localIp ?? '0.0.0.0',
        'port': _port,
      },
      'server': {
        'status': 'online',
        'startedAt': _startedAt.toUtc().toIso8601String(),
        'build': RuntimeBuildInfo.toJson(),
      },
      'updatedAt':
          _systemStatusCache.lastUpdated?.toUtc().toIso8601String() ??
          now.toUtc().toIso8601String(),
    };
  }

  String _getTemperatureLevel(double temp) {
    if (temp <= 0) {
      return 'unknown';
    }
    if (temp < 40) {
      return 'low';
    }
    if (temp < 60) {
      return 'normal';
    }
    return 'high';
  }
}
