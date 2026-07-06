import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/streams/buffered_byte_stream_transformer.dart';

void main() {
  group('BufferedByteStreamTransformer', () {
    test(
      'does not subscribe to source until transformed stream is listened to',
      () async {
        var listened = false;
        final source = Stream<List<int>>.multi((controller) {
          listened = true;
          controller.close();
        });

        final transformed = bufferByteStream(source, 4);

        expect(listened, isFalse);

        await transformed.drain<void>();
        expect(listened, isTrue);
      },
    );

    test('coalesces small chunks while preserving byte order', () async {
      final transformed = bufferByteStream(
        Stream<List<int>>.fromIterable([
          utf8.encode('ab'),
          utf8.encode('cd'),
          utf8.encode('efg'),
          utf8.encode('hi'),
        ]),
        4,
      );

      final chunks = await transformed.toList();

      expect(chunks.map(utf8.decode).toList(), ['abcd', 'efgh', 'i']);
    });

    test('accepts Uint8List-backed streams used by request bodies', () async {
      final transformed = bufferByteStream(
        Stream<List<int>>.fromIterable(<Uint8List>[
          Uint8List.fromList(utf8.encode('ab')),
          Uint8List.fromList(utf8.encode('cdef')),
        ]),
        4,
      );

      final chunks = await transformed.toList();

      expect(chunks.map(utf8.decode).toList(), ['abcd', 'ef']);
    });
  });
}
