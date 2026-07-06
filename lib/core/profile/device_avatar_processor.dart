import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DeviceAvatarProcessor {
  DeviceAvatarProcessor._();

  static const int targetMaxBytes = 30 * 1024;
  static const int outputEdge = 256;

  static Future<Uint8List> prepareFromFile(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    return prepareFromBytes(bytes);
  }

  static Future<Uint8List> prepareFromBytes(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw FormatException('无法读取图片，请选择 JPEG 或 PNG');
    }
    final oriented = img.bakeOrientation(decoded);
    return encodeAvatarJpeg(_centerSquareCrop(oriented));
  }

  static Future<String> writeProcessedAvatar(Uint8List bytes) async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final profileDir = Directory(p.join(documentsDir.path, 'profile'));
    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }
    final destinationPath = p.join(profileDir.path, 'avatar.jpg');
    await File(destinationPath).writeAsBytes(bytes, flush: true);
    return destinationPath;
  }

  static Uint8List encodeAvatarJpeg(img.Image image) {
    img.Image working = image;
    if (working.width != working.height) {
      final size = math.min(working.width, working.height);
      working = img.copyCrop(
        working,
        x: (working.width - size) ~/ 2,
        y: (working.height - size) ~/ 2,
        width: size,
        height: size,
      );
    }

    for (final edge in <int>[outputEdge, 192, 128, 96]) {
      final resized = edge == working.width && edge == working.height
          ? working
          : img.copyResize(
              working,
              width: edge,
              height: edge,
              interpolation: img.Interpolation.linear,
            );
      for (final quality in <int>[82, 72, 62, 52, 42, 32]) {
        final bytes = Uint8List.fromList(
          img.encodeJpg(resized, quality: quality),
        );
        if (bytes.length <= targetMaxBytes) {
          return bytes;
        }
      }
    }

    final fallback = img.copyResize(
      working,
      width: 72,
      height: 72,
      interpolation: img.Interpolation.linear,
    );
    return Uint8List.fromList(img.encodeJpg(fallback, quality: 28));
  }

  static img.Image _centerSquareCrop(img.Image source) {
    final size = math.min(source.width, source.height);
    return img.copyCrop(
      source,
      x: (source.width - size) ~/ 2,
      y: (source.height - size) ~/ 2,
      width: size,
      height: size,
    );
  }
}
