// 文件输入：SettingsRepository, SettingsLocalDataSource
// 文件职责：实现 SettingsRepository 接口，聚合数据源完成设置管理
// 文件对外接口：SettingsRepositoryImpl
// 文件包含：SettingsRepositoryImpl
import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../domain/entities/server_settings_entity.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({required SettingsLocalDataSource localDataSource})
    : _localDataSource = localDataSource;

  final SettingsLocalDataSource _localDataSource;

  @override
  Future<AppResult<ServerSettingsEntity>> loadSettings() async {
    try {
      final settings = await _localDataSource.loadSettings();
      return AppResult.success(settings);
    } catch (e) {
      return AppResult.failure(AppFailure('加载设置失败：$e', code: 'INTERNAL_ERROR'));
    }
  }

  @override
  Future<AppResult<void>> saveSettings(ServerSettingsEntity settings) async {
    try {
      await _localDataSource.saveSettings(settings);
      return AppResult.success(null);
    } catch (e) {
      return AppResult.failure(AppFailure('保存设置失败：$e', code: 'INTERNAL_ERROR'));
    }
  }
}
