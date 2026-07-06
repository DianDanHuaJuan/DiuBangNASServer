class RuntimePresenceSnapshot {
  const RuntimePresenceSnapshot({
    required this.onlineDeviceIds,
    required this.connectedCount,
    required this.updatedAt,
  });

  factory RuntimePresenceSnapshot.empty() {
    return RuntimePresenceSnapshot(
      onlineDeviceIds: const <String>{},
      connectedCount: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  factory RuntimePresenceSnapshot.fromJson(Map<String, dynamic> json) {
    final rawIds = json['onlineDeviceIds'];
    final ids = rawIds is List
        ? rawIds
              .map((value) => value?.toString().trim() ?? '')
              .where((value) => value.isNotEmpty)
              .toSet()
        : const <String>{};
    final updatedAtRaw = json['updatedAt'] as String?;
    return RuntimePresenceSnapshot(
      onlineDeviceIds: ids,
      connectedCount: (json['connectedCount'] as num?)?.toInt() ?? ids.length,
      updatedAt: updatedAtRaw == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.parse(updatedAtRaw).toUtc(),
    );
  }

  final Set<String> onlineDeviceIds;
  final int connectedCount;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() {
    final sortedIds = onlineDeviceIds.toList(growable: false)..sort();
    return {
      'onlineDeviceIds': sortedIds,
      'connectedCount': connectedCount,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  bool isOnline(String deviceId) {
    final normalized = deviceId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return onlineDeviceIds.contains(normalized);
  }
}
