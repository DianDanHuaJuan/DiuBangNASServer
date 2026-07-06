// 文件输入：无
// 文件职责：定义统一内容读取接口
// 文件对外接口：DavContentReader
// 文件包含：DavContentReader 抽象类
import '../resources/dav_resource.dart';

abstract class DavContentReader {
  Stream<List<int>> openRead(
    DavResource resource, {
    int? rangeStart,
    int? rangeEnd,
  });
  Future<int> getFileSize(DavResource resource);
}
