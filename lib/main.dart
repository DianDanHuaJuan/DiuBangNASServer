// 文件输入：bootstrap, NasServerApp
// 文件职责：App 入口，调用 bootstrap 初始化后运行 App
// 文件对外接口：main()
// 文件包含：main 函数
import 'package:flutter/material.dart';
import 'app/bootstrap.dart';
import 'app/app.dart';
import 'core/startup/startup_telemetry.dart';

Future<void> main(List<String> args) async {
  StartupTelemetry.phase('main');
  await bootstrap(startupArgs: args);
  StartupTelemetry.phase('runApp');
  runApp(const NasServerApp());
}
