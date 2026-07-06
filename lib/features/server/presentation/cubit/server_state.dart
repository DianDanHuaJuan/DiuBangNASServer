// 文件输入：ViewStatus, ServerRunningInfoEntity, NetworkInterfaceCandidate
// 文件职责：定义服务管理页面的不可变状态
// 文件对外接口：ServerState
// 文件包含：ServerState
import '../../../../core/device/network_interface_candidate.dart';
import '../../../../core/state/view_status.dart';
import '../../domain/entities/server_running_info_entity.dart';

class ServerState {
  final ViewStatus viewStatus;
  final String? errorMessage;
  final ServerRunningInfoEntity? runningInfo;
  final ServerStatus serverStatus;
  final String deviceName;
  final String ipAddress;
  final int port;
  final DateTime? serverStartTime;
  final int onlineDeviceCount;
  final int tick;
  final List<NetworkInterfaceCandidate> pendingIpCandidates;

  const ServerState({
    this.viewStatus = ViewStatus.initial,
    this.errorMessage,
    this.runningInfo,
    this.serverStatus = ServerStatus.stopped,
    this.deviceName = 'Home-NAS-Server',
    this.ipAddress = '',
    this.port = 8080,
    this.serverStartTime,
    this.onlineDeviceCount = 0,
    this.tick = 0,
    this.pendingIpCandidates = const [],
  });

  Duration get uptime {
    if (serverStartTime == null) return Duration.zero;
    return DateTime.now().difference(serverStartTime!);
  }

  ServerState copyWith({
    ViewStatus? viewStatus,
    String? errorMessage,
    ServerRunningInfoEntity? runningInfo,
    ServerStatus? serverStatus,
    String? deviceName,
    String? ipAddress,
    int? port,
    DateTime? serverStartTime,
    bool clearServerStartTime = false,
    int? onlineDeviceCount,
    int? tick,
    List<NetworkInterfaceCandidate>? pendingIpCandidates,
    bool clearPendingIpCandidates = false,
  }) {
    return ServerState(
      viewStatus: viewStatus ?? this.viewStatus,
      errorMessage: errorMessage ?? this.errorMessage,
      runningInfo: runningInfo ?? this.runningInfo,
      serverStatus: serverStatus ?? this.serverStatus,
      deviceName: deviceName ?? this.deviceName,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      serverStartTime: clearServerStartTime
          ? null
          : (serverStartTime ?? this.serverStartTime),
      onlineDeviceCount: onlineDeviceCount ?? this.onlineDeviceCount,
      tick: tick ?? this.tick,
      pendingIpCandidates: clearPendingIpCandidates
          ? const []
          : (pendingIpCandidates ?? this.pendingIpCandidates),
    );
  }
}

enum ServerStatus {
  stopped,
  starting,
  running,
  stopping,
  error,
  awaitingIpSelection,
}
