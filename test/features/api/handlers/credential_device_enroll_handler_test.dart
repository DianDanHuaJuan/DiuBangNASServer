import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/tls/server_tls_manager.dart';
import 'package:nas_server/features/api/handlers/credential_device_enroll_handler.dart';
import 'package:shelf/shelf.dart';

import '../../../test_support/device_store_harness.dart';

void main() {
  group('CredentialDeviceEnrollHandler', () {
    const tlsMaterial = ServerTlsMaterial(
      serverId: 'srv-test-001',
      serverName: 'Test NAS',
      hostLabel: 'srv-test-001',
      localIp: '192.168.1.10',
      port: 8443,
      rootCaPem: '-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----',
      rootCaDerBase64Url: 'dGVzdA',
      leafCertificatePem:
          '-----BEGIN CERTIFICATE-----\nLEAF\n-----END CERTIFICATE-----',
      leafPrivateKeyPem:
          '-----BEGIN PRIVATE KEY-----\nKEY\n-----END PRIVATE KEY-----',
      caSha256: 'abc123',
      leafSha256: 'def456',
    );

    Future<ServerTlsMaterial> tlsProvider() async => tlsMaterial;

    Map<String, dynamic> enrollBody({
      String deviceId = 'device-a',
      String deviceName = 'Headless Client',
      String? physicalDeviceId,
    }) {
      return {
        'device_id': deviceId,
        'device_name': deviceName,
        if (physicalDeviceId != null) 'physical_device_id': physicalDeviceId,
      };
    }

    test('enrolls device with default admin/admin credentials', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final ownerCredentialStore = harness.createOwnerCredentialStore();
      final deviceStore = harness.createDeviceStore();
      await ownerCredentialStore.initialize();
      await deviceStore.initialize();

      final handler = CredentialDeviceEnrollHandler(
        ownerCredentialStore: ownerCredentialStore,
        deviceStore: deviceStore,
        tlsMaterialProvider: tlsProvider,
      ).handler;

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/auth/credential-device-enroll'),
          headers: {
            'Authorization': ownerCredentialStore.encodeBasicAuth(
              'admin',
              'admin',
            ),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(enrollBody(physicalDeviceId: 'physical-a')),
        ),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['serverId'], tlsMaterial.serverId);
      expect(body['baseUrl'], tlsMaterial.baseUrl);
      expect(body['rootCaPem'], tlsMaterial.rootCaPem);
      expect(body['caSha256'], tlsMaterial.caSha256);
      expect(body['deviceId'], isNotEmpty);
      expect(body['accessToken'], isNotEmpty);
      expect(body['refreshToken'], isNotEmpty);
      expect(body['sessionId'], startsWith('sess_'));
    });

    test('rejects invalid owner credentials', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final ownerCredentialStore = harness.createOwnerCredentialStore();
      final deviceStore = harness.createDeviceStore();
      await ownerCredentialStore.initialize();
      await deviceStore.initialize();

      final handler = CredentialDeviceEnrollHandler(
        ownerCredentialStore: ownerCredentialStore,
        deviceStore: deviceStore,
        tlsMaterialProvider: tlsProvider,
      ).handler;

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/auth/credential-device-enroll'),
          headers: {
            'Authorization': ownerCredentialStore.encodeBasicAuth(
              'admin',
              'wrong-password',
            ),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(enrollBody()),
        ),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 401);
      expect(body['code'], 'AUTH_INVALID');
    });

    test('creates distinct devices for different physical_device_id values', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final ownerCredentialStore = harness.createOwnerCredentialStore();
      final deviceStore = harness.createDeviceStore();
      await ownerCredentialStore.initialize();
      await deviceStore.initialize();

      final handler = CredentialDeviceEnrollHandler(
        ownerCredentialStore: ownerCredentialStore,
        deviceStore: deviceStore,
        tlsMaterialProvider: tlsProvider,
      ).handler;

      final firstResponse = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/auth/credential-device-enroll'),
          headers: {
            'Authorization': ownerCredentialStore.encodeBasicAuth(
              'admin',
              'admin',
            ),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(
            enrollBody(
              deviceId: 'device-1',
              physicalDeviceId: 'physical-1',
            ),
          ),
        ),
      );
      final secondResponse = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/auth/credential-device-enroll'),
          headers: {
            'Authorization': ownerCredentialStore.encodeBasicAuth(
              'admin',
              'admin',
            ),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(
            enrollBody(
              deviceId: 'device-2',
              physicalDeviceId: 'physical-2',
            ),
          ),
        ),
      );

      final firstBody =
          jsonDecode(await firstResponse.readAsString()) as Map<String, dynamic>;
      final secondBody =
          jsonDecode(await secondResponse.readAsString())
              as Map<String, dynamic>;

      expect(firstResponse.statusCode, 200);
      expect(secondResponse.statusCode, 200);
      expect(firstBody['deviceId'], isNot(equals(secondBody['deviceId'])));
    });
  });
}
