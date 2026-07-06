import 'dart:async';

import 'package:shelf/shelf.dart';

class ServerActivityTrackerSnapshot {
  const ServerActivityTrackerSnapshot({
    required this.inFlightRequests,
    required this.lastActivityAt,
  });

  final int inFlightRequests;
  final DateTime? lastActivityAt;
}

class ServerActivityTracker {
  ServerActivityTracker({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  int _inFlightRequests = 0;
  DateTime? _lastActivityAt;

  int get inFlightRequests => _inFlightRequests;
  DateTime? get lastActivityAt => _lastActivityAt;

  ServerActivityTrackerSnapshot get snapshot => ServerActivityTrackerSnapshot(
    inFlightRequests: _inFlightRequests,
    lastActivityAt: _lastActivityAt,
  );

  ServerActivityLease beginRequest(Request request) {
    _inFlightRequests += 1;
    _touch();
    return ServerActivityLease._(this);
  }

  void markRequestStarted(Request request) {
    beginRequest(request);
  }

  void markRequestFinished() {
    _finishRequest();
  }

  void _finishRequest() {
    if (_inFlightRequests > 0) {
      _inFlightRequests -= 1;
    }
    _touch();
  }

  bool isIdle({
    required bool hasRealtimeConnections,
    Duration quietPeriod = const Duration(seconds: 45),
  }) {
    if (hasRealtimeConnections || _inFlightRequests > 0) {
      return false;
    }
    final lastActivityAt = _lastActivityAt;
    if (lastActivityAt == null) {
      return true;
    }
    return _clock().difference(lastActivityAt) >= quietPeriod;
  }

  void reset() {
    _inFlightRequests = 0;
    _lastActivityAt = null;
  }

  void _touch() {
    _lastActivityAt = _clock();
  }
}

class ServerActivityLease {
  ServerActivityLease._(this._tracker);

  final ServerActivityTracker _tracker;
  bool _closed = false;

  Response bind(Response response) {
    return response.change(body: _bindBodyStream(response.read()));
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _tracker._finishRequest();
  }

  Stream<List<int>> _bindBodyStream(Stream<List<int>> source) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            close();
            controller.addError(error, stackTrace);
          },
          onDone: () async {
            close();
            await controller.close();
          },
          cancelOnError: false,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        close();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}
