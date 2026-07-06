import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device/device_info_service.dart';
import 'package:nas_server/core/device/local_network_address_service.dart';
import 'package:nas_server/core/device/network_info_helper.dart';
import 'package:nas_server/core/device/system_info_service.dart';
import 'package:nas_server/core/device/system_status_cache.dart';
import 'package:nas_server/core/storage/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SystemStatusCache> createTestSystemStatusCache({
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

  final networkService = LocalNetworkAddressService(
    keyValueStore: keyValueStore,
    networkInfoHelper: NetworkInfoHelper(),
  );
  await networkService.initialize();
  if (selectedIp != null) {
    await networkService.setSelectedIp(selectedIp);
  }

  return SystemStatusCache(
    deviceInfoService: DeviceInfoService(),
    systemInfoService: SystemInfoService(),
    localNetworkAddressService: networkService,
  );
}
