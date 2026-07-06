// 文件输入：无
// 文件职责：限制缩略图生成的并发数，保护服务端不过载
// 文件对外接口：ThumbnailConcurrencyLimiter
// 文件包含：ThumbnailConcurrencyLimiter
import 'dart:async';

class ThumbnailConcurrencyLimiter {
  ThumbnailConcurrencyLimiter({this.maxConcurrent = 20});

  final int maxConcurrent;
  int _currentCount = 0;
  final _waitingQueue = <Completer<void>>[];

  int get currentCount => _currentCount;
  int get waitingCount => _waitingQueue.length;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_currentCount < maxConcurrent) {
      _currentCount++;
      try {
        return await task();
      } finally {
        _release();
      }
    } else {
      final completer = Completer<void>();
      _waitingQueue.add(completer);
      try {
        await completer.future;
      } finally {
        _release();
      }
      _currentCount++;
      try {
        return await task();
      } finally {
        _release();
      }
    }
  }

  void _release() {
    if (_waitingQueue.isNotEmpty) {
      final completer = _waitingQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }

  void reset() {
    _currentCount = 0;
    _waitingQueue.clear();
  }
}
