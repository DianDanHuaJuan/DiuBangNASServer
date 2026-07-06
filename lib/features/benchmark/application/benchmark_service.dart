import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/streams/buffered_byte_stream_transformer.dart';
import '../../../core/transfer/server_transfer_tuning.dart';
import '../../../core/runtime/runtime_build_info.dart';
import '../../webdav/utils/range_parser.dart';
import '../domain/benchmark_models.dart';

class BenchmarkService {
  static const RangeParser _rangeParser = RangeParser();

  BenchmarkService({required String rootPath})
    : _artifactDirectory = Directory(
        p.join(rootPath, '.nas-benchmark-artifacts'),
      );

  static const Duration _sessionTtl = Duration(hours: 2);
  static const int _artifactChunkSize = 256 * 1024;
  static const int _maxFileSizeBytes = 1024 * 1024 * 1024;

  final Directory _artifactDirectory;
  final Map<String, _StoredBenchmarkSession> _sessions =
      <String, _StoredBenchmarkSession>{};
  final Random _random = Random.secure();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _artifactDirectory.create(recursive: true);
    _initialized = true;
  }

  Future<BenchmarkSessionResult> createSession({
    required BenchmarkTransferMode mode,
    required int fileSizeBytes,
    BenchmarkTransportType transportType = BenchmarkTransportType.direct,
  }) async {
    await initialize();
    await _cleanupExpiredSessions();
    _validateFileSize(fileSizeBytes);

    final createdAt = _now();
    final sessionId = _newId(prefix: 'bench');
    final traceId = _newId(prefix: 'trace');
    final artifactFile = File(
      p.join(_artifactDirectory.path, '$sessionId.bin'),
    );
    final session = _StoredBenchmarkSession(
      sessionId: sessionId,
      traceId: traceId,
      mode: mode,
      transportType: transportType,
      fileSizeBytes: fileSizeBytes,
      createdAt: createdAt,
      artifactFile: artifactFile,
    );
    _sessions[sessionId] = session;

    if (mode == BenchmarkTransferMode.download) {
      final stopwatch = Stopwatch()..start();
      await _generateArtifactFile(artifactFile, fileSizeBytes);
      stopwatch.stop();
      session.serverArtifactPreparationMs = stopwatch.elapsedMilliseconds;
    }

    return session.toResult();
  }

  Future<BenchmarkSessionResult> acceptUpload({
    required String sessionId,
    required Stream<List<int>> source,
  }) async {
    final session = await _requireSession(
      sessionId,
      expectedMode: BenchmarkTransferMode.upload,
    );
    await initialize();

    await _deleteIfExists(session.artifactFile);
    session.serverRequestStartedAt = _now();
    session.serverFirstByteAt = null;
    session.serverCompletedAt = null;
    session.serverBytesTransferred = 0;
    session.serverChunkCount = 0;

    final sink = session.artifactFile.openWrite();
    try {
      await for (final chunk in bufferByteStream(
        source,
        ServerTransferTuning.uploadStreamBufferSize,
      )) {
        session.serverFirstByteAt ??= _now();
        session.serverBytesTransferred += chunk.length;
        session.serverChunkCount += 1;
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }

    session.serverCompletedAt = _now();
    return session.toResult();
  }

  Future<BenchmarkDownloadHeaders> describeDownload(
    String sessionId, {
    String? rangeHeader,
  }) async {
    final prepared = await _prepareDownload(
      sessionId,
      rangeHeader: rangeHeader,
      markStarted: false,
    );
    return BenchmarkDownloadHeaders(
      statusCode: prepared.statusCode,
      headers: prepared.headers,
    );
  }

  Future<PreparedBenchmarkDownload> openDownload(
    String sessionId, {
    String? rangeHeader,
  }) async {
    final prepared = await _prepareDownload(
      sessionId,
      rangeHeader: rangeHeader,
      markStarted: true,
    );

    final file = prepared.file;
    final range = prepared.range;
    final session = await _requireSession(
      sessionId,
      expectedMode: BenchmarkTransferMode.download,
    );

    final stream =
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) {
            session.serverFirstByteAt ??= _now();
            session.serverBytesTransferred += chunk.length;
            session.serverChunkCount += 1;
            sink.add(chunk);
          },
          handleError: (error, stackTrace, sink) {
            sink.addError(error, stackTrace);
          },
          handleDone: (sink) {
            session.serverCompletedAt = _now();
            sink.close();
          },
        ).bind(
          bufferByteStream(
            file.openRead(range?.start, range == null ? null : range.end + 1),
            ServerTransferTuning.downloadStreamBufferSize,
          ),
        );

    return PreparedBenchmarkDownload(
      statusCode: prepared.statusCode,
      headers: prepared.headers,
      stream: stream,
    );
  }

  Future<BenchmarkSessionResult> reportClientMetrics({
    required String sessionId,
    required Map<String, dynamic> clientReport,
  }) async {
    final session = await _requireSession(sessionId);
    session.clientReport = Map<String, dynamic>.from(clientReport);
    return session.toResult();
  }

  Future<BenchmarkSessionResult> getSessionResult(String sessionId) async {
    final session = await _requireSession(sessionId);
    return session.toResult();
  }

  Future<void> deleteSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session == null) {
      return;
    }
    await _deleteIfExists(session.artifactFile);
  }

  Future<void> _cleanupExpiredSessions() async {
    final now = _now();
    final expiredSessionIds = _sessions.entries
        .where((entry) => now.difference(entry.value.createdAt) >= _sessionTtl)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final sessionId in expiredSessionIds) {
      await deleteSession(sessionId);
    }
  }

  Future<_PreparedBenchmarkDownload> _prepareDownload(
    String sessionId, {
    String? rangeHeader,
    required bool markStarted,
  }) async {
    final session = await _requireSession(
      sessionId,
      expectedMode: BenchmarkTransferMode.download,
    );
    await initialize();
    if (!await session.artifactFile.exists()) {
      throw const BenchmarkServiceException(
        statusCode: 404,
        code: 'BENCHMARK_ARTIFACT_MISSING',
        message: 'Benchmark artifact no longer exists on disk',
      );
    }

    final totalSize = session.fileSizeBytes;
    final range = rangeHeader == null
        ? null
        : _rangeParser.parse(rangeHeader, totalSize);
    if (rangeHeader != null && range == null) {
      throw BenchmarkServiceException(
        statusCode: 416,
        code: 'BENCHMARK_RANGE_INVALID',
        message: 'Invalid benchmark download range',
        headers: <String, String>{'Content-Range': 'bytes */$totalSize'},
      );
    }

    if (markStarted && session.serverRequestStartedAt == null) {
      session.serverRequestStartedAt = _now();
      session.serverFirstByteAt = null;
      session.serverCompletedAt = null;
      session.serverBytesTransferred = 0;
      session.serverChunkCount = 0;
    }

    final contentLength = range == null
        ? totalSize
        : range.end - range.start + 1;
    final headers = <String, String>{
      'Content-Type': 'application/octet-stream',
      'Content-Length': '$contentLength',
      'Content-Disposition':
          'attachment; filename="benchmark-${session.fileSizeBytes}.bin"',
      'Cache-Control': 'no-store',
      'Accept-Ranges': 'bytes',
      if (range != null)
        'Content-Range': 'bytes ${range.start}-${range.end}/${range.totalSize}',
    };

    return _PreparedBenchmarkDownload(
      file: session.artifactFile,
      range: range,
      statusCode: range == null ? 200 : 206,
      headers: headers,
    );
  }

  Future<_StoredBenchmarkSession> _requireSession(
    String sessionId, {
    BenchmarkTransferMode? expectedMode,
  }) async {
    await initialize();
    await _cleanupExpiredSessions();
    final session = _sessions[sessionId];
    if (session == null) {
      throw const BenchmarkServiceException(
        statusCode: 404,
        code: 'BENCHMARK_SESSION_NOT_FOUND',
        message: 'Benchmark session does not exist',
      );
    }
    if (expectedMode != null && session.mode != expectedMode) {
      throw BenchmarkServiceException(
        statusCode: 409,
        code: 'BENCHMARK_MODE_MISMATCH',
        message:
            'Benchmark session ${session.sessionId} does not support ${expectedMode.name}',
      );
    }
    return session;
  }

  Future<void> _generateArtifactFile(File file, int totalBytes) async {
    await _deleteIfExists(file);
    final sink = file.openWrite();
    final pattern = Uint8List(_artifactChunkSize);
    for (var index = 0; index < pattern.length; index += 1) {
      pattern[index] = index % 251;
    }
    var writtenBytes = 0;
    try {
      while (writtenBytes < totalBytes) {
        final remainingBytes = totalBytes - writtenBytes;
        if (remainingBytes >= pattern.length) {
          sink.add(pattern);
          writtenBytes += pattern.length;
          continue;
        }
        sink.add(pattern.sublist(0, remainingBytes));
        writtenBytes += remainingBytes;
      }
    } finally {
      await sink.close();
    }
  }

  void _validateFileSize(int fileSizeBytes) {
    if (fileSizeBytes <= 0) {
      throw const BenchmarkServiceException(
        statusCode: 400,
        code: 'BENCHMARK_FILE_SIZE_INVALID',
        message: 'fileSizeBytes must be greater than zero',
      );
    }
    if (fileSizeBytes > _maxFileSizeBytes) {
      throw BenchmarkServiceException(
        statusCode: 400,
        code: 'BENCHMARK_FILE_SIZE_INVALID',
        message:
            'fileSizeBytes exceeds benchmark limit of $_maxFileSizeBytes bytes',
      );
    }
  }

  String _newId({required String prefix}) {
    final bytes = List<int>.generate(
      9,
      (_) => _random.nextInt(256),
      growable: false,
    );
    final suffix = base64UrlEncode(bytes).replaceAll('=', '');
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  DateTime _now() => DateTime.now().toUtc();

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class PreparedBenchmarkDownload {
  const PreparedBenchmarkDownload({
    required this.statusCode,
    required this.headers,
    required this.stream,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> stream;
}

class BenchmarkDownloadHeaders {
  const BenchmarkDownloadHeaders({
    required this.statusCode,
    required this.headers,
  });

  final int statusCode;
  final Map<String, String> headers;
}

class BenchmarkServiceException implements Exception {
  const BenchmarkServiceException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String code;
  final String message;
  final Map<String, String> headers;

  @override
  String toString() => '$code: $message';
}

class _StoredBenchmarkSession {
  _StoredBenchmarkSession({
    required this.sessionId,
    required this.traceId,
    required this.mode,
    required this.transportType,
    required this.fileSizeBytes,
    required this.createdAt,
    required this.artifactFile,
  });

  final String sessionId;
  final String traceId;
  final BenchmarkTransferMode mode;
  final BenchmarkTransportType transportType;
  final int fileSizeBytes;
  final DateTime createdAt;
  final File artifactFile;

  DateTime? serverRequestStartedAt;
  DateTime? serverFirstByteAt;
  DateTime? serverCompletedAt;
  int serverBytesTransferred = 0;
  int serverChunkCount = 0;
  int serverArtifactPreparationMs = 0;
  Map<String, dynamic>? clientReport;

  BenchmarkSessionResult toResult() {
    return BenchmarkSessionResult(
      sessionId: sessionId,
      traceId: traceId,
      mode: mode,
      transportType: transportType,
      fileSizeBytes: fileSizeBytes,
      createdAt: createdAt,
      serverBuild: RuntimeBuildInfo.toJson(),
      serverMetrics: BenchmarkServerMetrics(
        requestStartedAt: serverRequestStartedAt,
        firstByteAt: serverFirstByteAt,
        completedAt: serverCompletedAt,
        bytesTransferred: serverBytesTransferred,
        chunkCount: serverChunkCount,
        artifactPreparationMs: serverArtifactPreparationMs,
      ),
      clientReport: clientReport,
    );
  }
}

class _PreparedBenchmarkDownload {
  const _PreparedBenchmarkDownload({
    required this.file,
    required this.range,
    required this.statusCode,
    required this.headers,
  });

  final File file;
  final RangeResult? range;
  final int statusCode;
  final Map<String, String> headers;
}
