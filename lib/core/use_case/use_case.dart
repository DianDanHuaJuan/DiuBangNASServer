// 文件输入：AppResult
// 文件职责：定义 UseCase 抽象基类，统一所有业务动作的调用方式
// 文件对外接口：UseCase, NoParams
// 文件包含：UseCase, NoParams
import '../result/app_result.dart';

export 'no_params.dart';

abstract class UseCase<T, P> {
  Future<AppResult<T>> call(P params);
}
