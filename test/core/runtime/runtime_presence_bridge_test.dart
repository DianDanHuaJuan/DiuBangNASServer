import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/runtime/runtime_presence_bridge.dart';
import 'package:nas_server/core/runtime/runtime_presence_snapshot.dart';
import 'package:nas_server/features/server/data/datasources/nas_foreground_task_contract.dart';

void main() {
  group('RuntimePresenceSnapshot', () {
    test('round-trips through json', () {
      final snapshot = RuntimePresenceSnapshot(
        onlineDeviceIds: {'tablet-01', 'phone-02'},
        connectedCount: 2,
        updatedAt: DateTime.utc(2026, 6, 5, 12, 30),
      );

      final restored = RuntimePresenceSnapshot.fromJson(snapshot.toJson());

      expect(restored.onlineDeviceIds, {'tablet-01', 'phone-02'});
      expect(restored.connectedCount, 2);
      expect(restored.updatedAt, DateTime.utc(2026, 6, 5, 12, 30));
      expect(restored.isOnline('tablet-01'), isTrue);
      expect(restored.isOnline('missing'), isFalse);
    });
  });

  group('RuntimePresenceBridge', () {
    Future<void> markRuntimeRunning(Map<String, String> storage) async {
      storage[NasForegroundTaskContract.runtimeStateKey] =
          NasForegroundTaskContract.stateRunning;
    }

    test('refresh reads published snapshot from shared storage', () async {
      final storage = <String, String>{};
      final bridge = RuntimePresenceBridge(
        readStorage: (key) async => storage[key],
        writeStorage: (key, value) async {
          storage[key] = value;
        },
        removeStorage: (key) async {
          storage.remove(key);
        },
      );

      await markRuntimeRunning(storage);
      await bridge.publish(
        onlineDeviceIds: const ['tablet-01'],
        connectedCount: 1,
      );

      final snapshot = await bridge.refresh();

      expect(snapshot.onlineDeviceIds, {'tablet-01'});
      expect(snapshot.connectedCount, 1);
      expect(bridge.isOnline('tablet-01'), isTrue);
      expect(bridge.connectedCount, 1);
      expect(
        storage.containsKey(NasForegroundTaskContract.presenceSnapshotKey),
        isTrue,
      );
    });

    test('refresh returns empty and clears stale snapshot when runtime stopped',
        () async {
      final storage = <String, String>{};
      final bridge = RuntimePresenceBridge(
        readStorage: (key) async => storage[key],
        writeStorage: (key, value) async {
          storage[key] = value;
        },
        removeStorage: (key) async {
          storage.remove(key);
        },
      );

      storage[NasForegroundTaskContract.presenceSnapshotKey] = jsonEncode(
        RuntimePresenceSnapshot(
          onlineDeviceIds: const {'tablet-01'},
          connectedCount: 1,
          updatedAt: DateTime.utc(2026, 6, 5, 12),
        ).toJson(),
      );
      storage[NasForegroundTaskContract.runtimeStateKey] =
          NasForegroundTaskContract.stateStopped;

      final snapshot = await bridge.refresh();

      expect(snapshot.onlineDeviceIds, isEmpty);
      expect(snapshot.connectedCount, 0);
      expect(bridge.isOnline('tablet-01'), isFalse);
      expect(bridge.connectedCount, 0);
      expect(
        storage.containsKey(NasForegroundTaskContract.presenceSnapshotKey),
        isFalse,
      );
    });

    test('clear removes cached snapshot', () async {
      final storage = <String, String>{};
      final bridge = RuntimePresenceBridge(
        readStorage: (key) async => storage[key],
        writeStorage: (key, value) async {
          storage[key] = value;
        },
        removeStorage: (key) async {
          storage.remove(key);
        },
      );

      await markRuntimeRunning(storage);
      await bridge.publish(
        onlineDeviceIds: const ['tablet-01'],
        connectedCount: 1,
      );
      await bridge.clear();
      final snapshot = await bridge.refresh();

      expect(snapshot.onlineDeviceIds, isEmpty);
      expect(snapshot.connectedCount, 0);
      expect(bridge.isOnline('tablet-01'), isFalse);
      expect(
        storage.containsKey(NasForegroundTaskContract.presenceSnapshotKey),
        isFalse,
      );
    });

    test('refresh ignores malformed json', () async {
      final storage = <String, String>{
        NasForegroundTaskContract.runtimeStateKey:
            NasForegroundTaskContract.stateRunning,
      };
      storage[NasForegroundTaskContract.presenceSnapshotKey] = '{not-json';
      final bridge = RuntimePresenceBridge(
        readStorage: (key) async => storage[key],
        writeStorage: (key, value) async {
          storage[key] = value;
        },
        removeStorage: (key) async {
          storage.remove(key);
        },
      );

      final snapshot = await bridge.refresh();

      expect(snapshot.onlineDeviceIds, isEmpty);
      expect(snapshot.connectedCount, 0);
    });

    test('publish stores sorted device ids', () async {
      final storage = <String, String>{};
      final bridge = RuntimePresenceBridge(
        readStorage: (key) async => storage[key],
        writeStorage: (key, value) async {
          storage[key] = value;
        },
        removeStorage: (key) async {
          storage.remove(key);
        },
      );

      await markRuntimeRunning(storage);
      await bridge.publish(
        onlineDeviceIds: const ['b-device', 'a-device'],
        connectedCount: 2,
      );

      final decoded =
          jsonDecode(storage[NasForegroundTaskContract.presenceSnapshotKey]!)
              as Map<String, dynamic>;
      expect(decoded['onlineDeviceIds'], ['a-device', 'b-device']);
    });
  });
}
