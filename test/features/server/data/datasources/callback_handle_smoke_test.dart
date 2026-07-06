import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/features/server/data/datasources/nas_foreground_task_handler.dart';

void main() {
  test('PluginUtilities returns handle for foreground task entrypoint', () {
    final callbackHandle = PluginUtilities.getCallbackHandle(
      nasForegroundTaskStartCallback,
    );

    expect(callbackHandle, isNotNull);
  });
}
