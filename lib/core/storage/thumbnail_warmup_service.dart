import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'platform_sqlite.dart';

import '../../features/realtime/data/realtime_connection_registry.dart';
import '../../features/server/data/datasources/server_activity_tracker.dart';
import 'file_index_service.dart';
import 'thumbnail_service.dart';

enum WarmupServiceStatus { idle, running, paused }

class ThumbnailWarmupProgress {
  const ThumbnailWarmupProgress({
    required this.status,
    required this.processedCount,
    required this.pendingCount,
    required this.failedCount,
    required this.currentFile,
  });

  final WarmupServiceStatus status;
  final int processedCount;
  final int pendingCount;
  final int failedCount;
  final String? currentFile;
}

class ThumbnailWarmupService {
  ThumbnailWarmupService({
    required String rootPath,
    required String databasePath,
    required ThumbnailService thumbnailService,
    required FileIndexService fileIndexService,
    required RealtimeConnectionRegistry realtimeConnectionRegistry,
    ServerActivityTracker? activityTracker,
    sqflite.DatabaseFactory? databaseFactory,
    Duration pollInterval = const Duration(seconds: 30),
    int batchSize = 8,
    int maxFailCount = 5,
    int incrementalScanBatchSize = 100,
    Duration incrementalScanInterval = const Duration(minutes: 30),
    Duration initialScanDelay = const Duration(seconds: 30),
  }) : _rootPath = rootPath,
       _databasePath = databasePath,
       _thumbnailService = thumbnailService,
       _fileIndexService = fileIndexService,
       _realtimeConnectionRegistry = realtimeConnectionRegistry,
       _databaseFactory = databaseFactory ?? _resolveDatabaseFactory(),
       _pollInterval = pollInterval,
       _batchSize = batchSize,
       _maxFailCount = maxFailCount,
       _incrementalScanBatchSize = incrementalScanBatchSize,
       _incrementalScanInterval = incrementalScanInterval,
       _initialScanDelay = initialScanDelay;

  final String _rootPath;
  final String _databasePath;
  final ThumbnailService _thumbnailService;
  final FileIndexService _fileIndexService;
  RealtimeConnectionRegistry _realtimeConnectionRegistry;
  final sqflite.DatabaseFactory _databaseFactory;
  final Duration _pollInterval;
  final int _batchSize;
  final int _maxFailCount;
  final int _incrementalScanBatchSize;
  final Duration _incrementalScanInterval;
  final Duration _initialScanDelay;

  sqflite.Database? _database;
  Timer? _pollTimer;
  Timer? _scheduledPumpTimer;
  Timer? _incrementalScanTimer;
  Timer? _initialScanTimer;
  Future<void>? _runFuture;
  bool _closed = false;
  bool _initialScanCompleted = false;
  bool _initialScanRunning = false;
  int _processedInCurrentRun = 0;
  String? _currentProcessingFile;
  StreamSubscription<bool>? _connectionStateSubscription;

  final _statusController = StreamController<ThumbnailWarmupProgress>.broadcast();

  Stream<ThumbnailWarmupProgress> get onProgressChanged => _statusController.stream;

  static sqflite.DatabaseFactory _resolveDatabaseFactory() {
    return PlatformSqlite.resolveDatabaseFactory();
  }

  Future<void> initialize({bool deferInitialScan = true}) async {
    await _openDatabase();
    await _resetRunningStates();
    await _migrateDatabaseIfNeeded();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(processPendingNow());
    });
    _incrementalScanTimer = Timer.periodic(_incrementalScanInterval, (_) {
      unawaited(_runIncrementalScan());
    });
    _bindConnectionStateListener();
    if (deferInitialScan) {
      _scheduleDeferredInitialScan();
    } else {
      await _runInitialScanOnce();
    }
    _schedulePump();
  }

  void _scheduleDeferredInitialScan() {
    _initialScanTimer?.cancel();
    _initialScanTimer = Timer(_initialScanDelay, () {
      unawaited(_runInitialScanOnce());
    });
  }

  Future<void> _runInitialScanOnce() async {
    if (_initialScanCompleted || _initialScanRunning || _closed) {
      return;
    }

    _initialScanRunning = true;
    try {
      await _ensureInitialScan();
      _initialScanCompleted = true;
    } finally {
      _initialScanRunning = false;
    }
  }

  Future<void> _ensureInitialScan() async {
    print('[ThumbnailWarmup] _ensureInitialScan: checking if database is empty...');
    final database = await _requireDatabase();
    final countResult = await database.rawQuery(
      'SELECT COUNT(*) as cnt FROM thumbnail_warmup_state',
    );
    final count = (countResult.first['cnt'] as int?) ?? 0;
    print('[ThumbnailWarmup] _ensureInitialScan: current state count=$count');
    if (count > 0) {
      print('[ThumbnailWarmup] _ensureInitialScan: database not empty, skipping initial scan');
      return;
    }

    // Reuse FileIndexService index instead of scanning the filesystem again.
    print('[ThumbnailWarmup] _ensureInitialScan: database empty, populating from file index...');
    int syncedCount = 0;
    String? cursor;
    int pageCount = 0;
    do {
      if (_closed) {
        print('[ThumbnailWarmup] _ensureInitialScan: service closed, aborting');
        return;
      }

      final page = await _fileIndexService.listFiles(
        cursor: cursor,
        limit: 200,
      );
      pageCount++;
      print('[ThumbnailWarmup] _ensureInitialScan: page $pageCount, ${page.items.length} items');

      for (final item in page.items) {
        if (_closed) {
          return;
        }
        if (!_isWarmupCategory(item.category)) {
          continue;
        }

        await _syncStateForCurrentSource(
          relativePath: item.path,
          category: item.category,
          sourceModifiedMs: item.modifiedAt.millisecondsSinceEpoch,
          sourceSizeBytes: item.size,
          dirtyReason: 'initial_scan',
          validateCachePresence: false,
        );
        syncedCount++;
        if (syncedCount % 100 == 0) {
          print('[ThumbnailWarmup] _ensureInitialScan: synced $syncedCount files...');
        }
      }

      cursor = page.nextCursor;
      if (!page.hasMore) {
        break;
      }
    } while (true);

    print('[ThumbnailWarmup] _ensureInitialScan: completed, synced $syncedCount files');
  }

  set realtimeConnectionRegistry(RealtimeConnectionRegistry value) {
    _realtimeConnectionRegistry = value;
    _bindConnectionStateListener();
  }

  void _bindConnectionStateListener() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _realtimeConnectionRegistry
        .onConnectionStateChanged
        .listen((hasConnections) {
      print('[ThumbnailWarmup] Connection state changed: hasConnections=$hasConnections');
      if (!hasConnections) {
        print('[ThumbnailWarmup] All clients disconnected, scheduling pump in 5s');
        _schedulePump(const Duration(seconds: 5));
        return;
      }

      print('[ThumbnailWarmup] Client connected, triggering deferred initial scan');
      unawaited(_runInitialScanOnce());
    });
  }

  Future<void> close() async {
    _closed = true;
    _pollTimer?.cancel();
    _scheduledPumpTimer?.cancel();
    _incrementalScanTimer?.cancel();
    _initialScanTimer?.cancel();
    await _connectionStateSubscription?.cancel();
    final runFuture = _runFuture;
    if (runFuture != null) {
      await runFuture.catchError((_) {});
    }
    final database = _database;
    _database = null;
    await database?.close();
    await _statusController.close();
  }

  Future<void> handlePathChanged(
    String relativePath, {
    String reason = 'changed',
  }) async {
    if (_closed) {
      return;
    }
    final normalizedRelativePath = _normalizeRelativePath(relativePath);
    if (_shouldSkipRelativePath(normalizedRelativePath)) {
      return;
    }

    print('[ThumbnailWarmup] handlePathChanged: $normalizedRelativePath reason=$reason');
    final entityType = await FileSystemEntity.type(
      _toLocalPath(normalizedRelativePath),
      followLinks: false,
    );
    if (entityType != FileSystemEntityType.file) {
      print('[ThumbnailWarmup] handlePathChanged: not a file, deleting state');
      await deletePathState(normalizedRelativePath);
      return;
    }

    await markPathDirty(normalizedRelativePath, reason: reason);
  }

  Future<void> markPathDirty(
    String relativePath, {
    String reason = 'changed',
  }) async {
    if (_closed) {
      return;
    }
    final normalizedRelativePath = _normalizeRelativePath(relativePath);
    if (_shouldSkipRelativePath(normalizedRelativePath)) {
      return;
    }

    print('[ThumbnailWarmup] markPathDirty: $normalizedRelativePath reason=$reason');
    final file = File(_toLocalPath(normalizedRelativePath));
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      print('[ThumbnailWarmup] markPathDirty: not a file, deleting state');
      await deletePathState(normalizedRelativePath);
      return;
    }

    final category = _resolveCategory(p.basename(file.path));
    if (!_isWarmupCategory(category)) {
      print('[ThumbnailWarmup] markPathDirty: not warmup category, deleting state');
      await deletePathState(normalizedRelativePath);
      return;
    }

    await _syncStateForCurrentSource(
      relativePath: normalizedRelativePath,
      category: category,
      sourceModifiedMs: stat.modified.millisecondsSinceEpoch,
      sourceSizeBytes: stat.size,
      dirtyReason: reason,
      validateCachePresence: false,
    );
    print('[ThumbnailWarmup] markPathDirty: done, scheduling pump');
    _schedulePump();
  }

  Future<void> deletePathState(String relativePath) async {
    if (_closed) {
      return;
    }
    final normalizedRelativePath = _normalizeRelativePath(relativePath);
    if (_shouldSkipRelativePath(normalizedRelativePath)) {
      return;
    }

    final database = await _requireDatabase();
    final rows = await _loadRowsForPath(normalizedRelativePath);
    for (final row in rows) {
      await _thumbnailService.deleteThumbnailVariant(
        _toServerFilePath(normalizedRelativePath),
        row.variant,
        sourceModifiedMs: row.sourceModifiedMs,
        sourceSizeBytes: row.sourceSizeBytes,
      );
    }
    await database.delete(
      'thumbnail_warmup_state',
      where: 'relative_path = ?',
      whereArgs: <Object?>[normalizedRelativePath],
    );
  }

  Future<ThumbnailWarmupProgress> getCurrentProgress() async {
    final database = await _requireDatabase();
    final pendingResult = await database.rawQuery(
      "SELECT COUNT(*) as cnt FROM thumbnail_warmup_state WHERE status = 'pending'",
    );
    final failedResult = await database.rawQuery(
      "SELECT COUNT(*) as cnt FROM thumbnail_warmup_state WHERE status = 'failed'",
    );
    final pendingCount = (pendingResult.first['cnt'] as int?) ?? 0;
    final failedCount = (failedResult.first['cnt'] as int?) ?? 0;

    return ThumbnailWarmupProgress(
      status: _runFuture != null
          ? WarmupServiceStatus.running
          : WarmupServiceStatus.idle,
      processedCount: _processedInCurrentRun,
      pendingCount: pendingCount,
      failedCount: failedCount,
      currentFile: _currentProcessingFile,
    );
  }

  Future<void> triggerManualFullScan() async {
    if (_closed || _runFuture != null) {
      return;
    }
    unawaited(_runFullScanInternal());
  }

  Future<void> processPendingNow() async {
    if (_closed) {
      print('[ThumbnailWarmup] processPendingNow: service is closed, skipping');
      return;
    }
    final currentRun = _runFuture;
    if (currentRun != null) {
      print('[ThumbnailWarmup] processPendingNow: already running, skipping');
      return currentRun;
    }

    print('[ThumbnailWarmup] processPendingNow: starting...');
    final completer = Completer<void>();
    _runFuture = completer.future;
    _processedInCurrentRun = 0;
    try {
      final isIdle = await _isServerIdle();
      print('[ThumbnailWarmup] processPendingNow: isIdle=$isIdle');
      if (!isIdle) {
        print('[ThumbnailWarmup] processPendingNow: server not idle, aborting');
        completer.complete();
        return;
      }

      await _runPendingBatch();
      completer.complete();
    } catch (error, stackTrace) {
      print('[ThumbnailWarmup] processPendingNow: ERROR $error');
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      print('[ThumbnailWarmup] processPendingNow: finished, processed=$_processedInCurrentRun');
      _runFuture = null;
      _currentProcessingFile = null;
      _notifyProgress();
    }
  }

  Future<void> _runPendingBatch() async {
    while (await _isServerIdle()) {
      final database = await _requireDatabase();
      final rows = await database.query(
        'thumbnail_warmup_state',
        where: 'status = ? OR (status = ? AND fail_count < ? AND next_retry_ms <= ?)',
        whereArgs: <Object?>[
          'pending',
          'failed',
          _maxFailCount,
          DateTime.now().millisecondsSinceEpoch,
        ],
        orderBy:
            'CASE variant WHEN "grid" THEN 0 ELSE 1 END, '
            'CASE status WHEN "pending" THEN 0 ELSE 1 END, '
            'COALESCE(last_checked_ms, 0) ASC, '
            'relative_path COLLATE NOCASE ASC, '
            'variant COLLATE NOCASE ASC',
        limit: _batchSize,
      );
      print('[ThumbnailWarmup] _runPendingBatch: fetched ${rows.length} rows');
      if (rows.isEmpty) {
        print('[ThumbnailWarmup] _runPendingBatch: no pending rows, exiting');
        return;
      }

      for (final row in rows) {
        if (!await _isServerIdle()) {
          print('[ThumbnailWarmup] _runPendingBatch: server no longer idle, breaking');
          return;
        }
        final stateRow = _WarmupStateRow.fromMap(row);
        print('[ThumbnailWarmup] _runPendingBatch: processing ${stateRow.relativePath} variant=${stateRow.variant.name}');
        await _processRow(stateRow);
        print('[ThumbnailWarmup] _runPendingBatch: done ${stateRow.relativePath} variant=${stateRow.variant.name}');
      }
    }
    print('[ThumbnailWarmup] _runPendingBatch: loop exited (not idle)');
  }

  Future<void> _processRow(_WarmupStateRow row) async {
    print('[ThumbnailWarmup] _processRow: checking file ${row.relativePath}');
    final file = File(_toLocalPath(row.relativePath));
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      print('[ThumbnailWarmup] _processRow: file not found, deleting state');
      await deletePathState(row.relativePath);
      return;
    }

    final currentCategory = _resolveCategory(p.basename(file.path));
    if (!_isWarmupCategory(currentCategory)) {
      print('[ThumbnailWarmup] _processRow: not warmup category, deleting state');
      await deletePathState(row.relativePath);
      return;
    }

    final currentModifiedMs = stat.modified.millisecondsSinceEpoch;
    final currentSizeBytes = stat.size;
    final currentGeneratorVersion = _thumbnailService.generatorVersion(
      row.variant,
    );
    if (row.sourceModifiedMs != currentModifiedMs ||
        row.sourceSizeBytes != currentSizeBytes ||
        row.generatorVersion != currentGeneratorVersion ||
        row.category != currentCategory) {
      print('[ThumbnailWarmup] _processRow: source changed, re-syncing');
      await _syncStateForCurrentSource(
        relativePath: row.relativePath,
        category: currentCategory,
        sourceModifiedMs: currentModifiedMs,
        sourceSizeBytes: currentSizeBytes,
        dirtyReason: 'source_changed',
        validateCachePresence: false,
      );
      return;
    }

    final database = await _requireDatabase();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await database.update(
      'thumbnail_warmup_state',
      <String, Object?>{'status': 'running', 'last_checked_ms': nowMs},
      where: 'relative_path = ? AND variant = ?',
      whereArgs: <Object?>[row.relativePath, row.variant.name],
    );

    _currentProcessingFile = row.relativePath;
    _processedInCurrentRun++;
    _notifyProgress();

    print('[ThumbnailWarmup] _processRow: generating thumbnail for ${row.relativePath} variant=${row.variant.name}');
    final bytes = await _thumbnailService.getOrGenerateThumbnail(
      _toServerFilePath(row.relativePath),
      row.variant,
    );
    if (bytes == null) {
      final failCount = row.failCount + 1;
      print('[ThumbnailWarmup] _processRow: generation FAILED for ${row.relativePath} variant=${row.variant.name}, failCount=$failCount');
      final nextRetryMs = failCount >= _maxFailCount
          ? null
          : nowMs + _calculateBackoffMs(failCount);
      await database.update(
        'thumbnail_warmup_state',
        <String, Object?>{
          'status': failCount >= _maxFailCount ? 'permanent_failed' : 'failed',
          'fail_count': failCount,
          'dirty_reason': 'generate_failed',
          'last_checked_ms': nowMs,
          'next_retry_ms': nextRetryMs,
        },
        where: 'relative_path = ? AND variant = ?',
        whereArgs: <Object?>[row.relativePath, row.variant.name],
      );
      return;
    }

    print('[ThumbnailWarmup] _processRow: generation SUCCESS for ${row.relativePath} variant=${row.variant.name}, size=${bytes.length}');
    await database.update(
      'thumbnail_warmup_state',
      <String, Object?>{
        'status': 'done',
        'fail_count': 0,
        'dirty_reason': null,
        'last_checked_ms': nowMs,
        'last_generated_ms': nowMs,
        'next_retry_ms': null,
      },
      where: 'relative_path = ? AND variant = ?',
      whereArgs: <Object?>[row.relativePath, row.variant.name],
    );
  }

  int _calculateBackoffMs(int failCount) {
    final baseMs = 5 * 60 * 1000;
    final multiplier = math.pow(2, failCount - 1).toInt();
    return baseMs * multiplier;
  }

  Future<void> _runIncrementalScan() async {
    print('[ThumbnailWarmup] _runIncrementalScan: checking...');
    if (_closed || _runFuture != null || !await _isServerIdle()) {
      print('[ThumbnailWarmup] _runIncrementalScan: skipped (closed=$_closed, runFuture=${_runFuture != null}, idle=${await _isServerIdle()})');
      return;
    }
    print('[ThumbnailWarmup] _runIncrementalScan: starting');

    final database = await _requireDatabase();
    final cutoffMs = DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    final rows = await database.query(
      'thumbnail_warmup_state',
      where: 'status = ? AND last_checked_ms < ?',
      whereArgs: <Object?>['done', cutoffMs],
      orderBy: 'last_checked_ms ASC',
      limit: _incrementalScanBatchSize,
    );

    for (final row in rows) {
      if (!await _isServerIdle()) {
        return;
      }
      final stateRow = _WarmupStateRow.fromMap(row);
      final file = File(_toLocalPath(stateRow.relativePath));
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        await deletePathState(stateRow.relativePath);
        continue;
      }

      final currentModifiedMs = stat.modified.millisecondsSinceEpoch;
      final currentSizeBytes = stat.size;
      if (stateRow.sourceModifiedMs != currentModifiedMs ||
          stateRow.sourceSizeBytes != currentSizeBytes) {
        print('[ThumbnailWarmup] _runIncrementalScan: stale ${stateRow.relativePath}, re-syncing');
        await _syncStateForCurrentSource(
          relativePath: stateRow.relativePath,
          category: stateRow.category,
          sourceModifiedMs: currentModifiedMs,
          sourceSizeBytes: currentSizeBytes,
          dirtyReason: 'incremental_scan_stale',
          validateCachePresence: false,
        );
      } else {
        await database.update(
          'thumbnail_warmup_state',
          <String, Object?>{'last_checked_ms': DateTime.now().millisecondsSinceEpoch},
          where: 'relative_path = ? AND variant = ?',
          whereArgs: <Object?>[stateRow.relativePath, stateRow.variant.name],
        );
      }
    }
    print('[ThumbnailWarmup] _runIncrementalScan: completed, checked ${rows.length} items');
  }

  Future<void> _runFullScanInternal() async {
    print('[ThumbnailWarmup] _runFullScanInternal: starting manual full scan');
    if (_closed) {
      print('[ThumbnailWarmup] _runFullScanInternal: service closed, aborting');
      return;
    }
    final completer = Completer<void>();
    _runFuture = completer.future;
    _processedInCurrentRun = 0;
    try {
      if (!await _isServerIdle()) {
        print('[ThumbnailWarmup] _runFullScanInternal: server not idle, aborting');
        completer.complete();
        return;
      }

      try {
        print('[ThumbnailWarmup] _runFullScanInternal: refreshing file index...');
        await _fileIndexService.refreshIndexWithCancellation(
          shouldContinue: _isServerIdle,
        );
      } on FileIndexRefreshCancelled {
        print('[ThumbnailWarmup] _runFullScanInternal: index refresh cancelled');
        completer.complete();
        return;
      }
      if (!await _isServerIdle()) {
        print('[ThumbnailWarmup] _runFullScanInternal: server no longer idle after index refresh');
        completer.complete();
        return;
      }

      final seenPaths = <String>{};
      String? cursor;
      int pageCount = 0;
      do {
        if (!await _isServerIdle()) {
          print('[ThumbnailWarmup] _runFullScanInternal: server no longer idle during scan');
          completer.complete();
          return;
        }

        final page = await _fileIndexService.listFiles(
          cursor: cursor,
          limit: 200,
        );
        pageCount++;
        print('[ThumbnailWarmup] _runFullScanInternal: page $pageCount, ${page.items.length} items');
        for (final item in page.items) {
          if (!_isWarmupCategory(item.category)) {
            continue;
          }
          seenPaths.add(item.path);
          await _syncStateForCurrentSource(
            relativePath: item.path,
            category: item.category,
            sourceModifiedMs: item.modifiedAt.millisecondsSinceEpoch,
            sourceSizeBytes: item.size,
            dirtyReason: 'manual_full_scan',
            validateCachePresence: true,
          );
          if (!await _isServerIdle()) {
            print('[ThumbnailWarmup] _runFullScanInternal: server no longer idle, aborting');
            completer.complete();
            return;
          }
        }

        cursor = page.nextCursor;
        if (!page.hasMore) {
          break;
        }
      } while (true);

      print('[ThumbnailWarmup] _runFullScanInternal: scanned ${seenPaths.length} items, cleaning orphans...');
      await _cleanupOrphanState(seenPaths);
      print('[ThumbnailWarmup] _runFullScanInternal: completed');
      completer.complete();
    } catch (error, stackTrace) {
      print('[ThumbnailWarmup] _runFullScanInternal: ERROR $error');
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _runFuture = null;
      _currentProcessingFile = null;
      _notifyProgress();
    }
  }

  Future<void> _cleanupOrphanState(Set<String> activeRelativePaths) async {
    final database = await _requireDatabase();
    final rows = await database.rawQuery(
      'SELECT DISTINCT relative_path FROM thumbnail_warmup_state',
    );
    for (final row in rows) {
      if (!await _isServerIdle()) {
        return;
      }
      final relativePath = row['relative_path'] as String;
      if (!activeRelativePaths.contains(relativePath)) {
        await deletePathState(relativePath);
      }
    }
  }

  Future<void> _syncStateForCurrentSource({
    required String relativePath,
    required String category,
    required int sourceModifiedMs,
    required int sourceSizeBytes,
    required String dirtyReason,
    required bool validateCachePresence,
  }) async {
    final normalizedRelativePath = _normalizeRelativePath(relativePath);
    final database = await _requireDatabase();
    final existingRows = await _loadRowsForPath(normalizedRelativePath);
    final existingByVariant = <ThumbnailType, _WarmupStateRow>{
      for (final row in existingRows) row.variant: row,
    };
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final batch = database.batch();

    for (final variant in ThumbnailType.values) {
      if (_closed) {
        return;
      }
      final generatorVersion = _thumbnailService.generatorVersion(variant);
      final existing = existingByVariant[variant];
      final versionChanged =
          existing == null ||
          existing.sourceModifiedMs != sourceModifiedMs ||
          existing.sourceSizeBytes != sourceSizeBytes ||
          existing.generatorVersion != generatorVersion ||
          existing.category != category;
      if (existing != null && versionChanged) {
        await _thumbnailService.deleteThumbnailVariant(
          _toServerFilePath(normalizedRelativePath),
          variant,
          sourceModifiedMs: existing.sourceModifiedMs,
          sourceSizeBytes: existing.sourceSizeBytes,
        );
      }

      var shouldGenerate =
          existing == null || existing.status != 'done' || versionChanged;
      if (!shouldGenerate && validateCachePresence) {
        shouldGenerate =
            await _thumbnailService.getThumbnail(
              _toServerFilePath(normalizedRelativePath),
              variant,
            ) ==
            null;
      }

      batch.insert(
        'thumbnail_warmup_state',
        <String, Object?>{
          'relative_path': normalizedRelativePath,
          'category': category,
          'variant': variant.name,
          'source_size_bytes': sourceSizeBytes,
          'source_modified_ms': sourceModifiedMs,
          'generator_version': generatorVersion,
          'status': shouldGenerate ? 'pending' : 'done',
          'dirty_reason': shouldGenerate ? dirtyReason : null,
          'fail_count': shouldGenerate ? 0 : (existing?.failCount ?? 0),
          'last_generated_ms': existing?.lastGeneratedMs,
          'last_checked_ms': nowMs,
          'next_retry_ms': null,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<bool> _isServerIdle() async {
    if (_closed) {
      return false;
    }
    final hasConnections = _realtimeConnectionRegistry.hasConnections;
    print('[ThumbnailWarmup] _isServerIdle: hasConnections=$hasConnections');
    return !hasConnections;
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
        version: 2,
        onCreate: (database, _) async {
          await _createTables(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute(
              'ALTER TABLE thumbnail_warmup_state ADD COLUMN next_retry_ms INTEGER',
            );
          }
        },
      ),
    );
  }

  Future<void> _createTables(sqflite.Database database) async {
    await database.execute('''
CREATE TABLE thumbnail_warmup_state (
  relative_path TEXT NOT NULL,
  category TEXT NOT NULL,
  variant TEXT NOT NULL,
  source_size_bytes INTEGER NOT NULL,
  source_modified_ms INTEGER NOT NULL,
  generator_version TEXT NOT NULL,
  status TEXT NOT NULL,
  dirty_reason TEXT,
  fail_count INTEGER NOT NULL DEFAULT 0,
  last_generated_ms INTEGER,
  last_checked_ms INTEGER,
  next_retry_ms INTEGER,
  PRIMARY KEY (relative_path, variant)
)
''');
    await database.execute('''
CREATE INDEX idx_thumbnail_warmup_status
ON thumbnail_warmup_state(status, next_retry_ms, last_checked_ms, relative_path COLLATE NOCASE)
''');
    await database.execute('''
CREATE INDEX idx_thumbnail_warmup_variant_priority
ON thumbnail_warmup_state(variant, status, next_retry_ms, last_checked_ms)
''');
    await database.execute('''
CREATE TABLE thumbnail_warmup_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
  }

  Future<void> _migrateDatabaseIfNeeded() async {
    final database = await _requireDatabase();
    final columns = await database.rawQuery(
      "PRAGMA table_info(thumbnail_warmup_state)",
    );
    final hasNextRetry = columns.any((c) => c['name'] == 'next_retry_ms');
    if (!hasNextRetry) {
      await database.execute(
        'ALTER TABLE thumbnail_warmup_state ADD COLUMN next_retry_ms INTEGER',
      );
    }
  }

  Future<void> _resetRunningStates() async {
    final database = await _requireDatabase();
    await database.update(
      'thumbnail_warmup_state',
      <String, Object?>{'status': 'pending'},
      where: 'status = ?',
      whereArgs: const <Object?>['running'],
    );
  }

  Future<List<_WarmupStateRow>> _loadRowsForPath(String relativePath) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      'thumbnail_warmup_state',
      where: 'relative_path = ?',
      whereArgs: <Object?>[relativePath],
    );
    return rows.map(_WarmupStateRow.fromMap).toList(growable: false);
  }

  Future<sqflite.Database> _requireDatabase() async {
    final database = _database;
    if (database == null) {
      throw StateError(
        'Thumbnail warmup database has not been initialized yet.',
      );
    }
    return database;
  }

  void _schedulePump([Duration delay = const Duration(seconds: 5)]) {
    if (_closed) {
      print('[ThumbnailWarmup] _schedulePump: service closed, not scheduling');
      return;
    }
    _scheduledPumpTimer?.cancel();
    print('[ThumbnailWarmup] _schedulePump: scheduling pump in ${delay.inSeconds}s');
    _scheduledPumpTimer = Timer(delay, () {
      print('[ThumbnailWarmup] _schedulePump: timer fired, calling processPendingNow');
      unawaited(processPendingNow());
    });
  }

  void _notifyProgress() {
    if (_statusController.isClosed) return;
    unawaited(() async {
      final progress = await getCurrentProgress();
      _statusController.add(progress);
    }());
  }

  String _normalizeRelativePath(String relativePath) {
    var normalized = relativePath.replaceAll('\\', '/').trim();
    if (normalized.startsWith('/fs/')) {
      normalized = normalized.substring(3);
    } else if (normalized == '/fs') {
      normalized = '/';
    }
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    return normalized;
  }

  String _toLocalPath(String relativePath) {
    final segments = _normalizeRelativePath(
      relativePath,
    ).split('/').where((segment) => segment.isNotEmpty);
    return p.joinAll(<String>[_rootPath, ...segments]);
  }

  String _toServerFilePath(String relativePath) {
    return '/fs${_normalizeRelativePath(relativePath)}';
  }

  bool _shouldSkipRelativePath(String relativePath) {
    final segments = _normalizeRelativePath(
      relativePath,
    ).split('/').where((segment) => segment.isNotEmpty);
    for (final segment in segments) {
      if (segment == '.thumbs' ||
          segment == '.relay' ||
          segment.startsWith('.nas-upload-')) {
        return true;
      }
    }
    return false;
  }

  bool _isWarmupCategory(String category) {
    return category == 'photo' || category == 'video';
  }

  String _resolveCategory(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    if (const {
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
    }.contains(ext)) {
      return 'photo';
    }
    if (const {
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.wmv',
      '.webm',
      '.3gp',
    }.contains(ext)) {
      return 'video';
    }
    return 'other';
  }
}

class _WarmupStateRow {
  const _WarmupStateRow({
    required this.relativePath,
    required this.category,
    required this.variant,
    required this.sourceSizeBytes,
    required this.sourceModifiedMs,
    required this.generatorVersion,
    required this.status,
    required this.failCount,
    this.lastGeneratedMs,
    this.nextRetryMs,
  });

  factory _WarmupStateRow.fromMap(Map<String, Object?> row) {
    return _WarmupStateRow(
      relativePath: row['relative_path'] as String,
      category: row['category'] as String,
      variant: ThumbnailType.values.byName(row['variant'] as String),
      sourceSizeBytes: row['source_size_bytes'] as int,
      sourceModifiedMs: row['source_modified_ms'] as int,
      generatorVersion: row['generator_version'] as String,
      status: row['status'] as String,
      failCount: row['fail_count'] as int? ?? 0,
      lastGeneratedMs: row['last_generated_ms'] as int?,
      nextRetryMs: row['next_retry_ms'] as int?,
    );
  }

  final String relativePath;
  final String category;
  final ThumbnailType variant;
  final int sourceSizeBytes;
  final int sourceModifiedMs;
  final String generatorVersion;
  final String status;
  final int failCount;
  final int? lastGeneratedMs;
  final int? nextRetryMs;
}
