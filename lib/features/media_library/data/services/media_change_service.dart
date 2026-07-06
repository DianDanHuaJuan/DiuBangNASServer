// 文件输入：MethodChannel
// 文件职责：监听 Android MediaStore 变化，通知 Flutter 层刷新缓存
// 文件对外接口：MediaChangeService
// 文件包含：MediaChangeService
import 'dart:io';

import 'package:flutter/services.dart';

typedef MediaChangeCallback = void Function();

class MediaChangeService {
  static const _channel = MethodChannel(
    'com.nasserver.nas_server/media_change',
  );

  MediaChangeCallback? onMediaChanged;
  bool _isObserving = false;

  MediaChangeService() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_handleMethodCall);
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMediaChanged':
        onMediaChanged?.call();
        return null;
      default:
        return null;
    }
  }

  Future<bool> startObserving() async {
    if (_isObserving) return true;
    if (!Platform.isAndroid) return true;

    try {
      await _channel.invokeMethod('startMediaChangeObserver');
      _isObserving = true;
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> stopObserving() async {
    if (!_isObserving) return true;
    if (!Platform.isAndroid) return true;

    try {
      await _channel.invokeMethod('stopMediaChangeObserver');
      _isObserving = false;
      return true;
    } on PlatformException {
      return false;
    }
  }

  bool get isObserving => _isObserving;
}
