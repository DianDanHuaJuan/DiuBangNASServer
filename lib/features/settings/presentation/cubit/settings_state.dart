// 文件输入：ViewStatus, ServerSettingsEntity
// 文件职责：定义设置页面的不可变状态
// 文件对外接口：SettingsState
// 文件包含：SettingsState
import '../../../../core/state/view_status.dart';
import '../../domain/entities/server_settings_entity.dart';

class SettingsState {
  final ViewStatus viewStatus;
  final ServerSettingsEntity? settings;
  final String? errorMessage;
  final bool isSaving;
  final String? successMessage;

  const SettingsState({
    this.viewStatus = ViewStatus.initial,
    this.settings,
    this.errorMessage,
    this.isSaving = false,
    this.successMessage,
  });

  SettingsState copyWith({
    ViewStatus? viewStatus,
    ServerSettingsEntity? settings,
    String? errorMessage,
    bool? isSaving,
    String? successMessage,
  }) {
    return SettingsState(
      viewStatus: viewStatus ?? this.viewStatus,
      settings: settings ?? this.settings,
      errorMessage: errorMessage,
      isSaving: isSaving ?? this.isSaving,
      successMessage: successMessage,
    );
  }
}
