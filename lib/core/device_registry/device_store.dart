import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../auth/secure_key_value_store.dart';
import 'device_models.dart';
import 'device_repository.dart';
import 'device_token_service.dart';
import 'sqlite_device_repository.dart';

typedef DeviceStoreListener = void Function(StoredDeviceRecord device);
typedef DeviceStoreDeletionListener = void Function(String deviceId);

class DeviceStore {
  DeviceStore({
    DeviceRepository? deviceRepository,
    DeviceTokenService? deviceTokenService,
    SecureKeyValueStore? storage,
    Future<String> Function()? databasePathProvider,
    List<DeviceStoreListener>? listeners,
    List<DeviceStoreDeletionListener>? deletionListeners,
    Random? random,
  }) : _providedDeviceRepository = deviceRepository,
       _providedDeviceTokenService = deviceTokenService,
       _storage = storage ?? FlutterSecureKeyValueStore(),
       _databasePathProvider = databasePathProvider,
       _listeners = listeners ?? <DeviceStoreListener>[],
       _deletionListeners =
           deletionListeners ?? <DeviceStoreDeletionListener>[],
       _random = random ?? Random.secure();

  final DeviceRepository? _providedDeviceRepository;
  final DeviceTokenService? _providedDeviceTokenService;
  final SecureKeyValueStore _storage;
  final Future<String> Function()? _databasePathProvider;
  final List<DeviceStoreListener> _listeners;
  final List<DeviceStoreDeletionListener> _deletionListeners;
  final Random _random;

  static const String _databasePathKey = 'device_registry_database_path_v1';
  static const String _tokenSigningKeyKey = 'device_token_signing_key_v1';
  static const String _databaseFileName = 'nas_devices.db';
  static final RegExp _whitespace = RegExp(r'\s+');

  DeviceRepository? _deviceRepository;
  DeviceTokenService? _deviceTokenService;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  Future<void> initialize() {
    if (_isInitialized) {
      return Future<void>.value();
    }

    final initializationFuture = _initializationFuture;
    if (initializationFuture != null) {
      return initializationFuture;
    }

    final future = _initializeInternal();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initializeInternal() async {
    DeviceRepository? repository;
    var createdRepository = false;
    try {
      repository = _providedDeviceRepository;
      if (repository == null) {
        repository = await _openRepository();
        createdRepository = true;
      }
      await repository.initialize();
      final tokenService =
          _providedDeviceTokenService ??
          DeviceTokenService(signingKey: await _loadOrCreateSigningKey());
      _deviceRepository = repository;
      _deviceTokenService = tokenService;
      _isInitialized = true;
    } catch (_) {
      if (createdRepository) {
        await repository?.close();
      }
      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<DeviceEnrollResult> enrollDevice({
    required String deviceId,
    required String deviceName,
    String? physicalDeviceId,
    String? platform,
    String? brand,
    String? model,
    String? label,
  }) async {
    final repository = await _requireRepository();
    final tokenService = await _requireTokenService();
    final normalizedDeviceId = _normalizeDeviceId(deviceId);
    final normalizedDeviceName = _normalizeDeviceName(deviceName);
    final normalizedPhysicalId = _normalizeDeviceId(
      physicalDeviceId ?? deviceId,
    );
    if (normalizedDeviceId == null ||
        normalizedDeviceName == null ||
        normalizedPhysicalId == null) {
      return const DeviceEnrollResult.failure(
        code: 'DEVICE_ID_REQUIRED',
        message: 'Device id and device name are required',
      );
    }

    // 优先按 physicalDeviceId 查找已有设备
    StoredDeviceRecord? existing = await repository.findDeviceByPhysicalId(
      normalizedPhysicalId,
    );
    if (existing != null && existing.deviceId != normalizedDeviceId) {
      // 同一物理设备但 deviceId 变了，复用旧记录并更新 deviceId
      existing = existing.copyWith(deviceId: normalizedDeviceId);
    }
    // 如果按 physicalDeviceId 没找到，再按 deviceId 查找
    existing ??= await repository.findDeviceById(normalizedDeviceId);

    if (existing != null) {
      switch (existing.status) {
        case DeviceStatus.disabled:
          return const DeviceEnrollResult.failure(
            code: 'DEVICE_DISABLED',
            message: 'This device has been disabled by the server owner',
          );
        case DeviceStatus.revoked:
          return const DeviceEnrollResult.failure(
            code: 'DEVICE_REVOKED',
            message:
                'This device has been revoked. Delete it before re-enrolling',
          );
        case DeviceStatus.active:
          break;
      }
    }

    final now = DateTime.now().toUtc();
    final nextCredentialVersion = _nextCredentialVersion();
    final device = existing == null
        ? StoredDeviceRecord(
            deviceId: normalizedDeviceId,
            physicalDeviceId: normalizedPhysicalId,
            deviceName: normalizedDeviceName,
            status: DeviceStatus.active,
            credentialVersion: nextCredentialVersion,
            firstPairedAt: now,
            createdAt: now,
            updatedAt: now,
            lastSeenAt: now,
          )
        : existing.copyWith(
            deviceName: normalizedDeviceName,
            physicalDeviceId: normalizedPhysicalId,
            platform: _normalizeOptional(platform) ?? existing.platform,
            brand: _normalizeOptional(brand) ?? existing.brand,
            model: _normalizeOptional(model) ?? existing.model,
            label: label?.trim().isNotEmpty == true
                ? label!.trim()
                : existing.label,
            credentialVersion: nextCredentialVersion,
            updatedAt: now,
            lastSeenAt: now,
          );

    if (existing == null) {
      await repository.createDevice(
        device,
        auditLog: _buildAuditLog(
          deviceId: device.deviceId,
          eventType: 'device.enrolled',
          details: <String, dynamic>{
            'deviceName': device.deviceName,
            'platform': device.platform,
            'physicalDeviceId': device.physicalDeviceId,
          },
        ),
      );
    } else {
      await repository.saveDevice(
        device,
        auditLog: _buildAuditLog(
          deviceId: device.deviceId,
          eventType: 'device.re_enrolled',
          details: <String, dynamic>{
            'deviceName': device.deviceName,
            'physicalDeviceId': device.physicalDeviceId,
          },
        ),
      );
    }

    await repository.revokeRefreshTokensForDevice(device.deviceId);

    final access = await tokenService.issueAccessToken(device: device);
    final refresh = await tokenService.issueRefreshToken(
      deviceId: device.deviceId,
    );
    await repository.saveRefreshToken(
      DeviceRefreshTokenRecord(
        tokenId: refresh.tokenId,
        deviceId: device.deviceId,
        tokenHash: refresh.hash,
        issuedAt: DateTime.now().toUtc(),
        expiresAt: refresh.expiresAt,
      ),
    );

    final enrolled = EnrolledDeviceTokens(
      device: device,
      accessToken: access.token,
      refreshToken: refresh.token,
      accessExpiresAt: access.expiresAt,
      refreshExpiresAt: refresh.expiresAt,
      sessionId: access.sessionId,
    );
    _notifyListeners(device);
    return DeviceEnrollResult.success(enrolled);
  }

  Future<DeviceTokenRefreshResult> refreshAccessToken(
    String refreshToken,
  ) async {
    final repository = await _requireRepository();
    final tokenService = await _requireTokenService();
    final normalized = refreshToken.trim();
    if (normalized.isEmpty) {
      return const DeviceTokenRefreshResult.failure(
        code: 'AUTH_INVALID',
        message: 'Refresh token is required',
      );
    }

    final tokenHash = await tokenService.hashRefreshToken(normalized);
    final stored = await repository.findRefreshTokenByHash(tokenHash);
    if (stored == null ||
        stored.revokedAt != null ||
        !stored.expiresAt.isAfter(DateTime.now().toUtc())) {
      return const DeviceTokenRefreshResult.failure(
        code: 'AUTH_INVALID',
        message: 'Invalid or expired refresh token',
      );
    }

    final device = await repository.findDeviceById(stored.deviceId);
    if (device == null || device.status != DeviceStatus.active) {
      return const DeviceTokenRefreshResult.failure(
        code: 'AUTH_REVOKED',
        message: 'Device is no longer active',
      );
    }

    if (!await isDeviceCredentialVersionValid(
      deviceId: device.deviceId,
      credentialVersion: device.credentialVersion,
    )) {
      return const DeviceTokenRefreshResult.failure(
        code: 'AUTH_REVOKED',
        message: 'Device credential has been revoked',
      );
    }

    final access = await tokenService.issueAccessToken(device: device);
    return DeviceTokenRefreshResult.success(
      RefreshedDeviceTokens(
        deviceId: device.deviceId,
        accessToken: access.token,
        accessExpiresAt: access.expiresAt,
        sessionId: access.sessionId,
      ),
    );
  }

  Future<List<DeviceSummary>> listDevices() async {
    final repository = await _requireRepository();
    final devices = await repository.listDevices();
    return devices.map(_toSummary).toList(growable: false);
  }

  Future<StoredDeviceRecord?> findDeviceById(String deviceId) async {
    final normalized = _normalizeDeviceId(deviceId);
    if (normalized == null) {
      return null;
    }
    return (await _requireRepository()).findDeviceById(normalized);
  }

  Future<StoredDeviceRecord?> findDeviceByPhysicalId(
    String physicalDeviceId,
  ) async {
    final normalized = physicalDeviceId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return (await _requireRepository()).findDeviceByPhysicalId(normalized);
  }

  Future<StoredDeviceRecord> updateDeviceLabel({
    required String deviceId,
    required String label,
  }) async {
    final repository = await _requireRepository();
    final device = await _requireDevice(deviceId);
    final updated = device.copyWith(
      label: label.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.saveDevice(updated);
    _notifyListeners(updated);
    return updated;
  }

  Future<StoredDeviceRecord> updateDeviceStatus({
    required String deviceId,
    required DeviceStatus status,
  }) async {
    final repository = await _requireRepository();
    final device = await _requireDevice(deviceId);
    if (device.status == status) {
      return device;
    }
    if (device.status == DeviceStatus.revoked &&
        status != DeviceStatus.revoked) {
      throw StateError('Revoked devices cannot be re-enabled');
    }

    final updated = device.copyWith(
      status: status,
      credentialVersion: _nextCredentialVersion(),
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.saveDevice(
      updated,
      auditLog: _buildAuditLog(
        deviceId: updated.deviceId,
        eventType: 'device.status.updated',
        details: <String, dynamic>{'status': status.name},
      ),
    );
    await repository.revokeRefreshTokensForDevice(updated.deviceId);
    _notifyListeners(updated);
    return updated;
  }

  Future<StoredDeviceRecord> rotateDeviceCredential(String deviceId) async {
    final repository = await _requireRepository();
    final device = await _requireDevice(deviceId);
    final updated = device.copyWith(
      credentialVersion: _nextCredentialVersion(),
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.saveDevice(
      updated,
      auditLog: _buildAuditLog(
        deviceId: updated.deviceId,
        eventType: 'device.credential.rotated',
        details: const <String, dynamic>{},
      ),
    );
    await repository.revokeRefreshTokensForDevice(updated.deviceId);
    _notifyListeners(updated);
    return updated;
  }

  Future<void> deleteDevice(String deviceId) async {
    final repository = await _requireRepository();
    final device = await _requireDevice(deviceId);
    await repository.deleteDevice(
      device.deviceId,
      auditLog: _buildAuditLog(
        deviceId: device.deviceId,
        eventType: 'device.deleted',
        details: const <String, dynamic>{},
      ),
    );
    _notifyDeletionListeners(device.deviceId);
  }

  Future<void> touchDeviceSeen(
    String deviceId, {
    String? deviceName,
    String? platform,
    String? brand,
    String? model,
  }) async {
    final repository = await _requireRepository();
    final normalized = _normalizeDeviceId(deviceId);
    if (normalized == null) {
      return;
    }
    final device = await repository.findDeviceById(normalized);
    if (device == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final nextDeviceName =
        _normalizeDeviceName(deviceName) ?? device.deviceName;
    final nextPlatform = _normalizeOptional(platform) ?? device.platform;
    final nextBrand = _normalizeOptional(brand) ?? device.brand;
    final nextModel = _normalizeOptional(model) ?? device.model;
    final metadataChanged =
        nextDeviceName != device.deviceName ||
        nextPlatform != device.platform ||
        nextBrand != device.brand ||
        nextModel != device.model;
    final updated = device.copyWith(
      deviceName: nextDeviceName,
      platform: nextPlatform,
      brand: nextBrand,
      model: nextModel,
      lastSeenAt: now,
      updatedAt: metadataChanged ? now : device.updatedAt,
    );
    await repository.saveDevice(updated);
    if (metadataChanged) {
      _notifyListeners(updated);
    }
  }

  Future<bool> isDeviceCredentialVersionValid({
    required String deviceId,
    required String credentialVersion,
  }) async {
    final device = await findDeviceById(deviceId);
    if (device == null) {
      return false;
    }
    if (device.status != DeviceStatus.active) {
      return false;
    }
    return device.credentialVersion == credentialVersion;
  }

  Future<DeviceTokenService> requireTokenService() => _requireTokenService();

  Future<DeviceTokenClaims?> verifyAccessToken(String accessToken) {
    return _requireTokenService().then(
      (service) => service.verifyAccessToken(accessToken),
    );
  }

  void addListener(DeviceStoreListener listener) {
    _listeners.add(listener);
  }

  void removeListener(DeviceStoreListener listener) {
    _listeners.remove(listener);
  }

  void addDeletionListener(DeviceStoreDeletionListener listener) {
    _deletionListeners.add(listener);
  }

  void removeDeletionListener(DeviceStoreDeletionListener listener) {
    _deletionListeners.remove(listener);
  }

  Future<void> dispose() async {
    await _deviceRepository?.close();
    _deviceRepository = null;
    _deviceTokenService = null;
    _isInitialized = false;
    _initializationFuture = null;
  }

  Future<DeviceRepository> _requireRepository() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _deviceRepository!;
  }

  Future<DeviceTokenService> _requireTokenService() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _deviceTokenService!;
  }

  Future<StoredDeviceRecord> _requireDevice(String deviceId) async {
    final device = await findDeviceById(deviceId);
    if (device == null) {
      throw StateError('Device $deviceId was not found');
    }
    return device;
  }

  Future<DeviceRepository> _openRepository() async {
    final databasePath = await _resolveDatabasePath();
    return SqliteDeviceRepository(databasePath: databasePath);
  }

  Future<String> _resolveDatabasePath() async {
    if (_databasePathProvider != null) {
      return _databasePathProvider();
    }

    final storedPath = await _storage.read(key: _databasePathKey);
    if (storedPath != null && storedPath.isNotEmpty) {
      return storedPath;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final databasePath = path.join(supportDirectory.path, _databaseFileName);
    await _storage.write(key: _databasePathKey, value: databasePath);
    return databasePath;
  }

  Future<List<int>> _loadOrCreateSigningKey() async {
    final encoded = await _storage.read(key: _tokenSigningKeyKey);
    if (encoded != null && encoded.isNotEmpty) {
      return base64Url.decode(base64Url.normalize(encoded));
    }

    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    await _storage.write(
      key: _tokenSigningKeyKey,
      value: base64UrlEncode(bytes),
    );
    return bytes;
  }

  DeviceSummary _toSummary(StoredDeviceRecord device) {
    return DeviceSummary(
      deviceId: device.deviceId,
      deviceName: device.deviceName,
      platform: device.platform,
      brand: device.brand,
      model: device.model,
      label: device.label,
      status: device.status,
      credentialVersion: device.credentialVersion,
      firstPairedAt: device.firstPairedAt,
      lastSeenAt: device.lastSeenAt,
      createdAt: device.createdAt,
    );
  }

  DeviceAuditLogRecord _buildAuditLog({
    required String deviceId,
    required String eventType,
    required Map<String, dynamic> details,
  }) {
    final now = DateTime.now().toUtc();
    return DeviceAuditLogRecord(
      logId:
          'log_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}',
      deviceId: deviceId,
      eventType: eventType,
      details: details,
      createdAt: now,
    );
  }

  String _nextCredentialVersion() {
    return 'cv_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }

  String? _normalizeDeviceId(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim().replaceAll(_whitespace, '-');
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeDeviceName(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String? _normalizeOptional(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  void _notifyListeners(StoredDeviceRecord device) {
    for (final listener in List<DeviceStoreListener>.from(_listeners)) {
      listener(device);
    }
  }

  void _notifyDeletionListeners(String deviceId) {
    for (final listener in List<DeviceStoreDeletionListener>.from(
      _deletionListeners,
    )) {
      listener(deviceId);
    }
  }
}
