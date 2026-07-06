import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device/device_info_service.dart';

void main() {
  group('WindowsPowerState', () {
    test('maps a desktop without battery to charging 100 percent', () {
      final state = WindowsPowerState.fromRawStatus(
        acLineStatus: 1,
        batteryFlag: 128,
        batteryLifePercent: 255,
      );

      expect(state.batteryLevel, 2);
      expect(state.batteryPercent, 100);
      expect(state.isCharging, isTrue);
    });

    test('maps a discharging battery to a normal telemetry snapshot', () {
      final state = WindowsPowerState.fromRawStatus(
        acLineStatus: 0,
        batteryFlag: 1,
        batteryLifePercent: 67,
      );

      expect(state.batteryLevel, 3);
      expect(state.batteryPercent, 67);
      expect(state.isCharging, isFalse);
    });
  });

  group('DeviceInfoService', () {
    test('exposes battery telemetry on Windows hosts', () async {
      final service = DeviceInfoService(
        isAndroidOverride: false,
        isWindowsOverride: true,
        windowsPowerStateReader: () => const WindowsPowerState(
          batteryLevel: 3,
          batteryPercent: 52,
          isCharging: false,
        ),
      );

      final info = await service.getDeviceInfo();

      expect(service.supportsBatteryTelemetry, isTrue);
      expect(info.batteryLevel, 3);
      expect(info.batteryPercent, 52);
      expect(info.isCharging, isFalse);
    });
  });
}
