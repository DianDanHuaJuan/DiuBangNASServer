import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef WindowsStorageUsageReader = StorageUsage Function(String volumePath);
typedef WindowsMemoryUsageReader = MemoryUsage Function();

class SystemInfoService {
  SystemInfoService({
    String Function()? storagePathProvider,
    ProcessRunner? processRunner,
    bool? isWindowsOverride,
    WindowsStorageUsageReader? windowsStorageUsageReader,
    WindowsMemoryUsageReader? windowsMemoryUsageReader,
  }) : _storagePathProvider = storagePathProvider,
       _processRunner = processRunner ?? Process.run,
       _isWindowsOverride = isWindowsOverride,
       _windowsStorageUsageReader =
           windowsStorageUsageReader ?? _queryWindowsStorageUsageNative,
       _windowsMemoryUsageReader =
           windowsMemoryUsageReader ?? _queryWindowsMemoryUsageNative;

  static const MethodChannel _channel = MethodChannel(
    'com.nas.server/system_info',
  );

  final String Function()? _storagePathProvider;
  final ProcessRunner _processRunner;
  final bool? _isWindowsOverride;
  final WindowsStorageUsageReader _windowsStorageUsageReader;
  final WindowsMemoryUsageReader _windowsMemoryUsageReader;

  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;

  Duration get recommendedRefreshInterval =>
      _isWindows ? const Duration(seconds: 20) : const Duration(seconds: 5);

  bool get supportsCpuTemperatureTelemetry => !_isWindows;

  Future<SystemStats> getSystemStats() async {
    if (_isWindows) {
      return _queryWindowsSystemStats();
    }

    final results = await Future.wait([
      queryStorageUsage(),
      queryMemoryUsage(),
      queryCpuTemperature(),
    ]);

    return SystemStats(
      storageUsage: results[0] as StorageUsage,
      memoryUsage: results[1] as MemoryUsage,
      cpuTemperatureLevel: results[2] as CpuTemperatureLevel,
    );
  }

  Future<StorageUsage> queryStorageUsage() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod('getStorageInfo');
        if (result != null) {
          return StorageUsage(
            totalBytes: result['totalBytes'] as int,
            usedBytes: result['usedBytes'] as int,
            usagePercent: result['usagePercent'] as double,
          );
        }
      }

      final targetPath = _storagePathProvider?.call() ?? '/sdcard';
      final stat = await _processRunner('df', [targetPath]);
      final lines = stat.stdout.toString().split('\n');
      if (lines.length > 1) {
        final parts = lines[1].split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final total = int.tryParse(parts[1]) ?? 0;
          final used = int.tryParse(parts[2]) ?? 0;
          final usagePercent = total > 0 ? (used / total) * 100 : 0.0;
          return StorageUsage(
            totalBytes: total * 1024,
            usedBytes: used * 1024,
            usagePercent: usagePercent,
          );
        }
      }
    } catch (e) {
      // ignore
    }

    return const StorageUsage(totalBytes: 0, usedBytes: 0, usagePercent: 0);
  }

  Future<MemoryUsage> queryMemoryUsage() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod('getMemoryInfo');
        if (result != null) {
          return MemoryUsage(
            totalBytes: result['totalBytes'] as int,
            usedBytes: result['usedBytes'] as int,
            usagePercent: result['usagePercent'] as double,
          );
        }
      }

      final stat = await _processRunner('cat', ['/proc/meminfo']);
      final lines = stat.stdout.toString().split('\n');
      int memTotal = 0;
      int memFree = 0;
      int buffers = 0;
      int cached = 0;

      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          memTotal = _parseMemValue(line);
        } else if (line.startsWith('MemFree:')) {
          memFree = _parseMemValue(line);
        } else if (line.startsWith('Buffers:')) {
          buffers = _parseMemValue(line);
        } else if (line.startsWith('Cached:')) {
          cached = _parseMemValue(line);
        }
      }

      final memAvailable = memFree + buffers + cached;
      final usedBytes = memTotal - memAvailable;
      final usagePercent = memTotal > 0 ? (usedBytes / memTotal) * 100 : 0.0;

      return MemoryUsage(
        totalBytes: memTotal * 1024,
        usedBytes: usedBytes * 1024,
        usagePercent: usagePercent,
      );
    } catch (e) {
      return const MemoryUsage(totalBytes: 0, usedBytes: 0, usagePercent: 0);
    }
  }

  Future<SystemStats> _queryWindowsSystemStats() async {
    final storageUsage = _queryWindowsStorageUsage();
    final memoryUsage = _queryWindowsMemoryUsage();
    return SystemStats(
      storageUsage: storageUsage,
      memoryUsage: memoryUsage,
      cpuTemperatureLevel: CpuTemperatureLevel.unknown,
    );
  }

  StorageUsage _queryWindowsStorageUsage() {
    final volumePath = _resolveWindowsVolumePath();
    try {
      return _windowsStorageUsageReader(volumePath);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to query Windows storage usage for $volumePath',
        name: 'nas_server.system_info',
        error: error,
        stackTrace: stackTrace,
      );
      return const StorageUsage(totalBytes: 0, usedBytes: 0, usagePercent: 0);
    }
  }

  MemoryUsage _queryWindowsMemoryUsage() {
    try {
      return _windowsMemoryUsageReader();
    } catch (error, stackTrace) {
      developer.log(
        'Failed to query Windows memory usage',
        name: 'nas_server.system_info',
        error: error,
        stackTrace: stackTrace,
      );
      return const MemoryUsage(totalBytes: 0, usedBytes: 0, usagePercent: 0);
    }
  }

  int _parseMemValue(String line) {
    final match = RegExp(r'(\d+)').firstMatch(line);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  Future<CpuTemperatureLevel> queryCpuTemperature() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod('getCpuTemperature');
        if (result != null) {
          final temp = (result['temperature'] as num).toDouble();
          return CpuTemperatureLevel.fromTemperature(temp);
        }
      }

      final thermalDir = Directory('/sys/class/thermal');
      if (await thermalDir.exists()) {
        final zones = await thermalDir.list().toList();
        for (final zone in zones) {
          if (zone is Directory && zone.path.contains('thermal_zone')) {
            final tempFile = File('${zone.path}/temp');
            if (await tempFile.exists()) {
              final content = await tempFile.readAsString();
              final temp = int.tryParse(content.trim());
              if (temp != null) {
                return CpuTemperatureLevel.fromTemperature(temp / 1000.0);
              }
            }
          }
        }
      }
    } catch (e) {
      // ignore
    }

    return CpuTemperatureLevel.unknown;
  }

  Duration getUptime() {
    if (_isWindows) {
      return Duration.zero;
    }
    try {
      final stat = File('/proc/uptime');
      if (stat.existsSync()) {
        final content = stat.readAsStringSync().split(' ')[0];
        final seconds = double.tryParse(content);
        if (seconds != null) {
          return Duration(seconds: seconds.toInt());
        }
      }
    } catch (e) {
      // ignore
    }
    return Duration.zero;
  }

  String _resolveWindowsVolumePath() {
    final candidates = <String?>[
      _storagePathProvider?.call(),
      Platform.resolvedExecutable,
      Directory.current.path,
      Platform.environment['SystemDrive'],
    ];

    for (final candidate in candidates) {
      final volumePath = _normalizeWindowsVolumePath(candidate);
      if (volumePath != null) {
        return volumePath;
      }
    }

    return r'C:\';
  }

  static double _calculateUsagePercent({
    required int totalBytes,
    required int usedBytes,
  }) {
    return totalBytes > 0 ? (usedBytes / totalBytes) * 100 : 0.0;
  }

  String? _normalizeWindowsVolumePath(String? rawPath) {
    if (rawPath == null) {
      return null;
    }

    final trimmedPath = rawPath.trim();
    if (trimmedPath.isEmpty) {
      return null;
    }

    final absolutePath = p.isAbsolute(trimmedPath)
        ? trimmedPath
        : p.absolute(trimmedPath);
    final rootPrefix = p.rootPrefix(absolutePath);
    final match = RegExp(r'^[A-Za-z]:').firstMatch(rootPrefix);
    if (match == null) {
      return null;
    }

    return '${match.group(0)}\\';
  }

  static StorageUsage _queryWindowsStorageUsageNative(String volumePath) {
    final volumePathPtr = volumePath.toNativeUtf16();
    final freeBytesAvailablePtr = calloc<Uint64>();
    final totalBytesPtr = calloc<Uint64>();
    final totalFreeBytesPtr = calloc<Uint64>();

    try {
      final result = GetDiskFreeSpaceEx(
        volumePathPtr,
        freeBytesAvailablePtr,
        totalBytesPtr,
        totalFreeBytesPtr,
      );
      if (result == 0) {
        throw StateError(
          'GetDiskFreeSpaceExW failed with error ${GetLastError()} for $volumePath',
        );
      }

      final totalBytes = totalBytesPtr.value;
      final totalFreeBytes = totalFreeBytesPtr.value;
      final usedBytes = totalBytes >= totalFreeBytes
          ? totalBytes - totalFreeBytes
          : 0;

      return StorageUsage(
        totalBytes: totalBytes,
        usedBytes: usedBytes,
        usagePercent: _calculateUsagePercent(
          totalBytes: totalBytes,
          usedBytes: usedBytes,
        ),
      );
    } finally {
      calloc.free(volumePathPtr);
      calloc.free(freeBytesAvailablePtr);
      calloc.free(totalBytesPtr);
      calloc.free(totalFreeBytesPtr);
    }
  }

  static MemoryUsage _queryWindowsMemoryUsageNative() {
    final memoryStatusPtr = calloc<MEMORYSTATUSEX>();

    try {
      memoryStatusPtr.ref.dwLength = sizeOf<MEMORYSTATUSEX>();
      final result = GlobalMemoryStatusEx(memoryStatusPtr);
      if (result == 0) {
        throw StateError(
          'GlobalMemoryStatusEx failed with error ${GetLastError()}',
        );
      }

      final totalBytes = memoryStatusPtr.ref.ullTotalPhys;
      final availableBytes = memoryStatusPtr.ref.ullAvailPhys;
      final usedBytes = totalBytes >= availableBytes
          ? totalBytes - availableBytes
          : 0;

      return MemoryUsage(
        totalBytes: totalBytes,
        usedBytes: usedBytes,
        usagePercent: _calculateUsagePercent(
          totalBytes: totalBytes,
          usedBytes: usedBytes,
        ),
      );
    } finally {
      calloc.free(memoryStatusPtr);
    }
  }
}

class SystemStats {
  final StorageUsage storageUsage;
  final MemoryUsage memoryUsage;
  final CpuTemperatureLevel cpuTemperatureLevel;

  const SystemStats({
    required this.storageUsage,
    required this.memoryUsage,
    required this.cpuTemperatureLevel,
  });
}

class StorageUsage {
  final int totalBytes;
  final int usedBytes;
  final double usagePercent;

  const StorageUsage({
    required this.totalBytes,
    required this.usedBytes,
    required this.usagePercent,
  });
}

class MemoryUsage {
  final int totalBytes;
  final int usedBytes;
  final double usagePercent;

  const MemoryUsage({
    required this.totalBytes,
    required this.usedBytes,
    required this.usagePercent,
  });
}

enum CpuTemperatureLevel {
  low,
  normal,
  high,
  unknown;

  static CpuTemperatureLevel fromTemperature(double temp) {
    if (temp <= 0) return unknown;
    if (temp < 40) return low;
    if (temp < 60) return normal;
    return high;
  }

  String get displayName {
    switch (this) {
      case CpuTemperatureLevel.low:
        return '低';
      case CpuTemperatureLevel.normal:
        return '正常';
      case CpuTemperatureLevel.high:
        return '高';
      case CpuTemperatureLevel.unknown:
        return '未知';
    }
  }
}
