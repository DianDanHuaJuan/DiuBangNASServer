import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/tls/server_tls_manager.dart';

void main() {
  group('ServerTlsMaterial', () {
    const material = ServerTlsMaterial(
      serverId: 'server-1',
      serverName: 'NAS Server',
      hostLabel: 'server-1',
      localIp: '192.168.1.100',
      port: 8443,
      rootCaPem:
          '-----BEGIN CERTIFICATE-----\nZmFrZS1yb290\n-----END CERTIFICATE-----',
      rootCaDerBase64Url: 'ZmFrZS1yb290',
      leafCertificatePem:
          '-----BEGIN CERTIFICATE-----\nZmFrZS1sZWFm\n-----END CERTIFICATE-----',
      leafPrivateKeyPem:
          '-----BEGIN PRIVATE KEY-----\nZmFrZS1rZXk=\n-----END PRIVATE KEY-----',
      caSha256: 'ca-sha',
      leafSha256: 'leaf-sha',
    );

    test('builds compact pairing payload', () {
      expect(material.buildCompactPairingPayload(), <String, String>{
        'i': 'server-1',
        'n': 'NAS Server',
        'u': 'https://192.168.1.100:8443',
        'f': 'ca-sha',
        'l': 'leaf-sha',
      });
    });

  });

  group('ServerTlsManager', () {
    test('normalizes host label from server id', () {
      expect(
        ServerTlsManager.buildHostLabel('  Demo Server__ID  '),
        'demo-server-id',
      );
    });
  });
}
