import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/tls/server_tls_certificate_builder.dart';
import 'package:nas_server/core/tls/server_tls_manager.dart';
import 'package:pointycastle/asn1/asn1_parser.dart';
import 'package:pointycastle/asn1/primitives/asn1_object_identifier.dart';
import 'package:pointycastle/asn1/primitives/asn1_octet_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';

void main() {
  group('ServerTlsCertificateBuilder', () {
    final builder = ServerTlsCertificateBuilder();

    test('generates Windows ECDSA material accepted by SecurityContext', () {
      final root = builder.generateRootMaterial(
        serverId: 'server-1',
        hostLabel: 'server-1',
        validityDays: 3650,
      );
      final leaf = builder.generateLeafMaterial(
        serverId: 'server-1',
        hostLabel: 'server-1',
        localIp: '192.168.1.100',
        issuer: root.subject,
        issuerPrivateKeyPem: root.privateKeyPem,
        issuerSubjectKeyIdentifier: root.subjectKeyIdentifier,
        validityDays: 825,
      );

      final material = ServerTlsMaterial(
        serverId: 'server-1',
        serverName: 'NAS Server',
        hostLabel: 'server-1',
        localIp: '192.168.1.100',
        port: 8443,
        rootCaPem: root.certificatePem,
        rootCaDerBase64Url: 'unused',
        leafCertificatePem: leaf.certificatePem,
        leafPrivateKeyPem: leaf.privateKeyPem,
        caSha256: 'unused',
        leafSha256: 'unused',
      );

      expect(() => material.createSecurityContext(), returnsNormally);
    });

    test(
      'encodes ECDSA signature algorithm without NULL and keeps IP SANs',
      () {
        final root = builder.generateRootMaterial(
          serverId: 'server-1',
          hostLabel: 'server-1',
          validityDays: 3650,
        );
        final leaf = builder.generateLeafMaterial(
          serverId: 'server-1',
          hostLabel: 'server-1',
          localIp: '192.168.1.100',
          issuer: root.subject,
          issuerPrivateKeyPem: root.privateKeyPem,
          issuerSubjectKeyIdentifier: root.subjectKeyIdentifier,
          validityDays: 825,
        );

        final certificate = _parseCertificate(leaf.certificatePem);
        final tbsCertificate = certificate.elements![0] as ASN1Sequence;
        final tbsSignatureAlgorithm =
            tbsCertificate.elements![2] as ASN1Sequence;
        final outerSignatureAlgorithm =
            certificate.elements![1] as ASN1Sequence;

        expect(tbsSignatureAlgorithm.elements, hasLength(1));
        expect(outerSignatureAlgorithm.elements, hasLength(1));
        expect(
          (tbsSignatureAlgorithm.elements!.single as ASN1ObjectIdentifier)
              .objectIdentifierAsString,
          '1.2.840.10045.4.3.2',
        );
        expect(
          (outerSignatureAlgorithm.elements!.single as ASN1ObjectIdentifier)
              .objectIdentifierAsString,
          '1.2.840.10045.4.3.2',
        );

        final sanExtension = _findExtension(certificate, '2.5.29.17');
        final sanSequence =
            ASN1Parser(
                  (sanExtension.elements!.last as ASN1OctetString).valueBytes!,
                ).nextObject()
                as ASN1Sequence;

        final ipSans = sanSequence.elements!
            .where((element) => element.tag == 0x87)
            .map((element) => Uint8List.fromList(element.valueBytes!))
            .toList();
        final dnsSans = sanSequence.elements!
            .where((element) => element.tag == 0x82)
            .map((element) => utf8.decode(element.valueBytes!))
            .toList();

        expect(dnsSans, containsAll(<String>['server-1.local', 'localhost']));
        expect(
          ipSans,
          containsAll(<Uint8List>[
            Uint8List.fromList(<int>[192, 168, 1, 100]),
            Uint8List.fromList(<int>[127, 0, 0, 1]),
          ]),
        );
      },
    );
  });
}

ASN1Sequence _parseCertificate(String pem) {
  final base64Body = pem
      .split(RegExp(r'\r?\n'))
      .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
      .join();
  return ASN1Parser(base64Decode(base64Body)).nextObject() as ASN1Sequence;
}

ASN1Sequence _findExtension(ASN1Sequence certificate, String oid) {
  final tbsCertificate = certificate.elements![0] as ASN1Sequence;
  final extensionObject = tbsCertificate.elements!.lastWhere(
    (element) => element.tag == 0xA3,
  );
  final extensionSequence =
      ASN1Parser(extensionObject.valueBytes!).nextObject() as ASN1Sequence;

  return extensionSequence.elements!.cast<ASN1Sequence>().firstWhere(
    (extension) =>
        ((extension.elements!.first) as ASN1ObjectIdentifier)
            .objectIdentifierAsString ==
        oid,
  );
}
