// 文件输入：AppRouter, AppTheme, ServiceLocator
// 文件职责：定义 MaterialApp 根组件，配置路由和主题
// 文件对外接口：NasServerApp
// 文件包含：NasServerApp
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/desktop/desktop_runtime_controller.dart';
import '../core/platform/app_platform.dart';
import '../core/startup/startup_telemetry.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'di/service_locator.dart';
import '../features/server/presentation/cubit/server_cubit.dart';

class NasServerApp extends StatefulWidget {
  const NasServerApp({super.key});

  @override
  State<NasServerApp> createState() => _NasServerAppState();
}

class _NasServerAppState extends State<NasServerApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_presentDesktopWindow());
    });
  }

  Future<void> _presentDesktopWindow() async {
    StartupTelemetry.phase('first_frame');
    if (!AppPlatform.isWindows) {
      return;
    }
    await DesktopRuntimeController.instance.presentWindowAfterFirstFrame();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ServerCubitImpl>(
      create: (_) => ServiceLocator.serverCubit,
      child: MaterialApp(
        title: '铥棒文件S',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        initialRoute: '/',
        onGenerateRoute: const AppRouter().generateRoute,
      ),
    );
  }
}
