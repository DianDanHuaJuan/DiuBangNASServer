import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as path;
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/server/presentation/cubit/server_cubit.dart';
import '../../features/server/presentation/cubit/server_state.dart';
import '../../features/settings/domain/entities/server_settings_entity.dart';
import '../platform/app_platform.dart';
import '../startup/startup_telemetry.dart';
import '../device/nsd_manager_plugin.dart';

class DesktopRuntimeController with WindowListener {
  DesktopRuntimeController._();

  static final DesktopRuntimeController instance = DesktopRuntimeController._();

  static const String launchMinimizedArgument = '--launch-minimized-to-tray';

  final WindowManager _windowManager = WindowManager.instance;
  final SystemTray _systemTray = SystemTray();

  ServerCubitImpl? _serverCubit;
  ServerSettingsEntity? _settings;
  Future<void> Function(ServerSettingsEntity settings)?
  _persistResidentSettings;
  StreamSubscription<ServerState>? _serverStateSubscription;
  bool _initialized = false;
  bool _trayReady = false;
  bool _trayInitAttempted = false;
  bool _launchHidden = false;
  bool _windowPresented = false;
  bool _isExiting = false;
  bool _isHidingWindow = false;

  static bool shouldLaunchHidden(List<String> startupArgs) {
    return AppPlatform.isWindows &&
        startupArgs.contains(launchMinimizedArgument);
  }

  /// Resolves the tray icon to an absolute path so init does not depend on CWD.
  static String? resolveTrayIconPath() {
    if (!Platform.isWindows) {
      return null;
    }

    final executable = Platform.resolvedExecutable;
    final executableDir = path.dirname(executable);
    final candidates = <String>[
      path.join(
        executableDir,
        'data',
        'flutter_assets',
        'windows',
        'runner',
        'resources',
        'app_icon.ico',
      ),
      path.join(executableDir, 'resources', 'app_icon.ico'),
      path.join(
        Directory.current.path,
        'windows',
        'runner',
        'resources',
        'app_icon.ico',
      ),
      path.normalize(
        path.join(
          executableDir,
          '..',
          'windows',
          'runner',
          'resources',
          'app_icon.ico',
        ),
      ),
    ];

    for (final candidate in candidates) {
      final normalized = path.normalize(candidate);
      if (File(normalized).existsSync()) {
        return normalized;
      }
    }
    return null;
  }

  /// Window/tray setup before [runApp]. Must not block on first-frame display.
  Future<void> prepareLaunch({
    required ServerSettingsEntity settings,
    required ServerCubitImpl serverCubit,
    required Future<void> Function(ServerSettingsEntity settings)
    persistResidentSettings,
    required bool launchHidden,
  }) async {
    if (!AppPlatform.isWindows) {
      return;
    }

    _settings = settings;
    _serverCubit = serverCubit;
    _persistResidentSettings = persistResidentSettings;
    _launchHidden = launchHidden;

    _configureLaunchAtStartup(settings);
    unawaited(_syncLaunchAtStartup(settings, failSilently: true));

    if (_initialized) {
      await _ensureTrayInitialized();
      unawaited(_safeRefreshTray());
      return;
    }

    StartupTelemetry.phase('desktop_prepare');
    await _windowManager.ensureInitialized();
    _windowManager.addListener(this);
    await _windowManager.setPreventClose(true);
    await _windowManager.setResizable(true);
    await _windowManager.setMinimumSize(const Size(1280, 720));
    await _windowManager.setSize(const Size(1280, 720));

    _serverStateSubscription = serverCubit.stream.listen((_) {
      unawaited(_safeRefreshTray());
    });

    _initialized = true;
    StartupTelemetry.phase('desktop_prepare_done');
  }

  Future<void> _ensureTrayInitialized() async {
    if (_trayReady || _trayInitAttempted) {
      return;
    }

    _trayInitAttempted = true;
    StartupTelemetry.phase('desktop_tray_init');
    await _initializeTray();
    unawaited(_safeRefreshTray());
  }

  /// Shows or hides the window after the first Flutter frame ([runApp] must run first).
  Future<void> presentWindowAfterFirstFrame() async {
    if (!AppPlatform.isWindows || !_initialized || _windowPresented) {
      return;
    }

    _windowPresented = true;
    StartupTelemetry.phase('desktop_present_window');

    await _windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 720),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        title: '铥棒文件S',
      ),
      () async {
        await _ensureTrayInitialized();

        if (_launchHidden && _trayReady) {
          await _hideWindowToTray();
          return;
        }

        if (_launchHidden && !_trayReady) {
          StartupTelemetry.phase(
            'desktop_tray_fallback',
            detail: 'tray_unavailable_showing_window',
          );
        }
        await showWindow();
      },
    );
  }

  Future<void> applySettings(ServerSettingsEntity settings) async {
    if (!AppPlatform.isWindows) {
      return;
    }

    _settings = settings;
    _configureLaunchAtStartup(settings);
    await _syncLaunchAtStartup(settings, failSilently: false);
    await _ensureTrayInitialized();
    await _safeRefreshTray();
  }

  Future<void> showWindow() async {
    if (!AppPlatform.isWindows) {
      return;
    }

    await _windowManager.setSkipTaskbar(false);
    await _windowManager.show();
    await _windowManager.focus();
    await _ensureTrayInitialized();
    await _safeRefreshTray();
  }

  Future<void> exitApplication() async {
    if (!AppPlatform.isWindows || _isExiting) {
      return;
    }

    _isExiting = true;
    try {
      final serverCubit = _serverCubit;
      if (serverCubit != null &&
          serverCubit.state.serverStatus == ServerStatus.running) {
        await serverCubit.stopServer();
      }
      await _serverStateSubscription?.cancel();
      _serverStateSubscription = null;
      await NsdManagerPlugin.unregisterService();
      if (_trayReady) {
        await _systemTray.destroy();
      }
      _windowManager.removeListener(this);
      await _windowManager.destroy();
    } finally {
      _isExiting = false;
    }
  }

  Future<void> toggleLaunchAtStartup() async {
    final settings = _settings;
    final persistResidentSettings = _persistResidentSettings;
    if (settings == null || persistResidentSettings == null) {
      return;
    }

    final updatedSettings = settings.copyWith(
      launchAtStartupEnabled: !settings.launchAtStartupEnabled,
    );

    _configureLaunchAtStartup(updatedSettings);
    await _syncLaunchAtStartup(updatedSettings, failSilently: false);

    try {
      await persistResidentSettings(updatedSettings);
      _settings = updatedSettings;
      await _safeRefreshTray();
    } catch (_) {
      _configureLaunchAtStartup(settings);
      await _syncLaunchAtStartup(settings, failSilently: true);
      rethrow;
    }
  }

  @override
  void onWindowClose() {
    final settings = _settings;
    if (_isExiting || settings == null) {
      return;
    }

    if (settings.hideToTrayOnClose && _trayReady) {
      unawaited(_hideWindowToTray());
      return;
    }

    unawaited(exitApplication());
  }

  @override
  void onWindowMinimize() {
    final settings = _settings;
    if (_isExiting ||
        settings == null ||
        !settings.minimizeToTray ||
        !_trayReady) {
      return;
    }

    unawaited(_hideWindowToTray());
  }

  Future<void> _initializeTray() async {
    final iconPath = resolveTrayIconPath();
    if (iconPath == null) {
      StartupTelemetry.phase('desktop_tray_skip', detail: 'icon_not_found');
      return;
    }

    try {
      await _systemTray.initSystemTray(
        iconPath: iconPath,
        toolTip: '铥棒文件S',
      );
      _trayReady = true;
      _systemTray.registerSystemTrayEventHandler((eventName) {
        switch (eventName) {
          case kSystemTrayEventClick:
          case kSystemTrayEventDoubleClick:
            unawaited(showWindow());
            return;
          case kSystemTrayEventRightClick:
            unawaited(_systemTray.popUpContextMenu());
            return;
        }
      });
      StartupTelemetry.phase('desktop_tray_ready');
    } catch (error, stackTrace) {
      _trayReady = false;
      StartupTelemetry.errorPhase('desktop_tray_init', error, stackTrace);
    }
  }

  Future<void> _safeRefreshTray() async {
    try {
      await _refreshTray();
    } catch (error, stackTrace) {
      StartupTelemetry.errorPhase('desktop_tray_refresh', error, stackTrace);
    }
  }

  Future<void> _refreshTray() async {
    if (!AppPlatform.isWindows || !_trayReady) {
      return;
    }

    final settings = _settings;
    final serverCubit = _serverCubit;
    if (settings == null || serverCubit == null) {
      return;
    }

    final state = serverCubit.state;
    final isRunning = state.serverStatus == ServerStatus.running;
    final isBusy =
        state.serverStatus == ServerStatus.starting ||
        state.serverStatus == ServerStatus.stopping;
    final isVisible = await _windowManager.isVisible();

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: isVisible ? '隐藏到托盘' : '显示主窗口',
        onClicked: (_) {
          unawaited(isVisible ? _hideWindowToTray() : showWindow());
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: isRunning ? '停止服务' : '启动服务',
        enabled: !isBusy,
        onClicked: (_) {
          if (isBusy) {
            return;
          }
          unawaited(
            isRunning ? serverCubit.stopServer() : serverCubit.startServer(),
          );
        },
      ),
      MenuItemCheckbox(
        label: '开机自启',
        checked: settings.launchAtStartupEnabled,
        onClicked: (_) {
          unawaited(toggleLaunchAtStartup());
        },
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '退出铥棒文件S',
        onClicked: (_) {
          unawaited(exitApplication());
        },
      ),
    ]);

    await _systemTray.setContextMenu(menu);
    await _systemTray.setToolTip(isRunning ? '铥棒文件S - 服务运行中' : '铥棒文件S - 服务未启动');
  }

  Future<void> _hideWindowToTray() async {
    if (_isHidingWindow) {
      return;
    }

    if (!_trayReady) {
      StartupTelemetry.phase(
        'desktop_tray_fallback',
        detail: 'hide_requested_tray_unavailable',
      );
      await showWindow();
      return;
    }

    _isHidingWindow = true;
    try {
      await _windowManager.setSkipTaskbar(true);
      await _windowManager.hide();
      await _safeRefreshTray();
    } finally {
      _isHidingWindow = false;
    }
  }

  void _configureLaunchAtStartup(ServerSettingsEntity settings) {
    launchAtStartup.setup(
      appName: '铥棒文件S',
      appPath: Platform.resolvedExecutable,
      args: settings.launchMinimizedToTray
          ? const [launchMinimizedArgument]
          : const [],
    );
  }

  Future<void> _syncLaunchAtStartup(
    ServerSettingsEntity settings, {
    required bool failSilently,
  }) async {
    try {
      final isEnabled = await launchAtStartup.isEnabled();
      if (isEnabled == settings.launchAtStartupEnabled) {
        return;
      }

      final succeeded = settings.launchAtStartupEnabled
          ? await launchAtStartup.enable()
          : await launchAtStartup.disable();
      if (!succeeded) {
        throw StateError(
          settings.launchAtStartupEnabled ? '启用开机自启失败' : '关闭开机自启失败',
        );
      }
    } catch (error, stackTrace) {
      if (!failSilently) {
        rethrow;
      }
      StartupTelemetry.errorPhase('desktop_launch_at_startup', error, stackTrace);
    }
  }
}
