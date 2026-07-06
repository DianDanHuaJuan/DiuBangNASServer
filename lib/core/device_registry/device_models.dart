enum DeviceStatus { active, disabled, revoked }

class StoredDeviceRecord {
  const StoredDeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.status,
    required this.credentialVersion,
    required this.firstPairedAt,
    required this.createdAt,
    required this.updatedAt,
    this.physicalDeviceId,
    this.platform,
    this.brand,
    this.model,
    this.label,
    this.lastSeenAt,
  });

  final String deviceId;
  final String? physicalDeviceId;
  final String deviceName;
  final String? platform;
  final String? brand;
  final String? model;
  final String? label;
  final DeviceStatus status;
  final String credentialVersion;
  final DateTime firstPairedAt;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  StoredDeviceRecord copyWith({
    String? deviceId,
    String? physicalDeviceId,
    String? deviceName,
    String? platform,
    String? brand,
    String? model,
    String? label,
    DeviceStatus? status,
    String? credentialVersion,
    DateTime? firstPairedAt,
    Object? lastSeenAt = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StoredDeviceRecord(
      deviceId: deviceId ?? this.deviceId,
      physicalDeviceId: physicalDeviceId ?? this.physicalDeviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      label: label ?? this.label,
      status: status ?? this.status,
      credentialVersion: credentialVersion ?? this.credentialVersion,
      firstPairedAt: firstPairedAt ?? this.firstPairedAt,
      lastSeenAt: lastSeenAt == _sentinel
          ? this.lastSeenAt
          : lastSeenAt as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DeviceSummary {
  const DeviceSummary({
    required this.deviceId,
    required this.deviceName,
    required this.status,
    required this.credentialVersion,
    required this.firstPairedAt,
    required this.createdAt,
    this.platform,
    this.brand,
    this.model,
    this.label,
    this.lastSeenAt,
  });

  final String deviceId;
  final String deviceName;
  final String? platform;
  final String? brand;
  final String? model;
  final String? label;
  final DeviceStatus status;
  final String credentialVersion;
  final DateTime firstPairedAt;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
}

class DeviceRefreshTokenRecord {
  const DeviceRefreshTokenRecord({
    required this.tokenId,
    required this.deviceId,
    required this.tokenHash,
    required this.issuedAt,
    required this.expiresAt,
    this.revokedAt,
  });

  final String tokenId;
  final String deviceId;
  final String tokenHash;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
}

class DeviceAuditLogRecord {
  const DeviceAuditLogRecord({
    required this.logId,
    required this.eventType,
    required this.details,
    required this.createdAt,
    this.deviceId,
    this.operatorOwnerId,
  });

  final String logId;
  final String? deviceId;
  final String? operatorOwnerId;
  final String eventType;
  final Map<String, dynamic> details;
  final DateTime createdAt;
}

class EnrolledDeviceTokens {
  const EnrolledDeviceTokens({
    required this.device,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.sessionId,
  });

  final StoredDeviceRecord device;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final String sessionId;
}

class DeviceEnrollResult {
  const DeviceEnrollResult._({
    this.tokens,
    this.failureCode,
    this.failureMessage,
  });

  const DeviceEnrollResult.success(EnrolledDeviceTokens tokens)
    : this._(tokens: tokens);

  const DeviceEnrollResult.failure({
    required String code,
    required String message,
  }) : this._(failureCode: code, failureMessage: message);

  final EnrolledDeviceTokens? tokens;
  final String? failureCode;
  final String? failureMessage;

  bool get isSuccess => tokens != null;
}

class RefreshedDeviceTokens {
  const RefreshedDeviceTokens({
    required this.deviceId,
    required this.accessToken,
    required this.accessExpiresAt,
    required this.sessionId,
  });

  final String deviceId;
  final String accessToken;
  final DateTime accessExpiresAt;
  final String sessionId;
}

class DeviceTokenRefreshResult {
  const DeviceTokenRefreshResult._({
    this.tokens,
    this.failureCode,
    this.failureMessage,
  });

  const DeviceTokenRefreshResult.success(RefreshedDeviceTokens tokens)
    : this._(tokens: tokens);

  const DeviceTokenRefreshResult.failure({
    required String code,
    required String message,
  }) : this._(failureCode: code, failureMessage: message);

  final RefreshedDeviceTokens? tokens;
  final String? failureCode;
  final String? failureMessage;

  bool get isSuccess => tokens != null;
}

class DeviceTokenClaims {
  const DeviceTokenClaims({
    required this.deviceId,
    required this.deviceName,
    required this.credentialVersion,
    required this.sessionId,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String deviceId;
  final String deviceName;
  final String credentialVersion;
  final String sessionId;
  final DateTime issuedAt;
  final DateTime expiresAt;
}

const Object _sentinel = Object();
