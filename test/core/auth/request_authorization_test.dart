import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/account_models.dart';
import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/request_authorization.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('request authorization helpers', () {
    test('requires authenticated request context before role checks', () async {
      final response = ensureRequestHasAnyRole(
        Request('GET', Uri.parse('http://localhost/api/v1/realtime/ws')),
        allowedRoles: {AccountRole.owner},
      );

      expect(response, isNotNull);
      expect(response!.statusCode, 401);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['code'], 'AUTH_REQUIRED');
    });

    test('forbids requests with disallowed roles', () async {
      final response = ensureRequestHasAnyRole(
        Request(
          'GET',
          Uri.parse('http://localhost/api/v1/realtime/ws'),
          context: {
            'authenticatedRequestContext': const AuthenticatedRequestContext(
              principalType: AuthPrincipalType.device,
              sessionId: 'sess-1',
              credentialVersion: 'cv-1',
              authScheme: 'bearer',
              deviceId: 'tablet-01',
              deviceName: 'Living Room Tablet',
              role: AccountRole.device,
            ),
          },
        ),
        allowedRoles: {AccountRole.owner},
      );

      expect(response, isNotNull);
      expect(response!.statusCode, 403);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['code'], 'AUTH_FORBIDDEN');
    });

    test('allows requests with matching roles', () {
      final response = ensureRequestHasAnyRole(
        Request(
          'GET',
          Uri.parse('http://localhost/api/v1/realtime/ws'),
          context: {
            'authenticatedRequestContext': const AuthenticatedRequestContext(
              principalType: AuthPrincipalType.owner,
              sessionId: 'sess-1',
              credentialVersion: 'cv-1',
              ownerId: 'owner-1',
              username: 'owner-user',
              label: '服务器管理员',
              role: AccountRole.owner,
              authScheme: 'bearer',
            ),
          },
        ),
        allowedRoles: {AccountRole.owner},
      );

      expect(response, isNull);
    });
  });
}
