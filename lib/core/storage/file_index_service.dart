import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'platform_sqlite.dart';
import 'share_internal_paths.dart';

class IndexedFileEntry {
  const IndexedFileEntry({
    required this.name,
    required this.path,
    required this.category,
    required this.size,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final String category;
  final int size;
  final DateTime modifiedAt;
}

class IndexedFilePage {
  const IndexedFilePage({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<IndexedFileEntry> items;
  final bool hasMore;
  final String? nextCursor;
}

class FileIndexService {
  FileIndexService({
    required String rootPath,
    required String databasePath,
    required bool recursiveScan,
    bool watchChanges = false,
    sqflite.DatabaseFactory? databaseFactory,
  }) : _rootPath = rootPath,
       _databasePath = databasePath,
       _recursiveScan = recursiveScan,
       _watchChanges = watchChanges,
       _databaseFactory = databaseFactory ?? _resolveDatabaseFactory();

  final String _rootPath;
  final String _databasePath;
  final bool _recursiveScan;
  final bool _watchChanges;
  final sqflite.DatabaseFactory _databaseFactory;
  Future<void> Function(String relativePath)? onPathChanged;

  sqflite.Database? _database;
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _refreshTimer;
  Future<void>? _refreshFuture;
  bool _refreshQueued = false;
  Future<void>? _initialIndexFuture;

  static sqflite.DatabaseFactory _resolveDatabaseFactory() {
    return PlatformSqlite.resolveDatabaseFactory();
  }

  Future<void> initialize({
    bool enableWatching = true,
    bool startBackgroundIndex = true,
  }) async {
    await _openDatabase();
    if (startBackgroundIndex) {
      scheduleBackgroundIndex();
    }
    if (_watchChanges && enableWatching) {
      _startWatching();
    }
  }

  bool get isIndexing => _refreshFuture != null;

  void scheduleBackgroundIndex() {
    if (_initialIndexFuture != null) {
      return;
    }
    _initialIndexFuture = refreshIndex();
  }

  Future<void> waitForInitialIndex() async {
    final future = _initialIndexFuture;
    if (future != null) {
      try {
        await future;
      } catch (_) {
        // Background indexing failures are retried on the next listFiles repair.
      }
    }
  }

  Future<void> enableWatching() async {
    if (!_watchChanges || _watchSubscription != null) {
      return;
    }
    _startWatching();
  }

  Future<IndexedFilePage> listFiles({
    String? cursor,
    required int limit,
    String? category,
  }) async {
    return _listFiles(cursor: cursor, limit: limit, category: category);
  }

  Future<IndexedFilePage> _listFiles({
    String? cursor,
    required int limit,
    String? category,
    bool allowRepair = true,
  }) async {
    final database = await _requireDatabase();
    final offset = _parseCursor(cursor);
    final normalizedLimit = limit.clamp(1, 200);
    final normalizedCategory = _normalizeCategory(category);
    final where = normalizedCategory == null ? null : 'category = ?';
    final whereArgs = normalizedCategory == null
        ? null
        : <Object?>[normalizedCategory];

    final rows = await database.query(
      'indexed_files',
      columns: const [
        'relative_path',
        'file_name',
        'category',
        'size_bytes',
        'modified_ms',
      ],
      where: where,
      whereArgs: whereArgs,
      orderBy: 'modified_ms DESC, relative_path COLLATE NOCASE ASC',
      limit: normalizedLimit + 1,
      offset: offset,
    );

    if (allowRepair && await _pageContainsStaleRows(rows)) {
      await refreshIndex();
      return _listFiles(
        cursor: cursor,
        limit: limit,
        category: category,
        allowRepair: false,
      );
    }

    final hasMore = rows.length > normalizedLimit;
    final pageRows = hasMore ? rows.take(normalizedLimit) : rows;
    final items = pageRows
        .map(
          (row) => IndexedFileEntry(
            name: row['file_name'] as String,
            path: row['relative_path'] as String,
            category: row['category'] as String,
            size: row['size_bytes'] as int,
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(
              row['modified_ms'] as int,
            ),
          ),
        )
        .toList(growable: false);

    return IndexedFilePage(
      items: items,
      hasMore: hasMore,
      nextCursor: hasMore ? '${offset + items.length}' : null,
    );
  }

  Future<void> refreshIndex() async {
    return refreshIndexWithCancellation();
  }

  Future<void> refreshIndexWithCancellation({
    FutureOr<bool> Function()? shouldContinue,
  }) async {
    if (_refreshFuture != null) {
      _refreshQueued = true;
      return _refreshFuture!;
    }

    late final Future<void> future;
    future = () async {
      final records = await _scanFilesWithCancellation(
        shouldContinue: shouldContinue,
      );
      final database = await _requireDatabase();
      await database.transaction((txn) async {
        await txn.delete('indexed_files');
        final batch = txn.batch();
        final indexedAt = DateTime.now().millisecondsSinceEpoch;
        for (final record in records) {
          batch.insert('indexed_files', {
            'relative_path': record.path,
            'file_name': record.name,
            'extension': record.extension,
            'category': record.category,
            'size_bytes': record.size,
            'modified_ms': record.modifiedAt.millisecondsSinceEpoch,
            'indexed_ms': indexedAt,
          });
        }
        await batch.commit(noResult: true);
      });
    }();
    _refreshFuture = future;
    _initialIndexFuture ??= future;
    try {
      await future;
    } catch (_) {
      _initialIndexFuture = null;
      rethrow;
    } finally {
      _refreshFuture = null;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(refreshIndexWithCancellation());
      }
    }
  }

  void scheduleRefresh({Duration delay = const Duration(milliseconds: 800)}) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(delay, () {
      unawaited(refreshIndex());
    });
  }

  Future<void> close() async {
    _refreshTimer?.cancel();
    await _watchSubscription?.cancel();
    final database = _database;
    _database = null;
    await database?.close();
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
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE indexed_files (
  relative_path TEXT PRIMARY KEY,
  file_name TEXT NOT NULL,
  extension TEXT NOT NULL,
  category TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  modified_ms INTEGER NOT NULL,
  indexed_ms INTEGER NOT NULL
)
''');
          await database.execute('''
CREATE INDEX idx_indexed_files_order
ON indexed_files(modified_ms DESC, relative_path COLLATE NOCASE ASC)
''');
          await database.execute('''
CREATE INDEX idx_indexed_files_category_order
ON indexed_files(category, modified_ms DESC, relative_path COLLATE NOCASE ASC)
''');
        },
      ),
    );
  }

  Future<sqflite.Database> _requireDatabase() async {
    final database = _database;
    if (database == null) {
      throw StateError('File index database has not been initialized.');
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
    if (category == null || category.isEmpty || category == 'all') {
      return null;
    }
    switch (category) {
      case 'photo':
      case 'video':
      case 'document':
      case 'other':
        return category;
    }
    throw const FormatException('Invalid category');
  }

  Future<List<_IndexedFileRecord>> _scanFilesWithCancellation({
    FutureOr<bool> Function()? shouldContinue,
  }) async {
    final rootDir = Directory(_rootPath);
    if (!await rootDir.exists()) {
      return const [];
    }

    final records = <_IndexedFileRecord>[];
    final directories = Queue<Directory>()..add(rootDir);

    while (directories.isNotEmpty) {
      await _throwIfCancelled(shouldContinue);
      final directory = directories.removeFirst();
      await for (final entity in directory.list(followLinks: false)) {
        await _throwIfCancelled(shouldContinue);
        final name = p.basename(entity.path);
        if (_shouldSkipPath(entity.path)) {
          continue;
        }

        if (entity is File) {
          final stat = await entity.stat();
          records.add(
            _IndexedFileRecord(
              name: name,
              path: _toDavRelativePath(entity.path),
              extension: _extensionOf(name),
              category: _resolveCategory(name),
              size: stat.size,
              modifiedAt: stat.modified,
            ),
          );
          continue;
        }

        if (_recursiveScan && entity is Directory) {
          directories.add(entity);
        }
      }

      if (!_recursiveScan) {
        break;
      }
    }

    return records;
  }

  Future<void> _throwIfCancelled(
    FutureOr<bool> Function()? shouldContinue,
  ) async {
    if (shouldContinue == null) {
      return;
    }
    final allowed = await shouldContinue();
    if (!allowed) {
      throw const FileIndexRefreshCancelled();
    }
  }

  String _toDavRelativePath(String localPath) {
    final relative = p
        .relative(localPath, from: _rootPath)
        .replaceAll('\\', '/');
    return '/$relative';
  }

  String _toLocalPath(String relativePath) {
    final segments = relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty);
    return p.joinAll([_rootPath, ...segments]);
  }

  String _extensionOf(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) {
      return '';
    }
    return name.substring(dotIndex + 1).toLowerCase();
  }

  String _resolveCategory(String name) {
    final extension = _extensionOf(name);
    if (const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
    }.contains(extension)) {
      return 'photo';
    }
    if (const {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm'}.contains(extension)) {
      return 'video';
    }
    if (const {
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
    }.contains(extension)) {
      return 'document';
    }
    return 'other';
  }

  bool _shouldSkipName(String name) {
    return shouldHideFromShareListing(name);
  }

  bool _shouldSkipPath(String entityPath) {
    final relativePath = p
        .relative(entityPath, from: _rootPath)
        .replaceAll('\\', '/')
        .trim();
    return shouldSkipSharePath(relativePath);
  }

  Future<bool> _pageContainsStaleRows(List<Map<String, Object?>> rows) async {
    for (final row in rows) {
      final relativePath = row['relative_path'] as String;
      final entityType = await FileSystemEntity.type(
        _toLocalPath(relativePath),
        followLinks: false,
      );
      if (entityType != FileSystemEntityType.file) {
        return true;
      }
    }
    return false;
  }

  void _startWatching() {
    final directory = Directory(_rootPath);
    if (!directory.existsSync()) {
      return;
    }

    _watchSubscription = directory.watch(recursive: _recursiveScan).listen((
      event,
    ) {
      if (_shouldSkipPath(event.path)) {
        return;
      }
      scheduleRefresh();
      final pathChangedCallback = onPathChanged;
      if (pathChangedCallback != null) {
        unawaited(pathChangedCallback(_toDavRelativePath(event.path)));
      }
    }, onError: (_) {});
  }
}

class FileIndexRefreshCancelled implements Exception {
  const FileIndexRefreshCancelled();
}

class _IndexedFileRecord {
  const _IndexedFileRecord({
    required this.name,
    required this.path,
    required this.extension,
    required this.category,
    required this.size,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final String extension;
  final String category;
  final int size;
  final DateTime modifiedAt;
}
