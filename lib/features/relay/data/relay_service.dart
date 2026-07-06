import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../../core/auth/auth_session_store.dart';
import '../../../core/auth/account_models.dart';
import '../../../core/device_registry/device_models.dart';
import '../../../core/device_registry/device_store.dart';
import '../../../core/streams/buffered_byte_stream_transformer.dart';
import '../../../core/transfer/server_transfer_tuning.dart';
import '../../webdav/utils/range_parser.dart';
import '../domain/relay_models.dart';
import '../relay_contract.dart';
import 'relay_realtime_publisher.dart';
import 'relay_temp_storage_manager.dart';
import 'relay_transfer_repository.dart';

typedef RelayClock = DateTime Function();

class RelayService {
  RelayService({
    required RelayTransferRepository repository,
    required RelayTempStorageManager storageManager,
    required DeviceStore deviceStore,
    required RelayRealtimePublisher realtimePublisher,
    RangeParser rangeParser = const RangeParser(),
    RelayClock? clock,
    Random? random,
  }) : _repository = repository,
       _storageManager = storageManager,
       _deviceStore = deviceStore,
       _realtimePublisher = realtimePublisher,
       _rangeParser = rangeParser,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final RelayTransferRepository _repository;
  final RelayTempStorageManager _storageManager;
  final DeviceStore _deviceStore;
  final RelayRealtimePublisher _realtimePublisher;
  final RangeParser _rangeParser;
  final RelayClock _clock;
  final Random _random;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _storageManager.initialize();
    await _repository.initialize();
    await _recoverInterruptedTransfers();
    await _cleanupExpiredTransfers();
    _initialized = true;
  }

  Future<void> close() async {
    _initialized = false;
    await _repository.close();
  }

  Future<RelayTransferAggregate> createTransfer({
    required AuthenticatedRequestContext authContext,
    required List<String> targetClientIds,
    required String fileName,
    required int fileSize,
    required String? mimeType,
    required String? checksum,
    required int? chunkSize,
    String? senderClientId,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final normalizedTargets = _normalizeTargetClientIds(targetClientIds);
    if (normalizedTargets.length != 1) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'RELAY_TARGET_UNSUPPORTED',
        message: 'Current relay MVP only supports a single target client',
      );
    }

    final normalizedFileName = _normalizeFileName(fileName);
    final normalizedChecksum = _normalizeChecksum(checksum);
    final normalizedChunkSize = _normalizeChunkSize(chunkSize);
    final normalizedMimeType = _normalizeOptionalString(mimeType);
    final effectiveSenderClientId = await _resolveSenderClientId(
      authContext,
      requestedSenderClientId: senderClientId,
    );
    final receiverClientId = normalizedTargets.single;

    if (effectiveSenderClientId == receiverClientId) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'RELAY_TARGET_INVALID',
        message: 'Sender and receiver must be different clients',
      );
    }

    _validateFileSize(fileSize);
    await _ensureKnownActiveRelayClient(receiverClientId);

    final retainedBytes = await _repository.sumRetainedBytes();
    if (retainedBytes + fileSize > relayMaxRetainedBytes) {
      throw const RelayServiceException(
        statusCode: 409,
        code: 'STORAGE_FULL',
        message: 'Relay storage quota has been exhausted',
      );
    }

    final now = _now();
    final transfer = RelayTransferRecord(
      transferId: _nextTransferId(),
      senderAccountId: authContext.ownerId ?? authContext.deviceId ?? '',
      senderLabel: authContext.label ?? authContext.deviceName ?? '',
      senderClientId: effectiveSenderClientId,
      targetCount: normalizedTargets.length,
      fileName: normalizedFileName,
      mimeType: normalizedMimeType,
      fileSize: fileSize,
      checksum: normalizedChecksum,
      chunkSize: normalizedChunkSize,
      status: RelayTransferStatus.created,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(relayDefaultTtl),
    );
    final targets = normalizedTargets
        .map(
          (receiver) => RelayTransferTargetRecord(
            transferId: transfer.transferId,
            receiverClientId: receiver,
            deliveryState: RelayTransferTargetState.pending,
            deliveredAt: now,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    final artifact = RelayTransferArtifactRecord(
      transferId: transfer.transferId,
      tempPath: _storageManager.stagingFilePath(transfer.transferId),
      chunkCount: 0,
      receivedBytes: 0,
      isSealed: false,
      cleanupState: RelayArtifactCleanupState.pending,
      updatedAt: now,
    );
    final aggregate = RelayTransferAggregate(
      transfer: transfer,
      targets: targets,
      artifact: artifact,
    );
    await _repository.createTransfer(aggregate);
    _realtimePublisher.publishCreated(aggregate);
    return aggregate;
  }

  Future<RelayTransferAggregate> uploadTransfer({
    required AuthenticatedRequestContext authContext,
    required String transferId,
    required Stream<List<int>> body,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final aggregate = await _requireTransfer(transferId);
    _ensureCanUpload(authContext, aggregate);
    _ensureUploadableStatus(aggregate.transfer.status);

    final startedAt = _now();
    await _repository.updateUploadProgress(
      transferId: transferId,
      status: RelayTransferStatus.uploading,
      chunkCount: 0,
      receivedBytes: 0,
      updatedAt: startedAt,
    );

    final progressReporter = _RelayUploadProgressReporter(
      repository: _repository,
      realtimePublisher: _realtimePublisher,
      aggregate: aggregate,
      clock: _now,
    );

    try {
      final sealedArtifact = await _storageManager.writeUploadStream(
        transfer: aggregate.transfer,
        source: body,
        onProgress: (receivedBytes) {
          progressReporter.record(receivedBytes);
        },
      );
      await progressReporter.drain();

      final readyAt = _now();
      await _repository.markTransferReady(
        transferId: transferId,
        sealedPath: sealedArtifact.sealedPath,
        chunkCount: sealedArtifact.chunkCount,
        receivedBytes: sealedArtifact.receivedBytes,
        readyAt: readyAt,
      );
      final updatedAggregate = await _requireTransfer(transferId);
      _realtimePublisher.publishReady(updatedAggregate);
      return updatedAggregate;
    } on RelayStorageException catch (error) {
      progressReporter.cancel();
      await progressReporter.drain(ignoreErrors: true);
      await _handleUploadStorageFailure(transferId: transferId, error: error);
      rethrow;
    } catch (error) {
      progressReporter.cancel();
      await progressReporter.drain(ignoreErrors: true);
      await _handleUploadUnexpectedFailure(
        transferId: transferId,
        error: error,
      );
      rethrow;
    }
  }

  Future<RelayDownloadHeaders> describeDownload({
    required AuthenticatedRequestContext authContext,
    required String transferId,
    String? rangeHeader,
  }) async {
    final prepared = await _prepareDownload(
      authContext: authContext,
      transferId: transferId,
      rangeHeader: rangeHeader,
      markStarted: false,
    );
    return RelayDownloadHeaders(
      statusCode: prepared.statusCode,
      headers: prepared.headers,
    );
  }

  Future<RelayDownloadPayload> openDownload({
    required AuthenticatedRequestContext authContext,
    required String transferId,
    String? rangeHeader,
  }) async {
    final prepared = await _prepareDownload(
      authContext: authContext,
      transferId: transferId,
      rangeHeader: rangeHeader,
      markStarted: true,
    );
    final stream = _buildDownloadStream(
      file: prepared.file,
      aggregate: prepared.aggregate,
      transferId: transferId,
      receiverClientId: prepared.receiverClientId,
      start: prepared.range?.start,
      endInclusive: prepared.range?.end,
      shouldMarkCompleted: prepared.shouldMarkCompleted,
    );
    return RelayDownloadPayload(
      statusCode: prepared.statusCode,
      headers: prepared.headers,
      stream: stream,
    );
  }

  Future<RelayTransferAggregate> acknowledgeDownloadCompleted({
    required AuthenticatedRequestContext authContext,
    required String transferId,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final aggregate = await _requireTransfer(transferId);
    final receiverClientId = _ensureCanDownload(authContext, aggregate);
    if (receiverClientId == null) {
      throw const RelayServiceException(
        statusCode: 403,
        code: 'AUTH_FORBIDDEN',
        message: 'Only the receiver can acknowledge relay downloads',
      );
    }
    if (!{
      RelayTransferStatus.uploading,
      RelayTransferStatus.ready,
      RelayTransferStatus.downloading,
      RelayTransferStatus.completed,
    }.contains(aggregate.transfer.status)) {
      throw const RelayServiceException(
        statusCode: 409,
        code: 'TRANSFER_STATUS_INVALID',
        message: 'This transfer is not ready to finish downloading',
      );
    }

    final target = aggregate.targetForClient(receiverClientId);
    if (target?.deliveryState == RelayTransferTargetState.completed &&
        aggregate.transfer.status == RelayTransferStatus.completed) {
      await _purgeTransferArtifactsIfFullyCompleted(transferId: transferId);
      return await _requireTransfer(transferId);
    }

    final completedAt = _now();
    await _repository.markTransferCompleted(
      transferId: transferId,
      receiverClientId: receiverClientId,
      completedAt: completedAt,
    );
    final completedAggregate = _buildCompletedAggregate(
      aggregate: aggregate,
      receiverClientId: receiverClientId,
      completedAt: completedAt,
    );
    await _purgeTransferArtifactsIfFullyCompleted(transferId: transferId);
    _realtimePublisher.publishCompleted(
      completedAggregate,
      receiverClientId: receiverClientId,
    );
    return completedAggregate;
  }

  Future<RelayTransferAggregate> cancelTransfer({
    required AuthenticatedRequestContext authContext,
    required String transferId,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final aggregate = await _requireTransfer(transferId);
    _ensureCanCancel(authContext, aggregate);
    if (aggregate.transfer.status.isTerminal) {
      throw const RelayServiceException(
        statusCode: 409,
        code: 'TRANSFER_STATUS_INVALID',
        message: 'This transfer is already finished and cannot be cancelled',
      );
    }

    final cancelledAt = _now();
    await _storageManager.deleteTransferData(transferId);
    await _repository.markTransferCancelled(
      transferId: transferId,
      cancelledAt: cancelledAt,
    );
    final updatedAggregate = await _requireTransfer(transferId);
    _realtimePublisher.publishCancelled(updatedAggregate);
    return updatedAggregate;
  }

  Future<List<RelayTransferAggregate>> listHistory({
    required AuthenticatedRequestContext authContext,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    if (authContext.role == AccountRole.owner) {
      return _repository.listTransfers();
    }

    final clientId = _normalizeClientId(authContext.clientId);
    if (clientId == null) {
      throw const RelayServiceException(
        statusCode: 403,
        code: 'AUTH_FORBIDDEN',
        message: 'Client relay history requires a bound deviceId',
      );
    }
    return _repository.listTransfers(participantClientId: clientId);
  }

  Future<RelayPeerHistoryPage> listPeerHistory({
    required AuthenticatedRequestContext authContext,
    required String peerClientId,
    int limit = 20,
    DateTime? beforeCreatedAt,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final normalizedPeer = _normalizeClientId(peerClientId);
    if (normalizedPeer == null) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message: 'peerClientId must be a non-empty clientId',
      );
    }

    final effectiveLimit = limit.clamp(1, 100);
    final selfClientId = _normalizeClientId(authContext.clientId);
    if (selfClientId == null) {
      throw const RelayServiceException(
        statusCode: 403,
        code: 'AUTH_FORBIDDEN',
        message: 'Client relay history requires a bound deviceId',
      );
    }

    final transfers = await _repository.listPeerTransfers(
      selfClientId: selfClientId,
      peerClientId: normalizedPeer,
      limit: effectiveLimit,
      beforeCreatedAt: beforeCreatedAt,
    );
    return RelayPeerHistoryPage(
      transfers: transfers,
      hasMore: transfers.length == effectiveLimit,
    );
  }

  Future<List<RelayTransferAggregate>> listPendingIncomingTransfers({
    required String receiverClientId,
    int limit = 50,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final normalized = _normalizeClientId(receiverClientId);
    if (normalized == null) {
      return const <RelayTransferAggregate>[];
    }

    final transfers = await _repository.listTransfers(
      participantClientId: normalized,
    );
    return transfers
        .where((aggregate) {
          if (aggregate.transfer.status.isTerminal) {
            return false;
          }
          return aggregate.targets.any(
            (target) =>
                target.receiverClientId == normalized &&
                (target.deliveryState == RelayTransferTargetState.pending ||
                    target.deliveryState == RelayTransferTargetState.ready),
          );
        })
        .take(limit)
        .toList(growable: false);
  }

  Future<void> uploadThumbnail({
    required AuthenticatedRequestContext authContext,
    required String transferId,
    required Stream<List<int>> body,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final aggregate = await _requireTransfer(transferId);
    _ensureCanUpload(authContext, aggregate);

    final thumbnailFile = File(
      _storageManager.thumbnailFilePath(transferId),
    );
    final stagingFile = File(
      _storageManager.thumbnailStagingFilePath(transferId),
    );
    await thumbnailFile.parent.create(recursive: true);
    await _storageManager.deleteThumbnailFile(transferId);
    final sink = stagingFile.openWrite();
    var receivedBytes = 0;
    try {
      await for (final chunk in bufferByteStream(
        body,
        ServerTransferTuning.uploadStreamBufferSize,
      )) {
        receivedBytes += chunk.length;
        sink.add(chunk);
      }
    } catch (error) {
      await sink.close();
      await _storageManager.deleteThumbnailFile(transferId);
      rethrow;
    }
    await sink.close();
    if (receivedBytes <= 0) {
      await _storageManager.deleteThumbnailFile(transferId);
      throw const RelayServiceException(
        statusCode: 400,
        code: 'THUMBNAIL_EMPTY',
        message: 'Thumbnail upload body was empty',
      );
    }
    await stagingFile.rename(thumbnailFile.path);

    await _repository.saveThumbnailPath(
      transferId: transferId,
      thumbnailPath: thumbnailFile.path,
      updatedAt: _now(),
    );
    final updatedAggregate = await _requireTransfer(transferId);
    _realtimePublisher.publishUploadProgress(
      updatedAggregate,
      receivedBytes: updatedAggregate.artifact.receivedBytes,
      chunkCount: updatedAggregate.artifact.chunkCount,
    );
  }

  Future<RelayDownloadHeaders> describeThumbnailDownload({
    required AuthenticatedRequestContext authContext,
    required String transferId,
  }) async {
    final thumbnail = await _prepareThumbnailDownload(
      authContext: authContext,
      transferId: transferId,
    );
    return RelayDownloadHeaders(
      statusCode: 200,
      headers: thumbnail.headers,
    );
  }

  Future<RelayDownloadPayload> openThumbnailDownload({
    required AuthenticatedRequestContext authContext,
    required String transferId,
  }) async {
    final thumbnail = await _prepareThumbnailDownload(
      authContext: authContext,
      transferId: transferId,
    );
    return RelayDownloadPayload(
      statusCode: 200,
      headers: thumbnail.headers,
      stream: thumbnail.file.openRead(),
    );
  }

  Future<RelayTransferAggregate> retryTransfer({
    required AuthenticatedRequestContext authContext,
    required String transferId,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final source = await _requireTransfer(transferId);
    _ensureCanRetry(authContext, source);
    if (!source.transfer.status.isTerminal) {
      throw const RelayServiceException(
        statusCode: 409,
        code: 'TRANSFER_STATUS_INVALID',
        message: 'Only terminal transfers can be retried',
      );
    }

    final retainedBytes = await _repository.sumRetainedBytes();
    if (retainedBytes + source.transfer.fileSize > relayMaxRetainedBytes) {
      throw const RelayServiceException(
        statusCode: 409,
        code: 'STORAGE_FULL',
        message: 'Relay storage quota has been exhausted',
      );
    }

    final now = _now();
    final retriedTransfer = RelayTransferRecord(
      transferId: _nextTransferId(),
      senderAccountId: source.transfer.senderAccountId,
      senderLabel: source.transfer.senderLabel,
      senderClientId: source.transfer.senderClientId,
      targetCount: source.targets.length,
      fileName: source.transfer.fileName,
      mimeType: source.transfer.mimeType,
      fileSize: source.transfer.fileSize,
      checksum: source.transfer.checksum,
      checksumAlgorithm: source.transfer.checksumAlgorithm,
      chunkSize: source.transfer.chunkSize,
      storageMode: source.transfer.storageMode,
      status: RelayTransferStatus.created,
      retryOfTransferId: source.transfer.transferId,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.add(relayDefaultTtl),
    );
    final targets = source.targets
        .map(
          (target) => RelayTransferTargetRecord(
            transferId: retriedTransfer.transferId,
            receiverClientId: target.receiverClientId,
            deliveryState: RelayTransferTargetState.pending,
            deliveredAt: now,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    final artifact = RelayTransferArtifactRecord(
      transferId: retriedTransfer.transferId,
      tempPath: _storageManager.stagingFilePath(retriedTransfer.transferId),
      chunkCount: 0,
      receivedBytes: 0,
      isSealed: false,
      cleanupState: RelayArtifactCleanupState.pending,
      updatedAt: now,
    );
    final retriedAggregate = RelayTransferAggregate(
      transfer: retriedTransfer,
      targets: targets,
      artifact: artifact,
    );
    await _repository.createTransfer(retriedAggregate);
    _realtimePublisher.publishCreated(retriedAggregate);
    return retriedAggregate;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  Future<_PreparedRelayDownload> _prepareDownload({
    required AuthenticatedRequestContext authContext,
    required String transferId,
    required String? rangeHeader,
    required bool markStarted,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    var aggregate = await _requireTransfer(transferId);
    final receiverClientId = _ensureCanDownload(authContext, aggregate);

    if (aggregate.artifact.cleanupState == RelayArtifactCleanupState.deleted) {
      throw const RelayServiceException(
        statusCode: 410,
        code: 'ARTIFACT_PURGED',
        message: 'Relay artifact has been released from NAS storage',
      );
    }

    if (!{
      RelayTransferStatus.ready,
      RelayTransferStatus.downloading,
      RelayTransferStatus.completed,
    }.contains(aggregate.transfer.status)) {
      throw const RelayServiceException(
        statusCode: 409,
        code: 'TRANSFER_STATUS_INVALID',
        message: 'This transfer is not ready to download',
      );
    }
    final fileSize = aggregate.transfer.fileSize;
    final isSealed =
        aggregate.artifact.isSealed && aggregate.artifact.sealedPath != null;
    if (!isSealed && rangeHeader != null) {
      throw const RelayServiceException(
        statusCode: 409,
        code: 'RANGE_NOT_AVAILABLE',
        message: 'Range requests are only available after relay upload seals',
      );
    }

    final File downloadFile;
    RangeResult? range;
    if (isSealed) {
      downloadFile = File(aggregate.artifact.sealedPath!);
      if (!await downloadFile.exists()) {
        throw const RelayServiceException(
          statusCode: 404,
          code: 'TRANSFER_NOT_FOUND',
          message: 'The relay artifact no longer exists on disk',
        );
      }
      range = rangeHeader == null
          ? null
          : _rangeParser.parse(rangeHeader, fileSize);
      if (rangeHeader != null && range == null) {
        throw RelayServiceException(
          statusCode: 416,
          code: 'RANGE_INVALID',
          message: 'Invalid range header',
          headers: <String, String>{'Content-Range': 'bytes */$fileSize'},
        );
      }
    } else {
      downloadFile = File(aggregate.artifact.tempPath);
      if (!await downloadFile.exists() ||
          aggregate.artifact.receivedBytes <= 0) {
        throw const RelayServiceException(
          statusCode: 409,
          code: 'TRANSFER_NOT_READY',
          message: 'The relay upload has not produced readable data yet',
        );
      }
    }

    if (markStarted &&
        receiverClientId != null &&
        aggregate.transfer.status != RelayTransferStatus.completed) {
      final startedAt = _now();
      await _repository.markTransferDownloadStarted(
        transferId: transferId,
        receiverClientId: receiverClientId,
        startedAt: startedAt,
      );
      final downloadingAggregate = _buildDownloadStartedAggregate(
        aggregate: aggregate,
        receiverClientId: receiverClientId,
        startedAt: startedAt,
      );
      _realtimePublisher.publishDownloadProgress(
        downloadingAggregate,
        receiverClientId: receiverClientId,
        receivedBytes: range == null ? 0 : range.end - range.start + 1,
      );
      aggregate = downloadingAggregate;
    }

    final start = range?.start;
    final end = range?.end;
    final contentLength = range == null ? fileSize : end! - start! + 1;
    final headers = <String, String>{
      'Content-Type': aggregate.transfer.mimeType ?? 'application/octet-stream',
      'Content-Length': '$contentLength',
      'Accept-Ranges': isSealed ? 'bytes' : 'none',
      'Content-Disposition': _buildContentDisposition(
        aggregate.transfer.fileName,
      ),
    };
    if (range != null) {
      headers['Content-Range'] =
          'bytes ${range.start}-${range.end}/${range.totalSize}';
    }

    return _PreparedRelayDownload(
      file: downloadFile,
      aggregate: aggregate,
      receiverClientId: receiverClientId,
      headers: headers,
      statusCode: range == null ? 200 : 206,
      range: range,
      shouldMarkCompleted:
          receiverClientId != null &&
          (range == null || (range.start == 0 && range.end == fileSize - 1)),
    );
  }

  Future<void> _recoverInterruptedTransfers() async {
    final transfers = await _repository.listTransfersForStartupRecovery();
    if (transfers.isEmpty) {
      return;
    }

    final interruptedAt = _now();
    for (final aggregate in transfers) {
      await _storageManager.deleteTransferData(aggregate.transfer.transferId);
      await _repository.markTransferInterrupted(
        transferId: aggregate.transfer.transferId,
        interruptedAt: interruptedAt,
      );
    }
  }

  Future<void> _cleanupExpiredTransfers() async {
    final expiredTransfers = await _repository.listExpiredTransfers(_now());
    for (final aggregate in expiredTransfers) {
      await _storageManager.deleteTransferData(aggregate.transfer.transferId);
      await _repository.markTransferExpired(
        transferId: aggregate.transfer.transferId,
        expiredAt: _now(),
      );
    }
  }

  Future<void> _purgeTransferArtifactsIfFullyCompleted({
    required String transferId,
  }) async {
    final aggregate = await _repository.findTransferById(transferId);
    if (aggregate == null) {
      return;
    }
    if (aggregate.transfer.status != RelayTransferStatus.completed) {
      return;
    }
    if (aggregate.artifact.cleanupState == RelayArtifactCleanupState.deleted) {
      return;
    }
    await _storageManager.deleteTransferData(transferId);
    await _repository.markArtifactDeleted(
      transferId: transferId,
      deletedAt: _now(),
    );
  }

  Future<RelayTransferAggregate> _requireTransfer(String transferId) async {
    final aggregate = await _repository.findTransferById(transferId);
    if (aggregate == null) {
      throw const RelayServiceException(
        statusCode: 404,
        code: 'TRANSFER_NOT_FOUND',
        message: 'Relay transfer does not exist',
      );
    }
    return aggregate;
  }

  Future<void> _handleUploadStorageFailure({
    required String transferId,
    required RelayStorageException error,
  }) async {
    await _storageManager.deleteTransferData(transferId);
    final timestamp = _now();
    switch (error.code) {
      case 'TRANSFER_STREAM_FAILED':
        await _repository.markTransferInterrupted(
          transferId: transferId,
          interruptedAt: timestamp,
        );
        break;
      default:
        await _repository.markTransferFailed(
          transferId: transferId,
          failedAt: timestamp,
          failureCode: error.code,
          failureMessage: error.message,
        );
        break;
    }
    final aggregate = await _repository.findTransferById(transferId);
    if (aggregate != null) {
      _realtimePublisher.publishFailed(
        aggregate,
        failureCode: error.code,
        failureMessage: error.message,
      );
    }
  }

  Future<void> _handleUploadUnexpectedFailure({
    required String transferId,
    required Object error,
  }) async {
    await _storageManager.deleteTransferData(transferId);
    final timestamp = _now();
    await _repository.markTransferInterrupted(
      transferId: transferId,
      interruptedAt: timestamp,
    );
    final aggregate = await _repository.findTransferById(transferId);
    if (aggregate != null) {
      _realtimePublisher.publishFailed(
        aggregate,
        failureCode: 'TRANSFER_STREAM_FAILED',
        failureMessage: '$error',
      );
    }
  }

  Future<String> _resolveSenderClientId(
    AuthenticatedRequestContext authContext, {
    String? requestedSenderClientId,
  }) async {
    final normalizedRequestedClientId = _normalizeClientId(
      requestedSenderClientId,
    );
    if (authContext.role == AccountRole.device) {
      final boundClientId = _normalizeClientId(authContext.clientId);
      if (boundClientId == null) {
        throw const RelayServiceException(
          statusCode: 403,
          code: 'AUTH_FORBIDDEN',
          message: 'Client relay actions require a bound deviceId',
        );
      }
      if (normalizedRequestedClientId != null &&
          normalizedRequestedClientId != boundClientId) {
        throw const RelayServiceException(
          statusCode: 403,
          code: 'AUTH_FORBIDDEN',
          message: 'Clients can only send relay transfers as themselves',
        );
      }
      return boundClientId;
    }

    if (normalizedRequestedClientId == null) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'CLIENT_ID_REQUIRED',
        message: 'Owner relay requests must declare senderDeviceId',
      );
    }
    await _ensureKnownActiveRelayClient(normalizedRequestedClientId);
    return normalizedRequestedClientId;
  }

  Future<void> _ensureKnownActiveRelayClient(String clientId) async {
    final device = await _deviceStore.findDeviceById(clientId);
    if (device == null || device.status != DeviceStatus.active) {
      throw RelayServiceException(
        statusCode: 404,
        code: 'RELAY_TARGET_NOT_FOUND',
        message: 'Relay device "$clientId" is not a known active device',
      );
    }
  }

  void _ensureCanUpload(
    AuthenticatedRequestContext authContext,
    RelayTransferAggregate aggregate,
  ) {
    if (authContext.role == AccountRole.owner) {
      return;
    }
    final clientId = _normalizeClientId(authContext.clientId);
    if (clientId == null || clientId != aggregate.transfer.senderClientId) {
      throw const RelayServiceException(
        statusCode: 403,
        code: 'AUTH_FORBIDDEN',
        message: 'Only the sender can upload this relay transfer',
      );
    }
  }

  void _ensureCanCancel(
    AuthenticatedRequestContext authContext,
    RelayTransferAggregate aggregate,
  ) {
    if (authContext.role == AccountRole.owner) {
      return;
    }
    final clientId = _normalizeClientId(authContext.clientId);
    if (clientId == null || clientId != aggregate.transfer.senderClientId) {
      throw const RelayServiceException(
        statusCode: 403,
        code: 'AUTH_FORBIDDEN',
        message: 'Only the sender can cancel this transfer',
      );
    }
  }

  void _ensureCanRetry(
    AuthenticatedRequestContext authContext,
    RelayTransferAggregate aggregate,
  ) {
    if (authContext.role == AccountRole.owner) {
      return;
    }
    final clientId = _normalizeClientId(authContext.clientId);
    if (clientId == null || clientId != aggregate.transfer.senderClientId) {
      throw const RelayServiceException(
        statusCode: 403,
        code: 'AUTH_FORBIDDEN',
        message: 'Only the original sender can retry this transfer',
      );
    }
  }

  String? _ensureCanDownload(
    AuthenticatedRequestContext authContext,
    RelayTransferAggregate aggregate,
  ) {
    if (authContext.role == AccountRole.owner) {
      return null;
    }
    final clientId = _normalizeClientId(authContext.clientId);
    if (clientId == null || !aggregate.isReceiver(clientId)) {
      throw const RelayServiceException(
        statusCode: 403,
        code: 'AUTH_FORBIDDEN',
        message: 'Only the receiver can download this relay transfer',
      );
    }
    return clientId;
  }

  void _ensureUploadableStatus(RelayTransferStatus status) {
    if (status == RelayTransferStatus.created ||
        status == RelayTransferStatus.uploading) {
      return;
    }
    throw const RelayServiceException(
      statusCode: 409,
      code: 'TRANSFER_STATUS_INVALID',
      message: 'This transfer is no longer accepting uploaded data',
    );
  }

  List<String> _normalizeTargetClientIds(List<String> targetClientIds) {
    final normalized = <String>{};
    for (final targetClientId in targetClientIds) {
      final clientId = _normalizeClientId(targetClientId);
      if (clientId != null) {
        normalized.add(clientId);
      }
    }
    if (normalized.isEmpty) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message: 'targetClientIds must contain at least one clientId',
      );
    }
    return normalized.toList(growable: false);
  }

  String _normalizeFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message: 'fileName is required',
      );
    }
    if (trimmed.contains('/') || trimmed.contains(r'\')) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message: 'fileName must not contain path separators',
      );
    }
    final baseName = p.basename(trimmed);
    if (baseName.isEmpty || baseName == '.' || baseName == '..') {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message: 'fileName is invalid',
      );
    }
    return baseName;
  }

  String? _normalizeOptionalString(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? _normalizeChecksum(String? checksum) {
    final trimmed = checksum?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final isValid = RegExp(r'^[0-9a-f]{64}$').hasMatch(trimmed);
    if (!isValid) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message: 'checksum must be a lowercase sha256 hex string',
      );
    }
    return trimmed;
  }

  int _normalizeChunkSize(int? chunkSize) {
    final normalizedChunkSize = chunkSize ?? relayDefaultChunkSizeBytes;
    if (normalizedChunkSize < relayMinChunkSizeBytes ||
        normalizedChunkSize > relayMaxChunkSizeBytes) {
      throw RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message:
            'chunkSize must be between $relayMinChunkSizeBytes and $relayMaxChunkSizeBytes bytes',
      );
    }
    return normalizedChunkSize;
  }

  void _validateFileSize(int fileSize) {
    if (fileSize < 0) {
      throw const RelayServiceException(
        statusCode: 400,
        code: 'INVALID_REQUEST',
        message: 'fileSize must be zero or greater',
      );
    }
    if (fileSize > relayMaxFileSizeBytes) {
      throw RelayServiceException(
        statusCode: 400,
        code: 'FILE_TOO_LARGE',
        message:
            'fileSize exceeds the current relay limit of $relayMaxFileSizeBytes bytes',
      );
    }
  }

  String? _normalizeClientId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  DateTime _now() => _clock().toUtc();

  String _nextTransferId() {
    final randomBytes = List<int>.generate(
      9,
      (_) => _random.nextInt(256),
      growable: false,
    );
    final randomSuffix = base64UrlEncode(randomBytes).replaceAll('=', '');
    return 'relay_${_now().microsecondsSinceEpoch}_$randomSuffix';
  }

  Stream<List<int>> _buildDownloadStream({
    required File file,
    required RelayTransferAggregate aggregate,
    required String transferId,
    required String? receiverClientId,
    required int? start,
    required int? endInclusive,
    required bool shouldMarkCompleted,
  }) {
    if (!aggregate.artifact.isSealed) {
      final liveSource = _buildLiveDownloadStream(
        transferId: transferId,
        aggregate: aggregate,
        initialFile: file,
      );
      if (!shouldMarkCompleted || receiverClientId == null) {
        return liveSource;
      }
      return _markCompletedWhenDone(
        source: liveSource,
        aggregate: aggregate,
        transferId: transferId,
        receiverClientId: receiverClientId,
      );
    }
    final endExclusive = endInclusive == null ? null : endInclusive + 1;
    final source = bufferByteStream(
      file.openRead(start, endExclusive),
      ServerTransferTuning.downloadStreamBufferSize,
    );
    if (!shouldMarkCompleted || receiverClientId == null) {
      return source;
    }
    return _markCompletedWhenDone(
      source: source,
      aggregate: aggregate,
      transferId: transferId,
      receiverClientId: receiverClientId,
    );
  }

  Stream<List<int>> _buildLiveDownloadStream({
    required String transferId,
    required RelayTransferAggregate aggregate,
    required File initialFile,
  }) async* {
    final totalBytes = aggregate.transfer.fileSize;
    var offset = 0;
    var currentAggregate = aggregate;
    var currentFile = initialFile;

    while (offset < totalBytes) {
      if (!await currentFile.exists()) {
        currentAggregate = await _requireTransfer(transferId);
        currentFile = _resolveDownloadFile(currentAggregate);
        if (!await currentFile.exists()) {
          if (currentAggregate.transfer.status.isTerminal) {
            throw RelayServiceException(
              statusCode: 409,
              code:
                  currentAggregate.transfer.failureCode ??
                  'TRANSFER_INTERRUPTED',
              message:
                  currentAggregate.transfer.failureMessage ??
                  'Relay upload ended before streaming download completed',
            );
          }
          await Future<void>.delayed(
            ServerTransferTuning.relayForwardReadPollInterval,
          );
          continue;
        }
      }

      final availableBytes = await currentFile.length();
      final clampedAvailableBytes = min(availableBytes, totalBytes);
      if (clampedAvailableBytes > offset) {
        await for (final chunk in bufferByteStream(
          currentFile.openRead(offset, clampedAvailableBytes),
          ServerTransferTuning.downloadStreamBufferSize,
        )) {
          offset += chunk.length;
          yield chunk;
        }
        continue;
      }

      currentAggregate = await _requireTransfer(transferId);
      currentFile = _resolveDownloadFile(currentAggregate);
      if (currentAggregate.transfer.status.isTerminal &&
          offset < totalBytes &&
          !currentAggregate.artifact.isSealed) {
        throw RelayServiceException(
          statusCode: 409,
          code: currentAggregate.transfer.failureCode ?? 'TRANSFER_INTERRUPTED',
          message:
              currentAggregate.transfer.failureMessage ??
              'Relay upload ended before streaming download completed',
        );
      }
      await Future<void>.delayed(
        ServerTransferTuning.relayForwardReadPollInterval,
      );
    }
  }

  File _resolveDownloadFile(RelayTransferAggregate aggregate) {
    final sealedPath = aggregate.artifact.sealedPath;
    if (aggregate.artifact.isSealed &&
        sealedPath != null &&
        sealedPath.trim().isNotEmpty) {
      return File(sealedPath);
    }
    return File(aggregate.artifact.tempPath);
  }

  Stream<List<int>> _markCompletedWhenDone({
    required Stream<List<int>> source,
    required RelayTransferAggregate aggregate,
    required String transferId,
    required String receiverClientId,
  }) {
    return source.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          sink.add(chunk);
        },
        handleError: (error, stackTrace, sink) {
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          sink.close();
          unawaited(
            _markTransferCompletedInBackground(
              aggregate: aggregate,
              transferId: transferId,
              receiverClientId: receiverClientId,
            ),
          );
        },
      ),
    );
  }

  RelayTransferAggregate _buildDownloadStartedAggregate({
    required RelayTransferAggregate aggregate,
    required String receiverClientId,
    required DateTime startedAt,
  }) {
    final updatedTargets = aggregate.targets
        .map(
          (target) => target.receiverClientId == receiverClientId
              ? target.copyWith(
                  deliveryState:
                      target.deliveryState == RelayTransferTargetState.completed
                      ? RelayTransferTargetState.completed
                      : RelayTransferTargetState.downloading,
                  downloadStartedAt: target.downloadStartedAt ?? startedAt,
                  updatedAt: startedAt,
                )
              : target,
        )
        .toList(growable: false);
    return RelayTransferAggregate(
      transfer: aggregate.transfer.copyWith(
        status: aggregate.transfer.status == RelayTransferStatus.completed
            ? RelayTransferStatus.completed
            : RelayTransferStatus.downloading,
        updatedAt: startedAt,
      ),
      targets: updatedTargets,
      artifact: aggregate.artifact.copyWith(updatedAt: startedAt),
    );
  }

  RelayTransferAggregate _buildCompletedAggregate({
    required RelayTransferAggregate aggregate,
    required String receiverClientId,
    required DateTime completedAt,
  }) {
    final updatedTargets = aggregate.targets
        .map(
          (target) => target.receiverClientId == receiverClientId
              ? target.copyWith(
                  deliveryState: RelayTransferTargetState.completed,
                  downloadStartedAt: target.downloadStartedAt ?? completedAt,
                  downloadCompletedAt: completedAt,
                  updatedAt: completedAt,
                )
              : target,
        )
        .toList(growable: false);
    final isFullyCompleted = updatedTargets.every(
      (target) => target.deliveryState == RelayTransferTargetState.completed,
    );
    return RelayTransferAggregate(
      transfer: aggregate.transfer.copyWith(
        status: isFullyCompleted
            ? RelayTransferStatus.completed
            : RelayTransferStatus.downloading,
        updatedAt: completedAt,
        completedAt: isFullyCompleted ? completedAt : null,
      ),
      targets: updatedTargets,
      artifact: aggregate.artifact.copyWith(updatedAt: completedAt),
    );
  }

  Future<void> _markTransferCompletedInBackground({
    required RelayTransferAggregate aggregate,
    required String transferId,
    required String receiverClientId,
  }) async {
    final completedAt = _now();
    try {
      await _repository.markTransferCompleted(
        transferId: transferId,
        receiverClientId: receiverClientId,
        completedAt: completedAt,
      );
      final completedAggregate = _buildCompletedAggregate(
        aggregate: aggregate,
        receiverClientId: receiverClientId,
        completedAt: completedAt,
      );
      await _purgeTransferArtifactsIfFullyCompleted(transferId: transferId);
      _realtimePublisher.publishCompleted(
        completedAggregate,
        receiverClientId: receiverClientId,
      );
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  String _buildContentDisposition(String fileName) {
    final encodedFileName = Uri.encodeComponent(fileName);
    return "attachment; filename*=UTF-8''$encodedFileName";
  }

  Future<_RelayThumbnailDownload> _prepareThumbnailDownload({
    required AuthenticatedRequestContext authContext,
    required String transferId,
  }) async {
    await _ensureInitialized();
    await _cleanupExpiredTransfers();

    final aggregate = await _requireTransfer(transferId);
    _ensureCanDownload(authContext, aggregate);

    if (aggregate.artifact.cleanupState == RelayArtifactCleanupState.deleted) {
      throw const RelayServiceException(
        statusCode: 410,
        code: 'ARTIFACT_PURGED',
        message: 'Relay thumbnail has been released from NAS storage',
      );
    }

    final thumbnailFile = File(
      _storageManager.thumbnailFilePath(transferId),
    );
    if (!await thumbnailFile.exists()) {
      throw const RelayServiceException(
        statusCode: 404,
        code: 'THUMBNAIL_NOT_FOUND',
        message: 'Thumbnail not available for this transfer',
      );
    }

    final fileSize = await thumbnailFile.length();
    if (fileSize <= 0) {
      throw const RelayServiceException(
        statusCode: 404,
        code: 'THUMBNAIL_NOT_FOUND',
        message: 'Thumbnail not available for this transfer',
      );
    }

    return _RelayThumbnailDownload(
      file: thumbnailFile,
      fileSize: fileSize,
      headers: <String, String>{
        'Content-Type': await _thumbnailContentTypeFor(thumbnailFile),
        'Content-Length': '$fileSize',
      },
    );
  }

  Future<String> _thumbnailContentTypeFor(File thumbnailFile) async {
    final header = await thumbnailFile.openRead(0, 8).fold<List<int>>(
      <int>[],
      (previous, chunk) => previous.length >= 8
          ? previous
          : <int>[...previous, ...chunk].take(8).toList(growable: false),
    );
    if (header.length >= 8 &&
        header[0] == 0x89 &&
        header[1] == 0x50 &&
        header[2] == 0x4E &&
        header[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }
}

class _RelayThumbnailDownload {
  const _RelayThumbnailDownload({
    required this.file,
    required this.fileSize,
    required this.headers,
  });

  final File file;
  final int fileSize;
  final Map<String, String> headers;
}

class RelayDownloadHeaders {
  const RelayDownloadHeaders({required this.statusCode, required this.headers});

  final int statusCode;
  final Map<String, String> headers;
}

class RelayDownloadPayload {
  const RelayDownloadPayload({
    required this.statusCode,
    required this.headers,
    required this.stream,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> stream;
}

class RelayServiceException implements Exception {
  const RelayServiceException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const <String, dynamic>{},
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic> details;
  final Map<String, String> headers;

  @override
  String toString() => '$code ($statusCode): $message';
}

class _PreparedRelayDownload {
  const _PreparedRelayDownload({
    required this.file,
    required this.aggregate,
    required this.receiverClientId,
    required this.headers,
    required this.statusCode,
    required this.range,
    required this.shouldMarkCompleted,
  });

  final File file;
  final RelayTransferAggregate aggregate;
  final String? receiverClientId;
  final Map<String, String> headers;
  final int statusCode;
  final RangeResult? range;
  final bool shouldMarkCompleted;
}

class _RelayUploadProgressReporter {
  _RelayUploadProgressReporter({
    required RelayTransferRepository repository,
    required RelayRealtimePublisher realtimePublisher,
    required RelayTransferAggregate aggregate,
    required DateTime Function() clock,
  }) : _repository = repository,
       _realtimePublisher = realtimePublisher,
       _aggregate = aggregate,
       _clock = clock;

  final RelayTransferRepository _repository;
  final RelayRealtimePublisher _realtimePublisher;
  final RelayTransferAggregate _aggregate;
  final DateTime Function() _clock;

  Future<void> _flushChain = Future<void>.value();
  int _latestReceivedBytes = 0;
  DateTime? _latestUpdatedAt;
  int _lastQueuedBytes = 0;
  DateTime? _lastQueuedAt;
  int _persistedBytes = 0;
  bool _flushQueued = false;
  bool _cancelled = false;
  Object? _error;
  StackTrace? _errorStackTrace;

  void record(int receivedBytes) {
    if (_cancelled || _error != null) {
      return;
    }
    final now = _clock();
    _latestReceivedBytes = receivedBytes;
    _latestUpdatedAt = now;

    final lastQueuedAt = _lastQueuedAt;
    final shouldQueue =
        receivedBytes >= _aggregate.transfer.fileSize ||
        receivedBytes - _lastQueuedBytes >=
            ServerTransferTuning.relayUploadProgressPersistBytesThreshold ||
        (lastQueuedAt != null &&
            now.difference(lastQueuedAt) >=
                ServerTransferTuning.relayUploadProgressPersistInterval);
    if (!shouldQueue) {
      return;
    }

    _lastQueuedBytes = receivedBytes;
    _lastQueuedAt = now;
    _queueFlush();
  }

  void cancel() {
    _cancelled = true;
    _flushQueued = false;
  }

  Future<void> drain({bool ignoreErrors = false}) async {
    await _flushChain;
    if (!ignoreErrors && _error != null) {
      Error.throwWithStackTrace(_error!, _errorStackTrace!);
    }
  }

  void _queueFlush() {
    if (_flushQueued || _cancelled || _error != null) {
      return;
    }
    _flushQueued = true;
    _flushChain = _flushChain.then((_) => _flushPending());
  }

  Future<void> _flushPending() async {
    while (_flushQueued && !_cancelled) {
      _flushQueued = false;
      final updatedAt = _latestUpdatedAt;
      if (updatedAt == null || _latestReceivedBytes <= _persistedBytes) {
        continue;
      }

      final receivedBytes = _latestReceivedBytes;
      try {
        await _repository.updateUploadProgress(
          transferId: _aggregate.transfer.transferId,
          status: RelayTransferStatus.uploading,
          chunkCount: receivedBytes > 0 ? 1 : 0,
          receivedBytes: receivedBytes,
          updatedAt: updatedAt,
        );
      } catch (error, stackTrace) {
        _error ??= error;
        _errorStackTrace ??= stackTrace;
        rethrow;
      }

      _persistedBytes = receivedBytes;
      _realtimePublisher.publishUploadProgress(
        RelayTransferAggregate(
          transfer: _aggregate.transfer.copyWith(
            status: RelayTransferStatus.uploading,
            updatedAt: updatedAt,
          ),
          targets: _aggregate.targets,
          artifact: _aggregate.artifact.copyWith(
            chunkCount: receivedBytes > 0 ? 1 : 0,
            receivedBytes: receivedBytes,
            updatedAt: updatedAt,
          ),
        ),
        receivedBytes: receivedBytes,
        chunkCount: receivedBytes > 0 ? 1 : 0,
      );
    }
  }
}
