import 'dart:developer' as developer;

/// Lightweight startup phase markers for diagnosing cold-start stalls.
class StartupTelemetry {
  StartupTelemetry._();

  static const String _logName = 'nas_server.startup';

  static void phase(String name, {String? detail}) {
    final message = detail == null ? 'phase=$name' : 'phase=$name detail=$detail';
    developer.log(message, name: _logName);
  }

  static Future<T> timedPhase<T>(
    String name,
    Future<T> Function() action,
  ) async {
    final stopwatch = Stopwatch()..start();
    phase('${name}_start');
    try {
      return await action();
    } catch (error, stackTrace) {
      errorPhase(name, error, stackTrace);
      rethrow;
    } finally {
      stopwatch.stop();
      phase('${name}_done', detail: 'duration_ms=${stopwatch.elapsedMilliseconds}');
    }
  }

  static void errorPhase(String phase, Object error, [StackTrace? stackTrace]) {
    developer.log(
      'phase=$phase failed',
      name: _logName,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
