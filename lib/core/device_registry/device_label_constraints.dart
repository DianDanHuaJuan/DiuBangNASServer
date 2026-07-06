/// Device display alias constraints shared by API handlers and DeviceStore.
abstract final class DeviceLabelConstraints {
  static const int maxLength = 32;

  static String normalize(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Returns a user-facing error message, or `null` when valid.
  /// Empty normalized label means "clear alias" and is always allowed.
  static String? validate(String? raw) {
    final normalized = normalize(raw ?? '');
    if (normalized.isEmpty) {
      return null;
    }
    final runeCount = normalized.runes.length;
    if (runeCount > maxLength) {
      return 'Label must be at most $maxLength characters';
    }
    return null;
  }
}
