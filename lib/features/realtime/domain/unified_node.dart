import '../../../core/device_registry/device_models.dart';

enum NodeKind { server, client }

enum NodeRelation { self, current, saved, discovered, peer, managed }

enum PresenceStatus { offline, connecting, online }

enum NodeAdminState { active, disabled, deleted }

class UnifiedNode {
  const UnifiedNode({
    required this.nodeId,
    required this.kind,
    required this.identity,
    required this.network,
    required this.presence,
    required this.runtime,
    required this.management,
    required this.meta,
    this.relations = const <NodeRelation>{},
    this.client,
    this.server,
  });

  final String nodeId;
  final NodeKind kind;
  final Set<NodeRelation> relations;
  final NodeIdentity identity;
  final NodeNetwork network;
  final NodePresence presence;
  final NodeRuntime runtime;
  final NodeManagement management;
  final NodeMeta meta;
  final ClientFacet? client;
  final ServerFacet? server;

  UnifiedNode copyWith({
    String? nodeId,
    NodeKind? kind,
    Set<NodeRelation>? relations,
    NodeIdentity? identity,
    NodeNetwork? network,
    NodePresence? presence,
    NodeRuntime? runtime,
    NodeManagement? management,
    NodeMeta? meta,
    Object? client = _sentinel,
    Object? server = _sentinel,
  }) {
    return UnifiedNode(
      nodeId: nodeId ?? this.nodeId,
      kind: kind ?? this.kind,
      relations: relations ?? this.relations,
      identity: identity ?? this.identity,
      network: network ?? this.network,
      presence: presence ?? this.presence,
      runtime: runtime ?? this.runtime,
      management: management ?? this.management,
      meta: meta ?? this.meta,
      client: client == _sentinel ? this.client : client as ClientFacet?,
      server: server == _sentinel ? this.server : server as ServerFacet?,
    );
  }
}

class NodeIdentity {
  const NodeIdentity({
    required this.displayName,
    this.serverId,
    this.accountId,
    this.clientId,
    this.deviceId,
    this.username,
    this.label,
    this.deviceName,
    this.platform,
    this.brand,
    this.manufacturer,
    this.model,
    this.systemVersion,
    this.appVersion,
  });

  final String? serverId;
  final String? accountId;
  final String? clientId;
  final String? deviceId;
  final String displayName;
  final String? username;
  final String? label;
  final String? deviceName;
  final String? platform;
  final String? brand;
  final String? manufacturer;
  final String? model;
  final String? systemVersion;
  final String? appVersion;

  NodeIdentity copyWith({
    Object? serverId = _sentinel,
    Object? accountId = _sentinel,
    Object? clientId = _sentinel,
    Object? deviceId = _sentinel,
    String? displayName,
    Object? username = _sentinel,
    Object? label = _sentinel,
    Object? deviceName = _sentinel,
    Object? platform = _sentinel,
    Object? brand = _sentinel,
    Object? manufacturer = _sentinel,
    Object? model = _sentinel,
    Object? systemVersion = _sentinel,
    Object? appVersion = _sentinel,
  }) {
    return NodeIdentity(
      serverId: serverId == _sentinel ? this.serverId : serverId as String?,
      accountId: accountId == _sentinel ? this.accountId : accountId as String?,
      clientId: clientId == _sentinel ? this.clientId : clientId as String?,
      deviceId: deviceId == _sentinel ? this.deviceId : deviceId as String?,
      displayName: displayName ?? this.displayName,
      username: username == _sentinel ? this.username : username as String?,
      label: label == _sentinel ? this.label : label as String?,
      deviceName: deviceName == _sentinel
          ? this.deviceName
          : deviceName as String?,
      platform: platform == _sentinel ? this.platform : platform as String?,
      brand: brand == _sentinel ? this.brand : brand as String?,
      manufacturer: manufacturer == _sentinel
          ? this.manufacturer
          : manufacturer as String?,
      model: model == _sentinel ? this.model : model as String?,
      systemVersion: systemVersion == _sentinel
          ? this.systemVersion
          : systemVersion as String?,
      appVersion: appVersion == _sentinel
          ? this.appVersion
          : appVersion as String?,
    );
  }
}

class NodeNetwork {
  const NodeNetwork({
    this.connectBaseUrl,
    this.host,
    this.port,
    this.serverLanIp,
    this.reportedRouteIp,
    this.observedRemoteIp,
    this.reachable,
    this.reachableCheckedAt,
  });

  final String? connectBaseUrl;
  final String? host;
  final int? port;
  final String? serverLanIp;
  final String? reportedRouteIp;
  final String? observedRemoteIp;
  final bool? reachable;
  final DateTime? reachableCheckedAt;

  NodeNetwork copyWith({
    Object? connectBaseUrl = _sentinel,
    Object? host = _sentinel,
    Object? port = _sentinel,
    Object? serverLanIp = _sentinel,
    Object? reportedRouteIp = _sentinel,
    Object? observedRemoteIp = _sentinel,
    Object? reachable = _sentinel,
    Object? reachableCheckedAt = _sentinel,
  }) {
    return NodeNetwork(
      connectBaseUrl: connectBaseUrl == _sentinel
          ? this.connectBaseUrl
          : connectBaseUrl as String?,
      host: host == _sentinel ? this.host : host as String?,
      port: port == _sentinel ? this.port : port as int?,
      serverLanIp: serverLanIp == _sentinel
          ? this.serverLanIp
          : serverLanIp as String?,
      reportedRouteIp: reportedRouteIp == _sentinel
          ? this.reportedRouteIp
          : reportedRouteIp as String?,
      observedRemoteIp: observedRemoteIp == _sentinel
          ? this.observedRemoteIp
          : observedRemoteIp as String?,
      reachable: reachable == _sentinel ? this.reachable : reachable as bool?,
      reachableCheckedAt: reachableCheckedAt == _sentinel
          ? this.reachableCheckedAt
          : reachableCheckedAt as DateTime?,
    );
  }
}

class NodePresence {
  const NodePresence({
    this.status = PresenceStatus.offline,
    this.connectionId,
    this.sessionId,
    this.connectedAt,
    this.lastHeartbeatAt,
    this.lastSeenAt,
  });

  final PresenceStatus status;
  final String? connectionId;
  final String? sessionId;
  final DateTime? connectedAt;
  final DateTime? lastHeartbeatAt;
  final DateTime? lastSeenAt;

  NodePresence copyWith({
    PresenceStatus? status,
    Object? connectionId = _sentinel,
    Object? sessionId = _sentinel,
    Object? connectedAt = _sentinel,
    Object? lastHeartbeatAt = _sentinel,
    Object? lastSeenAt = _sentinel,
  }) {
    return NodePresence(
      status: status ?? this.status,
      connectionId: connectionId == _sentinel
          ? this.connectionId
          : connectionId as String?,
      sessionId: sessionId == _sentinel ? this.sessionId : sessionId as String?,
      connectedAt: connectedAt == _sentinel
          ? this.connectedAt
          : connectedAt as DateTime?,
      lastHeartbeatAt: lastHeartbeatAt == _sentinel
          ? this.lastHeartbeatAt
          : lastHeartbeatAt as DateTime?,
      lastSeenAt: lastSeenAt == _sentinel
          ? this.lastSeenAt
          : lastSeenAt as DateTime?,
    );
  }
}

class NodeRuntime {
  const NodeRuntime({
    this.status,
    this.uptimeSeconds,
    this.batteryLevel,
    this.batteryPercent,
    this.isCharging,
    this.storageTotal,
    this.storageUsed,
    this.storageAvailable,
  });

  final String? status;
  final int? uptimeSeconds;
  final int? batteryLevel;
  final double? batteryPercent;
  final bool? isCharging;
  final int? storageTotal;
  final int? storageUsed;
  final int? storageAvailable;
}

class NodeManagement {
  const NodeManagement({
    this.adminState = NodeAdminState.active,
    this.allowedActions = const <String>{},
  });

  final NodeAdminState adminState;
  final Set<String> allowedActions;

  NodeManagement copyWith({
    NodeAdminState? adminState,
    Set<String>? allowedActions,
  }) {
    return NodeManagement(
      adminState: adminState ?? this.adminState,
      allowedActions: allowedActions ?? this.allowedActions,
    );
  }
}

class NodeMeta {
  const NodeMeta({
    required this.updatedAt,
    this.updatedFrom = const <String>{},
    this.revision = 0,
  });

  final Set<String> updatedFrom;
  final DateTime updatedAt;
  final int revision;
}

class ClientFacet {
  const ClientFacet({
    required this.deviceStatus,
    required this.role,
    this.credentialVersion,
    this.boundDeviceId,
    this.boundDeviceName,
    this.boundAt,
    this.createdAt,
    this.lastUsedAt,
    this.lastBoundAt,
  });

  final DeviceStatus deviceStatus;
  final String role;
  final String? credentialVersion;
  final String? boundDeviceId;
  final String? boundDeviceName;
  final DateTime? boundAt;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? lastBoundAt;

  ClientFacet copyWith({
    DeviceStatus? deviceStatus,
    String? role,
    Object? credentialVersion = _sentinel,
    Object? boundDeviceId = _sentinel,
    Object? boundDeviceName = _sentinel,
    Object? boundAt = _sentinel,
    Object? createdAt = _sentinel,
    Object? lastUsedAt = _sentinel,
    Object? lastBoundAt = _sentinel,
  }) {
    return ClientFacet(
      deviceStatus: deviceStatus ?? this.deviceStatus,
      role: role ?? this.role,
      credentialVersion: credentialVersion == _sentinel
          ? this.credentialVersion
          : credentialVersion as String?,
      boundDeviceId: boundDeviceId == _sentinel
          ? this.boundDeviceId
          : boundDeviceId as String?,
      boundDeviceName: boundDeviceName == _sentinel
          ? this.boundDeviceName
          : boundDeviceName as String?,
      boundAt: boundAt == _sentinel ? this.boundAt : boundAt as DateTime?,
      createdAt: createdAt == _sentinel
          ? this.createdAt
          : createdAt as DateTime?,
      lastUsedAt: lastUsedAt == _sentinel
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
      lastBoundAt: lastBoundAt == _sentinel
          ? this.lastBoundAt
          : lastBoundAt as DateTime?,
    );
  }
}

class ServerFacet {
  const ServerFacet({
    this.serverVersion,
    this.protocol,
    this.capabilities,
    this.roots = const <Map<String, dynamic>>[],
    this.webdavConfig,
    this.smbConfig,
    this.certificateSha256,
    this.isTrusted = false,
    this.trustedHosts = const <String>[],
  });

  final String? serverVersion;
  final String? protocol;
  final Map<String, dynamic>? capabilities;
  final List<Map<String, dynamic>> roots;
  final Map<String, dynamic>? webdavConfig;
  final Map<String, dynamic>? smbConfig;
  final String? certificateSha256;
  final bool isTrusted;
  final List<String> trustedHosts;
}

const Object _sentinel = Object();
