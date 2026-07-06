// 文件输入：DeviceInfoService, KeyValueStore, FileSystemService
// 文件职责：处理 GET /api/v1/bootstrap 请求，返回服务器信息、fileAccess、capabilities
// 文件对外接口：BootstrapHandler
// 文件包含：BootstrapHandler
import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../../../core/auth/request_authorization.dart';
import '../../../core/platform/app_platform.dart';
import '../../../core/runtime/runtime_build_info.dart';
import '../../realtime/realtime_contract.dart';

class BootstrapHandler {
  BootstrapHandler({
    required String serverName,
    required String serverId,
    required String serverVersion,
    required String caSha256,
    bool mediaLibraryEnabled = false,
    bool imagePreviewEnabled = true,
    bool videoPreviewEnabled = true,
    bool progressiveVideoPreviewEnabled = true,
    bool hlsVideoPreviewEnabled = false,
    bool transcodeVideoPreviewEnabled = false,
    bool thumbnailEnabled = true,
    bool batchThumbnailEnabled = true,
  }) : _serverName = serverName,
       _serverId = serverId,
       _serverVersion = serverVersion,
       _caSha256 = caSha256,
       _mediaLibraryEnabled = mediaLibraryEnabled,
       _imagePreviewEnabled = imagePreviewEnabled,
       _videoPreviewEnabled = videoPreviewEnabled,
       _progressiveVideoPreviewEnabled = progressiveVideoPreviewEnabled,
       _hlsVideoPreviewEnabled = hlsVideoPreviewEnabled,
       _transcodeVideoPreviewEnabled = transcodeVideoPreviewEnabled,
       _thumbnailEnabled = thumbnailEnabled,
       _batchThumbnailEnabled = batchThumbnailEnabled;

  final String _serverName;
  final String _serverId;
  final String _serverVersion;
  final String _caSha256;
  final bool _mediaLibraryEnabled;
  final bool _imagePreviewEnabled;
  final bool _videoPreviewEnabled;
  final bool _progressiveVideoPreviewEnabled;
  final bool _hlsVideoPreviewEnabled;
  final bool _transcodeVideoPreviewEnabled;
  final bool _thumbnailEnabled;
  final bool _batchThumbnailEnabled;

  Handler get handler {
    return (Request request) async {
      final authError = ensureAuthenticatedRequestContext(request);
      if (authError != null) {
        return authError;
      }
      final authContext = requireAuthenticatedRequestContext(request)!;
      final baseUrl = _buildAbsoluteUrl(request: request, path: '');

      final response = {
        'server': {
          'id': _serverId,
          'name': _serverName,
          'version': _serverVersion,
          'platform': AppPlatform.identifier,
          'build': RuntimeBuildInfo.toJson(),
          'status': 'online',
          'tls': {'enabled': true, 'caSha256': _caSha256},
        },
        'auth': {
          'type': authContext.isDevice ? 'device' : 'owner',
          'tokenType': authContext.isDevice ? 'Device' : 'Bearer',
          'sessionEndpoint': '/api/v1/auth/session',
          if (authContext.isDevice)
            'refreshEndpoint': '/api/v1/auth/device/refresh',
          if (authContext.isOwner)
            'currentSession': {
              'ownerId': authContext.ownerId,
              'role': authContext.role.name,
              'username': authContext.username,
              'label': authContext.label,
              'sessionId': authContext.sessionId,
            },
          if (authContext.isDevice)
            'currentDevice': {
              'deviceId': authContext.deviceId,
              'deviceName': authContext.deviceName,
              'role': authContext.role.name,
              'sessionId': authContext.sessionId,
            },
        },
        'fileAccess': {
          'protocol': 'webdav',
          'webdav': {
            'baseUrl': _buildAbsoluteUrl(request: request, path: '/dav'),
          },
          'roots': [
            {
              'id': 'fs',
              'name': _serverName,
              'path': '/fs',
              'type': 'local',
              'writable': true,
            },
            if (_mediaLibraryEnabled)
              {
                'id': 'library',
                'name': '媒体库',
                'path': '/library',
                'type': 'mediastore',
                'writable': false,
              },
          ],
        },
        'capabilities': {
          'security': {'transport': 'https', 'caSha256': _caSha256},
          'dashboard': true,
          'upload': {
            'streaming': true,
            'directoryHierarchy': false,
            'conflictPolicies': ['skip', 'overwrite', 'autoRename'],
            'defaultConflictPolicy': 'fail',
          },
          'preview': {
            'image': _imagePreviewEnabled,
            'video': _videoPreviewEnabled,
            'thumbnail': _thumbnailEnabled,
            'batchThumbnail': _batchThumbnailEnabled,
            'progressive': _progressiveVideoPreviewEnabled,
            'hls': _hlsVideoPreviewEnabled,
            'transcode': _transcodeVideoPreviewEnabled,
          },
          'relay': {
            'enabled': true,
            'requireAccept': false,
            'deliveryMode': 'store_on_nas',
            'transportProtocol': 'webdav',
            'webdavBasePath': '/dav/relay',
          },
          'realtime': {
            'websocket': true,
            'endpoint': realtimeWebSocketPath,
            'heartbeatIntervalSec': realtimeHeartbeatInterval.inSeconds,
            'heartbeatTimeoutSec': realtimeHeartbeatTimeout.inSeconds,
          },
        },
        'baseUrl': baseUrl,
      };

      return Response.ok(
        jsonEncode(response),
        headers: {'Content-Type': 'application/json'},
      );
    };
  }

  String _buildAbsoluteUrl({
    required Request request,
    required String path,
    Map<String, String>? queryParameters,
  }) {
    final requestUri = request.requestedUri;
    return Uri(
      scheme: requestUri.scheme,
      userInfo: requestUri.userInfo,
      host: requestUri.host,
      port: requestUri.hasPort ? requestUri.port : null,
      path: path,
      queryParameters: queryParameters,
    ).toString();
  }
}
