import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class FfmpegLocator {
  const FfmpegLocator();

  static String? _cachedFfmpegPath;
  static bool _ffmpegSearched = false;

  Future<String?> find() async {
    if (_ffmpegSearched) {
      return _cachedFfmpegPath;
    }
    _ffmpegSearched = true;

    final executableDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      p.join(executableDir, 'ffmpeg.exe'),
      p.join(executableDir, 'tools', 'ffmpeg.exe'),
      p.join(executableDir, 'data', 'flutter_assets', 'assets', 'ffmpeg.exe'),
    ];

    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        _cachedFfmpegPath = candidate;
        return _cachedFfmpegPath;
      }
    }

    try {
      final result = await Process.run(
        'where',
        const <String>['ffmpeg.exe'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final lines = LineSplitter.split('${result.stdout}')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty);
        for (final line in lines) {
          if (await File(line).exists()) {
            _cachedFfmpegPath = line;
            return _cachedFfmpegPath;
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
