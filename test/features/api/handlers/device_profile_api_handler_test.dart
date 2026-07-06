import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/bearer_auth_middleware.dart';
import 'package:nas_server/core/device_registry/device_avatar_store.dart';
import 'package:nas_server/core/device_registry/device_label_constraints.dart';
import 'package:nas_server/core/device_registry/device_store.dart';
import 'package:nas_server/features/api/handlers/device_profile_api_handler.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../../../test_support/device_store_harness.dart';

void main() {
  group('DeviceProfileApiHandler', () {
    late TestDeviceStoreHarness harness;
    late DeviceStore deviceStore;
    late AuthSessionStore authSessionStore;
    late DeviceAvatarStore avatarStore;
    late DeviceProfileApiHandler handler;
    late Directory rootDirectory;

    setUp(() async {
      harness = await TestDeviceStoreHarness.create();
      rootDirectory = Directory(harness.deviceDatabasePath).parent;
      deviceStore = harness.createDeviceStore();
      await deviceStore.initialize();
      authSessionStore = AuthSessionStore(
        deviceStateValidator: deviceStore.isDeviceCredentialVersionValid,
        deviceTokenService: await deviceStore.requireTokenService(),
      );
      avatarStore = DeviceAvatarStore(
        avatarDirectoryPath: p.join(rootDirectory.path, 'device_avatars'),
      );
      handler = DeviceProfileApiHandler(
        deviceStore: deviceStore,
        avatarStore: avatarStore,
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('device can read and patch its own profile label', () async {
      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
      );
      expect(enrolled.isSuccess, isTrue);
      final auth = await authSessionStore.authenticateAccessToken(
        enrolled.tokens!.accessToken,
        deviceStore: deviceStore,
      );
      final context = auth.context!;

      final getResponse = await handler.getMyProfile(
        _request(authContext: context),
      );
      expect(getResponse.statusCode, 200);
      final profile = jsonDecode(await getResponse.readAsString()) as Map;
      expect(profile['deviceId'], 'tablet-01');
      expect(profile['deviceName'], 'Living Room Tablet');

      final patchResponse = await handler.patchMyProfile(
        _request(
          authContext: context,
          method: 'PATCH',
          body: jsonEncode({'label': '客厅平板'}),
        ),
      );
      expect(patchResponse.statusCode, 200);
      final patched = jsonDecode(await patchResponse.readAsString()) as Map;
      expect(patched['label'], '客厅平板');

      final stored = await deviceStore.findDeviceById('tablet-01');
      expect(stored?.label, '客厅平板');
    });

    test('rejects label longer than max length', () async {
      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'tablet-03',
        deviceName: 'Bedroom Tablet',
      );
      final auth = await authSessionStore.authenticateAccessToken(
        enrolled.tokens!.accessToken,
        deviceStore: deviceStore,
      );
      final context = auth.context!;
      final longLabel = '中' * (DeviceLabelConstraints.maxLength + 1);

      final patchResponse = await handler.patchMyProfile(
        _request(
          authContext: context,
          method: 'PATCH',
          body: jsonEncode({'label': longLabel}),
        ),
      );

      expect(patchResponse.statusCode, 400);
      final body = jsonDecode(await patchResponse.readAsString()) as Map;
      expect(body['code'], 'INVALID_LABEL');
    });

    test('device can upload and delete avatar bytes', () async {
      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'tablet-02',
        deviceName: 'Kitchen Tablet',
      );
      final auth = await authSessionStore.authenticateAccessToken(
        enrolled.tokens!.accessToken,
        deviceStore: deviceStore,
      );
      final context = auth.context!;

      final putResponse = await handler.putMyAvatar(
        _request(
          authContext: context,
          method: 'PUT',
          bodyBytes: <int>[0xFF, 0xD8, 0xFF, 0xD9],
        ),
      );
      expect(putResponse.statusCode, 200);

      final deleteResponse = await handler.deleteMyAvatar(
        _request(authContext: context, method: 'DELETE'),
      );
      expect(deleteResponse.statusCode, 204);
    });
  });
}

Request _request({
  required AuthenticatedRequestContext authContext,
  String method = 'GET',
  String? body,
  List<int>? bodyBytes,
}) {
  return Request(
    method,
    Uri.parse('http://localhost/device-profile'),
    body: bodyBytes ?? body,
    context: {authenticatedRequestContextKey: authContext},
  );
}
