// 文件输入：ServerSettingsEntity, AppResult
// 文件职责：定义设置管理的抽象仓库接口
// 文件对外接口：SettingsRepository（抽象类）
// 文件包含：SettingsRepository 抽象类
import '../../../../core/result/app_result.dart';
import '../entities/server_settings_entity.dart';

abstract class SettingsRepository {
  Future<AppResult<ServerSettingsEntity>> loadSettings();
  Future<AppResult<void>> saveSettings(ServerSettingsEntity settings);
}
