import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/services.dart';

import 'broadcast_display_name_policy.dart';

class NsdManagerPlugin {
  static const MethodChannel _channel = MethodChannel(
    'com.nasserver.nas_server/nsd',
  );
  static BonsoirBroadcast? _windowsBroadcast;
  static StreamSubscription<BonsoirBroadcastEvent>? _windowsBroadcastEvents;

  static Future<Map<String, dynamic>> registerService({
    required String serviceName,
    String serviceType = '_webdavs._tcp.',
    required int port,
    Map<String, String> txtRecords = const {},
  }) async {
    if (Platform.isWindows) {
      return _registerWindowsService(
        serviceName: serviceName,
        serviceType: serviceType,
        port: port,
        txtRecords: txtRecords,
      );
    }

    if (!Platform.isAndroid) {
      return {
        'success': true,
        'degraded': true,
        'message': 'mDNS registration is not available on this platform.',
        'serviceName': serviceName,
      };
    }

    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('registerService', {
            'serviceName': serviceName,
            'serviceType': serviceType,
            'port': port,
            'txtRecords': txtRecords,
          });
      return {
        'success': true,
        'serviceName': result?['serviceName'] ?? serviceName,
      };
    } on PlatformException catch (e) {
      return {'success': false, 'error': e.message};
    } on MissingPluginException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }

  static Future<Map<String, dynamic>> registerServiceWithDisambiguation({
    required String serviceName,
    required String physicalDeviceId,
    String serviceType = '_webdavs._tcp.',
    required int port,
    Map<String, String> txtRecords = const {},
  }) async {
    final firstAttempt = await registerService(
      serviceName: serviceName,
      serviceType: serviceType,
      port: port,
      txtRecords: txtRecords,
    );
    if (firstAttempt['success'] == true) {
      return firstAttempt;
    }
    if (!_shouldRetryWithSuffix(firstAttempt)) {
      return firstAttempt;
    }

    final disambiguated = BroadcastDisplayNamePolicy.disambiguate(
      serviceName,
      physicalDeviceId,
    );
    if (disambiguated == serviceName) {
      return firstAttempt;
    }

    await unregisterService();
    return registerService(
      serviceName: disambiguated,
      serviceType: serviceType,
      port: port,
      txtRecords: txtRecords,
    );
  }

  static bool _shouldRetryWithSuffix(Map<String, dynamic> result) {
    if (result['success'] == true) {
      return false;
    }
    final error = '${result['error'] ?? ''}'.toLowerCase();
    return error.contains('冲突') ||
        error.contains('already exists') ||
        error.contains('registration_failed') ||
        error.contains('namealreadyexists');
  }

  static Future<Map<String, dynamic>> unregisterService() async {
    if (Platform.isWindows) {
      return _unregisterWindowsService();
    }

    if (!Platform.isAndroid) {
      return {
        'success': true,
        'degraded': true,
        'message': 'mDNS registration is not available on this platform.',
      };
    }

    try {
      await _channel.invokeMethod('unregisterService');
      return {'success': true};
    } on PlatformException catch (e) {
      return {'success': false, 'error': e.message};
    } on MissingPluginException catch (e) {
      return {'success': false, 'error': e.message};
    }
  }

  static Future<Map<String, dynamic>> _registerWindowsService({
    required String serviceName,
    required String serviceType,
    required int port,
    required Map<String, String> txtRecords,
  }) async {
    try {
      await _disposeWindowsBroadcast();

      final normalizedType = serviceType.endsWith('.')
          ? serviceType.substring(0, serviceType.length - 1)
          : serviceType;
      final service = BonsoirService.ignoreNorms(
        name: serviceName,
        type: normalizedType,
        port: port,
        attributes: {...BonsoirService.defaultAttributes, ...txtRecords},
      );
      final broadcast = BonsoirBroadcast(service: service, printLogs: false);

      await broadcast.initialize();

      final completer = Completer<Map<String, dynamic>>();
      _windowsBroadcastEvents = broadcast.eventStream?.listen(
        (event) {
          if (event is BonsoirBroadcastStartedEvent && !completer.isCompleted) {
            completer.complete({
              'success': true,
              'serviceName': event.service.name,
            });
          } else if (event is BonsoirBroadcastNameAlreadyExistsEvent &&
              !completer.isCompleted) {
            completer.complete({
              'success': false,
              'error': 'mDNS 服务名称冲突，请修改服务器名称后重试。',
            });
          }
        },
        onError: (Object error, StackTrace _) {
          if (!completer.isCompleted) {
            completer.complete({'success': false, 'error': '$error'});
          }
        },
      );

      await broadcast.start();
      _windowsBroadcast = broadcast;

      final result = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => {'success': true, 'serviceName': service.name},
      );
      if (result['success'] == true) {
        return result;
      }

      await _disposeWindowsBroadcast();
      return result;
    } catch (error) {
      await _disposeWindowsBroadcast();
      return {'success': false, 'error': '$error'};
    }
  }

  static Future<Map<String, dynamic>> _unregisterWindowsService() async {
    try {
      await _disposeWindowsBroadcast();
      return {'success': true};
    } catch (error) {
      return {'success': false, 'error': '$error'};
    }
  }

  static Future<void> _disposeWindowsBroadcast() async {
    await _windowsBroadcastEvents?.cancel();
    _windowsBroadcastEvents = null;
    if (_windowsBroadcast != null && !_windowsBroadcast!.isStopped) {
      await _windowsBroadcast!.stop().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    }
    _windowsBroadcast = null;
  }
}
