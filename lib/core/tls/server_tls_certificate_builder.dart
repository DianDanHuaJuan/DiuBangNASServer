import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asn1/asn1_object.dart';
import 'package:pointycastle/asn1/primitives/asn1_bit_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_boolean.dart';
import 'package:pointycastle/asn1/primitives/asn1_integer.dart';
import 'package:pointycastle/asn1/primitives/asn1_object_identifier.dart';
import 'package:pointycastle/asn1/primitives/asn1_octet_string.dart';
import 'package:pointycastle/asn1/primitives/asn1_sequence.dart';
import 'package:pointycastle/asn1/primitives/asn1_utc_time.dart';
import 'package:pointycastle/digests/sha1.dart';

class GeneratedServerTlsMaterial {
  const GeneratedServerTlsMaterial({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.subject,
    required this.subjectKeyIdentifier,
  });

  final String certificatePem;
  final String privateKeyPem;
  final Map<String, String> subject;
  final Uint8List subjectKeyIdentifier;
}

class ServerTlsCertificateBuilder {
  GeneratedServerTlsMaterial generateRootMaterial({
    required String serverId,
    required String hostLabel,
    required int validityDays,
  }) {
    final keyPair = CryptoUtils.generateEcKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;
    final subject = <String, String>{
      'CN': 'NASServer $hostLabel Root CA',
      'O': 'NASServer',
      'OU': serverId,
    };
    final subjectKeyIdentifier = computeSubjectKeyIdentifier(publicKey);

    return GeneratedServerTlsMaterial(
      certificatePem: _buildCertificatePem(
        issuer: subject,
        subject: subject,
        subjectPublicKey: publicKey,
        signingPrivateKey: privateKey,
        validityDays: validityDays,
        extensions: <ASN1Sequence>[
          _buildExtension(
            oid: '2.5.29.19',
            value: _buildBasicConstraints(
              certificateAuthority: true,
              pathLen: 0,
            ),
            critical: true,
          ),
          _buildExtension(
            oid: '2.5.29.15',
            value: _buildKeyUsage(<int>[5, 6]),
            critical: true,
          ),
          _buildExtension(
            oid: '2.5.29.14',
            value: ASN1OctetString(octets: subjectKeyIdentifier),
          ),
          _buildExtension(
            oid: '2.5.29.35',
            value: _buildAuthorityKeyIdentifier(subjectKeyIdentifier),
          ),
        ],
      ),
      privateKeyPem: CryptoUtils.encodePrivateEcdsaKeyToPkcs8(privateKey),
      subject: subject,
      subjectKeyIdentifier: subjectKeyIdentifier,
    );
  }

  GeneratedServerTlsMaterial generateLeafMaterial({
    required String serverId,
    required String hostLabel,
    required String localIp,
    required Map<String, String> issuer,
    required String issuerPrivateKeyPem,
    required Uint8List issuerSubjectKeyIdentifier,
    required int validityDays,
  }) {
    final keyPair = CryptoUtils.generateEcKeyPair();
    final privateKey = keyPair.privateKey as ECPrivateKey;
    final publicKey = keyPair.publicKey as ECPublicKey;
    final subject = <String, String>{
      'CN': '$hostLabel.local',
      'O': 'NASServer',
      'OU': serverId,
    };
    final subjectKeyIdentifier = computeSubjectKeyIdentifier(publicKey);

    return GeneratedServerTlsMaterial(
      certificatePem: _buildCertificatePem(
        issuer: issuer,
        subject: subject,
        subjectPublicKey: publicKey,
        signingPrivateKey: CryptoUtils.ecPrivateKeyFromPem(issuerPrivateKeyPem),
        validityDays: validityDays,
        extensions: <ASN1Sequence>[
          _buildExtension(
            oid: '2.5.29.19',
            value: _buildBasicConstraints(certificateAuthority: false),
            critical: true,
          ),
          _buildExtension(
            oid: '2.5.29.15',
            value: _buildKeyUsage(<int>[0]),
            critical: true,
          ),
          _buildExtension(
            oid: '2.5.29.37',
            value: _buildServerAuthExtendedKeyUsage(),
          ),
          _buildExtension(
            oid: '2.5.29.17',
            value: _buildSubjectAlternativeNames(
              hostLabel: hostLabel,
              localIp: localIp,
            ),
          ),
          _buildExtension(
            oid: '2.5.29.14',
            value: ASN1OctetString(octets: subjectKeyIdentifier),
          ),
          _buildExtension(
            oid: '2.5.29.35',
            value: _buildAuthorityKeyIdentifier(issuerSubjectKeyIdentifier),
          ),
        ],
      ),
      privateKeyPem: CryptoUtils.encodePrivateEcdsaKeyToPkcs8(privateKey),
      subject: subject,
      subjectKeyIdentifier: subjectKeyIdentifier,
    );
  }

  Uint8List computeSubjectKeyIdentifier(ECPublicKey publicKey) {
    final digest = SHA1Digest();
    return Uint8List.fromList(digest.process(publicKey.Q!.getEncoded(false)));
  }

  Uint8List computeSubjectKeyIdentifierFromPrivateKeyPem(String privateKeyPem) {
    final privateKey = CryptoUtils.ecPrivateKeyFromPem(privateKeyPem);
    final publicPoint = privateKey.parameters!.G * privateKey.d!;
    final publicKey = ECPublicKey(publicPoint, privateKey.parameters);
    return computeSubjectKeyIdentifier(publicKey);
  }

  void validateIdentity({
    required String rootCaPem,
    required String leafCertificatePem,
    required String leafPrivateKeyPem,
  }) {
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(
      Uint8List.fromList('$leafCertificatePem\n$rootCaPem'.codeUnits),
    );
    context.usePrivateKeyBytes(Uint8List.fromList(leafPrivateKeyPem.codeUnits));
  }

  String _buildCertificatePem({
    required Map<String, String> issuer,
    required Map<String, String> subject,
    required ECPublicKey subjectPublicKey,
    required ECPrivateKey signingPrivateKey,
    required int validityDays,
    required List<ASN1Sequence> extensions,
  }) {
    final tbsCertificate = ASN1Sequence();
    final version = ASN1Object(tag: 0xA0);
    version.valueBytes = ASN1Integer(BigInt.from(2)).encode();

    tbsCertificate
      ..add(version)
      ..add(ASN1Integer(_nextSerialNumber()))
      ..add(_buildSignatureAlgorithm())
      ..add(X509Utils.encodeDN(issuer))
      ..add(_buildValidity(validityDays))
      ..add(X509Utils.encodeDN(subject))
      ..add(_buildSubjectPublicKeyInfo(subjectPublicKey))
      ..add(_buildExtensionsObject(extensions));

    final signature = X509Utils.eccSign(
      tbsCertificate.encode(),
      signingPrivateKey,
      'SHA-256',
    );
    final signatureValue = ASN1Sequence()
      ..add(ASN1Integer(signature.r))
      ..add(ASN1Integer(signature.s));

    final certificate = ASN1Sequence()
      ..add(tbsCertificate)
      ..add(_buildSignatureAlgorithm())
      ..add(ASN1BitString(stringValues: signatureValue.encode()));

    return X509Utils.encodeASN1ObjectToPem(
      certificate,
      X509Utils.BEGIN_CERT,
      X509Utils.END_CERT,
    );
  }

  ASN1Sequence _buildSignatureAlgorithm() {
    return ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromName('ecdsaWithSHA256'));
  }

  ASN1Sequence _buildValidity(int validityDays) {
    final notBefore = DateTime.now().subtract(const Duration(minutes: 5));
    return ASN1Sequence()
      ..add(ASN1UtcTime(notBefore))
      ..add(ASN1UtcTime(notBefore.add(Duration(days: validityDays))));
  }

  ASN1Sequence _buildSubjectPublicKeyInfo(ECPublicKey publicKey) {
    final algorithm = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromName('ecPublicKey'))
      ..add(ASN1ObjectIdentifier.fromName(publicKey.parameters!.domainName));
    return ASN1Sequence()
      ..add(algorithm)
      ..add(ASN1BitString(stringValues: publicKey.Q!.getEncoded(false)));
  }

  ASN1Object _buildExtensionsObject(List<ASN1Sequence> extensions) {
    final extensionSequence = ASN1Sequence();
    for (final extension in extensions) {
      extensionSequence.add(extension);
    }
    final extensionObject = ASN1Object(tag: 0xA3);
    extensionObject.valueBytes = extensionSequence.encode();
    return extensionObject;
  }

  ASN1Sequence _buildExtension({
    required String oid,
    required ASN1Object value,
    bool critical = false,
  }) {
    final sequence = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString(oid));
    if (critical) {
      sequence.add(ASN1Boolean(true));
    }
    sequence.add(ASN1OctetString(octets: value.encode()));
    return sequence;
  }

  ASN1Sequence _buildBasicConstraints({
    required bool certificateAuthority,
    int? pathLen,
  }) {
    final sequence = ASN1Sequence();
    if (certificateAuthority) {
      sequence.add(ASN1Boolean(true));
    }
    if (certificateAuthority && pathLen != null) {
      sequence.add(ASN1Integer(BigInt.from(pathLen)));
    }
    return sequence;
  }

  ASN1BitString _buildKeyUsage(List<int> bitPositions) {
    final highestBit = bitPositions.reduce(max);
    final bytes = Uint8List((highestBit ~/ 8) + 1);
    for (final bitPosition in bitPositions) {
      final byteIndex = bitPosition ~/ 8;
      final bitIndex = bitPosition % 8;
      bytes[byteIndex] |= 0x80 >> bitIndex;
    }
    final bitString = ASN1BitString(stringValues: bytes);
    bitString.unusedbits = (8 - ((highestBit % 8) + 1)) % 8;
    return bitString;
  }

  ASN1Sequence _buildServerAuthExtendedKeyUsage() {
    return ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.5.5.7.3.1'));
  }

  ASN1Sequence _buildSubjectAlternativeNames({
    required String hostLabel,
    required String localIp,
  }) {
    final parsedLocalIp = InternetAddress.tryParse(localIp);
    if (parsedLocalIp == null) {
      throw FormatException('Invalid IP address for TLS SAN: $localIp');
    }

    return ASN1Sequence()
      ..add(_buildContextString(tag: 0x82, value: '$hostLabel.local'))
      ..add(_buildContextString(tag: 0x82, value: 'localhost'))
      ..add(_buildContextBytes(tag: 0x87, value: parsedLocalIp.rawAddress))
      ..add(
        _buildContextBytes(
          tag: 0x87,
          value: InternetAddress.loopbackIPv4.rawAddress,
        ),
      );
  }

  ASN1Sequence _buildAuthorityKeyIdentifier(Uint8List keyIdentifier) {
    return ASN1Sequence()
      ..add(_buildContextBytes(tag: 0x80, value: keyIdentifier));
  }

  ASN1Object _buildContextString({required int tag, required String value}) {
    final object = ASN1Object(tag: tag);
    object.valueBytes = Uint8List.fromList(value.codeUnits);
    return object;
  }

  ASN1Object _buildContextBytes({required int tag, required List<int> value}) {
    final object = ASN1Object(tag: tag);
    object.valueBytes = Uint8List.fromList(value);
    return object;
  }

  BigInt _nextSerialNumber() {
    final random = Random.secure();
    BigInt serialNumber;
    do {
      serialNumber = BigInt.zero;
      for (var index = 0; index < 16; index++) {
        serialNumber = (serialNumber << 8) | BigInt.from(random.nextInt(256));
      }
    } while (serialNumber == BigInt.zero);
    return serialNumber;
  }
}
