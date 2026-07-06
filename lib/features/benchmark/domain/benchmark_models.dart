enum BenchmarkTransferMode {
  upload,
  download;

  static BenchmarkTransferMode parse(String value) {
    return BenchmarkTransferMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () {
        throw FormatException('Unsupported benchmark mode: $value');
      },
    );
  }
}

enum BenchmarkTransportType {
  direct,
  directDav,
  directHttp,
  directDavHttp,
  relay;

  bool get isHttpTransport => this == directHttp || this == directDavHttp;

  static BenchmarkTransportType parse(String value) {
    return BenchmarkTransportType.values.firstWhere(
      (transportType) => transportType.name == value,
      orElse: () {
        throw FormatException('Unsupported benchmark transport type: $value');
      },
    );
  }
}

class BenchmarkServerMetrics {
  const BenchmarkServerMetrics({
    required this.requestStartedAt,
    required this.firstByteAt,
    required this.completedAt,
    required this.bytesTransferred,
    required this.chunkCount,
    required this.artifactPreparationMs,
  });

  final DateTime? requestStartedAt;
  final DateTime? firstByteAt;
  final DateTime? completedAt;
  final int bytesTransferred;
  final int chunkCount;
  final int artifactPreparationMs;

  Map<String, dynamic> toJson() {
    final elapsedMs = requestStartedAt == null || completedAt == null
        ? null
        : completedAt!.difference(requestStartedAt!).inMilliseconds;
    final averageMBps = elapsedMs == null || elapsedMs <= 0
        ? null
        : (bytesTransferred / 1024 / 1024) / (elapsedMs / 1000);
    return <String, dynamic>{
      'requestStartedAt': requestStartedAt?.toUtc().toIso8601String(),
      'firstByteAt': firstByteAt?.toUtc().toIso8601String(),
      'completedAt': completedAt?.toUtc().toIso8601String(),
      'bytesTransferred': bytesTransferred,
      'chunkCount': chunkCount,
      'artifactPreparationMs': artifactPreparationMs,
      'elapsedMs': elapsedMs,
      'averageMBps': averageMBps,
    };
  }
}

class BenchmarkSessionResult {
  const BenchmarkSessionResult({
    required this.sessionId,
    required this.traceId,
    required this.mode,
    required this.transportType,
    required this.fileSizeBytes,
    required this.createdAt,
    required this.serverBuild,
    required this.serverMetrics,
    this.clientReport,
  });

  final String sessionId;
  final String traceId;
  final BenchmarkTransferMode mode;
  final BenchmarkTransportType transportType;
  final int fileSizeBytes;
  final DateTime createdAt;
  final Map<String, String> serverBuild;
  final BenchmarkServerMetrics serverMetrics;
  final Map<String, dynamic>? clientReport;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'traceId': traceId,
      'mode': mode.name,
      'transportType': transportType.name,
      'fileSizeBytes': fileSizeBytes,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'serverBuild': serverBuild,
      'serverMetrics': serverMetrics.toJson(),
      'clientReport': clientReport,
    };
  }
}
