// 文件输入：ServiceLocator, PermissionService
// 文件职责：App 启动前的初始化流程，包括依赖注册、权限检查、存储根目录初始化
// 文件对外接口：bootstrap()
// 文件包含：bootstrap 函数
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../core/desktop/desktop_runtime_controller.dart';
import '../core/platform/app_platform.dart';
import '../core/startup/startup_telemetry.dart';
import 'di/service_locator.dart';

Future<void> bootstrap({List<String> startupArgs = const []}) async {
  await StartupTelemetry.timedPhase('binding', () async {
    WidgetsFlutterBinding.ensureInitialized();
    if (AppPlatform.supportsForegroundService) {
      FlutterForegroundTask.initCommunicationPort();
    }
  });

  await StartupTelemetry.timedPhase('setup', () {
    return ServiceLocator.setup(initializeHeavyServices: false);
  });

  if (AppPlatform.isWindows) {
    await StartupTelemetry.timedPhase('desktop_prepare', () {
      return DesktopRuntimeController.instance.prepareLaunch(
        settings: ServiceLocator.currentServerSettings,
        serverCubit: ServiceLocator.serverCubit,
        persistResidentSettings: ServiceLocator.persistResidentSettings,
        launchHidden: DesktopRuntimeController.shouldLaunchHidden(startupArgs),
      );
    });
  }

  unawaited(
    ServiceLocator.runDeferredStartup().catchError(
      (Object error, StackTrace stackTrace) {
        StartupTelemetry.errorPhase('deferred_startup', error, stackTrace);
      },
    ),
  );

  if (AppPlatform.requiresRuntimePermissions) {
    await StartupTelemetry.timedPhase(
      'permissions',
      ServiceLocator.requestPermissions,
    );
  }

  StartupTelemetry.phase('bootstrap_ready');
}
