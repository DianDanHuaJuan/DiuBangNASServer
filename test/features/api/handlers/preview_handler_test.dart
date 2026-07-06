import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/core/auth/auth_headers.dart';
import 'package:nas_server/features/api/handlers/preview_handler.dart';
import 'package:nas_server/features/webdav/resolvers/dav_resource_resolver.dart';
import 'package:nas_server/features/webdav/resources/dav_resource.dart';
import 'package:nas_server/features/webdav/utils/content_type_resolver.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('PreviewHandler', () {
    test(
      'returns progressive metadata for videos with poster and auth headers',
      () async {
        final resolver = _FakeDavResourceResolver({
          '/fs/movies/demo.mp4': DavResource.fsFile(
            davPath: '/fs/movies/demo.mp4',
            name: 'demo.mp4',
            size: 123456,
            contentType: 'video/mp4',
            lastModified: DateTime.utc(2026, 4, 8, 12),
          ),
        });
        final handler = PreviewHandler(
          resourceResolver: resolver,
          contentTypeResolver: ContentTypeResolver(),
        ).handler;

        final response = await handler(
          Request(
            'GET',
            Uri.parse(
              'http://10.0.0.8:9090/api/v1/preview/meta?path=%2Ffs%2Fmovies%2Fdemo.mp4',
            ),
            headers: const {'Authorization': 'Basic abc123'},
          ),
        );

        expect(response.statusCode, 200);
        final json =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(json['kind'], 'video');
        expect(json['strategy'], 'progressive');
        expect(json['url'], 'http://10.0.0.8:9090/dav/fs/movies/demo.mp4');
        expect(json['headers'], const {'Authorization': 'Basic abc123'});
        expect(json['contentType'], 'video/mp4');
        expect(json['size'], 123456);
        expect(
          json['thumbnailUrl'],
          'http://10.0.0.8:9090/api/v1/thumbnail?path=%2Ffs%2Fmovies%2Fdemo.mp4&type=grid',
        );
        expect(
          json['posterUrl'],
          'http://10.0.0.8:9090/api/v1/thumbnail?path=%2Ffs%2Fmovies%2Fdemo.mp4&type=preview',
        );
        expect(json['expiresAt'], isNull);
      },
    );

    test(
      'returns preview metadata for images and forwards auth context headers',
      () async {
        final resolver = _FakeDavResourceResolver({
          '/fs/photos/cover.jpg': DavResource.fsFile(
            davPath: '/fs/photos/cover.jpg',
            name: 'cover.jpg',
            size: 2048,
            contentType: 'image/jpeg',
            lastModified: DateTime.utc(2026, 4, 8, 12),
          ),
        });
        final handler = PreviewHandler(
          resourceResolver: resolver,
          contentTypeResolver: ContentTypeResolver(),
        ).handler;

        final response = await handler(
          Request(
            'GET',
            Uri.parse(
              'http://10.0.0.8:9090/api/v1/preview/meta?path=%2Ffs%2Fphotos%2Fcover.jpg',
            ),
            headers: const {
              'Authorization': 'Bearer demo-token',
              clientIdHeaderName: 'windows-client-01',
            },
          ),
        );

        expect(response.statusCode, 200);
        final json =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(json['kind'], 'image');
        expect(json['strategy'], 'direct');
        expect(
          json['url'],
          'http://10.0.0.8:9090/api/v1/thumbnail?path=%2Ffs%2Fphotos%2Fcover.jpg&type=preview',
        );
        expect(json['headers'], const {
          'Authorization': 'Bearer demo-token',
          clientIdHeaderName: 'windows-client-01',
        });
        expect(json['contentType'], 'image/jpeg');
        expect(json['size'], 2048);
        expect(
          json['thumbnailUrl'],
          'http://10.0.0.8:9090/api/v1/thumbnail?path=%2Ffs%2Fphotos%2Fcover.jpg&type=grid',
        );
        expect(json['posterUrl'], isNull);
      },
    );

    test(
      'falls back to the original file URL for images when preview thumbnails are disabled',
      () async {
        final resolver = _FakeDavResourceResolver({
          '/fs/photos/cover.jpg': DavResource.fsFile(
            davPath: '/fs/photos/cover.jpg',
            name: 'cover.jpg',
            size: 2048,
            contentType: 'image/jpeg',
            lastModified: DateTime.utc(2026, 4, 8, 12),
          ),
        });
        final handler = PreviewHandler(
          resourceResolver: resolver,
          contentTypeResolver: ContentTypeResolver(),
          thumbnailEnabled: false,
        ).handler;

        final response = await handler(
          Request(
            'GET',
            Uri.parse(
              'http://10.0.0.8:9090/api/v1/preview/meta?path=%2Ffs%2Fphotos%2Fcover.jpg',
            ),
          ),
        );

        expect(response.statusCode, 200);
        final json =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(json['kind'], 'image');
        expect(json['strategy'], 'direct');
        expect(json['url'], 'http://10.0.0.8:9090/dav/fs/photos/cover.jpg');
        expect(json['headers'], isNull);
        expect(json['thumbnailUrl'], isNull);
        expect(json['posterUrl'], isNull);
      },
    );

    test('returns unsupported payload for unsupported file types', () async {
      final resolver = _FakeDavResourceResolver({
        '/fs/docs/readme.txt': DavResource.fsFile(
          davPath: '/fs/docs/readme.txt',
          name: 'readme.txt',
          size: 32,
          contentType: 'text/plain',
          lastModified: DateTime.utc(2026, 4, 8, 12),
        ),
      });
      final handler = PreviewHandler(
        resourceResolver: resolver,
        contentTypeResolver: ContentTypeResolver(),
      ).handler;

      final response = await handler(
        Request(
          'GET',
          Uri.parse(
            'http://10.0.0.8:9090/api/v1/preview/meta?path=%2Ffs%2Fdocs%2Freadme.txt',
          ),
        ),
      );

      expect(response.statusCode, 200);
      final json =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(json['kind'], isNull);
      expect(json['strategy'], 'unsupported');
      expect(json['url'], isNull);
      expect(json['headers'], isNull);
      expect(json['thumbnailUrl'], isNull);
      expect(json['posterUrl'], isNull);
    });

    test(
      'rejects library paths when preview is limited to the shared directory',
      () async {
        final handler = PreviewHandler(
          resourceResolver: _FakeDavResourceResolver(const {}),
          contentTypeResolver: ContentTypeResolver(),
          mediaLibraryEnabled: false,
        ).handler;

        final response = await handler(
          Request(
            'GET',
            Uri.parse(
              'http://10.0.0.8:9090/api/v1/preview/meta?path=%2Flibrary%2Fcover.jpg',
            ),
          ),
        );

        expect(response.statusCode, 400);
        final json =
            jsonDecode(await response.readAsString()) as Map<String, dynamic>;
        expect(json['code'], 'INVALID_PARAMS');
        expect(json['message'], 'Path must start with /fs');
      },
    );
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
