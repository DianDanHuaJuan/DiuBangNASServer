import 'package:flutter_test/flutter_test.dart';

import '../../test_support/device_store_harness.dart';

void main() {
  group('OwnerCredentialStore', () {
    test('seeds the default owner during initialization', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final store = harness.createOwnerCredentialStore();

      await store.initialize();

      expect(await store.getOwnerUsername(), 'admin');
      expect(
        await store.verifyOwnerCredential(username: 'admin', password: 'admin'),
        isTrue,
      );
    });

    test('lazily initializes once for concurrent reads', () async {
      final harness = await TestDeviceStoreHarness.create();
      addTearDown(harness.dispose);
      final store = harness.createOwnerCredentialStore();

      final results = await Future.wait<Object?>([
        store.getOwnerUsername(),
        store.isUsingDefaultOwnerCredential(),
      ]);

      expect(results[0], 'admin');
      expect(results[1], isTrue);
    });
  });
}
