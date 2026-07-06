import '../relay_contract.dart';

enum RelayTransferStatus {
  created,
  uploading,
  ready,
  downloading,
  completed,
  cancelled,
  expired,
  failed,
  interrupted,
}

extension RelayTransferStatusX on RelayTransferStatus {
  bool get isTerminal => switch (this) {
    RelayTransferStatus.completed ||
    RelayTransferStatus.cancelled ||
    RelayTransferStatus.expired ||
    RelayTransferStatus.failed ||
    RelayTransferStatus.interrupted => true,
    RelayTransferStatus.created ||
    RelayTransferStatus.uploading ||
    RelayTransferStatus.ready ||
    RelayTransferStatus.downloading => false,
  };
}

enum RelayTransferTargetState {
  pending,
  ready,
  downloading,
  completed,
  cancelled,
  expired,
  failed,
  interrupted,
}

enum RelayArtifactCleanupState { pending, sealed, deleted }

class RelayTransferRecord {
  const RelayTransferRecord({
    required this.transferId,
    required this.senderAccountId,
    required this.senderLabel,
    required this.senderClientId,
    required this.targetCount,
    required this.fileName,
    this.mimeType,
    required this.fileSize,
    this.checksum,
    this.checksumAlgorithm = 'sha256',
    required this.chunkSize,
    this.storageMode = relayStorageModeStoreOnNas,
    required this.status,
    this.retryOfTransferId,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.expiredAt,
    this.readyAt,
    this.completedAt,
    this.cancelledAt,
    this.failedAt,
    this.interruptedAt,
    this.failureCode,
    this.failureMessage,
  });

  final String transferId;
  final String senderAccountId;
  final String senderLabel;
  final String senderClientId;
  final int targetCount;
  final String fileName;
  final String? mimeType;
  final int fileSize;
  final String? checksum;
  final String checksumAlgorithm;
  final int chunkSize;
  final String storageMode;
  final RelayTransferStatus status;
  final String? retryOfTransferId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final DateTime? expiredAt;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? failedAt;
  final DateTime? interruptedAt;
  final String? failureCode;
  final String? failureMessage;

  int get expectedChunkCount {
    if (fileSize <= 0) {
      return 0;
    }
    return (fileSize + chunkSize - 1) ~/ chunkSize;
  }

  RelayTransferRecord copyWith({
    String? transferId,
    String? senderAccountId,
    String? senderLabel,
    String? senderClientId,
    int? targetCount,
    String? fileName,
    Object? mimeType = _sentinel,
    int? fileSize,
    Object? checksum = _sentinel,
    String? checksumAlgorithm,
    int? chunkSize,
    String? storageMode,
    RelayTransferStatus? status,
    Object? retryOfTransferId = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    Object? expiredAt = _sentinel,
    Object? readyAt = _sentinel,
    Object? completedAt = _sentinel,
    Object? cancelledAt = _sentinel,
    Object? failedAt = _sentinel,
    Object? interruptedAt = _sentinel,
    Object? failureCode = _sentinel,
    Object? failureMessage = _sentinel,
  }) {
    return RelayTransferRecord(
      transferId: transferId ?? this.transferId,
      senderAccountId: senderAccountId ?? this.senderAccountId,
      senderLabel: senderLabel ?? this.senderLabel,
      senderClientId: senderClientId ?? this.senderClientId,
      targetCount: targetCount ?? this.targetCount,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType == _sentinel ? this.mimeType : mimeType as String?,
      fileSize: fileSize ?? this.fileSize,
      checksum: checksum == _sentinel ? this.checksum : checksum as String?,
      checksumAlgorithm: checksumAlgorithm ?? this.checksumAlgorithm,
      chunkSize: chunkSize ?? this.chunkSize,
      storageMode: storageMode ?? this.storageMode,
      status: status ?? this.status,
      retryOfTransferId: retryOfTransferId == _sentinel
          ? this.retryOfTransferId
          : retryOfTransferId as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      expiredAt: expiredAt == _sentinel
          ? this.expiredAt
          : expiredAt as DateTime?,
      readyAt: readyAt == _sentinel ? this.readyAt : readyAt as DateTime?,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as DateTime?,
      cancelledAt: cancelledAt == _sentinel
          ? this.cancelledAt
          : cancelledAt as DateTime?,
      failedAt: failedAt == _sentinel ? this.failedAt : failedAt as DateTime?,
      interruptedAt: interruptedAt == _sentinel
          ? this.interruptedAt
          : interruptedAt as DateTime?,
      failureCode: failureCode == _sentinel
          ? this.failureCode
          : failureCode as String?,
      failureMessage: failureMessage == _sentinel
          ? this.failureMessage
          : failureMessage as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transferId': transferId,
      'senderAccountId': senderAccountId,
      'senderLabel': senderLabel,
      'senderClientId': senderClientId,
      'targetCount': targetCount,
      'fileName': fileName,
      if (mimeType != null) 'mimeType': mimeType,
      'fileSize': fileSize,
      if (checksum != null) 'checksum': checksum,
      'checksumAlgorithm': checksumAlgorithm,
      'chunkSize': chunkSize,
      'storageMode': storageMode,
      'status': status.name,
      if (retryOfTransferId != null) 'retryOfTransferId': retryOfTransferId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (expiredAt != null) 'expiredAt': expiredAt!.toUtc().toIso8601String(),
      if (readyAt != null) 'readyAt': readyAt!.toUtc().toIso8601String(),
      if (completedAt != null)
        'completedAt': completedAt!.toUtc().toIso8601String(),
      if (cancelledAt != null)
        'cancelledAt': cancelledAt!.toUtc().toIso8601String(),
      if (failedAt != null) 'failedAt': failedAt!.toUtc().toIso8601String(),
      if (interruptedAt != null)
        'interruptedAt': interruptedAt!.toUtc().toIso8601String(),
      if (failureCode != null) 'failureCode': failureCode,
      if (failureMessage != null) 'failureMessage': failureMessage,
    };
  }
}

class RelayTransferTargetRecord {
  const RelayTransferTargetRecord({
    required this.transferId,
    required this.receiverClientId,
    required this.deliveryState,
    required this.updatedAt,
    this.deliveredAt,
    this.downloadStartedAt,
    this.downloadCompletedAt,
  });

  final String transferId;
  final String receiverClientId;
  final RelayTransferTargetState deliveryState;
  final DateTime updatedAt;
  final DateTime? deliveredAt;
  final DateTime? downloadStartedAt;
  final DateTime? downloadCompletedAt;

  RelayTransferTargetRecord copyWith({
    String? transferId,
    String? receiverClientId,
    RelayTransferTargetState? deliveryState,
    DateTime? updatedAt,
    Object? deliveredAt = _sentinel,
    Object? downloadStartedAt = _sentinel,
    Object? downloadCompletedAt = _sentinel,
  }) {
    return RelayTransferTargetRecord(
      transferId: transferId ?? this.transferId,
      receiverClientId: receiverClientId ?? this.receiverClientId,
      deliveryState: deliveryState ?? this.deliveryState,
      updatedAt: updatedAt ?? this.updatedAt,
      deliveredAt: deliveredAt == _sentinel
          ? this.deliveredAt
          : deliveredAt as DateTime?,
      downloadStartedAt: downloadStartedAt == _sentinel
          ? this.downloadStartedAt
          : downloadStartedAt as DateTime?,
      downloadCompletedAt: downloadCompletedAt == _sentinel
          ? this.downloadCompletedAt
          : downloadCompletedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transferId': transferId,
      'receiverClientId': receiverClientId,
      'deliveryState': deliveryState.name,
      if (deliveredAt != null)
        'deliveredAt': deliveredAt!.toUtc().toIso8601String(),
      if (downloadStartedAt != null)
        'downloadStartedAt': downloadStartedAt!.toUtc().toIso8601String(),
      if (downloadCompletedAt != null)
        'downloadCompletedAt': downloadCompletedAt!.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

class RelayTransferArtifactRecord {
  const RelayTransferArtifactRecord({
    required this.transferId,
    required this.tempPath,
    this.sealedPath,
    required this.chunkCount,
    required this.receivedBytes,
    required this.isSealed,
    required this.cleanupState,
    required this.updatedAt,
  });

  final String transferId;
  final String tempPath;
  final String? sealedPath;
  final int chunkCount;
  final int receivedBytes;
  final bool isSealed;
  final RelayArtifactCleanupState cleanupState;
  final DateTime updatedAt;

  RelayTransferArtifactRecord copyWith({
    String? transferId,
    String? tempPath,
    Object? sealedPath = _sentinel,
    int? chunkCount,
    int? receivedBytes,
    bool? isSealed,
    RelayArtifactCleanupState? cleanupState,
    DateTime? updatedAt,
  }) {
    return RelayTransferArtifactRecord(
      transferId: transferId ?? this.transferId,
      tempPath: tempPath ?? this.tempPath,
      sealedPath: sealedPath == _sentinel
          ? this.sealedPath
          : sealedPath as String?,
      chunkCount: chunkCount ?? this.chunkCount,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      isSealed: isSealed ?? this.isSealed,
      cleanupState: cleanupState ?? this.cleanupState,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transferId': transferId,
      'tempPath': tempPath,
      if (sealedPath != null) 'sealedPath': sealedPath,
      'chunkCount': chunkCount,
      'receivedBytes': receivedBytes,
      'isSealed': isSealed,
      'cleanupState': cleanupState.name,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

class RelayTransferAggregate {
  const RelayTransferAggregate({
    required this.transfer,
    required this.targets,
    required this.artifact,
  });

  final RelayTransferRecord transfer;
  final List<RelayTransferTargetRecord> targets;
  final RelayTransferArtifactRecord artifact;

  List<String> get receiverClientIds =>
      targets.map((target) => target.receiverClientId).toList(growable: false);

  bool isReceiver(String clientId) {
    return targets.any((target) => target.receiverClientId == clientId);
  }

  RelayTransferTargetRecord? targetForClient(String clientId) {
    for (final target in targets) {
      if (target.receiverClientId == clientId) {
        return target;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      ...transfer.toJson(),
      'targets': targets
          .map((target) => target.toJson())
          .toList(growable: false),
      'artifact': artifact.toJson(),
      'transport': RelayTransportDescriptor.forAggregate(this).toJson(),
    };
  }
}

class RelayTransportDescriptor {
  const RelayTransportDescriptor({
    required this.protocol,
    required this.upload,
    required this.download,
    this.thumbnailUpload,
    this.thumbnailDownload,
  });

  factory RelayTransportDescriptor.forTransfer(String transferId) {
    final payloadPath = buildRelayWebdavPayloadPath(transferId);
    final thumbnailPath = buildRelayWebdavThumbnailPath(transferId);
    return RelayTransportDescriptor(
      protocol: 'webdav',
      upload: RelayTransportEndpointDescriptor(method: 'PUT', path: payloadPath),
      download: RelayTransportEndpointDescriptor(
        method: 'GET',
        path: payloadPath,
        supportsRange: true,
      ),
      thumbnailUpload: RelayTransportEndpointDescriptor(
        method: 'PUT',
        path: thumbnailPath,
      ),
      thumbnailDownload: RelayTransportEndpointDescriptor(
        method: 'GET',
        path: thumbnailPath,
      ),
    );
  }

  factory RelayTransportDescriptor.forAggregate(
    RelayTransferAggregate aggregate,
  ) {
    final descriptor = RelayTransportDescriptor.forTransfer(
      aggregate.transfer.transferId,
    );
    return RelayTransportDescriptor(
      protocol: descriptor.protocol,
      upload: descriptor.upload,
      download: RelayTransportEndpointDescriptor(
        method: descriptor.download.method,
        path: descriptor.download.path,
        supportsRange: aggregate.artifact.isSealed,
      ),
      thumbnailUpload: descriptor.thumbnailUpload,
      thumbnailDownload: descriptor.thumbnailDownload,
    );
  }

  final String protocol;
  final RelayTransportEndpointDescriptor upload;
  final RelayTransportEndpointDescriptor download;
  final RelayTransportEndpointDescriptor? thumbnailUpload;
  final RelayTransportEndpointDescriptor? thumbnailDownload;

  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol,
      'upload': upload.toJson(),
      'download': download.toJson(),
      if (thumbnailUpload != null) 'thumbnailUpload': thumbnailUpload!.toJson(),
      if (thumbnailDownload != null)
        'thumbnailDownload': thumbnailDownload!.toJson(),
    };
  }
}

class RelayTransportEndpointDescriptor {
  const RelayTransportEndpointDescriptor({
    required this.method,
    required this.path,
    this.supportsRange,
  });

  final String method;
  final String path;
  final bool? supportsRange;

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'path': path,
      if (supportsRange != null) 'supportsRange': supportsRange,
    };
  }
}

class RelayPeerHistoryPage {
  const RelayPeerHistoryPage({
    required this.transfers,
    required this.hasMore,
  });

  final List<RelayTransferAggregate> transfers;
  final bool hasMore;
}

const Object _sentinel = Object();
