abstract interface class MediaLibraryThumbnailLookup {
  Future<void> ensureLoaded();

  String? findContentUriByFileName(String fileName);
}
