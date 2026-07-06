import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encryption_key_loader.dart';

/// Generate ENC1 tokens by AES-128-GCM encrypting a small JSON payload.
///
/// The token format is `ENC1|base64url(nonce || ciphertext || mac)`.
Future<String> generateEnc1Token(
  String username,
  String password, {
  int ttlSeconds = 300,
}) async {
  final keyBytes = await loadEncryptionKey();
  final secretKey = SecretKey(keyBytes);
  final algorithm = AesGcm.with128bits();

  final expiry =
      (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) + ttlSeconds;

  final payload = jsonEncode({
    'username': username,
    'password': password,
    'exp': expiry,
  });

  final plaintext = utf8.encode(payload);

  final secretBox = await algorithm.encrypt(plaintext, secretKey: secretKey);

  final nonce = secretBox.nonce;
  final cipherText = secretBox.cipherText;
  final mac = secretBox.mac.bytes;

  final builder = BytesBuilder();
  builder.add(nonce);
  builder.add(cipherText);
  builder.add(mac);
  final combined = builder.toBytes();

  final token = base64UrlEncode(combined);
  return 'ENC1|$token';
}
