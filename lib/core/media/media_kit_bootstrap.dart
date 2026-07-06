import 'package:media_kit/media_kit.dart';

/// Lazily initializes MediaKit for preview/playback screens only.
class MediaKitBootstrap {
  MediaKitBootstrap._();

  static bool _isInitialized = false;

  static void ensureInitialized() {
    if (_isInitialized) {
      return;
    }
    MediaKit.ensureInitialized();
    _isInitialized = true;
  }
}
