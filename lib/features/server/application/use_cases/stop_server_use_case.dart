// 文件输入：ServerRepository, NoParams, AppResult
// 文件职责：执行服务停止的完整业务流程
// 文件对外接口：StopServerUseCase
// 文件包含：StopServerUseCase
import '../../../../core/use_case/use_case.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/error/app_failure.dart';
import '../../domain/repositories/server_repository.dart';

class StopServerUseCase implements UseCase<void, NoParams> {
  const StopServerUseCase(this._repository);

  final ServerRepository _repository;

  @override
  Future<AppResult<void>> call(NoParams params) async {
    try {
      await _repository.stopServer();
      return AppResult.success(null);
    } catch (e) {
      return AppResult.failure(AppFailure(e.toString()));
    }
  }
}
