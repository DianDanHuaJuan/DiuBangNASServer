// 文件输入：ServerRunningInfoEntity
// 文件职责：展示服务运行状态卡片（IP、端口、运行时长）
// 文件对外接口：ServerStatusCard
// 文件包含：ServerStatusCard
import 'package:flutter/material.dart';

class ServerStatusCard extends StatelessWidget {
  const ServerStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(child: Text('Server Status'));
  }
}
