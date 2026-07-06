import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/app/di/service_locator.dart';
import 'package:nas_server/app/theme/app_theme.dart';
import 'package:nas_server/core/device/local_network_address_service.dart';
import 'package:nas_server/core/device/network_info_helper.dart';
import 'package:nas_server/core/device/network_interface_candidate.dart';
import 'package:nas_server/core/result/app_result.dart';
import 'package:nas_server/core/storage/key_value_store.dart';
import 'package:nas_server/features/settings/application/use_cases/load_server_settings_use_case.dart';
import 'package:nas_server/features/settings/application/use_cases/update_server_settings_use_case.dart';
import 'package:nas_server/features/settings/domain/entities/server_settings_entity.dart';
import 'package:nas_server/features/settings/domain/repositories/settings_repository.dart';
import 'package:nas_server/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:nas_server/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ServiceLocator.localNetworkAddressService = LocalNetworkAddressService(
      keyValueStore: KeyValueStore(sharedPreferences: prefs),
      networkInfoHelper: _FakeNetworkInfoHelper(),
    );
  });

  testWidgets('renders desktop settings cards in a 2x1 layout', (tester) async {
    tester.view.physicalSize = const Size(1400, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = _FakeSettingsRepository();
    final cubit = SettingsCubit(
      loadServerSettingsUseCase: LoadServerSettingsUseCase(repository),
      updateServerSettingsUseCase: UpdateServerSettingsUseCase(repository),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme.copyWith(platform: TargetPlatform.windows),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1400, 1200)),
          child: Scaffold(
            body: SettingsPage(
              settingsCubit: cubit,
              includeDeviceIdentityCard: false,
              loadOwnerCredentialInfo: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    expect(find.text('服务设置'), findsOneWidget);
    expect(find.text('桌面行为'), findsOneWidget);
    expect(find.text('共享目录'), findsOneWidget);
    expect(find.text('网络设置'), findsOneWidget);
    expect(find.text('保存设置'), findsOneWidget);
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  ServerSettingsEntity _settings = const ServerSettingsEntity(
    port: 8080,
    serverName: '铥棒文件S',
    storagePath: r'D:\DiuBangShare',
    launchAtStartupEnabled: true,
    hideToTrayOnClose: true,
    minimizeToTray: true,
    launchMinimizedToTray: false,
  );

  @override
  Future<AppResult<ServerSettingsEntity>> loadSettings() async {
    return AppResult.success(_settings);
  }

  @override
  Future<AppResult<void>> saveSettings(ServerSettingsEntity settings) async {
    _settings = settings;
    return AppResult.success(null);
  }
}

class _FakeNetworkInfoHelper extends NetworkInfoHelper {
  @override
  Future<List<NetworkInterfaceCandidate>> listIpv4Candidates() async {
    return const [
      NetworkInterfaceCandidate(
        address: '192.168.1.10',
        interfaceName: 'Ethernet',
        isPrivate: true,
      ),
    ];
  }
}
