// 文件输入：服务端传输热路径的统一调优参数。
// 文件职责：集中定义 WebDAV、relay、benchmark 与 HTTP 热路径复用的传输调优常量。
// 文件对外接口：ServerTransferTuning。
// 文件包含：ServerTransferTuning。

/// 输入：请求路径与传输链路调优需求。
/// 职责：统一维护服务端传输缓冲、relay 节流和热路径判定参数。
/// 对外接口：uploadStreamBufferSize, downloadStreamBufferSize, relayUploadProgressPersistBytesThreshold, isHotTransferPath()。
class ServerTransferTuning {
  ServerTransferTuning._();

  static const int uploadStreamBufferSize = 4 * 1024 * 1024;
  static const int downloadStreamBufferSize = 8 * 1024 * 1024;
  static const int downloadBufferingThresholdBytes = 1024 * 1024;

  static const int relayMinChunkSizeBytes = 1024 * 1024;
  static const int relayMaxChunkSizeBytes = 4 * 1024 * 1024;
  static const int relayDefaultChunkSizeBytes = relayMinChunkSizeBytes;

  static const int relayUploadProgressPersistBytesThreshold = 16 * 1024 * 1024;
  static const Duration relayUploadProgressPersistInterval = Duration(
    seconds: 1,
  );
  static const Duration relayForwardReadPollInterval = Duration(
    milliseconds: 60,
  );

  static bool isHotTransferPath(String path) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    return normalizedPath == 'dav' || normalizedPath.startsWith('dav/');
  }
}
