import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device/system_status_cache.dart';
import 'package:nas_server/features/api/handlers/dashboard_handler.dart';
import 'package:shelf/shelf.dart';

import '../../../helpers/system_status_cache_test_helper.dart';

void main() {
  group('DashboardHandler', () {
    test(
      'returns contract fields for battery, uptime, memory and build info',
      () async {
        final cache = await createTestSystemStatusCache(selectedIp: '192.168.1.10');
        cache.deviceId = 'device-1';
        cache.model = 'Pixel 7';
        cache.brand = 'google';
        cache.systemVersion = '14';
        cache.batteryLevel = 2;
        cache.batteryPercent = 88.5;
        cache.isCharging = true;
        cache.totalStorage = 128000;
        cache.usedStorage = 64000;
        cache.totalMemory = 8192;
        cache.usedMemory = 4096;
        cache.cpuTemperature = 42.5;
        cache.localIp = '192.168.1.10';
        cache.lastUpdated = DateTime.utc(2024, 3, 24, 12);

        final startedAt = DateTime.now().subtract(const Duration(minutes: 2));
        final handler = DashboardHandler(
          systemStatusCache: cache,
          port: 9090,
          startedAt: startedAt,
        );

        final response = await handler.handler(
          Request('GET', Uri.parse('http://localhost/api/v1/dashboard')),
        );
        final payload =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;

        expect(response.statusCode, 200);
        expect(payload['device']['platform'], isNotEmpty);
        expect(payload['device']['batteryLevel'], 2);
        expect(payload['device']['batteryPercent'], 88.5);
        expect(payload['system']['memory']['totalBytes'], 8192);
        expect(payload['system']['uptime'], greaterThanOrEqualTo(120));
        expect(payload['server']['build']['appVersion'], isNotEmpty);
        expect(payload['server']['build']['buildSha'], isNotEmpty);
        expect(payload['server']['build']['buildTime'], isNotEmpty);
      },
    );
  });
}
