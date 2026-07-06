import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device_registry/device_models.dart';

import '../../test_support/device_store_harness.dart';

void main() {
  group('DeviceStore', () {
    test('lazily initializes once for concurrent access', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final deviceStore = harness.createDeviceStore();

      final results = await Future.wait<Object?>([
        deviceStore.listDevices(),
        deviceStore.requireTokenService(),
      ]);

      expect(results[0], isEmpty);
      expect(results[1], isNotNull);
    });

    test('enrolls a device and issues access tokens', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();

      final result = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
        platform: 'android',
      );

      expect(result.isSuccess, isTrue);
      expect(result.tokens!.device.deviceId, 'tablet-01');
      expect(result.tokens!.device.deviceName, 'Living Room Tablet');
      expect(result.tokens!.accessToken, isNotEmpty);
      expect(result.tokens!.refreshToken, isNotEmpty);

      final claims = await deviceStore.verifyAccessToken(
        result.tokens!.accessToken,
      );
      expect(claims?.deviceId, 'tablet-01');
      expect(
        claims?.credentialVersion,
        result.tokens!.device.credentialVersion,
      );
    });

    test('rejects enrollment for disabled devices', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();

      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
      );
      expect(enrolled.isSuccess, isTrue);

      await deviceStore.updateDeviceStatus(
        deviceId: 'tablet-01',
        status: DeviceStatus.disabled,
      );

      final retry = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
      );

      expect(retry.isSuccess, isFalse);
      expect(retry.failureCode, 'DEVICE_DISABLED');
    });

    test(
      're-enroll rotates credential version and revokes old access tokens',
      () async {
        final harness = await TestDeviceStoreHarness.create();
        addTearDown(harness.dispose);
        final deviceStore = harness.createDeviceStore();
        await deviceStore.initialize();

        final first = await deviceStore.enrollDevice(
          deviceId: 'tablet-01',
          deviceName: 'Living Room Tablet',
        );
        expect(first.isSuccess, isTrue);
        final firstAccessToken = first.tokens!.accessToken;
        final firstCredentialVersion = first.tokens!.device.credentialVersion;

        final second = await deviceStore.enrollDevice(
          deviceId: 'tablet-01',
          deviceName: 'Living Room Tablet',
        );

        expect(second.isSuccess, isTrue);
        expect(
          second.tokens!.device.credentialVersion,
          isNot(equals(firstCredentialVersion)),
        );

        final authSessionStore = await harness.createDeviceAuthSessionStore(
          deviceStore: deviceStore,
        );
        final authentication = await authSessionStore.authenticateAccessToken(
          firstAccessToken,
          deviceStore: deviceStore,
        );

        expect(authentication.isSuccess, isFalse);
        expect(authentication.failureCode, 'AUTH_REVOKED');
      },
    );

    test('allows delete and re-enroll for the same device id', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();

      final first = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
      );
      expect(first.isSuccess, isTrue);
      final firstCredentialVersion = first.tokens!.device.credentialVersion;

      await deviceStore.deleteDevice('tablet-01');

      final second = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
      );

      expect(second.isSuccess, isTrue);
      expect(
        second.tokens!.device.credentialVersion,
        isNot(equals(firstCredentialVersion)),
      );
    });

    test('invalidates tokens after credential version bump', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();

      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
      );
      expect(enrolled.isSuccess, isTrue);
      final accessToken = enrolled.tokens!.accessToken;
      final credentialVersion = enrolled.tokens!.device.credentialVersion;

      expect(
        await deviceStore.isDeviceCredentialVersionValid(
          deviceId: 'tablet-01',
          credentialVersion: credentialVersion,
        ),
        isTrue,
      );

      await deviceStore.rotateDeviceCredential('tablet-01');

      expect(
        await deviceStore.isDeviceCredentialVersionValid(
          deviceId: 'tablet-01',
          credentialVersion: credentialVersion,
        ),
        isFalse,
      );

      final claims = await deviceStore.verifyAccessToken(accessToken);
      expect(claims, isNotNull);

      final authSessionStore = await harness.createDeviceAuthSessionStore(
        deviceStore: deviceStore,
      );
      final authentication = await authSessionStore.authenticateAccessToken(
        accessToken,
        deviceStore: deviceStore,
      );

      expect(authentication.isSuccess, isFalse);
      expect(authentication.failureCode, 'AUTH_REVOKED');
    });
  });
}
