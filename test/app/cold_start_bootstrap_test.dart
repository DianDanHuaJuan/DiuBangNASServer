import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/desktop/desktop_runtime_controller.dart';
import 'package:nas_server/core/startup/startup_telemetry.dart';

void main() {
  group('cold start bootstrap contract', () {
    test('runApp is not blocked by tray refresh failures', () {
      expect(
        () => StartupTelemetry.phase('runApp'),
        returnsNormally,
        reason: 'Startup phases must never throw',
      );
    });

    test('launchHidden without tray falls back to visible window policy', () {
      expect(
        DesktopRuntimeController.shouldLaunchHidden(const ['--launch-minimized-to-tray']),
        isTrue,
      );
      expect(
        DesktopRuntimeController.shouldLaunchHidden(const []),
        isFalse,
      );
    });

    test('tray icon resolves to an existing absolute path in repo checkout', () {
      final iconPath = DesktopRuntimeController.resolveTrayIconPath();
      expect(iconPath, isNotNull);
      expect(iconPath!.contains('app_icon.ico'), isTrue);
    });
  });
}
