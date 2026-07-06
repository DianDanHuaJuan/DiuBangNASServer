import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/error/app_failure.dart';
import 'package:nas_server/core/result/app_result.dart';
import 'package:nas_server/core/storage/file_system_service.dart';
import 'package:nas_server/features/settings/application/params/update_server_settings_params.dart';
import 'package:nas_server/features/settings/application/use_cases/update_server_settings_use_case.dart';
import 'package:nas_server/features/settings/domain/entities/server_settings_entity.dart';
import 'package:nas_server/features/settings/domain/repositories/settings_repository.dart';

void main() {
  group('UpdateServerSettingsUseCase', () {
    test(
      'saves settings and applies them through the injected callback',
      () async {
        final repository = _FakeSettingsRepository(
          settings: const ServerSettingsEntity(
            port: 8080,
            serverName: 'NAS Server',
            storagePath: '/sdcard/NASServer',
          ),
        );
        ServerSettingsEntity? appliedSettings;
        final useCase = UpdateServerSettingsUseCase(
          repository,
          onSettingsSaved: (settings) async {
            appliedSettings = settings;
          },
        );

        final result = await useCase(
          const UpdateServerSettingsParams(port: 9090, serverName: 'Home NAS'),
        );

        expect(result, isA<AppSuccess<void>>());
        expect(repository.savedSettings?.port, 9090);
        expect(repository.savedSettings?.serverName, 'Home NAS');
        expect(appliedSettings?.port, 9090);
        expect(appliedSettings?.serverName, 'Home NAS');
      },
    );

    test(
      'normalizes the validated storage path before saving settings',
      () async {
        final repository = _FakeSettingsRepository(
          settings: const ServerSettingsEntity(
            port: 8080,
            serverName: 'NAS Server',
            storagePath: r'D:\ExistingShare',
          ),
        );
        final useCase = UpdateServerSettingsUseCase(
          repository,
          validateStoragePath: (storagePath) async => r'D:\ExistingShare',
        );

        final result = await useCase(
          const UpdateServerSettingsParams(
            port: 8080,
            serverName: 'NAS Server',
            storagePath: 'D:\\ExistingShare\\',
          ),
        );

        expect(result, isA<AppSuccess<void>>());
        expect(repository.savedSettings?.storagePath, r'D:\ExistingShare');
      },
    );

    test('returns failure when applying settings throws', () async {
      final repository = _FakeSettingsRepository(
        settings: const ServerSettingsEntity(
          port: 8080,
          serverName: 'NAS Server',
          storagePath: '/sdcard/NASServer',
        ),
      );
      final useCase = UpdateServerSettingsUseCase(
        repository,
        onSettingsSaved: (_) async => throw StateError('restart failed'),
      );

      final result = await useCase(
        const UpdateServerSettingsParams(port: 9090, serverName: 'Home NAS'),
      );

      expect(result, isA<AppError<void>>());
      final failure = (result as AppError<void>).failure;
      expect(failure.code, 'INTERNAL_ERROR');
      expect(failure.message, contains('Failed to apply settings'));
    });

    test('returns failure when storage path validation fails', () async {
      final repository = _FakeSettingsRepository(
        settings: const ServerSettingsEntity(
          port: 8080,
          serverName: 'NAS Server',
          storagePath: r'D:\ExistingShare',
        ),
      );
      final useCase = UpdateServerSettingsUseCase(
        repository,
        validateStoragePath: (_) async => throw const SharedRootPathException(
          SharedRootPathErrorCode.driveRootUnsupported,
          '共享目录不能直接设置为盘符根目录，请选择具体文件夹。',
        ),
      );

      final result = await useCase(
        const UpdateServerSettingsParams(
          port: 8080,
          serverName: 'NAS Server',
          storagePath: 'C:\\',
        ),
      );

      expect(result, isA<AppError<void>>());
      final failure = (result as AppError<void>).failure;
      expect(failure.code, 'INVALID_STORAGE_PATH');
      expect(failure.message, contains('共享目录不能直接设置为盘符根目录'));
      expect(repository.savedSettings, isNull);
    });
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({required this.settings});

  ServerSettingsEntity settings;
  ServerSettingsEntity? savedSettings;

  @override
  Future<AppResult<ServerSettingsEntity>> loadSettings() async {
    return AppResult.success(settings);
  }

  @override
  Future<AppResult<void>> saveSettings(ServerSettingsEntity settings) async {
    savedSettings = settings;
    this.settings = settings;
    return AppResult.success(null);
  }
}
