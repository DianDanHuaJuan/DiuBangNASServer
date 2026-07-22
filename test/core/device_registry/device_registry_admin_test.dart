import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device_registry/device_models.dart';
import 'package:nas_server/core/device_registry/device_registry_admin.dart';
import 'package:nas_server/core/device_registry/device_store.dart';

import '../../test_support/device_store_harness.dart';

void main() {
  group('DeviceRegistryAdmin', () {
    late TestDeviceStoreHarness harness;
    late DeviceStore deviceStore;
    late List<Object> sentToTask;
    late List<void Function(Object data)> callbacks;

    setUp(() async {
      harness = await TestDeviceStoreHarness.create();
      deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();
      sentToTask = <Object>[];
      callbacks = <void Function(Object data)>[];
    });

    tearDown(() async {
      await harness.dispose();
    });

    DeviceRegistryAdmin buildAdmin({
      required bool ownsServerRuntime,
      required bool foregroundRunning,
      required bool supportsForegroundService,
    }) {
      return DeviceRegistryAdmin(
        deviceStore: deviceStore,
        ownsServerRuntime: () => ownsServerRuntime,
        isForegroundServiceRunning: () async => foregroundRunning,
        supportsForegroundService: () => supportsForegroundService,
        sendDataToTask: (data) {
          sentToTask.add(data);
          Future<void>.microtask(() {
            final map = data as Map;
            for (final callback in List.of(callbacks)) {
              callback(<String, dynamic>{
                'event': DeviceRegistryCommand.resultEvent,
                'requestId': map['requestId'],
                'ok': true,
              });
            }
          });
        },
        addTaskDataCallback: callbacks.add,
        removeTaskDataCallback: callbacks.remove,
        requestIdFactory: () => 'req-1',
      );
    }

    test('mutates local store when this isolate owns server runtime', () async {
      await deviceStore.enrollDevice(
        deviceId: 'phone-01',
        deviceName: 'Phone',
      );
      final admin = buildAdmin(
        ownsServerRuntime: true,
        foregroundRunning: true,
        supportsForegroundService: true,
      );

      await admin.deleteDevice('phone-01');

      expect(await deviceStore.findDeviceById('phone-01'), isNull);
      expect(sentToTask, isEmpty);
    });

    test('mutates local store on Windows-like hosts without FGS', () async {
      await deviceStore.enrollDevice(
        deviceId: 'phone-02',
        deviceName: 'Phone 2',
      );
      final admin = buildAdmin(
        ownsServerRuntime: false,
        foregroundRunning: false,
        supportsForegroundService: false,
      );

      await admin.deleteDevice('phone-02');

      expect(await deviceStore.findDeviceById('phone-02'), isNull);
      expect(sentToTask, isEmpty);
    });

    test('forwards delete to FGS when UI isolate and service running', () async {
      await deviceStore.enrollDevice(
        deviceId: 'phone-03',
        deviceName: 'Phone 3',
      );
      final admin = buildAdmin(
        ownsServerRuntime: false,
        foregroundRunning: true,
        supportsForegroundService: true,
      );

      await admin.deleteDevice('phone-03');

      expect(sentToTask, hasLength(1));
      final payload = sentToTask.single as Map;
      expect(payload['event'], DeviceRegistryCommand.event);
      expect(payload['action'], DeviceRegistryCommand.actionDelete);
      expect(payload['deviceId'], 'phone-03');
      // UI isolate store is not written; FGS owns the mutation.
      expect(await deviceStore.findDeviceById('phone-03'), isNotNull);
    });

    test('forwards status update to FGS on Android UI isolate', () async {
      await deviceStore.enrollDevice(
        deviceId: 'phone-04',
        deviceName: 'Phone 4',
      );
      final admin = buildAdmin(
        ownsServerRuntime: false,
        foregroundRunning: true,
        supportsForegroundService: true,
      );

      await admin.updateDeviceStatus(
        deviceId: 'phone-04',
        status: DeviceStatus.disabled,
      );

      expect(sentToTask, hasLength(1));
      final payload = sentToTask.single as Map;
      expect(payload['action'], DeviceRegistryCommand.actionSetStatus);
      expect(payload['status'], 'disabled');
      expect(
        (await deviceStore.findDeviceById('phone-04'))?.status,
        DeviceStatus.active,
      );
    });
  });
}
