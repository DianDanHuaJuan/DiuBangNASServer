// 文件输入：无
// 文件职责：定义配对会话实体
// 文件对外接口：PairingSession
// 文件包含：PairingSession
import 'dart:convert';
import 'dart:typed_data';

class PairingSession {
  final String serverId;
  final Uint8List privateKey;
  final Uint8List publicKey;
  final DateTime expiresAt;

  const PairingSession({
    required this.serverId,
    required this.privateKey,
    required this.publicKey,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'privateKey': base64UrlEncode(privateKey),
      'publicKey': base64UrlEncode(publicKey),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  factory PairingSession.fromJson(Map<String, dynamic> json) {
    return PairingSession(
      serverId: json['serverId'] as String? ?? '',
      privateKey: Uint8List.fromList(
        base64Url.decode(
          base64Url.normalize(json['privateKey'] as String? ?? ''),
        ),
      ),
      publicKey: Uint8List.fromList(
        base64Url.decode(
          base64Url.normalize(json['publicKey'] as String? ?? ''),
        ),
      ),
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
