// 文件输入：dashboard payload builder、presence repository、relay service
// 文件职责：构建 websocket hello.ack 中的初始快照
// 文件对外接口：RealtimeSnapshotBuilder
// 文件包含：RealtimeSnapshotBuilder
import '../../api/handlers/dashboard_payload_builder.dart';
import '../../relay/data/relay_service.dart';
import 'realtime_presence_repository.dart';
import 'realtime_status_publisher.dart' show EnrolledDeviceIdsProvider;

class RealtimeSnapshotBuilder {
  RealtimeSnapshotBuilder({
    required DashboardPayloadBuilder dashboardPayloadBuilder,
    required RealtimePresenceRepository presenceRepository,
    RelayService? relayService,
    EnrolledDeviceIdsProvider? enrolledDeviceIdsProvider,
  }) : _dashboardPayloadBuilder = dashboardPayloadBuilder,
       _presenceRepository = presenceRepository,
       _relayService = relayService,
       _enrolledDeviceIdsProvider = enrolledDeviceIdsProvider;

  final DashboardPayloadBuilder _dashboardPayloadBuilder;
  final RealtimePresenceRepository _presenceRepository;
  final RelayService? _relayService;
  final EnrolledDeviceIdsProvider? _enrolledDeviceIdsProvider;

  Map<String, dynamic> build() {
    return {
      'dashboard': _dashboardPayloadBuilder.build(),
      'presence': {'clients': _presenceRepository.presenceSnapshot()},
    };
  }

  Future<Map<String, dynamic>> buildForClient({String? clientId}) async {
    final snapshot = build();
    final presence = <String, dynamic>{
      ...?(snapshot['presence'] as Map<String, dynamic>?),
    };
    final enrolledIds = await _loadEnrolledDeviceIds();
    if (enrolledIds != null) {
      presence['enrolledDeviceIds'] = enrolledIds;
    }
    final withPresence = <String, dynamic>{
      ...snapshot,
      'presence': presence,
    };

    if (clientId == null || clientId.trim().isEmpty) {
      return withPresence;
    }

    final relayService = _relayService;
    if (relayService == null) {
      return withPresence;
    }

    final pending = await relayService.listPendingIncomingTransfers(
      receiverClientId: clientId,
    );
    if (pending.isEmpty) {
      return withPresence;
    }

    return {
      ...withPresence,
      'relay': {
        'pendingTransfers': pending
            .map((transfer) => transfer.toJson())
            .toList(growable: false),
      },
    };
  }

  Future<List<String>?> _loadEnrolledDeviceIds() async {
    final provider = _enrolledDeviceIdsProvider;
    if (provider == null) {
      return null;
    }
    try {
      return await provider();
    } catch (_) {
      return null;
    }
  }
}
