// 文件输入：无
// 文件职责：定义业务失败封装，供 Repository 层返回给上层
// 文件对外接口：AppFailure
// 文件包含：AppFailure
class AppFailure {
  final String message;
  final String? code;
  const AppFailure(this.message, {this.code});
}
