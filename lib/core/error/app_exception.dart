// 文件输入：无
// 文件职责：定义业务异常基类，供 DataSource 和底层服务抛出
// 文件对外接口：AppException
// 文件包含：AppException
class AppException implements Exception {
  final String message;
  final String? code;
  const AppException(this.message, {this.code});
}
