// 文件输入：bool isRunning, VoidCallback onPressed
// 文件职责：服务启停按钮组件
// 文件对外接口：ServerControlButton
// 文件包含：ServerControlButton
import 'package:flutter/material.dart';

class ServerControlButton extends StatelessWidget {
  final bool isRunning;
  final bool isLoading;
  final VoidCallback onPressed;
  const ServerControlButton({
    super.key,
    required this.isRunning,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: Text(isRunning ? 'Stop' : 'Start'),
    );
  }
}
