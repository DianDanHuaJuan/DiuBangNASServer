import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'server_tls_certificate_builder.dart';

class ServerTlsNativeMaterialRecord {
  const ServerTlsNativeMaterialRecord({
    required this.hostLabel,
    required this.rootCaPem,
    required this.leafCertificatePem,
    required this.leafPrivateKeyPem,
  });

  final String hostLabel;
  final String rootCaPem;
  final String leafCertificatePem;
  final String leafPrivateKeyPem;

  factory ServerTlsNativeMaterialRecord.fromMap(Map<dynamic, dynamic> map) {
    return ServerTlsNativeMaterialRecord(
      hostLabel: map['hostLabel'] as String? ?? '',
      rootCaPem: map['rootCaPem'] as String? ?? '',
      leafCertificatePem: map['leafCertificatePem'] as String? ?? '',
      leafPrivateKeyPem: map['leafPrivateKeyPem'] as String? ?? '',
    );
  }
}

abstract class ServerTlsNativeDataSource {
  Future<ServerTlsNativeMaterialRecord> ensureMaterial({
    required String serverId,
    required String hostLabel,
    required String localIp,
  });
}

class MethodChannelServerTlsNativeDataSource
    implements ServerTlsNativeDataSource {
  MethodChannelServerTlsNativeDataSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.nasserver.nas_server/tls');

  final MethodChannel _channel;

  @override
  Future<ServerTlsNativeMaterialRecord> ensureMaterial({
    required String serverId,
    required String hostLabel,
    required String localIp,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'ensureTlsMaterial',
      <String, dynamic>{
        'serverId': serverId,
        'hostLabel': hostLabel,
        'localIp': localIp,
      },
    );
    if (result == null) {
      throw const FormatException('Native TLS material response was empty');
    }
    return ServerTlsNativeMaterialRecord.fromMap(result);
  }
}

class FileBackedServerTlsNativeDataSource implements ServerTlsNativeDataSource {
  static const _tlsDirectoryName = 'tls';
  static const _rootCaCertFileName = 'root_ca_cert.pem';
  static const _rootCaKeyFileName = 'root_ca_key.pem';
  static const _leafCertFileName = 'server_leaf_cert.pem';
  static const _leafKeyFileName = 'server_leaf_key.pem';
  static const _metadataFileName = 'tls_metadata_native.json';
  static const _metadataVersion = 3;
  static const _rootValidityDays = 3650;
  static const _leafValidityDays = 825;

  FileBackedServerTlsNativeDataSource({
    ServerTlsCertificateBuilder? certificateBuilder,
    Future<Directory> Function()? supportDirectoryResolver,
  }) : _certificateBuilder =
           certificateBuilder ?? ServerTlsCertificateBuilder(),
       _supportDirectoryResolver =
           supportDirectoryResolver ?? getApplicationSupportDirectory;

  final ServerTlsCertificateBuilder _certificateBuilder;
  final Future<Directory> Function() _supportDirectoryResolver;

  @override
  Future<ServerTlsNativeMaterialRecord> ensureMaterial({
    required String serverId,
    required String hostLabel,
    required String localIp,
  }) async {
    final tlsDirectory = await _resolveTlsDirectory();
    final metadataFile = File(p.join(tlsDirectory.path, _metadataFileName));
    final rootCaCertFile = File(p.join(tlsDirectory.path, _rootCaCertFileName));
    final rootCaKeyFile = File(p.join(tlsDirectory.path, _rootCaKeyFileName));
    final leafCertFile = File(p.join(tlsDirectory.path, _leafCertFileName));
    final leafKeyFile = File(p.join(tlsDirectory.path, _leafKeyFileName));

    final metadata = await _loadMetadata(metadataFile);
    final rootSubject = <String, String>{
      'CN': 'NASServer $hostLabel Root CA',
      'O': 'NASServer',
      'OU': serverId,
    };

    var rootMaterial =
        metadata != null &&
            metadata.version == _metadataVersion &&
            metadata.serverId == serverId &&
            metadata.hostLabel == hostLabel &&
            await rootCaCertFile.exists() &&
            await rootCaKeyFile.exists()
        ? _StoredTlsMaterial(
            certificatePem: await rootCaCertFile.readAsString(),
            privateKeyPem: await rootCaKeyFile.readAsString(),
            subject: rootSubject,
            subjectKeyIdentifier: _certificateBuilder
                .computeSubjectKeyIdentifierFromPrivateKeyPem(
                  await rootCaKeyFile.readAsString(),
                ),
          )
        : _generateRootMaterial(serverId: serverId, hostLabel: hostLabel);

    var leafMaterial =
        metadata != null &&
            metadata.version == _metadataVersion &&
            metadata.serverId == serverId &&
            metadata.hostLabel == hostLabel &&
            metadata.localIp == localIp &&
            await leafCertFile.exists() &&
            await leafKeyFile.exists()
        ? _StoredTlsMaterial(
            certificatePem: await leafCertFile.readAsString(),
            privateKeyPem: await leafKeyFile.readAsString(),
            subject: <String, String>{
              'CN': '$hostLabel.local',
              'O': 'NASServer',
              'OU': serverId,
            },
          )
        : _generateLeafMaterial(
            serverId: serverId,
            hostLabel: hostLabel,
            localIp: localIp,
            issuer: rootMaterial.subject,
            issuerPrivateKeyPem: rootMaterial.privateKeyPem,
            issuerSubjectKeyIdentifier: rootMaterial.subjectKeyIdentifier!,
          );

    try {
      _certificateBuilder.validateIdentity(
        rootCaPem: rootMaterial.certificatePem,
        leafCertificatePem: leafMaterial.certificatePem,
        leafPrivateKeyPem: leafMaterial.privateKeyPem,
      );
    } on TlsException {
      rootMaterial = _generateRootMaterial(
        serverId: serverId,
        hostLabel: hostLabel,
      );
      leafMaterial = _generateLeafMaterial(
        serverId: serverId,
        hostLabel: hostLabel,
        localIp: localIp,
        issuer: rootMaterial.subject,
        issuerPrivateKeyPem: rootMaterial.privateKeyPem,
        issuerSubjectKeyIdentifier: rootMaterial.subjectKeyIdentifier!,
      );
      _certificateBuilder.validateIdentity(
        rootCaPem: rootMaterial.certificatePem,
        leafCertificatePem: leafMaterial.certificatePem,
        leafPrivateKeyPem: leafMaterial.privateKeyPem,
      );
    }

    await rootCaCertFile.writeAsString(rootMaterial.certificatePem);
    await rootCaKeyFile.writeAsString(rootMaterial.privateKeyPem);
    await leafCertFile.writeAsString(leafMaterial.certificatePem);
    await leafKeyFile.writeAsString(leafMaterial.privateKeyPem);
    await metadataFile.writeAsString(
      jsonEncode(<String, dynamic>{
        'version': _metadataVersion,
        'serverId': serverId,
        'hostLabel': hostLabel,
        'localIp': localIp,
      }),
    );

    return ServerTlsNativeMaterialRecord(
      hostLabel: hostLabel,
      rootCaPem: rootMaterial.certificatePem,
      leafCertificatePem: leafMaterial.certificatePem,
      leafPrivateKeyPem: leafMaterial.privateKeyPem,
    );
  }

  Future<Directory> _resolveTlsDirectory() async {
    final supportDirectory = await _supportDirectoryResolver();
    final tlsDirectory = Directory(
      p.join(supportDirectory.path, _tlsDirectoryName),
    );
    if (!await tlsDirectory.exists()) {
      await tlsDirectory.create(recursive: true);
    }
    return tlsDirectory;
  }

  Future<_StoredTlsMetadata?> _loadMetadata(File metadataFile) async {
    if (!await metadataFile.exists()) {
      return null;
    }

    final raw = (await metadataFile.readAsString()).trim();
    if (raw.isEmpty) {
      return null;
    }

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _StoredTlsMetadata(
        version: (json['version'] as num?)?.toInt() ?? 0,
        serverId: json['serverId'] as String? ?? '',
        hostLabel: json['hostLabel'] as String? ?? '',
        localIp: json['localIp'] as String? ?? '',
      );
    } on FormatException {
      return null;
    }
  }

  _StoredTlsMaterial _generateRootMaterial({
    required String serverId,
    required String hostLabel,
  }) {
    final material = _certificateBuilder.generateRootMaterial(
      serverId: serverId,
      hostLabel: hostLabel,
      validityDays: _rootValidityDays,
    );
    return _StoredTlsMaterial(
      certificatePem: material.certificatePem,
      privateKeyPem: material.privateKeyPem,
      subject: material.subject,
      subjectKeyIdentifier: material.subjectKeyIdentifier,
    );
  }

  _StoredTlsMaterial _generateLeafMaterial({
    required String serverId,
    required String hostLabel,
    required String localIp,
    required Map<String, String> issuer,
    required String issuerPrivateKeyPem,
    required Uint8List issuerSubjectKeyIdentifier,
  }) {
    final material = _certificateBuilder.generateLeafMaterial(
      serverId: serverId,
      hostLabel: hostLabel,
      localIp: localIp,
      issuer: issuer,
      issuerPrivateKeyPem: issuerPrivateKeyPem,
      issuerSubjectKeyIdentifier: issuerSubjectKeyIdentifier,
      validityDays: _leafValidityDays,
    );
    return _StoredTlsMaterial(
      certificatePem: material.certificatePem,
      privateKeyPem: material.privateKeyPem,
      subject: material.subject,
    );
  }
}

class _StoredTlsMaterial {
  const _StoredTlsMaterial({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.subject,
    this.subjectKeyIdentifier,
  });

  final String certificatePem;
  final String privateKeyPem;
  final Map<String, String> subject;
  final Uint8List? subjectKeyIdentifier;
}

class _StoredTlsMetadata {
  const _StoredTlsMetadata({
    required this.version,
    required this.serverId,
    required this.hostLabel,
    required this.localIp,
  });

  final int version;
  final String serverId;
  final String hostLabel;
  final String localIp;
}
