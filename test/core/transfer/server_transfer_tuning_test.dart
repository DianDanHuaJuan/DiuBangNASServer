import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/transfer/server_transfer_tuning.dart';

void main() {
  group('ServerTransferTuning', () {
    test('identifies WebDAV paths as hot transfer paths', () {
      expect(ServerTransferTuning.isHotTransferPath('dav/fs/demo.mp4'), isTrue);
      expect(
        ServerTransferTuning.isHotTransferPath('/dav/relay/demo/payload'),
        isTrue,
      );
      expect(
        ServerTransferTuning.isHotTransferPath('/api/v1/bootstrap'),
        isFalse,
      );
    });

    test('uses larger upload buffering than relay chunk metadata default', () {
      expect(
        ServerTransferTuning.uploadStreamBufferSize,
        greaterThan(ServerTransferTuning.relayDefaultChunkSizeBytes),
      );
      expect(ServerTransferTuning.downloadStreamBufferSize, greaterThan(0));
    });
  });
}
