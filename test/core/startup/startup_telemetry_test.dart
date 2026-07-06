import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/startup/startup_telemetry.dart';

void main() {
  test('StartupTelemetry phase does not throw', () {
    expect(() => StartupTelemetry.phase('test'), returnsNormally);
  });

  test('StartupTelemetry timedPhase reports duration', () async {
    await StartupTelemetry.timedPhase('timed_test', () async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return 42;
    });
  });
}
