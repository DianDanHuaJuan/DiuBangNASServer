import '../../core/transfer/server_transfer_tuning.dart';

const String relayApiBasePath = '/api/v1/relay';
const String relayWebdavBasePath = '/dav/relay';
const String relayWebdavPayloadSegment = 'payload';
const String relayWebdavThumbnailSegment = 'thumbnail';
const String relayStorageDirectoryName = '.relay';
const Duration relayDefaultTtl = Duration(hours: 72);
const int relayMinChunkSizeBytes = ServerTransferTuning.relayMinChunkSizeBytes;
const int relayMaxChunkSizeBytes = ServerTransferTuning.relayMaxChunkSizeBytes;
const int relayDefaultChunkSizeBytes =
    ServerTransferTuning.relayDefaultChunkSizeBytes;
const int relayMaxFileSizeBytes = 2 * 1024 * 1024 * 1024;
const int relayMaxRetainedBytes = 20 * 1024 * 1024 * 1024;
const String relayStorageModeStoreOnNas = 'store_on_nas';
const String relayChunkChecksumHeader = 'X-NAS-Chunk-Checksum';
const String relayChunkStartHeader = 'X-NAS-Chunk-Start';
const String relayChunkEndHeader = 'X-NAS-Chunk-End';

String buildRelayWebdavPayloadPath(String transferId) {
  return '$relayWebdavBasePath/$transferId/$relayWebdavPayloadSegment';
}

String buildRelayWebdavThumbnailPath(String transferId) {
  return '$relayWebdavBasePath/$transferId/$relayWebdavThumbnailSegment';
}
