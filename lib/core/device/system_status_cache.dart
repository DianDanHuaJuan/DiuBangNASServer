import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../app/di/service_locator.dart';
import 'device_info_service.dart';
import 'local_network_address_service.dart';
import 'system_info_service.dart';

class SystemStatusCache extends ChangeNotifier {
  SystemStatusCache({
    required DeviceInfoService deviceInfoService,
    required SystemInfoService systemInfoService,
    required LocalNetworkAddressService localNetworkAddressService,
  }) : _deviceInfoService = deviceInfoService,
       _systemInfoService = systemInfoService,
       _localNetworkAddressService = localNetworkAddressService {
    _localNetworkAddressService.addListener(_syncLocalIpFromService);
  }

  final DeviceInfoService _deviceInfoService;
  final SystemInfoService _systemInfoService;
  final LocalNetworkAddressService _localNetworkAddressService;

  Timer? _refreshTimer;
  bool _isRefreshing = false;
  final ValueNotifier<bool> isInitialized = ValueNotifier(false);

  String deviceId = '';
  String model = '';
  String brand = '';
  String systemVersion = '';
  int totalStorage = 0;
  int totalMemory = 0;

  int batteryLevel = 1;
  double batteryPercent = 0.0;
  bool isCharging = false;
  int usedStorage = 0;
  int usedMemory = 0;
  double cpuTemperature = 0.0;

  String? localIp;

  DateTime? lastUpdated;
  int connectedClients = 0;

  Duration get refreshInterval => _systemInfoService.recommendedRefreshInterval;

  Future<void> initialize() async {
    await _loadStaticData();
    _syncLocalIpFromService();
    await refresh();
    _startPeriodicRefresh();
    isInitialized.value = true;
    notifyListeners();
  }

  Future<void> _loadStaticData() async {
    final deviceInfo = await _deviceInfoService.getDeviceInfo();
    deviceId = deviceInfo.deviceId;
    model = deviceInfo.model;
    brand = deviceInfo.brand;
    systemVersion = deviceInfo.systemVersion;

    final systemStats = await _systemInfoService.getSystemStats();
    totalStorage = systemStats.storageUsage.totalBytes;
    totalMemory = systemStats.memoryUsage.totalBytes;
  }

  Future<void> refresh() async {
    if (_isRefreshing) {
      return;
    }

    _isRefreshing = true;
    try {
      if (_deviceInfoService.supportsBatteryTelemetry) {
        final batteryState = await _deviceInfoService.queryBatteryState();
        if (batteryState != null) {
          batteryPercent = batteryState.batteryPercent;
          batteryLevel = batteryState.batteryLevel;
          isCharging = batteryState.isCharging;
        }
      }
      final systemStats = await _systemInfoService.getSystemStats();

      totalStorage = systemStats.storageUsage.totalBytes;
      usedStorage = systemStats.storageUsage.usedBytes;
      usedMemory = systemStats.memoryUsage.usedBytes;
      cpuTemperature = _extractTemperature(systemStats);
      _syncLocalIpFromService();
      connectedClients = _countConnectedClients();
      lastUpdated = DateTime.now();
      notifyListeners();
    } catch (e) {
      // ignore errors during refresh
    } finally {
      _isRefreshing = false;
    }
  }

  void _syncLocalIpFromService() {
    localIp = _localNetworkAddressService.effectiveIp;
  }

  double _extractTemperature(SystemStats stats) {
    if (stats.cpuTemperatureLevel == CpuTemperatureLevel.unknown) {
      return 0.0;
    }
    return 0.0;
  }

  int _countConnectedClients() {
    final registry = ServiceLocator.realtimeConnectionRegistry;
    if (registry == null) return 0;
    return registry.connections.length;
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(refreshInterval, (_) {
      unawaited(refresh());
    });
  }

  Future<void> refreshStorageStats() async {
    await refresh();
  }

  Future<void> refreshIpAddress() async {
    _syncLocalIpFromService();
    lastUpdated = DateTime.now();
    notifyListeners();
  }

  void notifyRuntimeStateChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _localNetworkAddressService.removeListener(_syncLocalIpFromService);
    _refreshTimer?.cancel();
    isInitialized.dispose();
    super.dispose();
  }

  int get freeStorage => totalStorage - usedStorage;
  int get freeMemory => totalMemory - usedMemory;
  double get storageUsagePercent =>
      totalStorage > 0 ? (usedStorage / totalStorage) * 100 : 0;
  double get memoryUsagePercent =>
      totalMemory > 0 ? (usedMemory / totalMemory) * 100 : 0;
}
