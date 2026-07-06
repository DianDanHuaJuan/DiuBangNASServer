import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/device/broadcast_display_name_policy.dart';

void main() {
  group('BroadcastDisplayNamePolicy', () {
    test('sanitizeForBroadcast strips unsafe characters', () {
      expect(
        BroadcastDisplayNamePolicy.sanitizeForBroadcast('客厅/NAS*'),
        '客厅NAS',
      );
    });

    test('disambiguate appends physical id suffix within max length', () {
      final result = BroadcastDisplayNamePolicy.disambiguate(
        '客厅 NAS 设备名称很长需要截断',
        'nas-abcdef1234567890',
      );
      expect(result.endsWith('-7890'), isTrue);
      expect(result.runes.length, lessThanOrEqualTo(32));
    });

    test('physicalIdSuffix uses last alphanumeric tail', () {
      expect(
        BroadcastDisplayNamePolicy.physicalIdSuffix('nas-abcdef1234567890'),
        '7890',
      );
    });

    test('fallbackBroadcastName never empty', () {
      expect(
        BroadcastDisplayNamePolicy.fallbackBroadcastName('nas-abc'),
        isNotEmpty,
      );
    });
  });
}
