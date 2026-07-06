class SettingsApplyStatus {
  const SettingsApplyStatus({
    this.isApplying = false,
    this.message,
    this.errorMessage,
  });

  final bool isApplying;
  final String? message;
  final String? errorMessage;

  static const idle = SettingsApplyStatus();

  SettingsApplyStatus copyWith({
    bool? isApplying,
    String? message,
    String? errorMessage,
    bool clearMessage = false,
    bool clearError = false,
  }) {
    return SettingsApplyStatus(
      isApplying: isApplying ?? this.isApplying,
      message: clearMessage ? null : (message ?? this.message),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
