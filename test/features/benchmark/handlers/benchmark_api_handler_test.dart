import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/features/benchmark/application/benchmark_service.dart';
import 'package:nas_server/features/benchmark/handlers/benchmark_api_handler.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('BenchmarkApiHandler', () {
    test('supports HEAD and ranged GET for benchmark downloads', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nas-benchmark-handler',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final service = BenchmarkService(rootPath: tempDir.path);
      final handler = BenchmarkApiHandler(benchmarkService: service);

      final createResponse = await handler.createSessionHandler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/debug/benchmark/sessions'),
          body: jsonEncode(<String, dynamic>{
            'mode': 'download',
            'transportType': 'direct',
            'fileSizeBytes': 32,
          }),
          headers: const <String, String>{'Content-Type': 'application/json'},
        ),
      );

      final createPayload =
          jsonDecode(await createResponse.readAsString())
              as Map<String, dynamic>;
      final session = createPayload['session'] as Map<String, dynamic>;
      final sessionId = session['sessionId'] as String;

      final headResponse = await handler.headDownloadHandler(
        Request(
          'HEAD',
          Uri.parse(
            'http://localhost/api/v1/debug/benchmark/sessions/$sessionId/download',
          ),
        ),
        sessionId,
      );

      expect(headResponse.statusCode, 200);
      expect(headResponse.headers['Content-Length'], '32');
      expect(headResponse.headers['Accept-Ranges'], 'bytes');

      final partialResponse = await handler.downloadHandler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/v1/debug/benchmark/sessions/$sessionId/download',
          ),
          headers: const <String, String>{'Range': 'bytes=4-7'},
        ),
        sessionId,
      );

      expect(partialResponse.statusCode, 206);
      expect(partialResponse.headers['Content-Range'], 'bytes 4-7/32');
      expect(await _readBody(partialResponse), <int>[4, 5, 6, 7]);
    });
  });
}

Future<List<int>> _readBody(Response response) async {
  return response.read().fold<List<int>>(<int>[], (buffer, chunk) {
    buffer.addAll(chunk);
    return buffer;
  });
}
