// 文件输入：RouteNames, 各 Page 组件
// 文件职责：定义 App 全部路由映射
// 文件对外接口：AppRouter
// 文件包含：AppRouter
import 'package:flutter/material.dart';
import 'route_names.dart';
import '../../features/server/presentation/pages/server_management_page.dart';

class AppRouter {
  const AppRouter({this.serverManagementPageBuilder});

  final WidgetBuilder? serverManagementPageBuilder;

  Route<dynamic> generateRoute(RouteSettings settings) {
    final serverPageBuilder =
        serverManagementPageBuilder ?? (_) => const ServerManagementPage();

    switch (settings.name) {
      case RouteNames.serverManagement:
        return MaterialPageRoute(builder: serverPageBuilder);
      default:
        return MaterialPageRoute(builder: serverPageBuilder);
    }
  }
}
