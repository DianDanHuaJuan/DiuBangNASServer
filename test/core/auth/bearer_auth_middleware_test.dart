import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/bearer_auth_middleware.dart';
import 'package:shelf/shelf.dart';

import '../../test_support/device_store_harness.dart';

void main() {
  group('bearerAuthMiddleware', () {
    test('accepts valid device bearer tokens and injects request context', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final deviceStore = harness.createDeviceStore();
      final authSessionStore = await harness.createAuthSessionStore(
        deviceStore: deviceStore,
      );
      final enrolled = await deviceStore.enrollDevice(
        deviceId: 'tablet-01',
        deviceName: 'Living Room Tablet',
      );
      expect(enrolled.isSuccess, isTrue);

      final handler = Pipeline()
          .addMiddleware(
            bearerAuthMiddleware(authSessionStore, deviceStore: deviceStore),
          )
          .addHandler((request) {
            final context = authenticatedRequestContextFromRequest(request);
            expect(context?.deviceId, 'tablet-01');
            expect(context?.isDevice, isTrue);
            return Response.ok('ok');
          });

      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/api/v1/bootstrap'),
          headers: {
            'Authorization': 'Bearer ${enrolled.tokens!.accessToken}',
          },
        ),
      );

      expect(response.statusCode, 200);
    });

    test('accepts valid owner bearer tokens and injects request context', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final ownerCredentialStore = harness.createOwnerCredentialStore();
      final authSessionStore = await harness.createAuthSessionStore(
        ownerCredentialStore: ownerCredentialStore,
      );
      final ownerAuth = await ownerCredentialStore.authenticate(
        username: 'admin',
        password: 'admin',
      );
      final issuedSession = await authSessionStore.issueOwnerSession(
        owner: ownerAuth.owner!,
      );

      final handler = Pipeline()
          .addMiddleware(bearerAuthMiddleware(authSessionStore))
          .addHandler((request) {
            final context = authenticatedRequestContextFromRequest(request);
            expect(context?.ownerId, ownerAuth.owner!.ownerId);
            expect(context?.isOwner, isTrue);
            return Response.ok('ok');
          });

      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/api/v1/bootstrap'),
          headers: {'Authorization': 'Bearer ${issuedSession.accessToken}'},
        ),
      );

      expect(response.statusCode, 200);
    });

    test('rejects requests without bearer tokens', () async {
      final handler = const Pipeline()
          .addMiddleware(bearerAuthMiddleware(AuthSessionStore()))
          .addHandler((request) => Response.ok('ok'));

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/api/v1/bootstrap')),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 401);
      expect(body['code'], 'AUTH_REQUIRED');
    });
  });
}
