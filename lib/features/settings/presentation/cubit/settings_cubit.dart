// 文件输入：LoadServerSettingsUseCase, UpdateServerSettingsUseCase
// 文件职责：管理设置页面状态，接收用户操作并调用对应 UseCase
// 文件对外接口：SettingsCubit
// 文件包含：SettingsCubit
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/result/app_result.dart';
import '../../../../core/state/view_status.dart';
import '../../../../core/use_case/no_params.dart';
import '../../application/params/update_server_settings_params.dart';
import '../../application/use_cases/load_server_settings_use_case.dart';
import '../../application/use_cases/update_server_settings_use_case.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required LoadServerSettingsUseCase loadServerSettingsUseCase,
    required UpdateServerSettingsUseCase updateServerSettingsUseCase,
  }) : _loadServerSettingsUseCase = loadServerSettingsUseCase,
       _updateServerSettingsUseCase = updateServerSettingsUseCase,
       super(const SettingsState());

  final LoadServerSettingsUseCase _loadServerSettingsUseCase;
  final UpdateServerSettingsUseCase _updateServerSettingsUseCase;

  Future<void> loadSettings() async {
    emit(state.copyWith(viewStatus: ViewStatus.loading));

    final result = await _loadServerSettingsUseCase(NoParams());

    switch (result) {
      case AppSuccess(data: final settings):
        emit(
          state.copyWith(viewStatus: ViewStatus.success, settings: settings),
        );
      case AppError(failure: final failure):
        emit(
          state.copyWith(
            viewStatus: ViewStatus.failure,
            errorMessage: failure.message,
          ),
        );
    }
  }

  Future<void> updateSettings({
    required int port,
    String? serverName,
    String? storagePath,
    bool? launchAtStartupEnabled,
    bool? hideToTrayOnClose,
    bool? minimizeToTray,
    bool? launchMinimizedToTray,
  }) async {
    emit(state.copyWith(isSaving: true));

    final result = await _updateServerSettingsUseCase(
      UpdateServerSettingsParams(
        port: port,
        serverName: serverName,
        storagePath: storagePath,
        launchAtStartupEnabled: launchAtStartupEnabled,
        hideToTrayOnClose: hideToTrayOnClose,
        minimizeToTray: minimizeToTray,
        launchMinimizedToTray: launchMinimizedToTray,
      ),
    );

    switch (result) {
      case AppSuccess():
        emit(state.copyWith(isSaving: false, successMessage: '设置已保存'));
        await loadSettings();
      case AppError(failure: final failure):
        emit(state.copyWith(isSaving: false, errorMessage: failure.message));
    }
  }

  void clearMessages() {
    emit(state.copyWith(errorMessage: null, successMessage: null));
  }
}
