import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../storage/platform_sqlite.dart';

import 'secure_key_value_store.dart';

class OwnerCredentialStore {
  OwnerCredentialStore({
    SecureKeyValueStore? storage,
    Future<String> Function()? databasePathProvider,
    sqflite.DatabaseFactory? databaseFactory,
    Random? random,
  }) : _storage = storage ?? FlutterSecureKeyValueStore(),
       _databasePathProvider = databasePathProvider,
       _databaseFactory = databaseFactory,
       _random = random ?? Random.secure();

  final SecureKeyValueStore _storage;
  final Future<String> Function()? _databasePathProvider;
  final sqflite.DatabaseFactory? _databaseFactory;
  final Random _random;

  static const String _databasePathKey = 'owner_account_database_path_v1';
  static const String _databaseFileName = 'nas_owner.db';
  static const String _defaultUsername = 'admin';
  static const String _defaultPassword = 'admin';
  static const String _defaultOwnerLabel = '服务器管理员';
  static const String _passwordHashVersion = 'pbkdf2-sha256-v1';
  static const int _passwordSaltLength = 16;
  static const int _passwordHashIterations = 10000;
  static const int _passwordHashBits = 256;

  static final Pbkdf2 _passwordHasher = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _passwordHashIterations,
    bits: _passwordHashBits,
  );

  sqflite.Database? _database;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  Future<void> initialize() {
    if (_isInitialized) {
      return Future<void>.value();
    }

    final initializationFuture = _initializationFuture;
    if (initializationFuture != null) {
      return initializationFuture;
    }

    final future = _initializeInternal();
    _initializationFuture = future;
    return future;
  }

  Future<void> _initializeInternal() async {
    sqflite.Database? database;
    try {
      database = await _openDatabase();
      final owner = await _findOwnerInDatabase(database);
      if (owner == null) {
        await _insertOwnerInDatabase(
          database,
          username: _defaultUsername,
          password: _defaultPassword,
          label: _defaultOwnerLabel,
        );
      }
      _database = database;
      _isInitialized = true;
    } catch (_) {
      await database?.close();
      rethrow;
    } finally {
      _initializationFuture = null;
    }
  }

  Future<OwnerAuthenticationResult> authenticate({
    required String username,
    required String password,
  }) async {
    final owner = await _findOwner();
    if (owner == null ||
        owner.username != _normalizeUsername(username) ||
        !await _verifyPassword(owner, password)) {
      return const OwnerAuthenticationResult.failure(
        code: 'AUTH_INVALID',
        message: 'Invalid username or password',
      );
    }

    return OwnerAuthenticationResult.success(
      AuthenticatedOwner(
        ownerId: owner.ownerId,
        username: owner.username,
        label: owner.label,
        credentialVersion: owner.credentialVersion,
      ),
    );
  }

  Future<String?> getOwnerUsername() async {
    return (await _findOwner())?.username;
  }

  Future<bool> isUsingDefaultOwnerCredential() async {
    final owner = await _findOwner();
    if (owner == null) {
      return true;
    }
    return owner.username == _defaultUsername &&
        await _verifyPassword(owner, _defaultPassword);
  }

  Future<bool> verifyOwnerPassword(String password) async {
    final owner = await _findOwner();
    return owner != null && await _verifyPassword(owner, password);
  }

  Future<bool> verifyOwnerCredential({
    required String username,
    required String password,
  }) async {
    final owner = await _findOwner();
    return owner != null &&
        owner.username == _normalizeUsername(username) &&
        await _verifyPassword(owner, password);
  }

  Future<void> updateOwnerCredential({
    required String username,
    required String password,
  }) async {
    final owner = await _requireOwner();
    final database = await _requireDatabase();
    final normalizedUsername = _normalizeUsername(username);
    final protected = await _protectPassword(password);
    final now = DateTime.now().toUtc();
    await database.update(
      'owner_account',
      {
        'username': normalizedUsername,
        'label': owner.label,
        'password_hash': protected.hash,
        'password_salt': protected.salt,
        'credential_version': _nextCredentialVersion(),
        'updated_at': now.toIso8601String(),
      },
      where: 'owner_id = ?',
      whereArgs: [owner.ownerId],
    );
  }

  Future<bool> isOwnerSessionVersionValid({
    required String ownerId,
    required String credentialVersion,
  }) async {
    final owner = await _findOwner();
    return owner != null &&
        owner.ownerId == ownerId &&
        owner.credentialVersion == credentialVersion;
  }

  (String, String)? decodeBasicAuth(String authHeader) {
    if (!authHeader.startsWith('Basic ')) {
      return null;
    }
    try {
      final decoded = utf8.decode(
        base64.decode(authHeader.substring(6).trim()),
      );
      final separatorIndex = decoded.indexOf(':');
      if (separatorIndex <= 0) {
        return null;
      }
      return (
        decoded.substring(0, separatorIndex),
        decoded.substring(separatorIndex + 1),
      );
    } on FormatException {
      return null;
    }
  }

  String encodeBasicAuth(String username, String password) {
    return 'Basic ${base64.encode(utf8.encode('$username:$password'))}';
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
    _initializationFuture = null;
  }

  Future<_OwnerRecord> _requireOwner() async {
    final owner = await _findOwner();
    if (owner == null) {
      throw StateError('Owner account is not initialized');
    }
    return owner;
  }

  Future<_OwnerRecord?> _findOwner() async {
    final database = await _requireDatabase();
    return _findOwnerInDatabase(database);
  }

  Future<_OwnerRecord?> _findOwnerInDatabase(sqflite.Database database) async {
    final rows = await database.query('owner_account', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    return _mapOwnerRow(rows.first);
  }

  Future<void> _insertOwnerInDatabase(
    sqflite.Database database, {
    required String username,
    required String password,
    required String label,
  }) async {
    final protected = await _protectPassword(password);
    final now = DateTime.now().toUtc();
    await database.insert('owner_account', {
      'owner_id': _nextOwnerId(),
      'username': _normalizeUsername(username),
      'label': label,
      'password_hash_version': _passwordHashVersion,
      'password_hash': protected.hash,
      'password_salt': protected.salt,
      'credential_version': _nextCredentialVersion(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  Future<sqflite.Database> _requireDatabase() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _database!;
  }

  Future<sqflite.Database> _openDatabase() async {
    final databasePath = await _resolveDatabasePath();
    final factory = _databaseFactory ?? _resolveDatabaseFactory();
    return factory.openDatabase(
      databasePath,
      options: sqflite.OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE owner_account (
  owner_id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  password_hash_version TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  credential_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
        },
      ),
    );
  }

  static sqflite.DatabaseFactory _resolveDatabaseFactory() {
    return PlatformSqlite.resolveDatabaseFactory();
  }

  Future<String> _resolveDatabasePath() async {
    if (_databasePathProvider != null) {
      return _databasePathProvider();
    }

    final storedPath = await _storage.read(key: _databasePathKey);
    if (storedPath != null && storedPath.isNotEmpty) {
      return storedPath;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final databasePath = path.join(supportDirectory.path, _databaseFileName);
    await _storage.write(key: _databasePathKey, value: databasePath);
    return databasePath;
  }

  _OwnerRecord _mapOwnerRow(Map<String, Object?> row) {
    return _OwnerRecord(
      ownerId: row['owner_id'] as String,
      username: row['username'] as String,
      label: row['label'] as String,
      passwordHash: row['password_hash'] as String,
      passwordSalt: row['password_salt'] as String,
      credentialVersion: row['credential_version'] as String,
    );
  }

  Future<_ProtectedPassword> _protectPassword(String password) async {
    final salt = _randomBytes(_passwordSaltLength);
    final passwordHash = await _derivePasswordHash(password, salt);
    return _ProtectedPassword(
      hash: _encodeBytes(passwordHash),
      salt: _encodeBytes(salt),
    );
  }

  Future<Uint8List> _derivePasswordHash(String password, Uint8List salt) async {
    final derivedKey = await _passwordHasher.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await derivedKey.extractBytes());
  }

  Future<bool> _verifyPassword(_OwnerRecord owner, String candidate) async {
    final candidateHash = await _derivePasswordHash(
      candidate,
      _decodeBytes(owner.passwordSalt),
    );
    return _constantTimeEquals(_decodeBytes(owner.passwordHash), candidateHash);
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  String _encodeBytes(List<int> bytes) => base64.encode(bytes);

  Uint8List _decodeBytes(String encoded) =>
      Uint8List.fromList(base64.decode(encoded));

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var diff = 0;
    for (var index = 0; index < left.length; index++) {
      diff |= left[index] ^ right[index];
    }
    return diff == 0;
  }

  String _normalizeUsername(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Username must not be empty');
    }
    return trimmed;
  }

  String _nextOwnerId() {
    return 'owner_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }

  String _nextCredentialVersion() {
    return 'cv_${DateTime.now().toUtc().microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(16)}';
  }
}

class AuthenticatedOwner {
  const AuthenticatedOwner({
    required this.ownerId,
    required this.username,
    required this.label,
    required this.credentialVersion,
  });

  final String ownerId;
  final String username;
  final String label;
  final String credentialVersion;
}

class OwnerAuthenticationResult {
  const OwnerAuthenticationResult._({
    this.owner,
    this.failureCode,
    this.failureMessage,
  });

  const OwnerAuthenticationResult.success(AuthenticatedOwner owner)
    : this._(owner: owner);

  const OwnerAuthenticationResult.failure({
    required String code,
    required String message,
  }) : this._(failureCode: code, failureMessage: message);

  final AuthenticatedOwner? owner;
  final String? failureCode;
  final String? failureMessage;

  bool get isSuccess => owner != null;
}

class _OwnerRecord {
  const _OwnerRecord({
    required this.ownerId,
    required this.username,
    required this.label,
    required this.passwordHash,
    required this.passwordSalt,
    required this.credentialVersion,
  });

  final String ownerId;
  final String username;
  final String label;
  final String passwordHash;
  final String passwordSalt;
  final String credentialVersion;
}

class _ProtectedPassword {
  const _ProtectedPassword({required this.hash, required this.salt});

  final String hash;
  final String salt;
}
