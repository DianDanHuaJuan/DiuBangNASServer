import '../domain/relay_models.dart';

abstract class RelayTransferRepository {
  Future<void> initialize();

  Future<void> close();

  Future<void> createTransfer(RelayTransferAggregate aggregate);

  Future<RelayTransferAggregate?> findTransferById(String transferId);

  Future<List<RelayTransferAggregate>> listTransfers({
    String? participantClientId,
    int limit = 100,
  });

  Future<List<RelayTransferAggregate>> listPeerTransfers({
    required String selfClientId,
    required String peerClientId,
    required int limit,
    DateTime? beforeCreatedAt,
  });

  Future<int> sumRetainedBytes();

  Future<void> updateUploadProgress({
    required String transferId,
    required RelayTransferStatus status,
    required int chunkCount,
    required int receivedBytes,
    required DateTime updatedAt,
  });

  Future<void> markTransferReady({
    required String transferId,
    required String sealedPath,
    required int chunkCount,
    required int receivedBytes,
    required DateTime readyAt,
  });

  Future<void> markTransferDownloadStarted({
    required String transferId,
    required String receiverClientId,
    required DateTime startedAt,
  });

  Future<void> markTransferCompleted({
    required String transferId,
    required String receiverClientId,
    required DateTime completedAt,
  });

  Future<void> markTransferCancelled({
    required String transferId,
    required DateTime cancelledAt,
  });

  Future<void> markTransferFailed({
    required String transferId,
    required DateTime failedAt,
    required String failureCode,
    required String failureMessage,
  });

  Future<void> markTransferExpired({
    required String transferId,
    required DateTime expiredAt,
  });

  Future<void> markTransferInterrupted({
    required String transferId,
    required DateTime interruptedAt,
  });

  Future<List<RelayTransferAggregate>> listTransfersForStartupRecovery();

  Future<List<RelayTransferAggregate>> listExpiredTransfers(DateTime now);

  Future<void> saveThumbnailPath({
    required String transferId,
    required String thumbnailPath,
    required DateTime updatedAt,
  });

  Future<void> markArtifactDeleted({
    required String transferId,
    required DateTime deletedAt,
  });
}
