import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'device_models.dart';

typedef DeviceTokenClock = DateTime Function();

class DeviceTokenService {
  DeviceTokenService({
    required List<int> signingKey,
    Duration accessTokenTtl = const Duration(hours: 24),
    Duration refreshTokenTtl = const Duration(days: 90),
    Random? random,
    DeviceTokenClock? clock,
  }) : _signingKey = signingKey,
       _accessTokenTtl = accessTokenTtl,
       _refreshTokenTtl = refreshTokenTtl,
       _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  final List<int> _signingKey;
  final Duration _accessTokenTtl;
  final Duration _refreshTokenTtl;
  final Random _random;
  final DeviceTokenClock _clock;

  Duration get accessTokenTtl => _accessTokenTtl;
  Duration get refreshTokenTtl => _refreshTokenTtl;

  Future<({String token, DateTime expiresAt, String sessionId})> issueAccessToken({
    required StoredDeviceRecord device,
  }) async {
    final issuedAt = _now();
    final expiresAt = issuedAt.add(_accessTokenTtl);
    final sessionId = _nextSessionId(issuedAt);
    final token = await _signJwt(
      payload: <String, dynamic>{
        'sub': 'device:${device.deviceId}',
        'role': 'device',
        'deviceId': device.deviceId,
        'deviceName': device.deviceName,
        'credentialVersion': device.credentialVersion,
        'sessionId': sessionId,
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
      },
    );
    return (token: token, expiresAt: expiresAt, sessionId: sessionId);
  }

  Future<({String token, String hash, DateTime expiresAt, String tokenId})>
  issueRefreshToken({required String deviceId}) async {
    final issuedAt = _now();
    final expiresAt = issuedAt.add(_refreshTokenTtl);
    final tokenId = _nextTokenId('rt', issuedAt);
    final token = _nextOpaqueToken('rt');
    final hash = await _hashToken(token);
    return (
      token: token,
      hash: hash,
      expiresAt: expiresAt,
      tokenId: tokenId,
    );
  }

  Future<DeviceTokenClaims?> verifyAccessToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final parts = normalized.split('.');
    if (parts.length != 3) {
      return null;
    }

    final headerBytes = base64Url.decode(base64Url.normalize(parts[0]));
    final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
    final signature = base64Url.decode(base64Url.normalize(parts[2]));
    final signedContent = utf8.encode('${parts[0]}.${parts[1]}');
    final mac = Hmac.sha256();
    final expected = await mac.calculateMac(
      signedContent,
      secretKey: SecretKey(_signingKey),
    );
    if (signature.length != expected.bytes.length) {
      return null;
    }
    var valid = true;
    for (var index = 0; index < signature.length; index++) {
      if (signature[index] != expected.bytes[index]) {
        valid = false;
        break;
      }
    }
    if (!valid) {
      return null;
    }

    final header = jsonDecode(utf8.decode(headerBytes));
    if (header is! Map || header['alg'] != 'HS256' || header['typ'] != 'JWT') {
      return null;
    }

    final payload = jsonDecode(utf8.decode(payloadBytes));
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    final deviceId = payload['deviceId'] as String?;
    final deviceName = payload['deviceName'] as String?;
    final credentialVersion = payload['credentialVersion'] as String?;
    final sessionId = payload['sessionId'] as String?;
    final issuedAtSeconds = payload['iat'] as int?;
    final expiresAtSeconds = payload['exp'] as int?;
    if (deviceId == null ||
        deviceName == null ||
        credentialVersion == null ||
        sessionId == null ||
        issuedAtSeconds == null ||
        expiresAtSeconds == null) {
      return null;
    }

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      expiresAtSeconds * 1000,
      isUtc: true,
    );
    if (!expiresAt.isAfter(_now())) {
      return null;
    }

    return DeviceTokenClaims(
      deviceId: deviceId,
      deviceName: deviceName,
      credentialVersion: credentialVersion,
      sessionId: sessionId,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(
        issuedAtSeconds * 1000,
        isUtc: true,
      ),
      expiresAt: expiresAt,
    );
  }

  Future<String> hashRefreshToken(String token) => _hashToken(token);

  DateTime _now() => _clock().toUtc();

  String _nextSessionId(DateTime issuedAt) {
    return 'sess_${issuedAt.microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }

  String _nextTokenId(String prefix, DateTime issuedAt) {
    return '${prefix}_${issuedAt.microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }

  String _nextOpaqueToken(String prefix) {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return '${prefix}_${base64UrlEncode(bytes).replaceAll('=', '')}';
  }

  Future<String> _hashToken(String token) async {
    final digest = await Sha256().hash(utf8.encode(token));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<String> _signJwt({required Map<String, dynamic> payload}) async {
    final header = base64UrlEncode(
      utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})),
    ).replaceAll('=', '');
    final encodedPayload = base64UrlEncode(
      utf8.encode(jsonEncode(payload)),
    ).replaceAll('=', '');
    final signedContent = utf8.encode('$header.$encodedPayload');
    final mac = Hmac.sha256();
    final signature = await mac.calculateMac(
      signedContent,
      secretKey: SecretKey(_signingKey),
    );
    final encodedSignature = base64UrlEncode(signature.bytes).replaceAll(
      '=',
      '',
    );
    return '$header.$encodedPayload.$encodedSignature';
  }
}
