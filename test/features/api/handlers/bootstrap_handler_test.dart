import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/core/auth/bearer_auth_middleware.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/features/api/handlers/bootstrap_handler.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('BootstrapHandler', () {
    test('returns the authenticated current device snapshot', () async {
      final handler = BootstrapHandler(
        serverName: 'NAS Server',
        serverId: 'nas-server-001',
        serverVersion: '1.0.0',
        caSha256: 'test-ca-sha256',
      ).handler;

      final response = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/api/v1/bootstrap'),
          context: {
            authenticatedRequestContextKey: const AuthenticatedRequestContext(
              principalType: AuthPrincipalType.device,
              sessionId: 'sess-123',
              credentialVersion: 'cv-1',
              authScheme: 'bearer',
              deviceId: 'tablet-01',
              deviceName: 'Living Room Tablet',
              role: AccountRole.device,
            ),
          },
        ),
      );
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(body['auth']['type'], 'device');
      expect(body['auth']['currentDevice']['deviceId'], 'tablet-01');
      expect(body['auth']['currentDevice']['role'], 'device');
      expect(body['auth']['currentDevice']['sessionId'], 'sess-123');
      expect(body['auth']['refreshEndpoint'], '/api/v1/auth/device/refresh');
      expect(body['server']['platform'], isNotEmpty);
      expect(body['capabilities']['realtime']['websocket'], isTrue);
      expect(
        body['capabilities']['realtime']['endpoint'],
        '/api/v1/realtime/ws',
      );
      expect(body['capabilities']['realtime']['heartbeatIntervalSec'], 15);
      expect(body['fileAccess']['roots'], hasLength(1));
      expect(body['fileAccess']['roots'][0]['path'], '/fs');
      expect(body['capabilities']['preview']['image'], isTrue);
      expect(body['capabilities']['preview']['video'], isTrue);
      expect(body['capabilities']['preview']['progressive'], isTrue);
    });

    test(
      'omits media library roots and reflects preview capability flags',
      () async {
        final handler = BootstrapHandler(
          serverName: 'NAS Server',
          serverId: 'nas-server-001',
          serverVersion: '1.0.0',
          caSha256: 'test-ca-sha256',
          mediaLibraryEnabled: false,
          imagePreviewEnabled: true,
          videoPreviewEnabled: true,
          progressiveVideoPreviewEnabled: true,
          thumbnailEnabled: false,
          batchThumbnailEnabled: false,
        ).handler;

        final response = await handler(
          Request(
            'GET',
            Uri.parse('http://localhost/api/v1/bootstrap'),
            context: {
              authenticatedRequestContextKey: const AuthenticatedRequestContext(
                principalType: AuthPrincipalType.device,
                sessionId: 'sess-123',
                credentialVersion: 'cv-1',
                authScheme: 'bearer',
                deviceId: 'tablet-01',
                deviceName: 'Living Room Tablet',
                role: AccountRole.device,
              ),
            },
          ),
        );
        final body =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;

        expect(response.statusCode, 200);
        expect(body['server']['platform'], isNotEmpty);
        expect(body['fileAccess']['roots'], hasLength(1));
        expect(body['fileAccess']['roots'][0]['id'], 'fs');
        expect(body['capabilities']['preview']['thumbnail'], isFalse);
        expect(body['capabilities']['preview']['batchThumbnail'], isFalse);
      },
    );
  });
}
