// 文件输入：ServerRepository, NoParams, AppResult
// 文件职责：执行服务启动的完整业务流程
// 文件对外接口：StartServerUseCase
// 文件包含：StartServerUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/error/app_failure.dart';
import '../../domain/repositories/server_repository.dart';

class StartServerUseCase implements UseCase<void, NoParams> {
  const StartServerUseCase(this._repository);

  final ServerRepository _repository;

  @override
  Future<AppResult<void>> call(NoParams params) async {
    try {
      await _repository.startServer();
      return AppResult.success(null);
    } catch (e) {
      return AppResult.failure(AppFailure(e.toString()));
    }
  }
}
