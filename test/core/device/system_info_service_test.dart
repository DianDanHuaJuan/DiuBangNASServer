import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device/system_info_service.dart';

void main() {
  group('SystemInfoService', () {
    test(
      'uses Win32 readers and resolves storage volume from configured path',
      () async {
        String? capturedVolumePath;
        final service = SystemInfoService(
          storagePathProvider: () => r'D:\DiuBangServer\data',
          isWindowsOverride: true,
          windowsStorageUsageReader: (volumePath) {
            capturedVolumePath = volumePath;
            return const StorageUsage(
              totalBytes: 2000,
              usedBytes: 500,
              usagePercent: 25,
            );
          },
          windowsMemoryUsageReader: () => const MemoryUsage(
            totalBytes: 1000,
            usedBytes: 250,
            usagePercent: 25,
          ),
        );

        final stats = await service.getSystemStats();

        expect(capturedVolumePath, r'D:\');
        expect(stats.storageUsage.totalBytes, 2000);
        expect(stats.storageUsage.usedBytes, 500);
        expect(stats.storageUsage.usagePercent, 25);
        expect(stats.memoryUsage.totalBytes, 1000);
        expect(stats.memoryUsage.usedBytes, 250);
        expect(stats.memoryUsage.usagePercent, 25);
        expect(stats.cpuTemperatureLevel, CpuTemperatureLevel.unknown);
        expect(service.recommendedRefreshInterval, const Duration(seconds: 20));
        expect(service.supportsCpuTemperatureTelemetry, isFalse);
      },
    );

    test('keeps memory stats when Windows storage lookup fails', () async {
      final service = SystemInfoService(
        isWindowsOverride: true,
        windowsStorageUsageReader: (_) => throw StateError('disk failed'),
        windowsMemoryUsageReader: () => const MemoryUsage(
          totalBytes: 4096,
          usedBytes: 2048,
          usagePercent: 50,
        ),
      );

      final stats = await service.getSystemStats();

      expect(stats.storageUsage.totalBytes, 0);
      expect(stats.storageUsage.usedBytes, 0);
      expect(stats.memoryUsage.totalBytes, 4096);
      expect(stats.memoryUsage.usedBytes, 2048);
      expect(stats.memoryUsage.usagePercent, 50);
      expect(stats.cpuTemperatureLevel, CpuTemperatureLevel.unknown);
    });

    test('keeps storage stats when Windows memory lookup fails', () async {
      final service = SystemInfoService(
        storagePathProvider: () => r'D:\DiuBangServer\data',
        isWindowsOverride: true,
        windowsStorageUsageReader: (_) => const StorageUsage(
          totalBytes: 8192,
          usedBytes: 1024,
          usagePercent: 12.5,
        ),
        windowsMemoryUsageReader: () => throw StateError('memory failed'),
      );

      final stats = await service.getSystemStats();

      expect(stats.storageUsage.totalBytes, 8192);
      expect(stats.storageUsage.usedBytes, 1024);
      expect(stats.storageUsage.usagePercent, 12.5);
      expect(stats.memoryUsage.totalBytes, 0);
      expect(stats.memoryUsage.usedBytes, 0);
      expect(stats.cpuTemperatureLevel, CpuTemperatureLevel.unknown);
    });
  });
}
