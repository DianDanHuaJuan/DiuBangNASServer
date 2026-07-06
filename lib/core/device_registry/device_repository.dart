import 'device_models.dart';

abstract class DeviceRepository {
  Future<void> initialize();

  Future<void> close();

  Future<StoredDeviceRecord?> findDeviceById(String deviceId);

  Future<StoredDeviceRecord?> findDeviceByPhysicalId(String physicalDeviceId);

  Future<List<StoredDeviceRecord>> listDevices();

  Future<void> createDevice(
    StoredDeviceRecord device, {
    DeviceAuditLogRecord? auditLog,
  });

  Future<void> saveDevice(
    StoredDeviceRecord device, {
    DeviceAuditLogRecord? auditLog,
  });

  Future<void> deleteDevice(
    String deviceId, {
    DeviceAuditLogRecord? auditLog,
  });

  Future<void> saveRefreshToken(DeviceRefreshTokenRecord token);

  Future<DeviceRefreshTokenRecord?> findRefreshTokenByHash(String tokenHash);

  Future<void> revokeRefreshTokensForDevice(String deviceId);

  Future<void> deleteRefreshToken(String tokenId);
}
