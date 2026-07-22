import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/bearer_auth_middleware.dart';
import 'package:nas_server/core/device_registry/device_avatar_store.dart';
import 'package:nas_server/core/device_registry/device_label_constraints.dart';
import 'package:nas_server/core/device_registry/device_store.dart';
import 'package:nas_server/features/api/handlers/device_api_handler.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../../../test_support/device_store_harness.dart';

void main() {
  group('DeviceApiHandler.listProfiles', () {
    late TestDeviceStoreHarness harness;
    late DeviceStore deviceStore;
    late AuthSessionStore authSessionStore;
    late DeviceApiHandler handler;

    setUp(() async {
      harness = await TestDeviceStoreHarness.create();
      deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();
      authSessionStore = AuthSessionStore(
        deviceStateValidator: deviceStore.isDeviceCredentialVersionValid,
        deviceTokenService: await deviceStore.requireTokenService(),
      );
      handler = DeviceApiHandler(
        deviceStore: deviceStore,
        avatarStore: DeviceAvatarStore(
          avatarDirectoryPath: p.join(
            harness.deviceDatabasePath,
            'device_avatars',
          ),
        ),
        hostDeviceIdProvider: () async => 'host-01',
        isOnlineProvider: (deviceId) => deviceId == 'phone-01',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('returns requested active device profiles', () async {
      await deviceStore.enrollDevice(
        deviceId: 'phone-01',
        deviceName: 'Phone Hardware',
      );
      await deviceStore.updateDeviceLabel(
        deviceId: 'phone-01',
        label: '客厅手机',
      );
      await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Tablet Hardware',
      );

      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'reader-01',
        deviceName: 'Reader',
      );
      final auth = await authSessionStore.authenticateAccessToken(
        enrolled.tokens!.accessToken,
        deviceStore: deviceStore,
      );

      final response = await handler.listProfiles(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/devices/profiles?ids=phone-01,tablet-01,missing-01',
          ),
          context: {authenticatedRequestContextKey: auth.context!},
        ),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      final profiles = body['profiles'] as List;
      expect(profiles, hasLength(2));
      final phone = profiles.firstWhere(
        (item) => (item as Map)['deviceId'] == 'phone-01',
      ) as Map;
      expect(phone['label'], '客厅手机');
      expect(phone['deviceName'], 'Phone Hardware');
    });
  });

  group('DeviceApiHandler.listRoster', () {
    late TestDeviceStoreHarness harness;
    late DeviceStore deviceStore;
    late AuthSessionStore authSessionStore;
    late DeviceApiHandler handler;

    setUp(() async {
      harness = await TestDeviceStoreHarness.create();
      deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();
      authSessionStore = AuthSessionStore(
        deviceStateValidator: deviceStore.isDeviceCredentialVersionValid,
        deviceTokenService: await deviceStore.requireTokenService(),
      );
      handler = DeviceApiHandler(
        deviceStore: deviceStore,
        avatarStore: DeviceAvatarStore(
          avatarDirectoryPath: p.join(
            harness.deviceDatabasePath,
            'device_avatars',
          ),
        ),
        hostDeviceIdProvider: () async => 'host-01',
        isOnlineProvider: (deviceId) => deviceId == 'phone-01',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('returns active client devices excluding host', () async {
      await deviceStore.enrollDevice(
        deviceId: 'host-01',
        deviceName: 'NAS Host',
      );
      await deviceStore.enrollDevice(
        deviceId: 'phone-01',
        deviceName: 'Phone Hardware',
        brand: 'oneplus',
        model: 'plc110',
      );
      await deviceStore.updateDeviceLabel(
        deviceId: 'phone-01',
        label: '客厅手机',
      );
      await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Tablet Hardware',
      );

      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'reader-01',
        deviceName: 'Reader',
      );
      final auth = await authSessionStore.authenticateAccessToken(
        enrolled.tokens!.accessToken,
        deviceStore: deviceStore,
      );

      final response = await handler.listRoster(
        Request(
          'GET',
          Uri.parse('http://localhost/devices/roster'),
          context: {authenticatedRequestContextKey: auth.context!},
        ),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      final devices = (body['devices'] as List)
          .map((item) => item as Map)
          .toList(growable: false);
      final ids = devices.map((item) => item['deviceId']).toSet();
      expect(ids.contains('host-01'), isFalse);
      expect(ids.contains('phone-01'), isTrue);
      expect(ids.contains('tablet-01'), isTrue);

      final phone = devices.firstWhere((item) => item['deviceId'] == 'phone-01');
      expect(phone['displayName'], '客厅手机');
      expect(phone['online'], isTrue);

      final tablet =
          devices.firstWhere((item) => item['deviceId'] == 'tablet-01');
      expect(tablet['online'], isFalse);
    });
  });
}
