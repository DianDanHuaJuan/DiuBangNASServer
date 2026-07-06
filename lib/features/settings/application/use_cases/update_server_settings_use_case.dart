// 文件输入：SettingsRepository, UpdateServerSettingsParams
// 文件职责：保存用户修改的服务器设置
// 文件对外接口：UpdateServerSettingsUseCase
// 文件包含：UpdateServerSettingsUseCase
import '../../../../core/error/app_failure.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/use_case/use_case.dart';
import '../../domain/entities/server_settings_entity.dart';
import '../../domain/repositories/settings_repository.dart';
import '../params/update_server_settings_params.dart';

class UpdateServerSettingsUseCase
    implements UseCase<void, UpdateServerSettingsParams> {
  UpdateServerSettingsUseCase(
    this._repository, {
    Future<String> Function(String storagePath)? validateStoragePath,
    Future<void> Function(ServerSettingsEntity settings)? onSettingsSaved,
  }) : _validateStoragePath = validateStoragePath,
       _onSettingsSaved = onSettingsSaved;

  final SettingsRepository _repository;
  final Future<String> Function(String storagePath)? _validateStoragePath;
  final Future<void> Function(ServerSettingsEntity settings)? _onSettingsSaved;

  @override
  Future<AppResult<void>> call(UpdateServerSettingsParams params) async {
    final currentResult = await _repository.loadSettings();

    if (currentResult is AppError<ServerSettingsEntity>) {
      return AppError(currentResult.failure);
    }

    final currentSettings =
        (currentResult as AppSuccess<ServerSettingsEntity>).data;
    final requestedStoragePath =
        params.storagePath ?? currentSettings.storagePath;
    final validateStoragePath = _validateStoragePath;
    late final String validatedStoragePath;
    if (validateStoragePath != null) {
      try {
        validatedStoragePath = await validateStoragePath(requestedStoragePath);
      } catch (e) {
        return AppResult.failure(
          AppFailure('共享目录校验失败：$e', code: 'INVALID_STORAGE_PATH'),
        );
      }
    } else {
      validatedStoragePath = requestedStoragePath;
    }

    final newSettings = ServerSettingsEntity(
      port: params.port,
      serverName: params.serverName ?? currentSettings.serverName,
      storagePath: validatedStoragePath,
      launchAtStartupEnabled:
          params.launchAtStartupEnabled ??
          currentSettings.launchAtStartupEnabled,
      hideToTrayOnClose:
          params.hideToTrayOnClose ?? currentSettings.hideToTrayOnClose,
      minimizeToTray: params.minimizeToTray ?? currentSettings.minimizeToTray,
      launchMinimizedToTray:
          params.launchMinimizedToTray ?? currentSettings.launchMinimizedToTray,
    );

    final saveResult = await _repository.saveSettings(newSettings);
    switch (saveResult) {
      case AppSuccess():
        final onSettingsSaved = _onSettingsSaved;
        if (onSettingsSaved != null) {
          try {
            await onSettingsSaved(newSettings);
          } catch (e) {
            return AppResult.failure(
              AppFailure(
                'Failed to apply settings: $e',
                code: 'INTERNAL_ERROR',
              ),
            );
          }
        }
        return AppResult.success(null);
      case AppError(failure: final failure):
        return AppResult.failure(failure);
    }
  }
}
