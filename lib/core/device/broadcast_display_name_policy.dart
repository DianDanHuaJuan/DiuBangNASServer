import '../device_registry/device_label_constraints.dart';

/// Sanitizes and disambiguates human-facing names for mDNS / bootstrap broadcast.
abstract final class BroadcastDisplayNamePolicy {
  static const int maxBroadcastLength = DeviceLabelConstraints.maxLength;
  static const int suffixLength = 4;

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _unsafeChars = RegExp(r'[/\\:*?"<>|]');
  static final RegExp _alphanumeric = RegExp(r'[a-zA-Z0-9]');

  /// Returns a user-facing error message, or `null` when valid for save.
  static String? validateForSave(String? raw) {
    return DeviceLabelConstraints.validate(raw);
  }

  static String normalizeForSave(String raw) {
    return DeviceLabelConstraints.normalize(raw);
  }

  /// Runtime-safe broadcast base name; never returns empty.
  static String sanitizeForBroadcast(String raw) {
    final sanitized = _sanitizeCore(raw);
    if (sanitized.isNotEmpty) {
      return _truncate(sanitized, maxBroadcastLength);
    }
    return 'NAS';
  }

  static String physicalIdSuffix(String physicalDeviceId) {
    final alphanumericOnly = physicalDeviceId
        .split('')
        .where((char) => _alphanumeric.hasMatch(char))
        .join();
    if (alphanumericOnly.isEmpty) {
      return 'nas0';
    }
    final tail = alphanumericOnly.length <= suffixLength
        ? alphanumericOnly
        : alphanumericOnly.substring(alphanumericOnly.length - suffixLength);
    return tail.toLowerCase();
  }

  static String disambiguate(String baseName, String physicalDeviceId) {
    final suffix = '-${physicalIdSuffix(physicalDeviceId)}';
    final maxBaseLength = maxBroadcastLength - suffix.length;
    final sanitizedBase = _sanitizeCore(baseName);
    final truncatedBase = sanitizedBase.isEmpty
        ? 'NAS'
        : _truncate(sanitizedBase, maxBaseLength);
    return '$truncatedBase$suffix';
  }

  static String fallbackBroadcastName(String physicalDeviceId) {
    return disambiguate('NAS', physicalDeviceId);
  }

  static String _sanitizeCore(String raw) {
    var value = DeviceLabelConstraints.normalize(raw);
    value = value.replaceAll(_controlChars, '');
    value = value.replaceAll(_unsafeChars, '');
    value = value.replaceAll(RegExp(r'^\.+'), '');
    value = value.replaceAll(RegExp(r'\.+$'), '');
    return value.trim();
  }

  static String _truncate(String value, int maxLength) {
    if (value.runes.length <= maxLength) {
      return value;
    }
    return String.fromCharCodes(value.runes.take(maxLength));
  }
}
