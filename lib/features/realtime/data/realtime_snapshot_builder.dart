// 文件输入：dashboard payload builder、presence repository、relay service
// 文件职责：构建 websocket hello.ack 中的初始快照
// 文件对外接口：RealtimeSnapshotBuilder
// 文件包含：RealtimeSnapshotBuilder
import '../../api/handlers/dashboard_payload_builder.dart';
import '../../relay/data/relay_service.dart';
import 'realtime_presence_repository.dart';

class RealtimeSnapshotBuilder {
  RealtimeSnapshotBuilder({
    required DashboardPayloadBuilder dashboardPayloadBuilder,
    required RealtimePresenceRepository presenceRepository,
    RelayService? relayService,
  }) : _dashboardPayloadBuilder = dashboardPayloadBuilder,
       _presenceRepository = presenceRepository,
       _relayService = relayService;

  final DashboardPayloadBuilder _dashboardPayloadBuilder;
  final RealtimePresenceRepository _presenceRepository;
  final RelayService? _relayService;

  Map<String, dynamic> build() {
    return {
      'dashboard': _dashboardPayloadBuilder.build(),
      'presence': {'clients': _presenceRepository.presenceSnapshot()},
    };
  }

  Future<Map<String, dynamic>> buildForClient({String? clientId}) async {
    final snapshot = build();
    if (clientId == null || clientId.trim().isEmpty) {
      return snapshot;
    }

    final relayService = _relayService;
    if (relayService == null) {
      return snapshot;
    }

    final pending = await relayService.listPendingIncomingTransfers(
      receiverClientId: clientId,
    );
    if (pending.isEmpty) {
      return snapshot;
    }

    return {
      ...snapshot,
      'relay': {
        'pendingTransfers': pending
            .map((transfer) => transfer.toJson())
            .toList(growable: false),
      },
    };
  }
}
