import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/storage/ffmpeg_locator.dart';

class VideoHlsSession {
  const VideoHlsSession({required this.id, required this.playlistPath});

  final String id;
  final String playlistPath;
}

class VideoHlsSessionService {
  VideoHlsSessionService({
    required String rootPath,
    FfmpegLocator ffmpegLocator = const FfmpegLocator(),
  }) : _sessionRoot = Directory(p.join(rootPath, '.relay', 'preview_hls')),
       _ffmpegLocator = ffmpegLocator;

  final Directory _sessionRoot;
  final FfmpegLocator _ffmpegLocator;
  final Map<String, _ManagedVideoHlsSession> _sessionsBySourceKey =
      <String, _ManagedVideoHlsSession>{};
  final Map<String, _ManagedVideoHlsSession> _sessionsById =
      <String, _ManagedVideoHlsSession>{};
  int _nextSessionId = 0;

  static const Duration _startupTimeout = Duration(seconds: 30);
  static const Duration _assetWaitTimeout = Duration(seconds: 15);
  static const Duration _sessionTtl = Duration(minutes: 20);
  static const Duration _pollInterval = Duration(milliseconds: 400);

  Future<VideoHlsSession> ensureSession({required String sourcePath}) async {
    await _cleanupExpiredSessions();

    final sourceFile = File(sourcePath);
    final stat = await sourceFile.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw StateError('Video source is not available for HLS transcoding.');
    }

    final sourceKey =
        '$sourcePath|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    var session = _sessionsBySourceKey[sourceKey];
    if (session == null) {
      final sessionId = 'hls_${++_nextSessionId}';
      final outputDir = Directory(p.join(_sessionRoot.path, sessionId));
      session = _ManagedVideoHlsSession(
        id: sessionId,
        sourceKey: sourceKey,
        sourcePath: sourcePath,
        outputDir: outputDir,
      );
      _sessionsBySourceKey[sourceKey] = session;
      _sessionsById[sessionId] = session;
    }

    session.lastAccessedAt = DateTime.now();
    try {
      session.startFuture ??= _startSession(session);
      await session.startFuture;
    } catch (_) {
      session.startFuture = null;
      rethrow;
    }

    return VideoHlsSession(id: session.id, playlistPath: session.playlistPath);
  }

  Future<String> readPlaylist(String sessionId) async {
    final session = _sessionsById[sessionId];
    if (session == null) {
      throw StateError('HLS session not found.');
    }
    session.lastAccessedAt = DateTime.now();
    return File(session.playlistPath).readAsString();
  }

  Future<File> waitForAsset({
    required String sessionId,
    required String assetName,
  }) async {
    final session = _sessionsById[sessionId];
    if (session == null) {
      throw StateError('HLS session not found.');
    }

    final normalizedAssetName = p.basename(assetName.trim());
    if (normalizedAssetName.isEmpty || normalizedAssetName != assetName.trim()) {
      throw StateError('Invalid HLS asset name.');
    }

    session.lastAccessedAt = DateTime.now();
    final assetFile = File(p.join(session.outputDir.path, normalizedAssetName));
    final deadline = DateTime.now().add(_assetWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await assetFile.exists()) {
        return assetFile;
      }
      if (session.exitCode != null && session.exitCode != 0) {
        break;
      }
      await Future<void>.delayed(_pollInterval);
    }

    if (await assetFile.exists()) {
      return assetFile;
    }

    throw StateError(
      session.lastError ?? 'HLS asset is not ready yet for playback.',
    );
  }

  Future<void> _startSession(_ManagedVideoHlsSession session) async {
    final ffmpegPath = await _ffmpegLocator.find();
    if (ffmpegPath == null) {
      throw StateError('ffmpeg.exe is not available for video transcoding.');
    }

    await _sessionRoot.create(recursive: true);
    if (await session.outputDir.exists()) {
      await session.outputDir.delete(recursive: true);
    }
    await session.outputDir.create(recursive: true);

    final playlistFile = File(session.playlistPath);
    final process = await Process.start(ffmpegPath, <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      session.sourcePath,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-pix_fmt',
      'yuv420p',
      '-profile:v',
      'main',
      '-level',
      '4.1',
      '-g',
      '48',
      '-sc_threshold',
      '0',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-ac',
      '2',
      '-f',
      'hls',
      '-hls_time',
      '4',
      '-hls_list_size',
      '0',
      '-hls_playlist_type',
      'event',
      '-hls_flags',
      'independent_segments+append_list',
      '-hls_segment_filename',
      p.join(session.outputDir.path, 'segment_%05d.ts'),
      playlistFile.path,
    ], workingDirectory: session.outputDir.path);

    session.process = process;
    session.stderrFuture = process.stderr.transform(utf8.decoder).join();
    unawaited(process.stdout.drain<void>());
    unawaited(_watchProcessExit(session));

    await _waitUntilSessionReady(session);
  }

  Future<void> _watchProcessExit(_ManagedVideoHlsSession session) async {
    final process = session.process;
    if (process == null) {
      return;
    }

    final exitCode = await process.exitCode;
    session.exitCode = exitCode;
    final stderr = (await session.stderrFuture)?.trim();
    session.lastError = stderr == null || stderr.isEmpty ? null : stderr;
    session.process = null;
  }

  Future<void> _waitUntilSessionReady(_ManagedVideoHlsSession session) async {
    final deadline = DateTime.now().add(_startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _playlistHasPlayableSegments(session.playlistPath)) {
        return;
      }
      if (session.exitCode != null) {
        break;
      }
      await Future<void>.delayed(_pollInterval);
    }

    if (await _playlistHasPlayableSegments(session.playlistPath)) {
      return;
    }

    throw StateError(
      session.lastError ?? 'HLS playlist did not become ready in time.',
    );
  }

  Future<bool> _playlistHasPlayableSegments(String playlistPath) async {
    final playlistFile = File(playlistPath);
    if (!await playlistFile.exists()) {
      return false;
    }

    final content = await playlistFile.readAsString();
    for (final rawLine in LineSplitter.split(content)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      return true;
    }
    return false;
  }

  Future<void> _cleanupExpiredSessions() async {
    final now = DateTime.now();
    final expiredSessions = _sessionsById.values
        .where((session) => now.difference(session.lastAccessedAt) > _sessionTtl)
        .toList(growable: false);

    for (final session in expiredSessions) {
      session.process?.kill();
      _sessionsById.remove(session.id);
      _sessionsBySourceKey.remove(session.sourceKey);
      if (await session.outputDir.exists()) {
        await session.outputDir.delete(recursive: true);
      }
    }
  }
}

class _ManagedVideoHlsSession {
  _ManagedVideoHlsSession({
    required this.id,
    required this.sourceKey,
    required this.sourcePath,
    required this.outputDir,
  });

  final String id;
  final String sourceKey;
  final String sourcePath;
  final Directory outputDir;

  Future<void>? startFuture;
  Future<String>? stderrFuture;
  Process? process;
  int? exitCode;
  String? lastError;
  DateTime lastAccessedAt = DateTime.now();

  String get playlistPath => p.join(outputDir.path, 'playlist.m3u8');
}
