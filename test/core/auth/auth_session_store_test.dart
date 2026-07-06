import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/owner_credential_store.dart';

import '../../test_support/device_store_harness.dart';

void main() {
  group('AuthSessionStore', () {
    test('issues and authenticates owner bearer sessions', () async {
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
      expect(ownerAuth.isSuccess, isTrue);

      final issuedSession = await authSessionStore.issueOwnerSession(
        owner: ownerAuth.owner!,
      );

      final authentication = await authSessionStore.authenticate(
        'Bearer ${issuedSession.accessToken}',
      );

      expect(authentication.isSuccess, isTrue);
      expect(authentication.context?.ownerId, ownerAuth.owner!.ownerId);
      expect(authentication.context?.isOwner, isTrue);
      expect(
        authentication.context?.sessionId,
        issuedSession.context.sessionId,
      );
      expect(authentication.context?.authScheme, 'bearer');
    });

    test('issues and authenticates device JWT access tokens', () async {
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

      final authentication = await authSessionStore.authenticateAccessToken(
        enrolled.tokens!.accessToken,
        deviceStore: deviceStore,
      );

      expect(authentication.isSuccess, isTrue);
      expect(authentication.context?.deviceId, 'tablet-01');
      expect(authentication.context?.isDevice, isTrue);
      expect(
        authentication.context?.sessionId,
        enrolled.tokens!.sessionId,
      );
    });

    test('rejects invalid bearer tokens', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final authSessionStore = await harness.createAuthSessionStore();

      final authentication = await authSessionStore.authenticate(
        'Bearer invalid-token',
      );

      expect(authentication.isSuccess, isFalse);
      expect(authentication.failureCode, 'AUTH_INVALID');
    });

    test(
      'authenticates websocket handshakes directly from access tokens',
      () async {
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

        final authentication = await authSessionStore.authenticateAccessToken(
          enrolled.tokens!.accessToken,
          deviceStore: deviceStore,
        );

        expect(authentication.isSuccess, isTrue);
        expect(
          authentication.context?.sessionId,
          enrolled.tokens!.sessionId,
        );
      },
    );

    test(
      'revalidates owner sessions by session id and keeps sliding expiration semantics',
      () async {
        var now = DateTime.utc(2026, 4, 14, 8, 0);
        final harness = await TestDeviceStoreHarness.create();
        addTearDown(harness.dispose);
        final ownerCredentialStore = harness.createOwnerCredentialStore();
        await ownerCredentialStore.initialize();
        final authSessionStore = AuthSessionStore(
          ownerSessionTtl: const Duration(minutes: 10),
          ownerStateValidator: ownerCredentialStore.isOwnerSessionVersionValid,
          clock: () => now,
        );
        final ownerAuth = await ownerCredentialStore.authenticate(
          username: 'admin',
          password: 'admin',
        );
        final issuedSession = await authSessionStore.issueOwnerSession(
          owner: ownerAuth.owner!,
        );

        now = now.add(const Duration(minutes: 3));
        final refreshed = await authSessionStore.authenticateSessionId(
          issuedSession.context.sessionId,
        );
        expect(refreshed.isSuccess, isTrue);

        now = now.add(const Duration(minutes: 8));
        final stillValid = await authSessionStore.authenticateSessionId(
          issuedSession.context.sessionId,
          refreshExpiration: false,
        );
        expect(stillValid.isSuccess, isTrue);

        now = now.add(const Duration(minutes: 3));
        final expired = await authSessionStore.authenticateSessionId(
          issuedSession.context.sessionId,
          refreshExpiration: false,
        );
        expect(expired.isSuccess, isFalse);
        expect(expired.failureCode, 'AUTH_EXPIRED');
      },
    );

    test(
      'rejects owner session revalidation after credential revocation',
      () async {
        final harness = await TestDeviceStoreHarness.create();
        addTearDown(harness.dispose);
        final authSessionStore = AuthSessionStore(
          ownerStateValidator:
              ({
                required String ownerId,
                required String credentialVersion,
              }) async => false,
        );
        final issuedSession = await authSessionStore.issueOwnerSession(
          owner: const AuthenticatedOwner(
            ownerId: 'owner-1',
            username: 'admin',
            label: '服务器管理员',
            credentialVersion: 'cred-v1',
          ),
        );

        final authentication = await authSessionStore.authenticateSessionId(
          issuedSession.context.sessionId,
        );

        expect(authentication.isSuccess, isFalse);
        expect(authentication.failureCode, 'AUTH_REVOKED');
      },
    );

    test(
      'rejects device JWT authentication after credential version bump',
      () async {
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
        await deviceStore.rotateDeviceCredential('tablet-01');

        final authentication = await authSessionStore.authenticateAccessToken(
          enrolled.tokens!.accessToken,
          deviceStore: deviceStore,
        );

        expect(authentication.isSuccess, isFalse);
        expect(authentication.failureCode, 'AUTH_REVOKED');
      },
    );
  });
}
