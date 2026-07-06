// 文件输入：统一节点注册表
// 文件职责：从统一节点真源派生 presence/management/peer 快照
// 文件对外接口：RealtimePresenceRepository
// 文件包含：RealtimePresenceRepository
import '../../../core/device_registry/device_models.dart';
import 'unified_node_registry.dart';
import 'realtime_connection_registry.dart';

class RealtimePresenceRepository {
  RealtimePresenceRepository({UnifiedNodeRegistry? nodeRegistry})
    : _nodeRegistry = nodeRegistry ?? UnifiedNodeRegistry();

  final UnifiedNodeRegistry _nodeRegistry;

  void seedDevices(Iterable<StoredDeviceRecord> devices) {
    _nodeRegistry.seedDevices(devices);
  }

  void upsertDevice(StoredDeviceRecord device) {
    _nodeRegistry.upsertDevice(device);
  }

  void markOnline(RealtimeConnection connection) {
    _nodeRegistry.markClientOnline(connection);
  }

  void touch(RealtimeConnection connection) {
    _nodeRegistry.touchClient(connection);
  }

  void markOffline({required String clientId, required String connectionId}) {
    _nodeRegistry.markClientOffline(
      clientId: clientId,
      connectionId: connectionId,
    );
  }

  void removeDevice(String deviceId) {
    _nodeRegistry.removeDevice(deviceId);
  }

  List<Map<String, dynamic>> presenceSnapshot() {
    return _nodeRegistry.presenceSnapshot();
  }

  List<Map<String, dynamic>> snapshot() {
    return presenceSnapshot();
  }

  List<Map<String, dynamic>> managementSnapshot() {
    return _nodeRegistry.managementSnapshot();
  }

  List<Map<String, dynamic>> peerSnapshot() {
    return _nodeRegistry.peerSnapshot();
  }

  bool isOnline(String clientId) {
    return _nodeRegistry.isOnline(clientId);
  }

  void clear() {
    _nodeRegistry.clear();
  }
}
