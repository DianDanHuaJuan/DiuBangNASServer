const String deviceAvatarLegacyFolderName = 'device_avatars';

const Set<String> reservedShareSegments = {
  '.relay',
  '.thumbs',
  deviceAvatarLegacyFolderName,
};

bool isReservedShareSegment(String name) {
  return reservedShareSegments.contains(name);
}

bool shouldHideFromShareListing(String name) {
  return isReservedShareSegment(name) || name.startsWith('.nas-upload-');
}

bool shouldSkipSharePath(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/').trim();
  if (normalized.isEmpty || normalized == '.') {
    return false;
  }
  final segments = normalized.split('/').where((segment) => segment.isNotEmpty);
  return segments.any(shouldHideFromShareListing);
}
