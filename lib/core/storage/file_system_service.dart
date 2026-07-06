// 文件输入：dart:io
// 文件职责：封装文件系统操作，提供目录创建、文件读写、容量查询等能力
// 文件对外接口：FileSystemService
// 文件包含：FileSystemService
import 'dart:io';
import 'package:path/path.dart' as p;

import 'share_internal_paths.dart';

enum SharedRootPathErrorCode {
  emptyPath,
  nonAbsolutePath,
  networkPathUnsupported,
  driveRootUnsupported,
  systemDirectoryUnsupported,
  userProfileRootUnsupported,
  reservedDirectoryUnsupported,
  missingDirectory,
  notDirectory,
  inaccessibleDirectory,
  notWritableDirectory,
}

class SharedRootPathException implements Exception {
  const SharedRootPathException(this.code, this.message);

  final SharedRootPathErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class FileSystemService {
  FileSystemService({Map<String, String>? environment, bool? isWindowsPlatform})
    : _environment = environment ?? Platform.environment,
      _isWindowsPlatform = isWindowsPlatform ?? Platform.isWindows;

  static const String defaultRootPath = '/sdcard/NASServer';
  static final _reservedShareRootDirectoryNames = {
    '.relay',
    '.thumbs',
    deviceAvatarLegacyFolderName,
  };

  final Map<String, String> _environment;
  final bool _isWindowsPlatform;

  String normalizeSharedRootPath(String rawPath) {
    final trimmedPath = rawPath.trim();
    if (trimmedPath.isEmpty) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.emptyPath,
        '共享目录不能为空。',
      );
    }

    final normalizedPath = _canonicalizeDirectoryPath(trimmedPath);
    if (!p.isAbsolute(normalizedPath)) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.nonAbsolutePath,
        '共享目录必须是本机绝对路径。',
      );
    }

    if (_isWindowsPlatform && _looksLikeNetworkSharePath(normalizedPath)) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.networkPathUnsupported,
        '共享目录暂不支持网络共享路径，请选择本机磁盘中的文件夹。',
      );
    }

    return normalizedPath;
  }

  bool pathsEqual(String left, String right) {
    final normalizedLeft = _canonicalizeDirectoryPath(left);
    final normalizedRight = _canonicalizeDirectoryPath(right);
    if (_isWindowsPlatform) {
      return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    }
    return normalizedLeft == normalizedRight;
  }

  Future<String> validateSharedRootPath(
    String rawPath, {
    bool createIfMissing = false,
  }) async {
    final normalizedPath = normalizeSharedRootPath(rawPath);
    final rootPrefix = _canonicalizeDirectoryPath(p.rootPrefix(normalizedPath));

    if (pathsEqual(normalizedPath, rootPrefix)) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.driveRootUnsupported,
        '共享目录不能直接设置为盘符根目录，请选择具体文件夹。',
      );
    }

    final shareRootName = p.basename(normalizedPath).toLowerCase();
    if (_reservedShareRootDirectoryNames.contains(shareRootName)) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.reservedDirectoryUnsupported,
        '共享目录不能指向应用内部保留目录。',
      );
    }

    _validateWindowsProtectedPaths(normalizedPath);

    var entityType = await FileSystemEntity.type(
      normalizedPath,
      followLinks: true,
    );
    if (entityType == FileSystemEntityType.notFound && createIfMissing) {
      await Directory(normalizedPath).create(recursive: true);
      entityType = await FileSystemEntity.type(
        normalizedPath,
        followLinks: true,
      );
    }

    if (entityType == FileSystemEntityType.notFound) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.missingDirectory,
        '共享目录不存在，请先创建该文件夹。',
      );
    }

    if (entityType != FileSystemEntityType.directory) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.notDirectory,
        '共享目录必须是文件夹，不能选择文件。',
      );
    }

    final directory = Directory(normalizedPath);
    try {
      await directory.list(followLinks: false).take(1).drain();
    } on FileSystemException {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.inaccessibleDirectory,
        '共享目录当前不可访问，请检查目录权限。',
      );
    }

    final probeFile = File(
      p.join(
        normalizedPath,
        '.nas-write-check-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await probeFile.writeAsString('ok', flush: true);
    } on FileSystemException {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.notWritableDirectory,
        '共享目录必须可读写，当前目录无法写入。',
      );
    } finally {
      if (await probeFile.exists()) {
        await probeFile.delete();
      }
    }

    return normalizedPath;
  }

  Future<void> ensureRootDirectory({String? rootPath}) async {
    try {
      final dir = Directory(rootPath ?? defaultRootPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      // Android 11+ 需要 MANAGE_EXTERNAL_STORAGE 权限
      // 启动时不强制创建，等服务启动时再处理
    }
  }

  String getRootPath({String? rootPath}) {
    return rootPath ?? defaultRootPath;
  }

  Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  Future<bool> directoryExists(String path) async {
    return Directory(path).exists();
  }

  Future<List<FileSystemEntity>> listDirectory(String path) async {
    final dir = Directory(path);
    return dir.list().toList();
  }

  Future<File> readFile(String path) async {
    return File(path);
  }

  Future<IOSink> writeFile(String path) async {
    final file = File(path);
    return file.openWrite();
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: recursive);
    }
  }

  Future<void> createDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<int> getFileSize(String path) async {
    final file = File(path);
    return file.length();
  }

  Future<DateTime> getLastModified(String path) async {
    final file = File(path);
    return file.lastModified();
  }

  String joinPath(String part1, String part2) {
    return p.join(part1, part2);
  }

  String getFileName(String path) {
    return p.basename(path);
  }

  String getParentPath(String path) {
    return p.dirname(path);
  }

  bool isAbsolute(String path) {
    return p.isAbsolute(path);
  }

  Future<StorageInfo> queryStorageCapacity({String? rootPath}) async {
    final targetPath = rootPath ?? defaultRootPath;
    try {
      final dir = Directory(targetPath);
      final stat = await dir.stat();
      final totalBytes = stat.size;
      return StorageInfo(totalBytes: totalBytes, usedBytes: 0, freeBytes: 0);
    } catch (e) {
      return const StorageInfo(totalBytes: 0, usedBytes: 0, freeBytes: 0);
    }
  }

  /// Migrate files whose filenames contain percent-encoding sequences (e.g. "%20")
  /// to decoded names. Returns number of renamed files.
  Future<int> migratePercentEncodedFilenames({String? rootPath}) async {
    final target = rootPath ?? defaultRootPath;
    final dir = Directory(target);
    if (!await dir.exists()) return 0;

    int renamed = 0;
    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (!name.contains('%')) continue;
        try {
          final decoded = Uri.decodeComponent(name);
          if (decoded == name) continue;
          final destBase = p.join(p.dirname(entity.path), decoded);
          var finalDest = destBase;
          var counter = 1;
          while (await File(finalDest).exists()) {
            final ext = p.extension(decoded);
            final base = p.basenameWithoutExtension(decoded);
            finalDest = p.join(p.dirname(entity.path), '$base ($counter)$ext');
            counter++;
          }
          await entity.rename(finalDest);
          renamed++;
        } catch (e) {
          // ignore invalid percent-encodings or rename failures
        }
      }
    }

    return renamed;
  }

  String _canonicalizeDirectoryPath(String path) {
    final normalizedPath = p.normalize(path.trim());
    final rootPrefix = p.rootPrefix(normalizedPath);
    var canonicalPath = normalizedPath;
    while (canonicalPath.length > rootPrefix.length &&
        (canonicalPath.endsWith(r'\') || canonicalPath.endsWith('/'))) {
      canonicalPath = canonicalPath.substring(0, canonicalPath.length - 1);
    }
    return canonicalPath;
  }

  bool _looksLikeNetworkSharePath(String path) {
    return path.startsWith(r'\\') || path.startsWith('//');
  }

  bool _isSameOrWithin(String parentPath, String candidatePath) {
    final normalizedParent = _canonicalizeDirectoryPath(parentPath);
    final normalizedCandidate = _canonicalizeDirectoryPath(candidatePath);
    if (pathsEqual(normalizedParent, normalizedCandidate)) {
      return true;
    }

    final comparableParent = _isWindowsPlatform
        ? normalizedParent.toLowerCase()
        : normalizedParent;
    final comparableCandidate = _isWindowsPlatform
        ? normalizedCandidate.toLowerCase()
        : normalizedCandidate;
    return comparableCandidate.startsWith('$comparableParent${p.separator}');
  }

  void _validateWindowsProtectedPaths(String normalizedPath) {
    if (!_isWindowsPlatform) {
      return;
    }

    final userProfile = _environment['USERPROFILE']?.trim();
    if (userProfile != null &&
        userProfile.isNotEmpty &&
        pathsEqual(normalizedPath, userProfile)) {
      throw const SharedRootPathException(
        SharedRootPathErrorCode.userProfileRootUnsupported,
        '共享目录不能直接设置为当前用户主目录，请选择其下的具体文件夹。',
      );
    }

    final systemDrive = _environment['SystemDrive']?.trim().isNotEmpty == true
        ? _environment['SystemDrive']!.trim()
        : p.rootPrefix(normalizedPath);
    final blockedDirectories = <String>[
      p.join(systemDrive, 'Windows'),
      p.join(systemDrive, 'Program Files'),
      p.join(systemDrive, 'Program Files (x86)'),
      p.join(systemDrive, 'ProgramData'),
      p.join(systemDrive, r'$Recycle.Bin'),
      p.join(systemDrive, 'System Volume Information'),
    ];

    for (final blockedDirectory in blockedDirectories) {
      if (_isSameOrWithin(blockedDirectory, normalizedPath)) {
        throw const SharedRootPathException(
          SharedRootPathErrorCode.systemDirectoryUnsupported,
          '共享目录不能设置为 Windows 系统目录或其子目录。',
        );
      }
    }
  }
}

class StorageInfo {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;

  const StorageInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
  });
}
