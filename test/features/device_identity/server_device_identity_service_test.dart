import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device/device_info_service.dart';
import 'package:nas_server/core/device_registry/device_avatar_store.dart';
import 'package:nas_server/core/device_registry/device_store.dart';
import 'package:nas_server/core/profile/device_identity_store.dart';
import 'package:nas_server/core/storage/key_value_store.dart';
import 'package:nas_server/features/device_identity/domain/server_device_identity_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/device_store_harness.dart';

class _StubDeviceInfoService extends DeviceInfoService {
  _StubDeviceInfoService(this._deviceId);

  final String _deviceId;

  @override
  Future<String> getDeviceId() async => _deviceId;
}

Future<({ServerDeviceIdentityService service, DeviceStore deviceStore})>
_createFixture({
  required TestDeviceStoreHarness harness,
  required String hostPhysicalId,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final deviceStore = harness.createDeviceStore();
  await deviceStore.initialize();
  final tempDir = await Directory.systemTemp.createTemp('identity_test_');
  final service = ServerDeviceIdentityService(
    deviceStore: deviceStore,
    avatarStore: DeviceAvatarStore(
      avatarDirectoryPath: p.join(tempDir.path, 'device_avatars'),
    ),
    identityStore: DeviceIdentityStore(
      keyValueStore: KeyValueStore(sharedPreferences: prefs),
    ),
    deviceInfoService: _StubDeviceInfoService(hostPhysicalId),
  );
  return (service: service, deviceStore: deviceStore);
}

void main() {
  group('ServerDeviceIdentityService.listEnrolledClientDevices', () {
    test('excludes host when host and clients are enrolled', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final fixture = await _createFixture(
        harness: harness,
        hostPhysicalId: 'host-physical-01',
      );

      await fixture.deviceStore.enrollDevice(
        deviceId: 'host-physical-01',
        deviceName: 'NAS Host',
        physicalDeviceId: 'host-physical-01',
      );
      await fixture.deviceStore.enrollDevice(
        deviceId: 'phone-01',
        deviceName: 'Phone One',
        physicalDeviceId: 'phone-physical-01',
      );
      await fixture.deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Tablet One',
        physicalDeviceId: 'tablet-physical-01',
      );

      final clients = await fixture.service.listEnrolledClientDevices();

      expect(clients.length, 2);
      expect(
        clients.map((device) => device.deviceId).toList(),
        containsAll(['phone-01', 'tablet-01']),
      );
    });

    test('returns all devices when host is not enrolled', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final fixture = await _createFixture(
        harness: harness,
        hostPhysicalId: 'host-physical-01',
      );

      await fixture.deviceStore.enrollDevice(
        deviceId: 'phone-01',
        deviceName: 'Phone One',
        physicalDeviceId: 'phone-physical-01',
      );
      await fixture.deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Tablet One',
        physicalDeviceId: 'tablet-physical-01',
      );

      final clients = await fixture.service.listEnrolledClientDevices();
      final allDevices = await fixture.deviceStore.listDevices();

      expect(clients.length, allDevices.length);
      expect(
        clients.map((device) => device.deviceId).toList(),
        containsAll(allDevices.map((device) => device.deviceId)),
      );
    });
  });
}
