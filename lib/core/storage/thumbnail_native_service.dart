import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'ffmpeg_locator.dart';

class ThumbnailNativeService {
  static const _channel = MethodChannel('com.nasserver.nas_server/thumbnail');
  static const FfmpegLocator _ffmpegLocator = FfmpegLocator();

  Future<Uint8List?> generateThumbnail(
    String filePath,
    int size, {
    bool cropSquare = false,
  }) async {
    if (Platform.isWindows) {
      return _generateWindows(filePath, size, cropSquare: cropSquare);
    }
    if (Platform.isAndroid) {
      return _generateAndroid(filePath, size);
    }
    return null;
  }

  Future<Uint8List?> generateThumbnailFromUri(
    String contentUri,
    int size,
  ) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generateThumbnailFromUri',
        {'contentUri': contentUri, 'size': size},
      );

      if (result == null) return null;

      final success = result['success'] as bool? ?? false;
      if (!success) return null;

      final bytesList = result['bytes'] as List<dynamic>?;
      if (bytesList == null) return null;

      return Uint8List.fromList(bytesList.cast<int>());
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _generateAndroid(String filePath, int size) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generateThumbnail',
        {'filePath': filePath, 'size': size},
      );

      if (result == null) return null;

      final success = result['success'] as bool? ?? false;
      if (!success) return null;

      final bytesList = result['bytes'] as List<dynamic>?;
      if (bytesList == null) return null;

      return Uint8List.fromList(bytesList.cast<int>());
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _generateWindows(
    String filePath,
    int size, {
    required bool cropSquare,
  }) async {
    final ext = p.extension(filePath).toLowerCase();
    if (_isVideoExtension(ext)) {
      return _generateVideoThumbnailWindows(
        filePath,
        size,
        cropSquare: cropSquare,
      );
    }
    if (_isImageExtension(ext)) {
      return _generateImageThumbnailDart(
        filePath,
        size,
        cropSquare: cropSquare,
      );
    }
    return null;
  }

  Future<Uint8List?> _generateImageThumbnailDart(
    String filePath,
    int size, {
    required bool cropSquare,
  }) async {
    try {
      final fileBytes = await File(filePath).readAsBytes();
      final decoded = img.decodeImage(fileBytes);
      if (decoded == null) return null;

      final resized = _prepareImageForThumbnail(
        image: decoded,
        maxSize: size,
        cropSquare: cropSquare,
      );

      final jpegBytes = img.encodeJpg(resized, quality: 85);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _generateVideoThumbnailWindows(
    String filePath,
    int size, {
    required bool cropSquare,
  }) async {
    final ffmpegPath = await _ffmpegLocator.find();
    if (ffmpegPath == null) return null;

    Process? ffmpegProcess;
    Future<void>? stderrDrainFuture;
    try {
      ffmpegProcess = await Process.start(ffmpegPath, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        '0',
        '-i',
        filePath,
        '-vframes',
        '1',
        '-f',
        'image2pipe',
        '-vcodec',
        'mjpeg',
        '-an',
        '-nostdin',
        'pipe:1',
      ]);
      stderrDrainFuture = ffmpegProcess.stderr.drain<void>();

      final stdoutBytes = await ffmpegProcess.stdout
          .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk))
          .timeout(const Duration(seconds: 15));

      final exitCode = await ffmpegProcess.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          ffmpegProcess?.kill();
          return -1;
          },
      );
      await stderrDrainFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () async {},
      );

      if (exitCode != 0 || stdoutBytes.isEmpty) return null;

      final decoded = img.decodeImage(Uint8List.fromList(stdoutBytes));
      if (decoded == null) return null;

      final resized = _prepareImageForThumbnail(
        image: decoded,
        maxSize: size,
        cropSquare: cropSquare,
      );

      final jpegBytes = img.encodeJpg(resized, quality: 85);
      return Uint8List.fromList(jpegBytes);
    } catch (e) {
      ffmpegProcess?.kill();
      await stderrDrainFuture?.catchError((_) {});
      return null;
    }
  }

  img.Image _prepareImageForThumbnail({
    required img.Image image,
    required int maxSize,
    required bool cropSquare,
  }) {
    if (cropSquare) {
      return _resizeImageToCenterCropSquare(image: image, size: maxSize);
    }
    return _resizeImagePreservingAspectRatio(image: image, maxSize: maxSize);
  }

  img.Image _resizeImagePreservingAspectRatio({
    required img.Image image,
    required int maxSize,
  }) {
    if (maxSize <= 0 || image.width <= 0 || image.height <= 0) {
      return image;
    }

    final aspectRatio = image.width / image.height;
    final targetWidth = aspectRatio > 1
        ? maxSize
        : ((maxSize * aspectRatio).round()).clamp(1, maxSize);
    final targetHeight = aspectRatio > 1
        ? ((maxSize / aspectRatio).round()).clamp(1, maxSize)
        : maxSize;

    if (targetWidth == image.width && targetHeight == image.height) {
      return image;
    }

    return img.copyResize(image, width: targetWidth, height: targetHeight);
  }

  img.Image _resizeImageToCenterCropSquare({
    required img.Image image,
    required int size,
  }) {
    if (size <= 0 || image.width <= 0 || image.height <= 0) {
      return image;
    }

    if (image.width == size && image.height == size) {
      return image;
    }

    final scale = math.max(size / image.width, size / image.height);
    final targetWidth = math.max(size, (image.width * scale).round());
    final targetHeight = math.max(size, (image.height * scale).round());
    final resized = (targetWidth == image.width && targetHeight == image.height)
        ? image
        : img.copyResize(image, width: targetWidth, height: targetHeight);
    final cropX = ((resized.width - size) / 2).round().clamp(
      0,
      resized.width - size,
    );
    final cropY = ((resized.height - size) / 2).round().clamp(
      0,
      resized.height - size,
    );
    return img.copyCrop(resized, x: cropX, y: cropY, width: size, height: size);
  }

  bool _isImageExtension(String ext) {
    return ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'].contains(ext);
  }

  bool _isVideoExtension(String ext) {
    return ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp'].contains(ext);
  }
}
