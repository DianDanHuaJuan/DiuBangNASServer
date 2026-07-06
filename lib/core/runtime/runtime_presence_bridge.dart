import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../app/di/service_locator.dart';
import '../../features/realtime/data/realtime_connection_registry.dart';
import '../../features/realtime/data/realtime_presence_repository.dart';
import '../../features/server/data/datasources/nas_foreground_task_contract.dart';
import '../platform/app_platform.dart';
import 'runtime_presence_snapshot.dart';

typedef RuntimePresenceStorage = Future<String?> Function(String key);
typedef RuntimePresenceWriter = Future<void> Function(String key, String value);
typedef RuntimePresenceRemover = Future<void> Function(String key);

class RuntimePresenceBridge {
  RuntimePresenceBridge({
    RuntimePresenceStorage? readStorage,
    RuntimePresenceWriter? writeStorage,
    RuntimePresenceRemover? removeStorage,
  }) : _usesCustomStorage =
           readStorage != null ||
           writeStorage != null ||
           removeStorage != null,
       _readStorage =
           readStorage ??
           ((key) => FlutterForegroundTask.getData<String>(key: key)),
       _writeStorage =
           writeStorage ??
           ((key, value) => FlutterForegroundTask.saveData(key: key, value: value)),
       _removeStorage =
           removeStorage ??
           ((key) => FlutterForegroundTask.removeData(key: key));

  static final RuntimePresenceBridge instance = RuntimePresenceBridge();

  final bool _usesCustomStorage;

  final RuntimePresenceStorage _readStorage;
  final RuntimePresenceWriter _writeStorage;
  final RuntimePresenceRemover _removeStorage;

  RuntimePresenceSnapshot _cached = RuntimePresenceSnapshot.empty();

  RuntimePresenceSnapshot get cached => _cached;

  bool get _shouldPersistAcrossIsolates =>
      _usesCustomStorage || AppPlatform.supportsForegroundService;

  bool get _shouldGateOnMainServerRunning =>
      _shouldPersistAcrossIsolates && !_usesCustomStorage;

  bool isOnline(String deviceId) {
    final repository = ServiceLocator.realtimePresenceRepository;
    if (repository != null) {
      return repository.isOnline(deviceId);
    }
    if (_shouldGateOnMainServerRunning && !ServiceLocator.isServerRunning) {
      return false;
    }
    return _cached.isOnline(deviceId);
  }

  int get connectedCount {
    final registry = ServiceLocator.realtimeConnectionRegistry;
    if (registry != null) {
      return registry.connections.length;
    }
    if (_shouldGateOnMainServerRunning && !ServiceLocator.isServerRunning) {
      return 0;
    }
    return _cached.connectedCount;
  }

  Future<void> publish({
    required Iterable<String> onlineDeviceIds,
    required int connectedCount,
  }) async {
    final snapshot = RuntimePresenceSnapshot(
      onlineDeviceIds: onlineDeviceIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet(),
      connectedCount: connectedCount,
      updatedAt: DateTime.now().toUtc(),
    );
    _cached = snapshot;
    if (!_shouldPersistAcrossIsolates) {
      return;
    }
    await _writeStorage(
      NasForegroundTaskContract.presenceSnapshotKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<void> publishFromRuntime({
    RealtimePresenceRepository? presenceRepository,
    RealtimeConnectionRegistry? connectionRegistry,
  }) async {
    final repository =
        presenceRepository ?? ServiceLocator.realtimePresenceRepository;
    final registry =
        connectionRegistry ?? ServiceLocator.realtimeConnectionRegistry;
    if (repository == null || registry == null) {
      await publish(onlineDeviceIds: const [], connectedCount: 0);
      return;
    }

    final onlineDeviceIds = repository
        .presenceSnapshot()
        .map((entry) => entry['deviceId']?.toString().trim() ?? '')
        .where((deviceId) => deviceId.isNotEmpty);
    await publish(
      onlineDeviceIds: onlineDeviceIds,
      connectedCount: registry.connections.length,
    );
  }

  Future<RuntimePresenceSnapshot> refresh() async {
    if (!_shouldPersistAcrossIsolates) {
      _cached = _snapshotFromLocalRuntime();
      return _cached;
    }

    if (!await _isSharedRuntimeRunning()) {
      await clear();
      return _cached;
    }

    final raw = await _readStorage(NasForegroundTaskContract.presenceSnapshotKey);
    if (raw == null || raw.trim().isEmpty) {
      _cached = RuntimePresenceSnapshot.empty();
      return _cached;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cached = RuntimePresenceSnapshot.fromJson(decoded);
      }
    } catch (_) {
      _cached = RuntimePresenceSnapshot.empty();
    }
    return _cached;
  }

  Future<void> clear() async {
    _cached = RuntimePresenceSnapshot.empty();
    if (!_shouldPersistAcrossIsolates) {
      return;
    }
    await _removeStorage(NasForegroundTaskContract.presenceSnapshotKey);
  }

  Future<bool> _isSharedRuntimeRunning() async {
    final runtimeState = await _readStorage(
      NasForegroundTaskContract.runtimeStateKey,
    );
    return runtimeState == NasForegroundTaskContract.stateRunning;
  }

  RuntimePresenceSnapshot _snapshotFromLocalRuntime() {
    final repository = ServiceLocator.realtimePresenceRepository;
    final registry = ServiceLocator.realtimeConnectionRegistry;
    if (repository == null || registry == null) {
      return RuntimePresenceSnapshot.empty();
    }

    final onlineDeviceIds = repository
        .presenceSnapshot()
        .map((entry) => entry['deviceId']?.toString().trim() ?? '')
        .where((deviceId) => deviceId.isNotEmpty)
        .toSet();
    return RuntimePresenceSnapshot(
      onlineDeviceIds: onlineDeviceIds,
      connectedCount: registry.connections.length,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}
