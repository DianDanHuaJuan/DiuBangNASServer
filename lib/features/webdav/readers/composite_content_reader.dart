// 文件输入：FileSystemContentReader, MediaStoreContentReader
// 文件职责：根据资源类型选择合适的 ContentReader
// 文件对外接口：CompositeContentReader
// 文件包含：CompositeContentReader
import '../resources/dav_resource.dart';
import 'dav_content_reader.dart';
import 'file_system_content_reader.dart';
import 'media_store_content_reader.dart';

class CompositeContentReader implements DavContentReader {
  CompositeContentReader({
    required FileSystemContentReader fileSystemReader,
    required MediaStoreContentReader mediaStoreReader,
  }) : _fileSystemReader = fileSystemReader,
       _mediaStoreReader = mediaStoreReader;

  final FileSystemContentReader _fileSystemReader;
  final MediaStoreContentReader _mediaStoreReader;

  @override
  Stream<List<int>> openRead(
    DavResource resource, {
    int? rangeStart,
    int? rangeEnd,
  }) {
    if (resource.sourceType == DavSourceType.mediaStore) {
      return _mediaStoreReader.openRead(
        resource,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
    }
    return _fileSystemReader.openRead(
      resource,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }

  @override
  Future<int> getFileSize(DavResource resource) {
    if (resource.sourceType == DavSourceType.mediaStore) {
      return _mediaStoreReader.getFileSize(resource);
    }
    return _fileSystemReader.getFileSize(resource);
  }
}
