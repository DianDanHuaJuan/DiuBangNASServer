import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device/device_info_service.dart';
import 'package:nas_server/core/device/local_network_address_service.dart';
import 'package:nas_server/core/device/network_info_helper.dart';
import 'package:nas_server/core/device/network_interface_candidate.dart';
import 'package:nas_server/core/device/system_info_service.dart';
import 'package:nas_server/core/device/system_status_cache.dart';
import 'package:nas_server/core/storage/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SystemStatusCache', () {
    test(
      'refresh updates storage and memory even when network service has no ip',
      () async {
        final systemInfoService = _FakeSystemInfoService([
          const SystemStats(
            storageUsage: StorageUsage(
              totalBytes: 1000,
              usedBytes: 100,
              usagePercent: 10,
            ),
            memoryUsage: MemoryUsage(
              totalBytes: 2000,
              usedBytes: 200,
              usagePercent: 10,
            ),
            cpuTemperatureLevel: CpuTemperatureLevel.unknown,
          ),
          const SystemStats(
            storageUsage: StorageUsage(
              totalBytes: 1100,
              usedBytes: 150,
              usagePercent: 13.6,
            ),
            memoryUsage: MemoryUsage(
              totalBytes: 2100,
              usedBytes: 250,
              usagePercent: 11.9,
            ),
            cpuTemperatureLevel: CpuTemperatureLevel.unknown,
          ),
        ]);

        final cache = SystemStatusCache(
          deviceInfoService: _FakeDeviceInfoService(),
          systemInfoService: systemInfoService,
          localNetworkAddressService: await _createNetworkService(),
        );

        await cache.initialize();

        expect(cache.totalStorage, 1100);
        expect(cache.usedStorage, 150);
        expect(cache.totalMemory, 2000);
        expect(cache.usedMemory, 250);
        expect(cache.lastUpdated, isNotNull);
        cache.dispose();
      },
    );

    test(
      'refresh reads local ip from the unified network address service',
      () async {
        final cache = SystemStatusCache(
          deviceInfoService: _BatteryDeviceInfoService(),
          systemInfoService: _FakeSystemInfoService([
            const SystemStats(
              storageUsage: StorageUsage(
                totalBytes: 1000,
                usedBytes: 100,
                usagePercent: 10,
              ),
              memoryUsage: MemoryUsage(
                totalBytes: 2000,
                usedBytes: 200,
                usagePercent: 10,
              ),
              cpuTemperatureLevel: CpuTemperatureLevel.unknown,
            ),
          ]),
          localNetworkAddressService: await _createNetworkService(
            selectedIp: '192.168.1.10',
          ),
        );

        await cache.initialize();

        expect(cache.batteryLevel, 5);
        expect(cache.batteryPercent, 100);
        expect(cache.isCharging, isTrue);
        expect(cache.localIp, '192.168.1.10');
        cache.dispose();
      },
    );

    test('refreshStorageStats updates total and used storage together', () async {
      final systemInfoService = _FakeSystemInfoService([
        const SystemStats(
          storageUsage: StorageUsage(
            totalBytes: 1000,
            usedBytes: 100,
            usagePercent: 10,
          ),
          memoryUsage: MemoryUsage(
            totalBytes: 2000,
            usedBytes: 200,
            usagePercent: 10,
          ),
          cpuTemperatureLevel: CpuTemperatureLevel.unknown,
        ),
        const SystemStats(
          storageUsage: StorageUsage(
            totalBytes: 5000,
            usedBytes: 2500,
            usagePercent: 50,
          ),
          memoryUsage: MemoryUsage(
            totalBytes: 2000,
            usedBytes: 200,
            usagePercent: 10,
          ),
          cpuTemperatureLevel: CpuTemperatureLevel.unknown,
        ),
      ]);

      final cache = SystemStatusCache(
        deviceInfoService: _FakeDeviceInfoService(),
        systemInfoService: systemInfoService,
        localNetworkAddressService: await _createNetworkService(),
      );

      await cache.initialize();
      await cache.refreshStorageStats();

      expect(cache.totalStorage, 5000);
      expect(cache.usedStorage, 2500);
      cache.dispose();
    });
  });
}

Future<LocalNetworkAddressService> _createNetworkService({
  String? selectedIp,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final keyValueStore = KeyValueStore(sharedPreferences: prefs);
  if (selectedIp != null) {
    await keyValueStore.setString(
      LocalNetworkAddressService.preferredLocalIpv4Key,
      selectedIp,
    );
  }

  final service = LocalNetworkAddressService(
    keyValueStore: keyValueStore,
    networkInfoHelper: _EmptyNetworkInfoHelper(),
  );
  await service.initialize();
  return service;
}

class _FakeDeviceInfoService extends DeviceInfoService {
  @override
  bool get supportsBatteryTelemetry => false;
}

class _FakeSystemInfoService extends SystemInfoService {
  _FakeSystemInfoService(this._stats);

  final List<SystemStats> _stats;
  int _index = 0;

  @override
  Future<SystemStats> getSystemStats() async {
    final value = _stats[_index];
    if (_index < _stats.length - 1) {
      _index += 1;
    }
    return value;
  }
}

class _BatteryDeviceInfoService extends DeviceInfoService {
  _BatteryDeviceInfoService() : super(isWindowsOverride: false);

  @override
  bool get supportsBatteryTelemetry => true;

  @override
  Future<BatteryState?> queryBatteryState() async {
    return const BatteryState(
      batteryLevel: 5,
      batteryPercent: 100,
      isCharging: true,
    );
  }

  @override
  Future<DeviceInfo> getDeviceInfo() async {
    return const DeviceInfo(
      deviceId: 'windows-nas',
      deviceName: 'Windows NAS',
      model: 'Windows NAS',
      brand: 'windows',
      manufacturer: 'windows',
      systemVersion: 'Windows 11',
      batteryLevel: 5,
      batteryPercent: 100,
      isCharging: true,
    );
  }
}

class _EmptyNetworkInfoHelper extends NetworkInfoHelper {
  @override
  Future<List<NetworkInterfaceCandidate>> listIpv4Candidates() async {
    return const [];
  }
}
