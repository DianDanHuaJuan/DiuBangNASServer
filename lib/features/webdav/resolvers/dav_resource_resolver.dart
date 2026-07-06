// 文件输入：无
// 文件职责：定义统一资源解析接口
// 文件对外接口：DavResourceResolver
// 文件包含：DavResourceResolver 抽象类
import '../resources/dav_resource.dart';

abstract class DavResourceResolver {
  Future<DavResource?> resolve(String davPath);
  Future<List<DavResource>> listChildren(String davPath);
}
