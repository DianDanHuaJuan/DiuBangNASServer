// 文件输入：SettingsRepository
// 文件职责：加载当前服务器设置
// 文件对外接口：LoadServerSettingsUseCase
// 文件包含：LoadServerSettingsUseCase
import '../../../../core/result/app_result.dart';
import '../../../../core/use_case/use_case.dart';
import '../../domain/entities/server_settings_entity.dart';
import '../../domain/repositories/settings_repository.dart';

class LoadServerSettingsUseCase
    implements UseCase<ServerSettingsEntity, NoParams> {
  LoadServerSettingsUseCase(this._repository);

  final SettingsRepository _repository;

  @override
  Future<AppResult<ServerSettingsEntity>> call(NoParams params) {
    return _repository.loadSettings();
  }
}
