import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nas_server/core/storage/thumbnail_native_service.dart';

void main() {
  test('generates Windows grid thumbnails with center crop', () async {
    if (!Platform.isWindows) {
      return;
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'thumbnail-native-service-test',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    final imagePath = '${temporaryDirectory.path}\\portrait.png';
    final sourceImage = img.Image(width: 3000, height: 4000);
    img.fillRect(
      sourceImage,
      x1: 0,
      y1: 0,
      x2: sourceImage.width - 1,
      y2: 499,
      color: img.ColorRgb8(255, 0, 0),
    );
    img.fillRect(
      sourceImage,
      x1: 0,
      y1: 500,
      x2: sourceImage.width - 1,
      y2: 3499,
      color: img.ColorRgb8(0, 255, 0),
    );
    img.fillRect(
      sourceImage,
      x1: 0,
      y1: 3500,
      x2: sourceImage.width - 1,
      y2: sourceImage.height - 1,
      color: img.ColorRgb8(0, 0, 255),
    );
    await File(imagePath).writeAsBytes(img.encodePng(sourceImage));

    final service = ThumbnailNativeService();
    final thumbnailBytes = await service.generateThumbnail(
      imagePath,
      200,
      cropSquare: true,
    );

    expect(thumbnailBytes, isNotNull);
    final decodedThumbnail = img.decodeImage(thumbnailBytes!);
    expect(decodedThumbnail, isNotNull);
    expect(decodedThumbnail!.width, 200);
    expect(decodedThumbnail.height, 200);
    final centerPixel = decodedThumbnail.getPixel(100, 100);
    expect(centerPixel.g, greaterThan(centerPixel.r));
    expect(centerPixel.g, greaterThan(centerPixel.b));
  });

  test('keeps Windows preview thumbnails in original aspect ratio', () async {
    if (!Platform.isWindows) {
      return;
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'thumbnail-native-service-preview-test',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    final imagePath = '${temporaryDirectory.path}\\portrait-preview.png';
    final sourceImage = img.Image(width: 3000, height: 4000);
    await File(imagePath).writeAsBytes(img.encodePng(sourceImage));

    final service = ThumbnailNativeService();
    final thumbnailBytes = await service.generateThumbnail(imagePath, 800);

    expect(thumbnailBytes, isNotNull);
    final decodedThumbnail = img.decodeImage(thumbnailBytes!);
    expect(decodedThumbnail, isNotNull);
    expect(decodedThumbnail!.width, 600);
    expect(decodedThumbnail.height, 800);
  });
}
