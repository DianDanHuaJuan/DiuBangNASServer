// 文件输入：MediaLibraryRepository
// 文件职责：缓存媒体文件索引，提供 O(1) 查找能力
// 文件对外接口：MediaLibraryCache
// 文件包含：MediaLibraryCache
import '../../../../core/storage/media_library_thumbnail_lookup.dart';
import '../../domain/entities/media_asset.dart';
import '../../domain/repositories/media_library_repository.dart';
import '../../../../core/media_type.dart';

class MediaLibraryCache implements MediaLibraryThumbnailLookup {
  MediaLibraryCache({required MediaLibraryRepository repository})
    : _repository = repository;

  final MediaLibraryRepository _repository;

  Map<String, MediaAsset> _byFileName = {};
  Map<String, MediaAsset> _byContentUri = {};
  bool _isLoaded = false;
  DateTime? _lastRefreshTime;
  Future<void>? _loadFuture;

  bool get isLoaded => _isLoaded;
  DateTime? get lastRefreshTime => _lastRefreshTime;
  int get cachedCount => _byFileName.length;

  Future<void> load() {
    if (_isLoaded) {
      return Future.value();
    }

    final inFlight = _loadFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadInternal();
    _loadFuture = future;
    return future;
  }

  Future<void> _loadInternal() async {
    try {
      final results = await Future.wait([
        _repository.listAll(MediaType.image),
        _repository.listAll(MediaType.video),
      ]);
      final images = results[0];
      final videos = results[1];

      _byFileName = {};
      _byContentUri = {};

      for (final asset in [...images, ...videos]) {
        _byFileName[asset.displayName] = asset;
        _byContentUri[asset.contentUri] = asset;
      }

      _isLoaded = true;
      _lastRefreshTime = DateTime.now();
    } finally {
      _loadFuture = null;
    }
  }

  @override
  Future<void> ensureLoaded() async {
    if (!_isLoaded) {
      await load();
    }
  }

  Future<void> refresh() async {
    await _repository.invalidateCache();
    clear();
    await load();
  }

  MediaAsset? getByFileName(String fileName) {
    return _byFileName[fileName];
  }

  @override
  String? findContentUriByFileName(String fileName) {
    return _byFileName[fileName]?.contentUri;
  }

  MediaAsset? getByContentUri(String contentUri) {
    return _byContentUri[contentUri];
  }

  void clear() {
    _byFileName = {};
    _byContentUri = {};
    _isLoaded = false;
    _lastRefreshTime = null;
    _loadFuture = null;
  }

  void addAsset(MediaAsset asset) {
    _byFileName[asset.displayName] = asset;
    _byContentUri[asset.contentUri] = asset;
  }

  void removeByFileName(String fileName) {
    final asset = _byFileName[fileName];
    if (asset != null) {
      _byFileName.remove(fileName);
      _byContentUri.remove(asset.contentUri);
    }
  }

  void removeByContentUri(String contentUri) {
    final asset = _byContentUri[contentUri];
    if (asset != null) {
      _byContentUri.remove(contentUri);
      _byFileName.remove(asset.displayName);
    }
  }
}
