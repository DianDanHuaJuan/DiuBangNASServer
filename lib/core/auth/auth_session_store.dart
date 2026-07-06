import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'account_models.dart';
import 'owner_credential_store.dart';
import '../device_registry/device_models.dart';
import '../device_registry/device_store.dart';
import '../device_registry/device_token_service.dart';

typedef SessionOwnerStateValidator =
    Future<bool> Function({
      required String ownerId,
      required String credentialVersion,
    });
typedef SessionDeviceStateValidator =
    Future<bool> Function({
      required String deviceId,
      required String credentialVersion,
    });
typedef AuthSessionClock = DateTime Function();

class AuthenticatedRequestContext {
  const AuthenticatedRequestContext({
    required this.principalType,
    required this.sessionId,
    required this.authScheme,
    required this.credentialVersion,
    this.ownerId,
    this.username,
    this.label,
    this.deviceId,
    this.deviceName,
    this.role = AccountRole.owner,
  });

  final AuthPrincipalType principalType;
  final String sessionId;
  final String authScheme;
  final String credentialVersion;
  final String? ownerId;
  final String? username;
  final String? label;
  final String? deviceId;
  final String? deviceName;
  final AccountRole role;

  String? get accountId => ownerId;
  String? get clientId => deviceId;

  bool get isOwner => principalType == AuthPrincipalType.owner;
  bool get isDevice => principalType == AuthPrincipalType.device;
}

class IssuedAuthSession {
  const IssuedAuthSession({
    required this.context,
    required this.accessToken,
    required this.issuedAt,
    required this.expiresAt,
  });

  final AuthenticatedRequestContext context;
  final String accessToken;
  final DateTime issuedAt;
  final DateTime expiresAt;
}

class AuthSessionAuthenticationResult {
  const AuthSessionAuthenticationResult._({
    this.context,
    this.failureCode,
    this.failureMessage,
  });

  const AuthSessionAuthenticationResult.success(
    AuthenticatedRequestContext context,
  ) : this._(context: context);

  const AuthSessionAuthenticationResult.failure({
    required String code,
    required String message,
  }) : this._(failureCode: code, failureMessage: message);

  final AuthenticatedRequestContext? context;
  final String? failureCode;
  final String? failureMessage;

  bool get isSuccess => context != null;
}

class AuthSessionStore {
  AuthSessionStore({
    Duration ownerSessionTtl = const Duration(days: 7),
    Random? random,
    SessionOwnerStateValidator? ownerStateValidator,
    SessionDeviceStateValidator? deviceStateValidator,
    DeviceTokenService? deviceTokenService,
    AuthSessionClock? clock,
  }) : _ownerSessionTtl = ownerSessionTtl,
       _random = random ?? Random.secure(),
       _ownerStateValidator = ownerStateValidator,
       _deviceStateValidator = deviceStateValidator,
       _deviceTokenService = deviceTokenService,
       _clock = clock ?? DateTime.now;

  final Duration _ownerSessionTtl;
  final Random _random;
  final SessionOwnerStateValidator? _ownerStateValidator;
  final SessionDeviceStateValidator? _deviceStateValidator;
  final DeviceTokenService? _deviceTokenService;
  final AuthSessionClock _clock;

  final Map<String, _StoredOwnerSession> _ownerSessionsById =
      <String, _StoredOwnerSession>{};
  final Map<String, String> _ownerSessionIdByTokenHash = <String, String>{};

  Future<IssuedAuthSession> issueOwnerSession({
    required AuthenticatedOwner owner,
  }) async {
    _cleanupExpiredOwnerSessions();

    final issuedAt = _now();
    final expiresAt = issuedAt.add(_ownerSessionTtl);
    final sessionId = _nextSessionId(issuedAt);
    final accessToken = _nextOpaqueToken();
    final tokenHash = await _hashToken(accessToken);

    final storedSession = _StoredOwnerSession(
      sessionId: sessionId,
      ownerId: owner.ownerId,
      username: owner.username,
      label: owner.label,
      credentialVersion: owner.credentialVersion,
      tokenHash: tokenHash,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      lastSeenAt: issuedAt,
    );

    _ownerSessionsById[sessionId] = storedSession;
    _ownerSessionIdByTokenHash[tokenHash] = sessionId;

    return IssuedAuthSession(
      context: storedSession.toContext(),
      accessToken: accessToken,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  Future<AuthSessionAuthenticationResult> authenticate(
    String? authHeader, {
    DeviceStore? deviceStore,
  }) async {
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return const AuthSessionAuthenticationResult.failure(
        code: 'AUTH_REQUIRED',
        message: 'Bearer token is required',
      );
    }

    final token = authHeader.substring(7).trim();
    return authenticateAccessToken(token, deviceStore: deviceStore);
  }

  Future<AuthSessionAuthenticationResult> authenticateAccessToken(
    String? accessToken, {
    bool refreshExpiration = true,
    DeviceStore? deviceStore,
  }) async {
    final token = accessToken?.trim();
    if (token == null || token.isEmpty) {
      return const AuthSessionAuthenticationResult.failure(
        code: 'AUTH_REQUIRED',
        message: 'Access token is required',
      );
    }

    DeviceTokenService? tokenService = _deviceTokenService;
    if (tokenService == null && deviceStore != null) {
      tokenService = await deviceStore.requireTokenService();
    }
    if (tokenService != null) {
      final claims = await tokenService.verifyAccessToken(token);
      if (claims != null) {
        return _authenticateDeviceClaims(
          claims,
          deviceStore: deviceStore,
        );
      }
    }

    final tokenHash = await _hashToken(token);
    final sessionId = _ownerSessionIdByTokenHash[tokenHash];
    if (sessionId == null) {
      return const AuthSessionAuthenticationResult.failure(
        code: 'AUTH_INVALID',
        message: 'Invalid bearer token',
      );
    }

    final storedSession = _ownerSessionsById[sessionId];
    if (storedSession == null) {
      _ownerSessionIdByTokenHash.remove(tokenHash);
      return const AuthSessionAuthenticationResult.failure(
        code: 'AUTH_INVALID',
        message: 'Invalid bearer token',
      );
    }

    _cleanupExpiredOwnerSessions(excludingSessionId: storedSession.sessionId);
    return _authenticateStoredOwnerSession(
      storedSession,
      refreshExpiration: refreshExpiration,
    );
  }

  Future<AuthSessionAuthenticationResult> authenticateSessionId(
    String? sessionId, {
    bool refreshExpiration = true,
  }) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return const AuthSessionAuthenticationResult.failure(
        code: 'AUTH_REQUIRED',
        message: 'Session id is required',
      );
    }

    final storedSession = _ownerSessionsById[normalizedSessionId];
    if (storedSession == null) {
      return const AuthSessionAuthenticationResult.failure(
        code: 'AUTH_INVALID',
        message: 'Invalid session id',
      );
    }

    _cleanupExpiredOwnerSessions(excludingSessionId: storedSession.sessionId);
    return _authenticateStoredOwnerSession(
      storedSession,
      refreshExpiration: refreshExpiration,
    );
  }

  Future<AuthSessionAuthenticationResult> _authenticateDeviceClaims(
    DeviceTokenClaims claims, {
    DeviceStore? deviceStore,
  }) async {
    final validator = _deviceStateValidator;
    if (validator != null) {
      final isValid = await validator(
        deviceId: claims.deviceId,
        credentialVersion: claims.credentialVersion,
      );
      if (!isValid) {
        return const AuthSessionAuthenticationResult.failure(
          code: 'AUTH_REVOKED',
          message: 'Device credential has been revoked',
        );
      }
    }

    if (deviceStore != null) {
      await deviceStore.touchDeviceSeen(claims.deviceId);
    }

    return AuthSessionAuthenticationResult.success(
      AuthenticatedRequestContext(
        principalType: AuthPrincipalType.device,
        sessionId: claims.sessionId,
        authScheme: 'bearer',
        credentialVersion: claims.credentialVersion,
        deviceId: claims.deviceId,
        deviceName: claims.deviceName,
        role: AccountRole.device,
      ),
    );
  }

  Future<AuthSessionAuthenticationResult> _authenticateStoredOwnerSession(
    _StoredOwnerSession storedSession, {
    required bool refreshExpiration,
  }) async {
    final now = _now();
    if (!storedSession.expiresAt.isAfter(now)) {
      revokeSession(storedSession.sessionId);
      return const AuthSessionAuthenticationResult.failure(
        code: 'AUTH_EXPIRED',
        message: 'Session has expired',
      );
    }

    final ownerStateValidator = _ownerStateValidator;
    if (ownerStateValidator != null) {
      final isOwnerStillValid = await ownerStateValidator(
        ownerId: storedSession.ownerId,
        credentialVersion: storedSession.credentialVersion,
      );
      if (!isOwnerStillValid) {
        revokeSession(storedSession.sessionId);
        return const AuthSessionAuthenticationResult.failure(
          code: 'AUTH_REVOKED',
          message: 'Session has been revoked',
        );
      }
    }

    final authenticatedSession = refreshExpiration
        ? storedSession.copyWith(
            lastSeenAt: now,
            expiresAt: now.add(_ownerSessionTtl),
          )
        : storedSession;
    if (refreshExpiration) {
      _ownerSessionsById[storedSession.sessionId] = authenticatedSession;
    }

    return AuthSessionAuthenticationResult.success(
      authenticatedSession.toContext(),
    );
  }

  void revokeSession(String sessionId) {
    final storedSession = _ownerSessionsById.remove(sessionId);
    if (storedSession == null) {
      return;
    }
    _ownerSessionIdByTokenHash.remove(storedSession.tokenHash);
  }

  void revokeSessionsForOwner(String ownerId) {
    final sessionIds = _ownerSessionsById.values
        .where((session) => session.ownerId == ownerId)
        .map((session) => session.sessionId)
        .toList(growable: false);

    for (final sessionId in sessionIds) {
      revokeSession(sessionId);
    }
  }

  void clear() {
    _ownerSessionsById.clear();
    _ownerSessionIdByTokenHash.clear();
  }

  void _cleanupExpiredOwnerSessions({String? excludingSessionId}) {
    final now = _now();
    final expiredSessionIds = _ownerSessionsById.values
        .where(
          (session) =>
              session.sessionId != excludingSessionId &&
              !session.expiresAt.isAfter(now),
        )
        .map((session) => session.sessionId)
        .toList(growable: false);

    for (final sessionId in expiredSessionIds) {
      revokeSession(sessionId);
    }
  }

  DateTime _now() => _clock().toUtc();

  String _nextSessionId(DateTime issuedAt) {
    return 'sess_${issuedAt.microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }

  String _nextOpaqueToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<String> _hashToken(String token) async {
    final digest = await Sha256().hash(utf8.encode(token));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}

class _StoredOwnerSession {
  const _StoredOwnerSession({
    required this.sessionId,
    required this.ownerId,
    required this.username,
    required this.label,
    required this.credentialVersion,
    required this.tokenHash,
    required this.issuedAt,
    required this.expiresAt,
    required this.lastSeenAt,
  });

  final String sessionId;
  final String ownerId;
  final String username;
  final String label;
  final String credentialVersion;
  final String tokenHash;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime lastSeenAt;

  _StoredOwnerSession copyWith({
    DateTime? lastSeenAt,
    DateTime? expiresAt,
  }) {
    return _StoredOwnerSession(
      sessionId: sessionId,
      ownerId: ownerId,
      username: username,
      label: label,
      credentialVersion: credentialVersion,
      tokenHash: tokenHash,
      issuedAt: issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  AuthenticatedRequestContext toContext() {
    return AuthenticatedRequestContext(
      principalType: AuthPrincipalType.owner,
      sessionId: sessionId,
      ownerId: ownerId,
      username: username,
      label: label,
      authScheme: 'bearer',
      credentialVersion: credentialVersion,
      role: AccountRole.owner,
    );
  }
}
