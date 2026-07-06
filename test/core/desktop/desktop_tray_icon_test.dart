import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/desktop/desktop_runtime_controller.dart';
import 'package:path/path.dart' as path;

void main() {
  test('resolveTrayIconPath prefers project icon during flutter test', () {
    final resolved = DesktopRuntimeController.resolveTrayIconPath();
    expect(resolved, isNotNull);
    expect(File(resolved!).existsSync(), isTrue);
    expect(path.basename(resolved), 'app_icon.ico');
  });
}
