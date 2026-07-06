import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../storage/platform_sqlite.dart';

import 'device_models.dart';
import 'device_repository.dart';

class SqliteDeviceRepository implements DeviceRepository {
  SqliteDeviceRepository({
    required String databasePath,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _databasePath = databasePath,
       _databaseFactory = databaseFactory ?? _resolveDatabaseFactory();

  final String _databasePath;
  final sqflite.DatabaseFactory _databaseFactory;

  sqflite.Database? _database;

  static sqflite.DatabaseFactory _resolveDatabaseFactory() {
    return PlatformSqlite.resolveDatabaseFactory();
  }

  @override
  Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    _database = await _databaseFactory.openDatabase(
      _databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, _) async {
          await _createSchema(database);
        },
      ),
    );
  }

  Future<void> _createSchema(sqflite.Database database) async {
    await database.execute('''
CREATE TABLE devices (
  device_id TEXT PRIMARY KEY,
  physical_device_id TEXT,
  device_name TEXT NOT NULL,
  device_platform TEXT,
  device_brand TEXT,
  device_model TEXT,
  label TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  credential_version TEXT NOT NULL,
  first_paired_at TEXT NOT NULL,
  last_seen_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
    await database.execute('''
CREATE TABLE device_refresh_tokens (
  token_id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  issued_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  FOREIGN KEY(device_id) REFERENCES devices(device_id) ON DELETE CASCADE
)
''');
    await database.execute('''
CREATE TABLE device_audit_logs (
  log_id TEXT PRIMARY KEY,
  device_id TEXT,
  operator_owner_id TEXT,
  event_type TEXT NOT NULL,
  details_json TEXT NOT NULL,
  created_at TEXT NOT NULL
)
''');
    await database.execute('CREATE INDEX idx_devices_status ON devices(status)');
    await database.execute(
      'CREATE INDEX idx_devices_physical ON devices(physical_device_id)',
    );
    await database.execute(
      'CREATE INDEX idx_refresh_tokens_device ON device_refresh_tokens(device_id)',
    );
  }

  @override
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  @override
  Future<StoredDeviceRecord?> findDeviceById(String deviceId) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      'devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapDeviceRow(rows.first);
  }

  @override
  Future<StoredDeviceRecord?> findDeviceByPhysicalId(String physicalDeviceId) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      'devices',
      where: 'physical_device_id = ?',
      whereArgs: [physicalDeviceId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapDeviceRow(rows.first);
  }

  @override
  Future<List<StoredDeviceRecord>> listDevices() async {
    final database = await _requireDatabase();
    final rows = await database.query(
      'devices',
      orderBy: 'created_at DESC',
    );
    return rows.map(_mapDeviceRow).toList(growable: false);
  }

  @override
  Future<void> createDevice(
    StoredDeviceRecord device, {
    DeviceAuditLogRecord? auditLog,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await txn.insert('devices', _deviceToMap(device));
      if (auditLog != null) {
        await txn.insert('device_audit_logs', _auditToMap(auditLog));
      }
    });
  }

  @override
  Future<void> saveDevice(
    StoredDeviceRecord device, {
    DeviceAuditLogRecord? auditLog,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await txn.update(
        'devices',
        _deviceToMap(device),
        where: 'device_id = ?',
        whereArgs: [device.deviceId],
      );
      if (auditLog != null) {
        await txn.insert('device_audit_logs', _auditToMap(auditLog));
      }
    });
  }

  @override
  Future<void> deleteDevice(
    String deviceId, {
    DeviceAuditLogRecord? auditLog,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      if (auditLog != null) {
        await txn.insert('device_audit_logs', _auditToMap(auditLog));
      }
      await txn.delete(
        'device_refresh_tokens',
        where: 'device_id = ?',
        whereArgs: [deviceId],
      );
      await txn.delete(
        'devices',
        where: 'device_id = ?',
        whereArgs: [deviceId],
      );
    });
  }

  @override
  Future<void> saveRefreshToken(DeviceRefreshTokenRecord token) async {
    final database = await _requireDatabase();
    await database.insert(
      'device_refresh_tokens',
      {
        'token_id': token.tokenId,
        'device_id': token.deviceId,
        'token_hash': token.tokenHash,
        'issued_at': token.issuedAt.toUtc().toIso8601String(),
        'expires_at': token.expiresAt.toUtc().toIso8601String(),
        'revoked_at': token.revokedAt?.toUtc().toIso8601String(),
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  @override
  Future<DeviceRefreshTokenRecord?> findRefreshTokenByHash(
    String tokenHash,
  ) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      'device_refresh_tokens',
      where: 'token_hash = ?',
      whereArgs: [tokenHash],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapRefreshTokenRow(rows.first);
  }

  @override
  Future<void> revokeRefreshTokensForDevice(String deviceId) async {
    final database = await _requireDatabase();
    await database.update(
      'device_refresh_tokens',
      {'revoked_at': DateTime.now().toUtc().toIso8601String()},
      where: 'device_id = ? AND revoked_at IS NULL',
      whereArgs: [deviceId],
    );
  }

  @override
  Future<void> deleteRefreshToken(String tokenId) async {
    final database = await _requireDatabase();
    await database.delete(
      'device_refresh_tokens',
      where: 'token_id = ?',
      whereArgs: [tokenId],
    );
  }

  Future<sqflite.Database> _requireDatabase() async {
    final database = _database;
    if (database == null) {
      throw StateError('DeviceRepository is not initialized');
    }
    return database;
  }

  StoredDeviceRecord _mapDeviceRow(Map<String, Object?> row) {
    return StoredDeviceRecord(
      deviceId: row['device_id'] as String,
      physicalDeviceId: row['physical_device_id'] as String?,
      deviceName: row['device_name'] as String,
      platform: row['device_platform'] as String?,
      brand: row['device_brand'] as String?,
      model: row['device_model'] as String?,
      label: row['label'] as String?,
      status: DeviceStatus.values.byName(row['status'] as String),
      credentialVersion: row['credential_version'] as String,
      firstPairedAt: DateTime.parse(row['first_paired_at'] as String).toUtc(),
      lastSeenAt: row['last_seen_at'] == null
          ? null
          : DateTime.parse(row['last_seen_at'] as String).toUtc(),
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
    );
  }

  DeviceRefreshTokenRecord _mapRefreshTokenRow(Map<String, Object?> row) {
    return DeviceRefreshTokenRecord(
      tokenId: row['token_id'] as String,
      deviceId: row['device_id'] as String,
      tokenHash: row['token_hash'] as String,
      issuedAt: DateTime.parse(row['issued_at'] as String).toUtc(),
      expiresAt: DateTime.parse(row['expires_at'] as String).toUtc(),
      revokedAt: row['revoked_at'] == null
          ? null
          : DateTime.parse(row['revoked_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> _deviceToMap(StoredDeviceRecord device) {
    return {
      'device_id': device.deviceId,
      'physical_device_id': device.physicalDeviceId,
      'device_name': device.deviceName,
      'device_platform': device.platform,
      'device_brand': device.brand,
      'device_model': device.model,
      'label': device.label,
      'status': device.status.name,
      'credential_version': device.credentialVersion,
      'first_paired_at': device.firstPairedAt.toUtc().toIso8601String(),
      'last_seen_at': device.lastSeenAt?.toUtc().toIso8601String(),
      'created_at': device.createdAt.toUtc().toIso8601String(),
      'updated_at': device.updatedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, Object?> _auditToMap(DeviceAuditLogRecord auditLog) {
    return {
      'log_id': auditLog.logId,
      'device_id': auditLog.deviceId,
      'operator_owner_id': auditLog.operatorOwnerId,
      'event_type': auditLog.eventType,
      'details_json': jsonEncode(auditLog.details),
      'created_at': auditLog.createdAt.toUtc().toIso8601String(),
    };
  }
}
