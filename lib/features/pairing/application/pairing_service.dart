// 文件输入：ServerTlsMaterial, DeviceStore
// 文件职责：提供配对服务，包括二维码生成和加密设备令牌发放
// 文件对外接口：PairingService
// 文件包含：PairingService
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../../core/device_registry/device_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/tls/server_tls_manager.dart';
import '../domain/pairing_session.dart';

class PairingQrData {
  final String serverId;
  final String serverName;
  final String baseUrl;
  final String caFingerprint;
  final Uint8List serverPublicKey;

  const PairingQrData({
    required this.serverId,
    required this.serverName,
    required this.baseUrl,
    required this.caFingerprint,
    required this.serverPublicKey,
  });

  Map<String, dynamic> toJson() => {
    'i': serverId,
    'n': serverName,
    'u': baseUrl,
    'f': caFingerprint,
    'p': base64UrlEncode(serverPublicKey),
  };
}

class EncryptedDeviceEnrollment {
  final String encryptedEnrollment;
  final String serverPublicKey;

  const EncryptedDeviceEnrollment({
    required this.encryptedEnrollment,
    required this.serverPublicKey,
  });

  Map<String, dynamic> toJson() => {
    'encrypted_enrollment': encryptedEnrollment,
    'server_pub': serverPublicKey,
  };
}

class PairingService {
  PairingService({
    required ServerTlsManager tlsManager,
    required DeviceStore deviceStore,
    required KeyValueStore keyValueStore,
  }) : _tlsManager = tlsManager,
       _deviceStore = deviceStore,
       _keyValueStore = keyValueStore;

  final ServerTlsManager _tlsManager;
  final DeviceStore _deviceStore;
  final KeyValueStore _keyValueStore;
  final Map<String, PairingSession> _pendingSessions = {};
  static const String _pairingSessionStoragePrefix =
      'pairing.pending_session.v1.';
  static const Duration _sessionTtl = Duration(minutes: 5);
  static const Duration _requestTimestampTolerance = Duration(minutes: 5);

  /// 生成精简版配对二维码
  /// 返回格式: `NASPAIR3|base64url(gzip(json))`
  Future<String> generatePairingQrToken({
    required String serverId,
    required String serverName,
    required String localIp,
    required int port,
  }) async {
    final tlsMaterial = await _tlsManager.ensureMaterial(
      serverId: serverId,
      serverName: serverName,
      localIp: localIp,
      port: port,
    );

    final keyPair = await _generateX25519KeyPair();

    final session = PairingSession(
      serverId: serverId,
      privateKey: keyPair.privateKey,
      publicKey: keyPair.publicKey,
      expiresAt: DateTime.now().toUtc().add(_sessionTtl),
    );

    _pendingSessions[serverId] = session;
    await _persistSession(session);
    _scheduleSessionCleanup(serverId, session.expiresAt);

    final qrData = PairingQrData(
      serverId: serverId,
      serverName: serverName,
      baseUrl: tlsMaterial.baseUrl,
      caFingerprint: tlsMaterial.caSha256,
      serverPublicKey: keyPair.publicKey,
    );

    final jsonBytes = utf8.encode(jsonEncode(qrData.toJson()));
    final compressed = gzip.encode(jsonBytes);
    return 'NASPAIR3|${base64UrlEncode(compressed)}';
  }

  Future<String> getCaCertificatePem({
    required String serverId,
    required String serverName,
    required String localIp,
    required int port,
  }) async {
    final tlsMaterial = await _tlsManager.ensureMaterial(
      serverId: serverId,
      serverName: serverName,
      localIp: localIp,
      port: port,
    );
    return tlsMaterial.rootCaPem;
  }

  Future<EncryptedDeviceEnrollment> enrollDevice({
    required String serverId,
    required String clientPublicKeyBase64,
    required int timestampSeconds,
    required String deviceId,
    required String deviceName,
    String? physicalDeviceId,
    String? devicePlatform,
    String? deviceBrand,
    String? deviceModel,
  }) async {
    _validateRequestTimestamp(timestampSeconds);
    final session = await _loadSession(serverId);
    if (session == null || session.isExpired) {
      await _clearSession(serverId);
      throw PairingException('配对会话已过期，请重新扫描二维码');
    }

    final clientPublicKey = base64Url.decode(
      base64Url.normalize(clientPublicKeyBase64),
    );

    final sharedSecret = await _computeSharedSecret(
      privateKey: session.privateKey,
      publicKey: clientPublicKey,
    );

    final aesKey = await _deriveAesKey(
      sharedSecret: sharedSecret,
      serverId: serverId,
    );

    final enrollment = await _enrollDeviceTokens(
      deviceId: deviceId,
      deviceName: deviceName,
      physicalDeviceId: physicalDeviceId,
      devicePlatform: devicePlatform,
      deviceBrand: deviceBrand,
      deviceModel: deviceModel,
    );

    final encrypted = await _encryptEnrollment(
      enrollment: enrollment,
      key: aesKey,
    );

    await _clearSession(serverId);

    return EncryptedDeviceEnrollment(
      encryptedEnrollment: base64UrlEncode(encrypted),
      serverPublicKey: base64UrlEncode(session.publicKey),
    );
  }

  Future<_X25519KeyPair> _generateX25519KeyPair() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = keyPairData.bytes;
    final publicKeyBytes = publicKey.bytes;

    return _X25519KeyPair(
      privateKey: Uint8List.fromList(privateKeyBytes),
      publicKey: Uint8List.fromList(publicKeyBytes),
    );
  }

  Future<Uint8List> _computeSharedSecret({
    required Uint8List privateKey,
    required Uint8List publicKey,
  }) async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPairFromSeed(privateKey);
    final sharedSecret = await algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );

    return Uint8List.fromList(await sharedSecret.extractBytes());
  }

  Future<Uint8List> _deriveAesKey({
    required Uint8List sharedSecret,
    required String serverId,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    final secretKey = await hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: utf8.encode(serverId),
      info: utf8.encode('pairing-device-enrollment-v1'),
    );

    return Uint8List.fromList(await secretKey.extractBytes());
  }

  Future<Uint8List> _encryptEnrollment({
    required Map<String, dynamic> enrollment,
    required Uint8List key,
  }) async {
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(key);
    final plaintext = utf8.encode(jsonEncode(enrollment));

    final secretBox = await algorithm.encrypt(plaintext, secretKey: secretKey);

    final builder = BytesBuilder();
    builder.add(secretBox.nonce);
    builder.add(secretBox.cipherText);
    builder.add(secretBox.mac.bytes);
    return builder.toBytes();
  }

  Future<Map<String, dynamic>> _enrollDeviceTokens({
    required String deviceId,
    required String deviceName,
    String? physicalDeviceId,
    String? devicePlatform,
    String? deviceBrand,
    String? deviceModel,
  }) async {
    final result = await _deviceStore.enrollDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      physicalDeviceId: physicalDeviceId,
      platform: devicePlatform,
      brand: deviceBrand,
      model: deviceModel,
    );

    if (!result.isSuccess) {
      throw PairingException(
        result.failureMessage ?? '设备注册失败',
      );
    }

    final tokens = result.tokens!;
    return {
      'deviceId': tokens.device.deviceId,
      'deviceName': tokens.device.deviceName,
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
      'accessExpiresAt': tokens.accessExpiresAt.toUtc().toIso8601String(),
      'refreshExpiresAt': tokens.refreshExpiresAt.toUtc().toIso8601String(),
      'sessionId': tokens.sessionId,
    };
  }

  void _scheduleSessionCleanup(String serverId, DateTime expiresAt) {
    final delay = expiresAt.difference(DateTime.now());
    if (delay.isNegative) {
      _pendingSessions.remove(serverId);
      return;
    }

    Timer(delay, () {
      unawaited(_clearSession(serverId));
    });
  }

  void _validateRequestTimestamp(int timestampSeconds) {
    final requestTime = DateTime.fromMillisecondsSinceEpoch(
      timestampSeconds * 1000,
      isUtc: true,
    );
    final delta = DateTime.now().toUtc().difference(requestTime).abs();
    if (delta > _requestTimestampTolerance) {
      throw PairingException('配对请求时间戳无效，请重新扫描二维码');
    }
  }

  Future<void> _persistSession(PairingSession session) async {
    await _keyValueStore.setString(
      _sessionStorageKey(session.serverId),
      jsonEncode(session.toJson()),
    );
  }

  Future<PairingSession?> _loadSession(String serverId) async {
    await _keyValueStore.reload();

    final rawSession = _keyValueStore.getString(_sessionStorageKey(serverId));
    if (rawSession != null && rawSession.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSession);
        if (decoded is! Map) {
          await _clearSession(serverId);
          return null;
        }
        final session = PairingSession.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (session.isExpired) {
          await _clearSession(serverId);
          return null;
        }
        _pendingSessions[serverId] = session;
        return session;
      } catch (_) {
        await _clearSession(serverId);
        return null;
      }
    }

    final cachedSession = _pendingSessions[serverId];
    if (cachedSession == null) {
      return null;
    }
    if (cachedSession.isExpired) {
      await _clearSession(serverId);
      return null;
    }
    return cachedSession;
  }

  Future<void> _clearSession(String serverId) async {
    _pendingSessions.remove(serverId);
    await _keyValueStore.remove(_sessionStorageKey(serverId));
  }

  String _sessionStorageKey(String serverId) {
    return '$_pairingSessionStoragePrefix$serverId';
  }
}

class _X25519KeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;

  _X25519KeyPair({required this.privateKey, required this.publicKey});
}

class PairingException implements Exception {
  final String message;
  PairingException(this.message);

  @override
  String toString() => 'PairingException: $message';
}
