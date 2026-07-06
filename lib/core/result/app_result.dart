// 文件输入：AppFailure
// 文件职责：定义统一返回类型，替代 try/catch 在业务层传递成功或失败
// 文件对外接口：AppResult
// 文件包含：AppResult, AppSuccess, AppError
import '../error/app_failure.dart';

sealed class AppResult<T> {
  const AppResult();

  static AppResult<T> success<T>(T data) => AppSuccess(data);
  static AppResult<T> failure<T>(AppFailure failure) => AppError(failure);
}

class AppSuccess<T> extends AppResult<T> {
  final T data;
  const AppSuccess(this.data);
}

class AppError<T> extends AppResult<T> {
  final AppFailure failure;
  const AppError(this.failure);
}
