import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/ffmpeg_hls_encoder.dart';

void main() {
  test('FfmpegHlsEncoder lists encoder names from ffmpeg -encoders output', () {
    const encodersOutput = '''
 V..... h264_mf              H264 via MediaFoundation (codec h264)
 V..... libopenh264          OpenH264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)
''';

    expect(
      FfmpegHlsEncoder.videoEncoderArgs(FfmpegH264Encoder.h264Mf),
      contains('h264_mf'),
    );
    expect(
      FfmpegHlsEncoder.videoEncoderArgs(FfmpegH264Encoder.libOpenH264),
      contains('libopenh264'),
    );
    expect(encodersOutput, contains('h264_mf'));
    expect(encodersOutput, contains('libopenh264'));
  });
}
