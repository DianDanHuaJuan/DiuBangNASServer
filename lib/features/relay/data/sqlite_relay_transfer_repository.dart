import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/storage/platform_sqlite.dart';

import '../domain/relay_models.dart';
import 'relay_transfer_repository.dart';

class SqliteRelayTransferRepository implements RelayTransferRepository {
  SqliteRelayTransferRepository({
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
        version: 2,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, _) async {
          await _createSchema(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await database.execute(
              "ALTER TABLE relay_transfer_artifacts ADD COLUMN thumbnail_path TEXT",
            );
          }
        },
      ),
    );
  }

  @override
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  @override
  Future<void> createTransfer(RelayTransferAggregate aggregate) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await txn.insert(
        'relay_transfers',
        _mapTransferValues(aggregate.transfer),
      );
      for (final target in aggregate.targets) {
        await txn.insert('relay_transfer_targets', _mapTargetValues(target));
      }
      await txn.insert(
        'relay_transfer_artifacts',
        _mapArtifactValues(aggregate.artifact),
      );
    });
  }

  @override
  Future<RelayTransferAggregate?> findTransferById(String transferId) async {
    final database = await _requireDatabase();
    return _loadTransferAggregate(database, transferId);
  }

  @override
  Future<List<RelayTransferAggregate>> listTransfers({
    String? participantClientId,
    int limit = 100,
  }) async {
    final database = await _requireDatabase();
    final transferIds = participantClientId == null
        ? await _listTransferIds(database, limit: limit)
        : await _listParticipantTransferIds(
            database,
            participantClientId: participantClientId,
            limit: limit,
          );
    return _loadTransferAggregates(database, transferIds);
  }

  @override
  Future<List<RelayTransferAggregate>> listPeerTransfers({
    required String selfClientId,
    required String peerClientId,
    required int limit,
    DateTime? beforeCreatedAt,
  }) async {
    final database = await _requireDatabase();
    final transferIds = await _listPeerTransferIds(
      database,
      selfClientId: selfClientId,
      peerClientId: peerClientId,
      limit: limit,
      beforeCreatedAt: beforeCreatedAt,
    );
    return _loadTransferAggregates(database, transferIds);
  }

  @override
  Future<int> sumRetainedBytes() async {
    final database = await _requireDatabase();
    final rows = await database.rawQuery(
      '''
SELECT COALESCE(SUM(t.file_size), 0) AS total_bytes
FROM relay_transfers t
JOIN relay_transfer_artifacts a ON a.transfer_id = t.transfer_id
WHERE a.cleanup_state != ?
''',
      <Object?>[RelayArtifactCleanupState.deleted.name],
    );
    return (rows.first['total_bytes'] as int?) ?? 0;
  }

  @override
  Future<void> updateUploadProgress({
    required String transferId,
    required RelayTransferStatus status,
    required int chunkCount,
    required int receivedBytes,
    required DateTime updatedAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      final transfer = await _findTransfer(txn, transferId);
      if (transfer == null) {
        throw StateError('Transfer $transferId does not exist');
      }
      final effectiveStatus =
          transfer.status == RelayTransferStatus.downloading ||
              transfer.status == RelayTransferStatus.completed
          ? transfer.status
          : status;
      await _updateTransfer(txn, transferId, <String, Object?>{
        'status': effectiveStatus.name,
        'updated_at': _encodeDateTime(updatedAt),
      });
      await _updateArtifact(txn, transferId, <String, Object?>{
        'chunk_count': chunkCount,
        'received_bytes': receivedBytes,
        'updated_at': _encodeDateTime(updatedAt),
      });
    });
  }

  @override
  Future<void> markTransferReady({
    required String transferId,
    required String sealedPath,
    required int chunkCount,
    required int receivedBytes,
    required DateTime readyAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      final transfer = await _findTransfer(txn, transferId);
      if (transfer == null) {
        throw StateError('Transfer $transferId does not exist');
      }
      final targets = await _listTargets(txn, transferId);
      final hasDownloadingTarget = targets.any(
        (target) =>
            target.deliveryState == RelayTransferTargetState.downloading,
      );
      final hasCompletedTarget = targets.any(
        (target) => target.deliveryState == RelayTransferTargetState.completed,
      );
      final nextStatus = hasCompletedTarget
          ? RelayTransferStatus.completed
          : hasDownloadingTarget
          ? RelayTransferStatus.downloading
          : RelayTransferStatus.ready;
      await _updateTransfer(txn, transferId, <String, Object?>{
        'status': nextStatus.name,
        'updated_at': _encodeDateTime(readyAt),
        'ready_at': _encodeDateTime(readyAt),
        'completed_at': nextStatus == RelayTransferStatus.completed
            ? _encodeDateTime(transfer.completedAt ?? readyAt)
            : transfer.completedAt == null
            ? null
            : _encodeDateTime(transfer.completedAt),
        'failure_code': null,
        'failure_message': null,
      });
      await txn.update(
        'relay_transfer_targets',
        <String, Object?>{
          'delivery_state': RelayTransferTargetState.ready.name,
          'updated_at': _encodeDateTime(readyAt),
        },
        where: 'transfer_id = ? AND delivery_state = ?',
        whereArgs: <Object?>[transferId, RelayTransferTargetState.pending.name],
      );
      await _updateArtifact(txn, transferId, <String, Object?>{
        'sealed_path': sealedPath,
        'chunk_count': chunkCount,
        'received_bytes': receivedBytes,
        'is_sealed': 1,
        'cleanup_state': RelayArtifactCleanupState.sealed.name,
        'updated_at': _encodeDateTime(readyAt),
      });
    });
  }

  @override
  Future<void> markTransferDownloadStarted({
    required String transferId,
    required String receiverClientId,
    required DateTime startedAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      final target = await _findTarget(
        txn,
        transferId: transferId,
        receiverClientId: receiverClientId,
      );
      if (target == null) {
        throw StateError(
          'Transfer target $receiverClientId for $transferId does not exist',
        );
      }

      final nextState =
          target.deliveryState == RelayTransferTargetState.completed
          ? RelayTransferTargetState.completed
          : RelayTransferTargetState.downloading;
      await txn.update(
        'relay_transfer_targets',
        <String, Object?>{
          'delivery_state': nextState.name,
          'download_started_at': _encodeDateTime(
            target.downloadStartedAt ?? startedAt,
          ),
          'updated_at': _encodeDateTime(startedAt),
        },
        where: 'transfer_id = ? AND receiver_client_id = ?',
        whereArgs: <Object?>[transferId, receiverClientId],
      );

      final transfer = await _findTransfer(txn, transferId);
      if (transfer == null) {
        throw StateError('Transfer $transferId does not exist');
      }
      if (transfer.status != RelayTransferStatus.completed) {
        await _updateTransfer(txn, transferId, <String, Object?>{
          'status': RelayTransferStatus.downloading.name,
          'updated_at': _encodeDateTime(startedAt),
        });
      }
    });
  }

  @override
  Future<void> markTransferCompleted({
    required String transferId,
    required String receiverClientId,
    required DateTime completedAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      final target = await _findTarget(
        txn,
        transferId: transferId,
        receiverClientId: receiverClientId,
      );
      if (target == null) {
        throw StateError(
          'Transfer target $receiverClientId for $transferId does not exist',
        );
      }

      await txn.update(
        'relay_transfer_targets',
        <String, Object?>{
          'delivery_state': RelayTransferTargetState.completed.name,
          'download_started_at': _encodeDateTime(
            target.downloadStartedAt ?? completedAt,
          ),
          'download_completed_at': _encodeDateTime(completedAt),
          'updated_at': _encodeDateTime(completedAt),
        },
        where: 'transfer_id = ? AND receiver_client_id = ?',
        whereArgs: <Object?>[transferId, receiverClientId],
      );

      final rows = await txn.rawQuery(
        '''
SELECT COUNT(*) AS pending_targets
FROM relay_transfer_targets
WHERE transfer_id = ? AND delivery_state != ?
''',
        <Object?>[transferId, RelayTransferTargetState.completed.name],
      );
      final pendingTargets = (rows.first['pending_targets'] as int?) ?? 0;

      await _updateTransfer(txn, transferId, <String, Object?>{
        'status': pendingTargets == 0
            ? RelayTransferStatus.completed.name
            : RelayTransferStatus.downloading.name,
        'updated_at': _encodeDateTime(completedAt),
        'completed_at': pendingTargets == 0
            ? _encodeDateTime(completedAt)
            : null,
      });
    });
  }

  @override
  Future<void> markTransferCancelled({
    required String transferId,
    required DateTime cancelledAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await _setTransferTerminalState(
        txn,
        transferId: transferId,
        status: RelayTransferStatus.cancelled,
        targetState: RelayTransferTargetState.cancelled,
        timestampColumn: 'cancelled_at',
        timestamp: cancelledAt,
      );
    });
  }

  @override
  Future<void> markTransferFailed({
    required String transferId,
    required DateTime failedAt,
    required String failureCode,
    required String failureMessage,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await _setTransferTerminalState(
        txn,
        transferId: transferId,
        status: RelayTransferStatus.failed,
        targetState: RelayTransferTargetState.failed,
        timestampColumn: 'failed_at',
        timestamp: failedAt,
        extraTransferValues: <String, Object?>{
          'failure_code': failureCode,
          'failure_message': failureMessage,
        },
      );
    });
  }

  @override
  Future<void> markTransferExpired({
    required String transferId,
    required DateTime expiredAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await _setTransferTerminalState(
        txn,
        transferId: transferId,
        status: RelayTransferStatus.expired,
        targetState: RelayTransferTargetState.expired,
        timestampColumn: 'expired_at',
        timestamp: expiredAt,
      );
    });
  }

  @override
  Future<void> markTransferInterrupted({
    required String transferId,
    required DateTime interruptedAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await _setTransferTerminalState(
        txn,
        transferId: transferId,
        status: RelayTransferStatus.interrupted,
        targetState: RelayTransferTargetState.interrupted,
        timestampColumn: 'interrupted_at',
        timestamp: interruptedAt,
      );
    });
  }

  @override
  Future<List<RelayTransferAggregate>> listTransfersForStartupRecovery() async {
    final database = await _requireDatabase();
    final rows = await database.query(
      'relay_transfers',
      columns: const <String>['transfer_id'],
      where: 'status IN (?, ?, ?, ?)',
      whereArgs: <Object?>[
        RelayTransferStatus.created.name,
        RelayTransferStatus.uploading.name,
        RelayTransferStatus.ready.name,
        RelayTransferStatus.downloading.name,
      ],
      orderBy: 'created_at DESC',
    );
    return _loadTransferAggregates(
      database,
      rows.map((row) => row['transfer_id']! as String),
    );
  }

  @override
  Future<List<RelayTransferAggregate>> listExpiredTransfers(
    DateTime now,
  ) async {
    final database = await _requireDatabase();
    final rows = await database.rawQuery(
      '''
SELECT t.transfer_id
FROM relay_transfers t
JOIN relay_transfer_artifacts a ON a.transfer_id = t.transfer_id
WHERE t.expires_at <= ?
  AND a.cleanup_state != ?
  AND t.status NOT IN (?, ?, ?, ?)
ORDER BY t.created_at DESC
''',
      <Object?>[
        _encodeDateTime(now),
        RelayArtifactCleanupState.deleted.name,
        RelayTransferStatus.expired.name,
        RelayTransferStatus.ready.name,
        RelayTransferStatus.downloading.name,
        RelayTransferStatus.completed.name,
      ],
    );
    return _loadTransferAggregates(
      database,
      rows.map((row) => row['transfer_id']! as String),
    );
  }

  Future<sqflite.Database> _requireDatabase() async {
    final database = _database;
    if (database == null) {
      throw StateError('RelayTransferRepository.initialize() must be called');
    }
    return database;
  }

  Future<List<String>> _listTransferIds(
    sqflite.DatabaseExecutor executor, {
    required int limit,
  }) async {
    final rows = await executor.query(
      'relay_transfers',
      columns: const <String>['transfer_id'],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows
        .map((row) => row['transfer_id']! as String)
        .toList(growable: false);
  }

  Future<List<String>> _listParticipantTransferIds(
    sqflite.DatabaseExecutor executor, {
    required String participantClientId,
    required int limit,
  }) async {
    final rows = await executor.rawQuery(
      '''
SELECT DISTINCT t.transfer_id
FROM relay_transfers t
LEFT JOIN relay_transfer_targets tt ON tt.transfer_id = t.transfer_id
WHERE t.sender_client_id = ? OR tt.receiver_client_id = ?
ORDER BY t.created_at DESC
LIMIT $limit
''',
      <Object?>[participantClientId, participantClientId],
    );
    return rows
        .map((row) => row['transfer_id']! as String)
        .toList(growable: false);
  }

  Future<List<String>> _listPeerTransferIds(
    sqflite.DatabaseExecutor executor, {
    required String selfClientId,
    required String peerClientId,
    required int limit,
    DateTime? beforeCreatedAt,
  }) async {
    final beforeValue = beforeCreatedAt?.toUtc().toIso8601String();
    final rows = await executor.rawQuery(
      '''
SELECT DISTINCT t.transfer_id
FROM relay_transfers t
JOIN relay_transfer_targets tt ON tt.transfer_id = t.transfer_id
WHERE (
  (t.sender_client_id = ? AND tt.receiver_client_id = ?)
  OR (t.sender_client_id = ? AND tt.receiver_client_id = ?)
)
AND (? IS NULL OR t.created_at < ?)
ORDER BY t.created_at DESC
LIMIT $limit
''',
      <Object?>[
        selfClientId,
        peerClientId,
        peerClientId,
        selfClientId,
        beforeValue,
        beforeValue,
      ],
    );
    return rows
        .map((row) => row['transfer_id']! as String)
        .toList(growable: false);
  }

  Future<List<RelayTransferAggregate>> _loadTransferAggregates(
    sqflite.DatabaseExecutor executor,
    Iterable<String> transferIds,
  ) async {
    final aggregates = <RelayTransferAggregate>[];
    for (final transferId in transferIds) {
      final aggregate = await _loadTransferAggregate(executor, transferId);
      if (aggregate != null) {
        aggregates.add(aggregate);
      }
    }
    return aggregates;
  }

  Future<RelayTransferAggregate?> _loadTransferAggregate(
    sqflite.DatabaseExecutor executor,
    String transferId,
  ) async {
    final transfer = await _findTransfer(executor, transferId);
    if (transfer == null) {
      return null;
    }
    final targets = await _listTargets(executor, transferId);
    final artifact = await _findArtifact(executor, transferId);
    if (artifact == null) {
      throw StateError('Relay artifact $transferId does not exist');
    }
    return RelayTransferAggregate(
      transfer: transfer,
      targets: targets,
      artifact: artifact,
    );
  }

  Future<RelayTransferRecord?> _findTransfer(
    sqflite.DatabaseExecutor executor,
    String transferId,
  ) async {
    final rows = await executor.query(
      'relay_transfers',
      where: 'transfer_id = ?',
      whereArgs: <Object?>[transferId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapTransfer(rows.first);
  }

  Future<List<RelayTransferTargetRecord>> _listTargets(
    sqflite.DatabaseExecutor executor,
    String transferId,
  ) async {
    final rows = await executor.query(
      'relay_transfer_targets',
      where: 'transfer_id = ?',
      whereArgs: <Object?>[transferId],
      orderBy: 'receiver_client_id ASC',
    );
    return rows.map(_mapTarget).toList(growable: false);
  }

  Future<RelayTransferTargetRecord?> _findTarget(
    sqflite.DatabaseExecutor executor, {
    required String transferId,
    required String receiverClientId,
  }) async {
    final rows = await executor.query(
      'relay_transfer_targets',
      where: 'transfer_id = ? AND receiver_client_id = ?',
      whereArgs: <Object?>[transferId, receiverClientId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapTarget(rows.first);
  }

  Future<RelayTransferArtifactRecord?> _findArtifact(
    sqflite.DatabaseExecutor executor,
    String transferId,
  ) async {
    final rows = await executor.query(
      'relay_transfer_artifacts',
      where: 'transfer_id = ?',
      whereArgs: <Object?>[transferId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapArtifact(rows.first);
  }

  Future<void> _setTransferTerminalState(
    sqflite.Transaction txn, {
    required String transferId,
    required RelayTransferStatus status,
    required RelayTransferTargetState targetState,
    required String timestampColumn,
    required DateTime timestamp,
    Map<String, Object?> extraTransferValues = const <String, Object?>{},
  }) async {
    await _updateTransfer(txn, transferId, <String, Object?>{
      'status': status.name,
      'updated_at': _encodeDateTime(timestamp),
      timestampColumn: _encodeDateTime(timestamp),
      ...extraTransferValues,
    });
    await txn.update(
      'relay_transfer_targets',
      <String, Object?>{
        'delivery_state': targetState.name,
        'updated_at': _encodeDateTime(timestamp),
      },
      where: 'transfer_id = ?',
      whereArgs: <Object?>[transferId],
    );
    await _updateArtifact(txn, transferId, <String, Object?>{
      'cleanup_state': RelayArtifactCleanupState.deleted.name,
      'updated_at': _encodeDateTime(timestamp),
    });
  }

  Future<void> _updateTransfer(
    sqflite.Transaction txn,
    String transferId,
    Map<String, Object?> values,
  ) async {
    final affectedRows = await txn.update(
      'relay_transfers',
      values,
      where: 'transfer_id = ?',
      whereArgs: <Object?>[transferId],
    );
    if (affectedRows != 1) {
      throw StateError('Transfer $transferId does not exist');
    }
  }

  Future<void> _updateArtifact(
    sqflite.Transaction txn,
    String transferId,
    Map<String, Object?> values,
  ) async {
    final affectedRows = await txn.update(
      'relay_transfer_artifacts',
      values,
      where: 'transfer_id = ?',
      whereArgs: <Object?>[transferId],
    );
    if (affectedRows != 1) {
      throw StateError('Artifact $transferId does not exist');
    }
  }

  Map<String, Object?> _mapTransferValues(RelayTransferRecord transfer) {
    return <String, Object?>{
      'transfer_id': transfer.transferId,
      'sender_account_id': transfer.senderAccountId,
      'sender_label': transfer.senderLabel,
      'sender_client_id': transfer.senderClientId,
      'target_count': transfer.targetCount,
      'file_name': transfer.fileName,
      'mime_type': transfer.mimeType,
      'file_size': transfer.fileSize,
      'checksum': transfer.checksum,
      'checksum_algorithm': transfer.checksumAlgorithm,
      'chunk_size': transfer.chunkSize,
      'storage_mode': transfer.storageMode,
      'status': transfer.status.name,
      'retry_of_transfer_id': transfer.retryOfTransferId,
      'created_at': _encodeDateTime(transfer.createdAt),
      'updated_at': _encodeDateTime(transfer.updatedAt),
      'expires_at': _encodeDateTime(transfer.expiresAt),
      'expired_at': _encodeDateTime(transfer.expiredAt),
      'ready_at': _encodeDateTime(transfer.readyAt),
      'completed_at': _encodeDateTime(transfer.completedAt),
      'cancelled_at': _encodeDateTime(transfer.cancelledAt),
      'failed_at': _encodeDateTime(transfer.failedAt),
      'interrupted_at': _encodeDateTime(transfer.interruptedAt),
      'failure_code': transfer.failureCode,
      'failure_message': transfer.failureMessage,
    };
  }

  Map<String, Object?> _mapTargetValues(RelayTransferTargetRecord target) {
    return <String, Object?>{
      'transfer_id': target.transferId,
      'receiver_client_id': target.receiverClientId,
      'delivery_state': target.deliveryState.name,
      'delivered_at': _encodeDateTime(target.deliveredAt),
      'download_started_at': _encodeDateTime(target.downloadStartedAt),
      'download_completed_at': _encodeDateTime(target.downloadCompletedAt),
      'updated_at': _encodeDateTime(target.updatedAt),
    };
  }

  Map<String, Object?> _mapArtifactValues(
    RelayTransferArtifactRecord artifact,
  ) {
    return <String, Object?>{
      'transfer_id': artifact.transferId,
      'temp_path': artifact.tempPath,
      'sealed_path': artifact.sealedPath,
      'chunk_count': artifact.chunkCount,
      'received_bytes': artifact.receivedBytes,
      'is_sealed': artifact.isSealed ? 1 : 0,
      'cleanup_state': artifact.cleanupState.name,
      'updated_at': _encodeDateTime(artifact.updatedAt),
    };
  }

  RelayTransferRecord _mapTransfer(Map<String, Object?> row) {
    return RelayTransferRecord(
      transferId: row['transfer_id']! as String,
      senderAccountId: row['sender_account_id']! as String,
      senderLabel: row['sender_label']! as String,
      senderClientId: row['sender_client_id']! as String,
      targetCount: row['target_count']! as int,
      fileName: row['file_name']! as String,
      mimeType: row['mime_type'] as String?,
      fileSize: row['file_size']! as int,
      checksum: row['checksum'] as String?,
      checksumAlgorithm: row['checksum_algorithm']! as String,
      chunkSize: row['chunk_size']! as int,
      storageMode: row['storage_mode']! as String,
      status: _parseTransferStatus(row['status']! as String),
      retryOfTransferId: row['retry_of_transfer_id'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      expiresAt: DateTime.parse(row['expires_at']! as String).toUtc(),
      expiredAt: _parseDateTime(row['expired_at']),
      readyAt: _parseDateTime(row['ready_at']),
      completedAt: _parseDateTime(row['completed_at']),
      cancelledAt: _parseDateTime(row['cancelled_at']),
      failedAt: _parseDateTime(row['failed_at']),
      interruptedAt: _parseDateTime(row['interrupted_at']),
      failureCode: row['failure_code'] as String?,
      failureMessage: row['failure_message'] as String?,
    );
  }

  RelayTransferTargetRecord _mapTarget(Map<String, Object?> row) {
    return RelayTransferTargetRecord(
      transferId: row['transfer_id']! as String,
      receiverClientId: row['receiver_client_id']! as String,
      deliveryState: _parseTargetState(row['delivery_state']! as String),
      deliveredAt: _parseDateTime(row['delivered_at']),
      downloadStartedAt: _parseDateTime(row['download_started_at']),
      downloadCompletedAt: _parseDateTime(row['download_completed_at']),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    );
  }

  RelayTransferArtifactRecord _mapArtifact(Map<String, Object?> row) {
    return RelayTransferArtifactRecord(
      transferId: row['transfer_id']! as String,
      tempPath: row['temp_path']! as String,
      sealedPath: row['sealed_path'] as String?,
      chunkCount: row['chunk_count']! as int,
      receivedBytes: row['received_bytes']! as int,
      isSealed: (row['is_sealed']! as int) == 1,
      cleanupState: _parseCleanupState(row['cleanup_state']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    );
  }

  String? _encodeDateTime(DateTime? value) {
    return value?.toUtc().toIso8601String();
  }

  DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.parse(value).toUtc();
  }

  RelayTransferStatus _parseTransferStatus(String value) {
    return RelayTransferStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw StateError('Unknown relay transfer status: $value'),
    );
  }

  RelayTransferTargetState _parseTargetState(String value) {
    return RelayTransferTargetState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => throw StateError('Unknown relay target state: $value'),
    );
  }

  RelayArtifactCleanupState _parseCleanupState(String value) {
    return RelayArtifactCleanupState.values.firstWhere(
      (state) => state.name == value,
      orElse: () => throw StateError('Unknown relay cleanup state: $value'),
    );
  }

  @override
  Future<void> saveThumbnailPath({
    required String transferId,
    required String thumbnailPath,
    required DateTime updatedAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await _updateArtifact(txn, transferId, <String, Object?>{
        'thumbnail_path': thumbnailPath,
        'updated_at': _encodeDateTime(updatedAt),
      });
    });
  }

  @override
  Future<void> markArtifactDeleted({
    required String transferId,
    required DateTime deletedAt,
  }) async {
    final database = await _requireDatabase();
    await database.transaction((txn) async {
      await _updateArtifact(txn, transferId, <String, Object?>{
        'cleanup_state': RelayArtifactCleanupState.deleted.name,
        'updated_at': _encodeDateTime(deletedAt),
      });
    });
  }
}

Future<void> _createSchema(sqflite.DatabaseExecutor database) async {
  await database.execute('''
CREATE TABLE relay_transfers (
  transfer_id TEXT PRIMARY KEY,
  sender_account_id TEXT NOT NULL,
  sender_label TEXT NOT NULL,
  sender_client_id TEXT NOT NULL,
  target_count INTEGER NOT NULL,
  file_name TEXT NOT NULL,
  mime_type TEXT,
  file_size INTEGER NOT NULL,
  checksum TEXT,
  checksum_algorithm TEXT NOT NULL,
  chunk_size INTEGER NOT NULL,
  storage_mode TEXT NOT NULL,
  status TEXT NOT NULL,
  retry_of_transfer_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  expired_at TEXT,
  ready_at TEXT,
  completed_at TEXT,
  cancelled_at TEXT,
  failed_at TEXT,
  interrupted_at TEXT,
  failure_code TEXT,
  failure_message TEXT
)
''');
  await database.execute('''
CREATE TABLE relay_transfer_targets (
  transfer_id TEXT NOT NULL,
  receiver_client_id TEXT NOT NULL,
  delivery_state TEXT NOT NULL,
  delivered_at TEXT,
  download_started_at TEXT,
  download_completed_at TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (transfer_id, receiver_client_id),
  FOREIGN KEY(transfer_id) REFERENCES relay_transfers(transfer_id) ON DELETE CASCADE
)
''');
  await database.execute('''
CREATE TABLE relay_transfer_artifacts (
  transfer_id TEXT PRIMARY KEY,
  temp_path TEXT NOT NULL,
  sealed_path TEXT,
  chunk_count INTEGER NOT NULL,
  received_bytes INTEGER NOT NULL,
  is_sealed INTEGER NOT NULL,
  cleanup_state TEXT NOT NULL,
  thumbnail_path TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(transfer_id) REFERENCES relay_transfers(transfer_id) ON DELETE CASCADE
)
''');
  await database.execute(
    'CREATE INDEX idx_relay_transfers_sender_client_id ON relay_transfers(sender_client_id)',
  );
  await database.execute(
    'CREATE INDEX idx_relay_transfers_status ON relay_transfers(status)',
  );
  await database.execute(
    'CREATE INDEX idx_relay_transfers_expires_at ON relay_transfers(expires_at)',
  );
  await database.execute(
    'CREATE INDEX idx_relay_targets_receiver_client_id ON relay_transfer_targets(receiver_client_id)',
  );
  await database.execute(
    'CREATE INDEX idx_relay_artifacts_cleanup_state ON relay_transfer_artifacts(cleanup_state)',
  );
}
