import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/storage/ffmpeg_locator.dart';

void main() {
  test('FfmpegLocator finds bundled ffmpeg in assets or release directory', () async {
    final locator = FfmpegLocator();
    final path = await locator.find();

    expect(
      path,
      isNotNull,
      reason:
          'ffmpeg.exe should be present in assets or the test runner directory',
    );
    expect(path!.toLowerCase(), endsWith('ffmpeg.exe'));
  });
}
