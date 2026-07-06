import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/features/server/data/datasources/server_activity_tracker.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('ServerActivityTracker', () {
    test('reports idle only after response stream finishes', () async {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final tracker = ServerActivityTracker(clock: () => now);
      final request = Request(
        'GET',
        Uri.parse('https://localhost/api/v1/test'),
      );
      final bodyController = StreamController<List<int>>();

      expect(
        tracker.isIdle(
          hasRealtimeConnections: false,
          quietPeriod: const Duration(seconds: 30),
        ),
        isTrue,
      );

      final response = tracker
          .beginRequest(request)
          .bind(Response.ok(bodyController.stream));
      final readFuture = response.read().drain<void>();
      await Future<void>.delayed(Duration.zero);
      expect(
        tracker.isIdle(
          hasRealtimeConnections: false,
          quietPeriod: const Duration(seconds: 30),
        ),
        isFalse,
      );

      bodyController.add(<int>[1, 2, 3]);
      now = now.add(const Duration(seconds: 31));
      expect(
        tracker.isIdle(
          hasRealtimeConnections: false,
          quietPeriod: const Duration(seconds: 30),
        ),
        isFalse,
      );

      await bodyController.close();
      await readFuture;
      now = now.add(const Duration(seconds: 31));
      expect(
        tracker.isIdle(
          hasRealtimeConnections: false,
          quietPeriod: const Duration(seconds: 30),
        ),
        isTrue,
      );
      expect(
        tracker.isIdle(
          hasRealtimeConnections: true,
          quietPeriod: const Duration(seconds: 30),
        ),
        isFalse,
      );
    });
  });
}
