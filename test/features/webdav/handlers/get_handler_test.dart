import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/features/webdav/handlers/get_handler.dart';
import 'package:nas_server/features/webdav/readers/dav_content_reader.dart';
import 'package:nas_server/features/webdav/resolvers/dav_resource_resolver.dart';
import 'package:nas_server/features/webdav/resources/dav_resource.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('GetHandler', () {
    test('serves full content with range-friendly headers', () async {
      final content = utf8.encode('hello world');
      final resource = DavResource.fsFile(
        davPath: '/fs/demo.mp4',
        name: 'demo.mp4',
        size: content.length,
        contentType: 'video/mp4',
        lastModified: DateTime.utc(2026, 4, 8, 12),
      );
      final handler = GetHandler(
        resolver: _FakeDavResourceResolver({'/fs/demo.mp4': resource}),
        contentReader: _FakeDavContentReader(content),
      );

      final response = await handler.handle(
        Request('GET', Uri.parse('http://localhost/fs/demo.mp4')),
      );

      expect(response.statusCode, 200);
      expect(response.headers['Content-Length'], '${content.length}');
      expect(response.headers['Accept-Ranges'], 'bytes');
      expect(
        response.headers['Content-Disposition'],
        contains('filename="demo.mp4"'),
      );
      expect(response.headers['Last-Modified'], isNotNull);
      expect(await _readBody(response), content);
    });

    test('serves suffix ranges with 206 response', () async {
      final content = utf8.encode('hello world');
      final resource = DavResource.fsFile(
        davPath: '/fs/demo.mp4',
        name: 'demo.mp4',
        size: content.length,
        contentType: 'video/mp4',
      );
      final handler = GetHandler(
        resolver: _FakeDavResourceResolver({'/fs/demo.mp4': resource}),
        contentReader: _FakeDavContentReader(content),
      );

      final response = await handler.handle(
        Request(
          'GET',
          Uri.parse('http://localhost/fs/demo.mp4'),
          headers: const {'Range': 'bytes=-5'},
        ),
      );

      expect(response.statusCode, 206);
      expect(response.headers['Content-Range'], 'bytes 6-10/11');
      expect(response.headers['Content-Length'], '5');
      expect(utf8.decode(await _readBody(response)), 'world');
    });

    test('rejects multi-range requests', () async {
      final content = utf8.encode('hello world');
      final resource = DavResource.fsFile(
        davPath: '/fs/demo.mp4',
        name: 'demo.mp4',
        size: content.length,
        contentType: 'video/mp4',
      );
      final handler = GetHandler(
        resolver: _FakeDavResourceResolver({'/fs/demo.mp4': resource}),
        contentReader: _FakeDavContentReader(content),
      );

      final response = await handler.handle(
        Request(
          'GET',
          Uri.parse('http://localhost/fs/demo.mp4'),
          headers: const {'Range': 'bytes=0-1,4-5'},
        ),
      );

      expect(response.statusCode, 416);
      expect(response.headers['Content-Range'], 'bytes */11');
    });
  });
}

Future<List<int>> _readBody(Response response) async {
  return response.read().fold<List<int>>(<int>[], (buffer, chunk) {
    buffer.addAll(chunk);
    return buffer;
  });
}

class _FakeDavResourceResolver implements DavResourceResolver {
  _FakeDavResourceResolver(this._resources);

  final Map<String, DavResource> _resources;

  @override
  Future<List<DavResource>> listChildren(String davPath) async => const [];

  @override
  Future<DavResource?> resolve(String davPath) async => _resources[davPath];
}

class _FakeDavContentReader implements DavContentReader {
  _FakeDavContentReader(this._content);

  final List<int> _content;

  @override
  Future<int> getFileSize(DavResource resource) async => _content.length;

  @override
  Stream<List<int>> openRead(
    DavResource resource, {
    int? rangeStart,
    int? rangeEnd,
  }) {
    final start = rangeStart ?? 0;
    final end = rangeEnd ?? (_content.length - 1);
    if (start < 0 || start >= _content.length || end < start) {
      return Stream<List<int>>.empty();
    }
    final safeEnd = end >= _content.length ? _content.length - 1 : end;
    return Stream<List<int>>.fromIterable([
      _content.sublist(start, safeEnd + 1),
    ]);
  }
}
