import 'dart:io';

import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Resolves the SQLite database factory for the current platform.
class PlatformSqlite {
  PlatformSqlite._();

  static bool _isInitialized = false;

  static sqflite.DatabaseFactory resolveDatabaseFactory() {
    if (Platform.isAndroid || Platform.isIOS) {
      return sqflite.databaseFactory;
    }
    ensureInitialized();
    return databaseFactoryFfi;
  }

  static void ensureInitialized() {
    if (Platform.isAndroid || Platform.isIOS) {
      return;
    }
    if (_isInitialized) {
      return;
    }
    sqfliteFfiInit();
    _isInitialized = true;
  }
}
