import '../../realtime/data/realtime_event_hub.dart';
import '../../realtime/data/realtime_presence_repository.dart';
import '../../realtime/realtime_contract.dart';
import '../domain/relay_models.dart';

class RelayRealtimePublisher {
  RelayRealtimePublisher({
    required RealtimeEventHub eventHub,
    required RealtimePresenceRepository presenceRepository,
  }) : _eventHub = eventHub,
       _presenceRepository = presenceRepository;

  final RealtimeEventHub _eventHub;
  final RealtimePresenceRepository _presenceRepository;

  bool isClientOnline(String clientId) {
    return _presenceRepository.isOnline(clientId);
  }

  void publishCreated(RelayTransferAggregate aggregate) {
    _broadcastToParticipants(
      aggregate,
      type: RealtimeMessageType.transferCreated,
      payload: const <String, dynamic>{},
    );
  }

  void publishUploadProgress(
    RelayTransferAggregate aggregate, {
    required int receivedBytes,
    required int chunkCount,
  }) {
    _broadcastToParticipants(
      aggregate,
      type: RealtimeMessageType.transferUploadProgress,
      payload: <String, dynamic>{
        'receivedBytes': receivedBytes,
        'chunkCount': chunkCount,
        'totalBytes': aggregate.transfer.fileSize,
        'totalChunks': aggregate.transfer.expectedChunkCount,
      },
    );
  }

  void publishReady(RelayTransferAggregate aggregate) {
    _broadcastToParticipants(
      aggregate,
      type: RealtimeMessageType.transferReady,
      payload: const <String, dynamic>{},
    );
  }

  void publishDownloadProgress(
    RelayTransferAggregate aggregate, {
    required String receiverClientId,
    required int receivedBytes,
  }) {
    _broadcastToParticipants(
      aggregate,
      type: RealtimeMessageType.transferDownloadProgress,
      payload: <String, dynamic>{
        'receiverClientId': receiverClientId,
        'receivedBytes': receivedBytes,
        'totalBytes': aggregate.transfer.fileSize,
      },
    );
  }

  void publishCompleted(
    RelayTransferAggregate aggregate, {
    required String receiverClientId,
  }) {
    _broadcastToParticipants(
      aggregate,
      type: RealtimeMessageType.transferCompleted,
      payload: <String, dynamic>{'receiverClientId': receiverClientId},
    );
  }

  void publishFailed(
    RelayTransferAggregate aggregate, {
    required String failureCode,
    required String failureMessage,
  }) {
    _broadcastToParticipants(
      aggregate,
      type: RealtimeMessageType.transferFailed,
      payload: <String, dynamic>{
        'failureCode': failureCode,
        'failureMessage': failureMessage,
      },
    );
  }

  void publishCancelled(RelayTransferAggregate aggregate) {
    _broadcastToParticipants(
      aggregate,
      type: RealtimeMessageType.transferCancelled,
      payload: const <String, dynamic>{},
    );
  }

  void _broadcastToParticipants(
    RelayTransferAggregate aggregate, {
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final clientIds = <String>{
      aggregate.transfer.senderClientId,
      ...aggregate.receiverClientIds,
    };
    _eventHub.broadcastToClientIds(
      clientIds,
      type: type,
      payload: <String, dynamic>{'transfer': aggregate.toJson(), ...payload},
    );
  }
}
