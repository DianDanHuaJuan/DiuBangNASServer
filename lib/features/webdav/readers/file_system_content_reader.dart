// 文件输入：FileSystemService
// 文件职责：负责文件系统资源读取
// 文件对外接口：FileSystemContentReader
// 文件包含：FileSystemContentReader
import 'dart:io';
import '../resources/dav_resource.dart';
import 'dav_content_reader.dart';

class FileSystemContentReader implements DavContentReader {
  @override
  Stream<List<int>> openRead(
    DavResource resource, {
    int? rangeStart,
    int? rangeEnd,
  }) {
    if (resource.sourceRef == null) {
      return Stream<List<int>>.empty();
    }

    final file = File(resource.sourceRef!);
    final endExclusive = rangeEnd == null ? null : rangeEnd + 1;
    return file.openRead(rangeStart, endExclusive);
  }

  @override
  Future<int> getFileSize(DavResource resource) async {
    if (resource.sourceRef == null) return 0;
    final file = File(resource.sourceRef!);
    return file.length();
  }
}
