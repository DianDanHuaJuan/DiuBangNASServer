// 文件输入：文件路径、缩略图类型、MediaLibraryCache
// 文件职责：管理 /fs 和 /library 目录下文件的缩略图生成和缓存
// 文件对外接口：ThumbnailService
// 文件包含：ThumbnailService
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'media_library_thumbnail_lookup.dart';
import 'path_mapper.dart';
import 'thumbnail_native_service.dart';

enum ThumbnailType { grid, preview }

class ThumbnailService {
  ThumbnailService({
    required String rootPath,
    MediaLibraryThumbnailLookup? mediaLibraryLookup,
    ThumbnailNativeService? nativeService,
  }) : _rootPath = rootPath,
       _pathMapper = PathMapper(rootPath: rootPath),
       _mediaLibraryLookup = mediaLibraryLookup,
       _nativeService = nativeService ?? ThumbnailNativeService();

  final String _rootPath;
  final PathMapper _pathMapper;
  final MediaLibraryThumbnailLookup? _mediaLibraryLookup;
  final ThumbnailNativeService _nativeService;
  final Map<String, Future<Uint8List?>> _inFlightGenerations =
      <String, Future<Uint8List?>>{};
  static final HashAlgorithm _thumbnailHashAlgorithm = Sha256();
  static const _gridSize = 200;
  static const _previewSize = 800;
  static const _gridCacheVersion = 'v2-center-crop';
  static const _previewCacheVersion = 'v1-aspect-fit';

  String get _thumbRoot => p.join(_rootPath, '.thumbs');

  String _getThumbDir(ThumbnailType type) {
    final dir = type == ThumbnailType.grid ? 'grid' : 'preview';
    return p.join(_thumbRoot, dir);
  }

  String generatorVersion(ThumbnailType type) {
    return type == ThumbnailType.grid
        ? _gridCacheVersion
        : _previewCacheVersion;
  }

  /// 返回已存在的缩略图本地绝对路径；不存在则返回 null（不会触发生成）。
  Future<String?> getThumbnailPath(String filePath, ThumbnailType type) async {
    final mappedPath = _resolveFileSystemPath(filePath);
    if (mappedPath == null) {
      return null;
    }

    final sourceVersion = await _resolveSourceVersion(mappedPath);
    if (sourceVersion == null) {
      return null;
    }

    final thumbPath = await _getThumbPath(
      mappedPath,
      type,
      sourceModifiedMs: sourceVersion.modifiedMs,
      sourceSizeBytes: sourceVersion.sizeBytes,
    );

    return await File(thumbPath).exists() ? thumbPath : null;
  }

  Future<String> _getThumbPath(
    MappedServerPath mappedPath,
    ThumbnailType type, {
    required int sourceModifiedMs,
    required int sourceSizeBytes,
  }) async {
    final dir = _getThumbDir(type);
    final ext = p.extension(mappedPath.segments.last);
    final cacheKey = await _buildCacheKey(
      mappedPath,
      type,
      sourceModifiedMs: sourceModifiedMs,
      sourceSizeBytes: sourceSizeBytes,
    );
    return p.join(dir, '$cacheKey$ext.thumb');
  }

  bool _isImageFile(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);
  }

  bool _isVideoFile(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    return ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp'].contains(ext);
  }

  Future<Uint8List?> getThumbnail(String filePath, ThumbnailType type) async {
    final mappedPath = _resolveFileSystemPath(filePath);
    if (mappedPath == null) {
      return null;
    }

    final sourceVersion = await _resolveSourceVersion(mappedPath);
    if (sourceVersion == null) {
      return null;
    }

    final thumbPath = await _getThumbPath(
      mappedPath,
      type,
      sourceModifiedMs: sourceVersion.modifiedMs,
      sourceSizeBytes: sourceVersion.sizeBytes,
    );

    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      return await thumbFile.readAsBytes();
    }

    return null;
  }

  Future<Uint8List?> generateThumbnail(
    String filePath,
    ThumbnailType type,
  ) async {
    final mappedPath = _resolveFileSystemPath(filePath);
    if (mappedPath == null) {
      return null;
    }

    final sourceVersion = await _resolveSourceVersion(mappedPath);
    if (sourceVersion == null) {
      return null;
    }

    final fileName = mappedPath.segments.last;

    if (!_isImageFile(fileName) && !_isVideoFile(fileName)) {
      return null;
    }

    final size = type == ThumbnailType.grid ? _gridSize : _previewSize;

    try {
      final bytes = await _generateNativeThumbnail(mappedPath, type, size);
      if (bytes != null) {
        await _saveThumbnail(
          mappedPath,
          type,
          bytes,
          sourceModifiedMs: sourceVersion.modifiedMs,
          sourceSizeBytes: sourceVersion.sizeBytes,
        );
      }
      return bytes;
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> getOrGenerateThumbnail(
    String filePath,
    ThumbnailType type,
  ) async {
    if (filePath.startsWith('/library/')) {
      return _generateMediaStoreThumbnail(filePath, type);
    }

    final mappedPath = _resolveFileSystemPath(filePath);
    if (mappedPath == null) {
      return null;
    }

    final sourceVersion = await _resolveSourceVersion(mappedPath);
    if (sourceVersion == null) {
      return null;
    }

    final thumbPath = await _getThumbPath(
      mappedPath,
      type,
      sourceModifiedMs: sourceVersion.modifiedMs,
      sourceSizeBytes: sourceVersion.sizeBytes,
    );

    return _runSingleflight(thumbPath, () async {
      final cachedBytes = await _readThumbnailBytes(thumbPath);
      if (cachedBytes != null) {
        return cachedBytes;
      }

      final fileName = mappedPath.segments.last;
      if (!_isImageFile(fileName) && !_isVideoFile(fileName)) {
        return null;
      }

      final size = type == ThumbnailType.grid ? _gridSize : _previewSize;
      try {
        final bytes = await _generateNativeThumbnail(mappedPath, type, size);
        if (bytes != null) {
          await _saveThumbnail(
            mappedPath,
            type,
            bytes,
            sourceModifiedMs: sourceVersion.modifiedMs,
            sourceSizeBytes: sourceVersion.sizeBytes,
          );
        }
        return bytes;
      } catch (e) {
        return null;
      }
    });
  }

  Future<Uint8List?> _generateMediaStoreThumbnail(
    String libraryPath,
    ThumbnailType type,
  ) async {
    late final MappedServerPath mappedPath;
    try {
      mappedPath = const PathMapper().resolve(
        libraryPath,
        allowedRoots: const {ServerPathRoot.library},
        allowRoot: false,
        allowNestedPaths: false,
      );
    } on PathMappingException {
      return null;
    }

    final fileName = mappedPath.fileName!;

    if (!_isImageFile(fileName) && !_isVideoFile(fileName)) {
      return null;
    }

    final size = type == ThumbnailType.grid ? _gridSize : _previewSize;

    try {
      final lookup = _mediaLibraryLookup;
      if (lookup == null) {
        return null;
      }
      await lookup.ensureLoaded();

      final contentUri = lookup.findContentUriByFileName(fileName);
      if (contentUri == null || contentUri.isEmpty) {
        return null;
      }

      return await _nativeService.generateThumbnailFromUri(contentUri, size);
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveThumbnail(
    MappedServerPath mappedPath,
    ThumbnailType type,
    Uint8List bytes, {
    required int sourceModifiedMs,
    required int sourceSizeBytes,
  }) async {
    final dir = _getThumbDir(type);
    final dirObj = Directory(dir);
    if (!await dirObj.exists()) {
      await dirObj.create(recursive: true);
    }

    final thumbPath = await _getThumbPath(
      mappedPath,
      type,
      sourceModifiedMs: sourceModifiedMs,
      sourceSizeBytes: sourceSizeBytes,
    );
    final thumbFile = File(thumbPath);
    final tempFile = File(_buildTemporaryThumbPath(thumbPath));
    await tempFile.writeAsBytes(bytes, flush: true);
    if (await thumbFile.exists()) {
      await thumbFile.delete();
    }
    await tempFile.rename(thumbPath);
  }

  Future<Uint8List?> _generateNativeThumbnail(
    MappedServerPath mappedPath,
    ThumbnailType type,
    int size,
  ) async {
    final localPath = mappedPath.localPath!;
    return await _nativeService.generateThumbnail(
      localPath,
      size,
      cropSquare: type == ThumbnailType.grid,
    );
  }

  Future<void> deleteThumbnails(
    String filePath, {
    int? sourceModifiedMs,
    int? sourceSizeBytes,
  }) async {
    for (final type in ThumbnailType.values) {
      await deleteThumbnailVariant(
        filePath,
        type,
        sourceModifiedMs: sourceModifiedMs,
        sourceSizeBytes: sourceSizeBytes,
      );
    }
  }

  Future<void> deleteThumbnailVariant(
    String filePath,
    ThumbnailType type, {
    int? sourceModifiedMs,
    int? sourceSizeBytes,
  }) async {
    final mappedPath = _resolveFileSystemPath(filePath);
    if (mappedPath == null) {
      return;
    }

    final resolvedModifiedMs = sourceModifiedMs;
    final resolvedSizeBytes = sourceSizeBytes;
    if ((resolvedModifiedMs == null) != (resolvedSizeBytes == null)) {
      throw ArgumentError(
        'sourceModifiedMs and sourceSizeBytes must both be provided together.',
      );
    }

    final sourceVersion =
        resolvedModifiedMs != null && resolvedSizeBytes != null
        ? _ThumbnailSourceVersion(
            modifiedMs: resolvedModifiedMs,
            sizeBytes: resolvedSizeBytes,
          )
        : await _resolveSourceVersion(mappedPath);
    if (sourceVersion == null) {
      return;
    }

    final thumbPath = await _getThumbPath(
      mappedPath,
      type,
      sourceModifiedMs: sourceVersion.modifiedMs,
      sourceSizeBytes: sourceVersion.sizeBytes,
    );
    final file = File(thumbPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> clearAllThumbnails() async {
    final thumbDir = Directory(_thumbRoot);
    if (await thumbDir.exists()) {
      await thumbDir.delete(recursive: true);
    }
  }

  MappedServerPath? _resolveFileSystemPath(String filePath) {
    try {
      return _pathMapper.resolve(
        filePath,
        allowedRoots: const {ServerPathRoot.fs},
        allowRoot: false,
        allowNestedPaths: true,
      );
    } on PathMappingException {
      return null;
    }
  }

  Future<String> _buildCacheKey(
    MappedServerPath mappedPath,
    ThumbnailType type, {
    required int sourceModifiedMs,
    required int sourceSizeBytes,
  }) async {
    final version = generatorVersion(type);
    final digest = await _thumbnailHashAlgorithm.hash(
      utf8.encode(
        '$version:${type.name}:${mappedPath.relativePath}:$sourceModifiedMs:$sourceSizeBytes',
      ),
    );
    return digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Uint8List?> _readThumbnailBytes(String thumbPath) async {
    final thumbFile = File(thumbPath);
    if (!await thumbFile.exists()) {
      return null;
    }
    return thumbFile.readAsBytes();
  }

  Future<_ThumbnailSourceVersion?> _resolveSourceVersion(
    MappedServerPath mappedPath,
  ) async {
    final localPath = mappedPath.localPath;
    if (localPath == null) {
      return null;
    }
    final stat = await File(localPath).stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }
    return _ThumbnailSourceVersion(
      modifiedMs: stat.modified.millisecondsSinceEpoch,
      sizeBytes: stat.size,
    );
  }

  String _buildTemporaryThumbPath(String thumbPath) {
    return '$thumbPath.${DateTime.now().microsecondsSinceEpoch}.$pid.part';
  }

  Future<Uint8List?> _runSingleflight(
    String key,
    Future<Uint8List?> Function() action,
  ) async {
    final existing = _inFlightGenerations[key];
    if (existing != null) {
      return existing;
    }

    late final Future<Uint8List?> future;
    future = () async {
      try {
        return await action();
      } finally {
        if (identical(_inFlightGenerations[key], future)) {
          _inFlightGenerations.remove(key);
        }
      }
    }();
    _inFlightGenerations[key] = future;
    return future;
  }
}

class _ThumbnailSourceVersion {
  const _ThumbnailSourceVersion({
    required this.modifiedMs,
    required this.sizeBytes,
  });

  final int modifiedMs;
  final int sizeBytes;
}
