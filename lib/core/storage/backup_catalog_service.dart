import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'platform_sqlite.dart';

class BackupPreflightItem {
  const BackupPreflightItem({
    required this.id,
    required this.sourceFingerprint,
    this.contentHash,
    required this.extension,
    required this.sizeBytes,
    required this.modifiedMs,
  });

  final String id;
  final String sourceFingerprint;
  final String? contentHash;
  final String extension;
  final int sizeBytes;
  final int modifiedMs;
}

class BackupPreflightDecision {
  const BackupPreflightDecision({
    required this.id,
    required this.action,
    required this.relativePath,
    required this.reason,
  });

  final String id;
  final String action;
  final String relativePath;
  final String reason;
}

class BackupCatalogRegistration {
  const BackupCatalogRegistration({
    required this.sourceFingerprint,
    required this.contentHash,
    required this.deviceId,
    this.deviceName,
    required this.sourceId,
    required this.sizeBytes,
    required this.modifiedMs,
    required this.relativePath,
  });

  final String sourceFingerprint;
  final String contentHash;
  final String deviceId;
  final String? deviceName;
  final String sourceId;
  final int sizeBytes;
  final int modifiedMs;
  final String relativePath;
}

class BackupCatalogOverview {
  const BackupCatalogOverview({
    required this.totalRecords,
    required this.totalStoredFiles,
    required this.totalStoredBytes,
    required this.deviceCount,
    required this.lastUpdatedAt,
  });

  final int totalRecords;
  final int totalStoredFiles;
  final int totalStoredBytes;
  final int deviceCount;
  final DateTime? lastUpdatedAt;
}

class BackupDeviceRecord {
  const BackupDeviceRecord({
    required this.deviceKey,
    required this.deviceId,
    required this.label,
    required this.recordCount,
    required this.storedFileCount,
    required this.totalBytes,
    required this.lastUpdatedAt,
  });

  final String deviceKey;
  final String deviceId;
  final String label;
  final int recordCount;
  final int storedFileCount;
  final int totalBytes;
  final DateTime? lastUpdatedAt;
}

class BackupFileRecord {
  const BackupFileRecord({
    required this.relativePath,
    required this.name,
    required this.extension,
    required this.category,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.updatedAt,
    required this.referenceCount,
    required this.deviceCount,
    required this.latestDeviceLabel,
  });

  final String relativePath;
  final String name;
  final String extension;
  final String category;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime updatedAt;
  final int referenceCount;
  final int deviceCount;
  final String latestDeviceLabel;
}

class BackupFilePage {
  const BackupFilePage({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<BackupFileRecord> items;
  final bool hasMore;
  final String? nextCursor;
}

class BackupCatalogService {
  BackupCatalogService({
    required String rootPath,
    required String databasePath,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _rootPath = rootPath,
       _databasePath = databasePath,
       _databaseFactory = databaseFactory ?? _resolveDatabaseFactory();

  final String _rootPath;
  final String _databasePath;
  final sqflite.DatabaseFactory _databaseFactory;

  sqflite.Database? _database;

  static const _photoExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  };
  static const _videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.webm',
    '.3gp',
    '.wmv',
    '.m4v',
  };
  static const _audioExtensions = {
    '.mp3',
    '.wav',
    '.aac',
    '.flac',
    '.m4a',
    '.ogg',
    '.wma',
    '.opus',
  };
  static const _documentExtensions = {
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.txt',
    '.md',
    '.csv',
  };

  static sqflite.DatabaseFactory _resolveDatabaseFactory() {
    return PlatformSqlite.resolveDatabaseFactory();
  }

  Future<void> initialize() async {
    await _openDatabase();
  }

  Future<List<BackupPreflightDecision>> preflight(
    List<BackupPreflightItem> items,
  ) async {
    final database = await _requireDatabase();
    final decisions = <BackupPreflightDecision>[];

    for (final item in items) {
      final exactRows = await database.query(
        'backup_catalog',
        columns: const ['relative_path', 'content_hash'],
        where: 'source_fingerprint = ?',
        whereArgs: [item.sourceFingerprint],
        limit: 1,
      );
      if (exactRows.isNotEmpty) {
        final relativePath = exactRows.first['relative_path'] as String;
        if (await _fileExists(relativePath)) {
          decisions.add(
            BackupPreflightDecision(
              id: item.id,
              action: 'skip',
              relativePath: relativePath,
              reason: 'source_match',
            ),
          );
          continue;
        }
        await database.delete(
          'backup_catalog',
          where: 'source_fingerprint = ?',
          whereArgs: [item.sourceFingerprint],
        );
      }

      final normalizedContentHash = item.contentHash?.trim();
      if (normalizedContentHash == null || normalizedContentHash.isEmpty) {
        decisions.add(
          BackupPreflightDecision(
            id: item.id,
            action: 'need_hash',
            relativePath: '/',
            reason: 'hash_required',
          ),
        );
        continue;
      }

      final contentRows = await database.query(
        'backup_catalog',
        columns: const ['relative_path'],
        where: 'content_hash = ?',
        whereArgs: [normalizedContentHash],
        limit: 1,
      );
      if (contentRows.isNotEmpty) {
        final relativePath = contentRows.first['relative_path'] as String;
        if (await _fileExists(relativePath)) {
          await registerUpload(
            BackupCatalogRegistration(
              sourceFingerprint: item.sourceFingerprint,
              contentHash: normalizedContentHash,
              deviceId: '',
              sourceId: item.sourceFingerprint,
              sizeBytes: item.sizeBytes,
              modifiedMs: item.modifiedMs,
              relativePath: relativePath,
            ),
          );
          decisions.add(
            BackupPreflightDecision(
              id: item.id,
              action: 'skip',
              relativePath: relativePath,
              reason: 'content_match',
            ),
          );
          continue;
        }
        await database.delete(
          'backup_catalog',
          where: 'content_hash = ? AND relative_path = ?',
          whereArgs: [normalizedContentHash, relativePath],
        );
      }

      decisions.add(
        BackupPreflightDecision(
          id: item.id,
          action: 'upload',
          relativePath: _buildRelativePath(
            contentHash: normalizedContentHash,
            extension: item.extension,
          ),
          reason: 'missing',
        ),
      );
    }

    return List.unmodifiable(decisions);
  }

  Future<void> registerUpload(BackupCatalogRegistration registration) async {
    final database = await _requireDatabase();
    await database.insert('backup_catalog', {
      'source_fingerprint': registration.sourceFingerprint,
      'content_hash': registration.contentHash,
      'device_id': registration.deviceId,
      'source_id': registration.sourceId,
      'size_bytes': registration.sizeBytes,
      'modified_ms': registration.modifiedMs,
      'relative_path': registration.relativePath,
      'device_name': registration.deviceName?.trim() ?? '',
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
  }

  Future<BackupCatalogOverview> fetchOverview() async {
    final database = await _requireDatabase();
    final recordRows = await database.rawQuery('''
SELECT
  COUNT(*) AS total_records,
  COUNT(DISTINCT CASE
    WHEN TRIM(device_id) != '' THEN TRIM(device_id)
    ELSE source_fingerprint
  END) AS device_count,
  MAX(updated_at_ms) AS last_updated_ms
FROM backup_catalog
''');
    final storedRows = await database.rawQuery('''
SELECT
  COUNT(*) AS total_stored_files,
  COALESCE(SUM(size_bytes), 0) AS total_stored_bytes
FROM (
  SELECT
    relative_path,
    MAX(size_bytes) AS size_bytes
  FROM backup_catalog
  GROUP BY relative_path
)
''');

    final recordRow = recordRows.first;
    final storedRow = storedRows.first;
    return BackupCatalogOverview(
      totalRecords: _readInt(recordRow['total_records']),
      totalStoredFiles: _readInt(storedRow['total_stored_files']),
      totalStoredBytes: _readInt(storedRow['total_stored_bytes']),
      deviceCount: _readInt(recordRow['device_count']),
      lastUpdatedAt: _readDateTime(recordRow['last_updated_ms']),
    );
  }

  Future<List<BackupDeviceRecord>> listDeviceRecords({int limit = 20}) async {
    final database = await _requireDatabase();
    final normalizedLimit = limit.clamp(1, 100);
    final rows = await database.rawQuery(
      '''
SELECT
  CASE
    WHEN TRIM(device_id) != '' THEN TRIM(device_id)
    ELSE source_fingerprint
  END AS device_key,
  MAX(device_id) AS device_id,
  COUNT(*) AS record_count,
  COUNT(DISTINCT relative_path) AS stored_file_count,
  COALESCE(SUM(size_bytes), 0) AS total_bytes,
  MAX(updated_at_ms) AS last_updated_ms,
  (
    SELECT CASE
      WHEN TRIM(latest.device_name) != '' THEN TRIM(latest.device_name)
      WHEN TRIM(latest.device_id) != '' THEN TRIM(latest.device_id)
      ELSE '未知设备'
    END
    FROM backup_catalog AS latest
    WHERE (
      CASE
        WHEN TRIM(latest.device_id) != '' THEN TRIM(latest.device_id)
        ELSE latest.source_fingerprint
      END
    ) = (
      CASE
        WHEN TRIM(backup_catalog.device_id) != '' THEN TRIM(backup_catalog.device_id)
        ELSE backup_catalog.source_fingerprint
      END
    )
    ORDER BY latest.updated_at_ms DESC
    LIMIT 1
  ) AS device_label
FROM backup_catalog
GROUP BY device_key
ORDER BY last_updated_ms DESC, device_label COLLATE NOCASE ASC
LIMIT ?
''',
      [normalizedLimit],
    );

    return rows
        .map(
          (row) => BackupDeviceRecord(
            deviceKey: '${row['device_key'] ?? ''}',
            deviceId: _normalizeDeviceId(row['device_id']),
            label: _normalizeDeviceLabel(row['device_label'], row['device_id']),
            recordCount: _readInt(row['record_count']),
            storedFileCount: _readInt(row['stored_file_count']),
            totalBytes: _readInt(row['total_bytes']),
            lastUpdatedAt: _readDateTime(row['last_updated_ms']),
          ),
        )
        .toList(growable: false);
  }

  Future<BackupFilePage> listBackupFiles({
    String? cursor,
    required int limit,
    String? category,
  }) async {
    return _listBackupFiles(
      cursor: cursor,
      limit: limit,
      category: category,
      allowRepair: true,
    );
  }

  Future<int> deleteEntriesForRelativePath(String relativePath) async {
    final database = await _requireDatabase();
    return database.delete(
      'backup_catalog',
      where: 'relative_path = ?',
      whereArgs: [relativePath],
    );
  }

  Future<int> purgeMissingFiles() async {
    final database = await _requireDatabase();
    final rows = await database.query(
      'backup_catalog',
      distinct: true,
      columns: const ['relative_path'],
    );

    var deleted = 0;
    for (final row in rows) {
      final relativePath = row['relative_path'] as String;
      if (await _fileExists(relativePath)) {
        continue;
      }
      deleted += await deleteEntriesForRelativePath(relativePath);
    }
    return deleted;
  }

  String resolveLocalPath(String relativePath) {
    final segments = relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty);
    return p.joinAll([_rootPath, ...segments]);
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<BackupFilePage> _listBackupFiles({
    String? cursor,
    required int limit,
    String? category,
    required bool allowRepair,
  }) async {
    final database = await _requireDatabase();
    final offset = _parseCursor(cursor);
    final normalizedLimit = limit.clamp(1, 200);
    final normalizedCategory = _normalizeCategory(category);
    final filter = _buildCategoryFilter(normalizedCategory);
    final whereClause = filter == null ? '' : 'WHERE ${filter.where}';

    final rows = await database.rawQuery(
      '''
SELECT
  relative_path,
  MAX(size_bytes) AS size_bytes,
  MAX(modified_ms) AS modified_ms,
  MAX(updated_at_ms) AS updated_at_ms,
  COUNT(*) AS reference_count,
  COUNT(DISTINCT CASE
    WHEN TRIM(device_id) != '' THEN TRIM(device_id)
    ELSE source_fingerprint
  END) AS device_count,
  (
    SELECT CASE
      WHEN TRIM(latest.device_name) != '' THEN TRIM(latest.device_name)
      WHEN TRIM(latest.device_id) != '' THEN TRIM(latest.device_id)
      ELSE '未知设备'
    END
    FROM backup_catalog AS latest
    WHERE latest.relative_path = backup_catalog.relative_path
    ORDER BY latest.updated_at_ms DESC
    LIMIT 1
  ) AS latest_device_label
FROM backup_catalog
$whereClause
GROUP BY relative_path
ORDER BY updated_at_ms DESC, relative_path COLLATE NOCASE ASC
LIMIT ? OFFSET ?
''',
      [...?filter?.args, normalizedLimit + 1, offset],
    );

    if (allowRepair) {
      final stalePaths = <String>[];
      for (final row in rows) {
        final relativePath = row['relative_path'] as String;
        if (!await _fileExists(relativePath)) {
          stalePaths.add(relativePath);
        }
      }
      if (stalePaths.isNotEmpty) {
        for (final relativePath in stalePaths) {
          await deleteEntriesForRelativePath(relativePath);
        }
        return _listBackupFiles(
          cursor: cursor,
          limit: limit,
          category: category,
          allowRepair: false,
        );
      }
    }

    final hasMore = rows.length > normalizedLimit;
    final pageRows = hasMore ? rows.take(normalizedLimit) : rows;
    final items = pageRows
        .map((row) {
          final relativePath = row['relative_path'] as String;
          final fileName = p.basename(relativePath);
          return BackupFileRecord(
            relativePath: relativePath,
            name: fileName,
            extension: p.extension(fileName).toLowerCase(),
            category: _resolveCategory(relativePath),
            sizeBytes: _readInt(row['size_bytes']),
            modifiedAt:
                _readDateTime(row['modified_ms']) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            updatedAt:
                _readDateTime(row['updated_at_ms']) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            referenceCount: _readInt(row['reference_count']),
            deviceCount: _readInt(row['device_count']),
            latestDeviceLabel: _normalizeDeviceLabel(
              row['latest_device_label'],
              row['latest_device_label'],
            ),
          );
        })
        .toList(growable: false);

    return BackupFilePage(
      items: items,
      hasMore: hasMore,
      nextCursor: hasMore ? '${offset + items.length}' : null,
    );
  }

  String _buildRelativePath({
    required String contentHash,
    required String extension,
  }) {
    final normalizedExtension = extension.trim().toLowerCase();
    if (normalizedExtension.isEmpty) {
      return '/$contentHash';
    }
    return normalizedExtension.startsWith('.')
        ? '/$contentHash$normalizedExtension'
        : '/$contentHash.$normalizedExtension';
  }

  Future<bool> _fileExists(String relativePath) async {
    return File(resolveLocalPath(relativePath)).exists();
  }

  Future<void> _openDatabase() async {
    if (_database != null) {
      return;
    }

    final databaseDir = Directory(p.dirname(_databasePath));
    if (!await databaseDir.exists()) {
      await databaseDir.create(recursive: true);
    }

    _database = await _databaseFactory.openDatabase(
      _databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: 3,
        onCreate: (database, _) async {
          await _createSchema(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          await database.execute('DROP TABLE IF EXISTS backup_catalog');
          await _createSchema(database);
        },
      ),
    );
  }

  Future<void> _createSchema(sqflite.Database database) async {
    await database.execute('''
CREATE TABLE backup_catalog (
  source_fingerprint TEXT PRIMARY KEY,
  content_hash TEXT NOT NULL,
  device_id TEXT NOT NULL,
  device_name TEXT NOT NULL DEFAULT '',
  source_id TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  modified_ms INTEGER NOT NULL,
  relative_path TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
''');
    await _createIndexes(database);
  }

  Future<void> _createIndexes(sqflite.Database database) async {
    await database.execute('''
CREATE INDEX IF NOT EXISTS idx_backup_catalog_content_hash
ON backup_catalog(content_hash)
''');
    await database.execute('''
CREATE INDEX IF NOT EXISTS idx_backup_catalog_relative_path
ON backup_catalog(relative_path)
''');
    await database.execute('''
CREATE INDEX IF NOT EXISTS idx_backup_catalog_device_order
ON backup_catalog(device_id, updated_at_ms DESC)
''');
  }

  Future<sqflite.Database> _requireDatabase() async {
    final database = _database;
    if (database == null) {
      throw StateError('Backup catalog database has not been initialized.');
    }
    return database;
  }

  int _parseCursor(String? cursor) {
    if (cursor == null || cursor.trim().isEmpty) {
      return 0;
    }
    final parsed = int.tryParse(cursor);
    if (parsed == null || parsed < 0) {
      throw const FormatException('Invalid cursor');
    }
    return parsed;
  }

  String? _normalizeCategory(String? category) {
    if (category == null || category.trim().isEmpty || category == 'all') {
      return null;
    }
    switch (category.trim()) {
      case 'photo':
      case 'video':
      case 'audio':
      case 'document':
      case 'other':
        return category.trim();
    }
    throw const FormatException('Invalid category');
  }

  _SqlFilter? _buildCategoryFilter(String? category) {
    if (category == null) {
      return null;
    }
    final extensions = switch (category) {
      'photo' => _photoExtensions,
      'video' => _videoExtensions,
      'audio' => _audioExtensions,
      'document' => _documentExtensions,
      'other' => null,
      _ => null,
    };
    if (extensions == null) {
      final knownExtensions = {
        ..._photoExtensions,
        ..._videoExtensions,
        ..._audioExtensions,
        ..._documentExtensions,
      };
      final clause = knownExtensions
          .map((_) => 'LOWER(relative_path) NOT LIKE ?')
          .join(' AND ');
      return _SqlFilter(
        where: clause,
        args: knownExtensions.map((ext) => '%$ext').toList(growable: false),
      );
    }
    final clause = extensions
        .map((_) => 'LOWER(relative_path) LIKE ?')
        .join(' OR ');
    return _SqlFilter(
      where: '($clause)',
      args: extensions.map((ext) => '%$ext').toList(growable: false),
    );
  }

  String _resolveCategory(String relativePath) {
    final extension = p.extension(relativePath).toLowerCase();
    if (_photoExtensions.contains(extension)) {
      return 'photo';
    }
    if (_videoExtensions.contains(extension)) {
      return 'video';
    }
    if (_audioExtensions.contains(extension)) {
      return 'audio';
    }
    if (_documentExtensions.contains(extension)) {
      return 'document';
    }
    return 'other';
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value') ?? 0;
  }

  DateTime? _readDateTime(Object? value) {
    final milliseconds = _readInt(value);
    if (milliseconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  String _normalizeDeviceId(Object? value) {
    final normalized = '$value'.trim();
    return normalized.isEmpty ? '--' : normalized;
  }

  String _normalizeDeviceLabel(Object? preferred, Object? fallback) {
    final preferredText = '$preferred'.trim();
    if (preferredText.isNotEmpty && preferredText != 'null') {
      return preferredText;
    }
    final fallbackText = '$fallback'.trim();
    if (fallbackText.isNotEmpty && fallbackText != 'null') {
      return fallbackText;
    }
    return '未知设备';
  }
}

class _SqlFilter {
  const _SqlFilter({required this.where, required this.args});

  final String where;
  final List<Object?> args;
}
