import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/media_type.dart';
import 'package:nas_server/features/media_library/data/cache/media_library_cache.dart';
import 'package:nas_server/features/media_library/domain/entities/media_asset.dart';
import 'package:nas_server/features/media_library/domain/repositories/media_library_repository.dart';

void main() {
  group('MediaLibraryCache', () {
    test('coalesces concurrent loads and indexes assets', () async {
      final repository = _FakeMediaLibraryRepository(
        assetsByType: {
          MediaType.image: [_asset('cover.jpg', 'content://images/1')],
          MediaType.video: [_asset('movie.mp4', 'content://videos/1')],
        },
      );
      final cache = MediaLibraryCache(repository: repository);

      await Future.wait([cache.load(), cache.ensureLoaded(), cache.load()]);

      expect(repository.listAllCalls[MediaType.image], 1);
      expect(repository.listAllCalls[MediaType.video], 1);
      expect(cache.isLoaded, isTrue);
      expect(cache.cachedCount, 2);
      expect(
        cache.getByFileName('cover.jpg')?.contentUri,
        'content://images/1',
      );
      expect(
        cache.getByContentUri('content://videos/1')?.displayName,
        'movie.mp4',
      );
    });

    test('refresh invalidates repository data and rebuilds indexes', () async {
      final repository = _FakeMediaLibraryRepository(
        assetsByType: {
          MediaType.image: [_asset('old.jpg', 'content://images/old')],
          MediaType.video: [_asset('movie.mp4', 'content://videos/1')],
        },
      );
      final cache = MediaLibraryCache(repository: repository);

      await cache.load();
      repository.assetsByType = {
        MediaType.image: [_asset('new.jpg', 'content://images/new')],
        MediaType.video: [_asset('movie.mp4', 'content://videos/1')],
      };

      await cache.refresh();

      expect(repository.invalidateCacheCalls, 1);
      expect(cache.cachedCount, 2);
      expect(cache.getByFileName('old.jpg'), isNull);
      expect(
        cache.getByFileName('new.jpg')?.contentUri,
        'content://images/new',
      );
      expect(
        cache.getByContentUri('content://images/new')?.displayName,
        'new.jpg',
      );
    });
  });
}

class _FakeMediaLibraryRepository implements MediaLibraryRepository {
  _FakeMediaLibraryRepository({
    required Map<MediaType, List<MediaAsset>> assetsByType,
  }) : assetsByType = Map.of(assetsByType);

  Map<MediaType, List<MediaAsset>> assetsByType;
  final Map<MediaType, int> listAllCalls = {};
  int invalidateCacheCalls = 0;

  @override
  Future<void> invalidateCache() async {
    invalidateCacheCalls += 1;
  }

  @override
  Future<MediaAsset?> getAsset(String contentUri) async {
    for (final assets in assetsByType.values) {
      for (final asset in assets) {
        if (asset.contentUri == contentUri) {
          return asset;
        }
      }
    }
    return null;
  }

  @override
  Future<List<MediaAsset>> listAll(MediaType type) async {
    listAllCalls[type] = (listAllCalls[type] ?? 0) + 1;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return List<MediaAsset>.from(assetsByType[type] ?? const []);
  }

  @override
  Future<List<MediaAsset>> listByBucket(MediaType type, String bucketId) async {
    final assets = await listAll(type);
    return assets.where((asset) => asset.bucketId == bucketId).toList();
  }

  @override
  Future<List<String>> listBuckets(MediaType type) async {
    final assets = await listAll(type);
    return assets.map((asset) => asset.bucketDisplayName).toSet().toList();
  }
}

MediaAsset _asset(String name, String contentUri) {
  return MediaAsset(
    contentUri: contentUri,
    displayName: name,
    relativePath: 'DCIM/',
    size: 1,
    mimeType: name.endsWith('.mp4') ? 'video/mp4' : 'image/jpeg',
    dateModified: DateTime(2024),
    mediaType: name.endsWith('.mp4') ? MediaType.video : MediaType.image,
    bucketId: 'bucket-1',
    bucketDisplayName: 'Camera',
  );
}
