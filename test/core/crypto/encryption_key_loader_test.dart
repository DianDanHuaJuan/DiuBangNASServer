import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/crypto/encryption_key_loader.dart';

void main() {
  test('parses the first non-comment line as the encryption key', () {
    const content = '''
# NAS QR key
# comment line

00112233445566778899aabbccddeeff
deadbeef
''';

    final key = parseEncryptionKey(content);

    expect(key, hasLength(16));
    expect(key.sublist(0, 4), <int>[0x00, 0x11, 0x22, 0x33]);
    expect(key.sublist(12, 16), <int>[0xcc, 0xdd, 0xee, 0xff]);
  });

  test('rejects invalid first non-comment lines', () {
    expect(
      () => parseEncryptionKey('# comment only\ninvalid-key'),
      throwsA(isA<FormatException>()),
    );
  });
}
