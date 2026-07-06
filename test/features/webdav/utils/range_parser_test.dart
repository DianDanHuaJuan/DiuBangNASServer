import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/features/webdav/utils/range_parser.dart';

void main() {
  group('RangeParser', () {
    const parser = RangeParser();

    test('parses open-ended ranges', () {
      final result = parser.parse('bytes=5-', 10);

      expect(result, isNotNull);
      expect(result!.start, 5);
      expect(result.end, 9);
      expect(result.totalSize, 10);
    });

    test('parses suffix ranges', () {
      final result = parser.parse('bytes=-3', 10);

      expect(result, isNotNull);
      expect(result!.start, 7);
      expect(result.end, 9);
    });

    test('rejects multiple ranges', () {
      expect(parser.parse('bytes=0-1,4-5', 10), isNull);
    });
  });
}
