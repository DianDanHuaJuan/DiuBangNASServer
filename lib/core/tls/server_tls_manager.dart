import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'server_tls_native_data_source.dart';

class ServerTlsMaterial {
  const ServerTlsMaterial({
    required this.serverId,
    required this.serverName,
    required this.hostLabel,
    required this.localIp,
    required this.port,
    required this.rootCaPem,
    required this.rootCaDerBase64Url,
    required this.leafCertificatePem,
    required this.leafPrivateKeyPem,
    required this.caSha256,
    required this.leafSha256,
  });

  final String serverId;
  final String serverName;
  final String hostLabel;
  final String localIp;
  final int port;
  final String rootCaPem;
  final String rootCaDerBase64Url;
  final String leafCertificatePem;
  final String leafPrivateKeyPem;
  final String caSha256;
  final String leafSha256;

  String get dnsName => '$hostLabel.local';

  String get baseUrl => 'https://$localIp:$port';

  SecurityContext createSecurityContext() {
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(
      utf8.encode('$leafCertificatePem\n$rootCaPem'),
    );
    context.usePrivateKeyBytes(utf8.encode(leafPrivateKeyPem));
    return context;
  }

  Map<String, String> buildCompactPairingPayload() {
    return <String, String>{
      'i': serverId,
      'n': serverName,
      'u': baseUrl,
      'f': caSha256,
      'l': leafSha256,
    };
  }
}

class ServerTlsManager {
  ServerTlsManager({ServerTlsNativeDataSource? nativeDataSource})
    : _nativeDataSource =
          nativeDataSource ??
          (Platform.isAndroid
              ? MethodChannelServerTlsNativeDataSource()
              : FileBackedServerTlsNativeDataSource());

  final ServerTlsNativeDataSource _nativeDataSource;

  Future<ServerTlsMaterial> ensureMaterial({
    required String serverId,
    required String serverName,
    required String localIp,
    required int port,
  }) async {
    final hostLabel = buildHostLabel(serverId);
    final nativeMaterial = await _nativeDataSource.ensureMaterial(
      serverId: serverId,
      hostLabel: hostLabel,
      localIp: localIp,
    );

    if (nativeMaterial.hostLabel.trim().isEmpty ||
        nativeMaterial.rootCaPem.trim().isEmpty ||
        nativeMaterial.leafCertificatePem.trim().isEmpty ||
        nativeMaterial.leafPrivateKeyPem.trim().isEmpty) {
      throw const FormatException('Native TLS material was incomplete');
    }

    final rootCaDerBytes = _pemToDerBytes(nativeMaterial.rootCaPem);
    final leafDerBytes = _pemToDerBytes(nativeMaterial.leafCertificatePem);

    return ServerTlsMaterial(
      serverId: serverId,
      serverName: serverName,
      hostLabel: nativeMaterial.hostLabel,
      localIp: localIp,
      port: port,
      rootCaPem: nativeMaterial.rootCaPem,
      rootCaDerBase64Url: base64UrlEncode(rootCaDerBytes),
      leafCertificatePem: nativeMaterial.leafCertificatePem,
      leafPrivateKeyPem: nativeMaterial.leafPrivateKeyPem,
      caSha256: await _calculateSha256(rootCaDerBytes),
      leafSha256: await _calculateSha256(leafDerBytes),
    );
  }

  static String buildHostLabel(String serverId) {
    final normalized = serverId
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isEmpty) {
      return 'nas-server';
    }
    return normalized.length <= 48 ? normalized : normalized.substring(0, 48);
  }

  Future<String> _calculateSha256(List<int> bytes) async {
    final digest = await Sha256().hash(bytes);
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  List<int> _pemToDerBytes(String pem) {
    final lines = pem
        .split(RegExp(r'\r?\n'))
        .where(
          (line) =>
              !line.startsWith('-----BEGIN ') &&
              !line.startsWith('-----END ') &&
              line.trim().isNotEmpty,
        )
        .join();
    return base64Decode(lines);
  }
}
