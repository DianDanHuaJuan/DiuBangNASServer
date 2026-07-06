import 'dart:io';

import 'package:nas_server/core/auth/auth_session_store.dart';
import 'package:nas_server/core/auth/owner_credential_store.dart';
import 'package:nas_server/core/device_registry/device_store.dart';
import 'package:path/path.dart' as path;

import 'in_memory_secure_key_value_store.dart';

class TestDeviceStoreHarness {
  TestDeviceStoreHarness._({
    required this.storage,
    required Directory databaseDirectory,
  }) : _databaseDirectory = databaseDirectory;

  final InMemorySecureKeyValueStore storage;
  final Directory _databaseDirectory;
  final List<DeviceStore> _deviceStores = <DeviceStore>[];
  final List<OwnerCredentialStore> _ownerStores = <OwnerCredentialStore>[];

  String get deviceDatabasePath =>
      path.join(_databaseDirectory.path, 'device_store_test.db');

  String get ownerDatabasePath =>
      path.join(_databaseDirectory.path, 'owner_store_test.db');

  static Future<TestDeviceStoreHarness> create({
    InMemorySecureKeyValueStore? storage,
  }) async {
    final databaseDirectory = await Directory.systemTemp.createTemp(
      'nas_device_store_',
    );
    return TestDeviceStoreHarness._(
      storage: storage ?? InMemorySecureKeyValueStore(),
      databaseDirectory: databaseDirectory,
    );
  }

  DeviceStore createDeviceStore() {
    final store = DeviceStore(
      storage: storage,
      databasePathProvider: () async => deviceDatabasePath,
    );
    _deviceStores.add(store);
    return store;
  }

  OwnerCredentialStore createOwnerCredentialStore() {
    final store = OwnerCredentialStore(
      storage: storage,
      databasePathProvider: () async => ownerDatabasePath,
    );
    _ownerStores.add(store);
    return store;
  }

  Future<AuthSessionStore> createAuthSessionStore({
    DeviceStore? deviceStore,
    OwnerCredentialStore? ownerCredentialStore,
  }) async {
    final devices = deviceStore ?? createDeviceStore();
    final owner = ownerCredentialStore ?? createOwnerCredentialStore();
    await devices.initialize();
    await owner.initialize();
    return AuthSessionStore(
      ownerStateValidator: owner.isOwnerSessionVersionValid,
      deviceStateValidator: devices.isDeviceCredentialVersionValid,
      deviceTokenService: await devices.requireTokenService(),
    );
  }

  Future<AuthSessionStore> createDeviceAuthSessionStore({
    required DeviceStore deviceStore,
  }) async {
    await deviceStore.initialize();
    return AuthSessionStore(
      deviceStateValidator: deviceStore.isDeviceCredentialVersionValid,
      deviceTokenService: await deviceStore.requireTokenService(),
    );
  }

  Future<void> dispose() async {
    for (final store in _deviceStores) {
      await store.dispose();
    }
    for (final store in _ownerStores) {
      await store.dispose();
    }
    if (await _databaseDirectory.exists()) {
      await _databaseDirectory.delete(recursive: true);
    }
  }
}
