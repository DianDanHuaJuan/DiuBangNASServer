// 文件输入：PairingService
// 文件职责：处理配对相关 HTTP 请求
// 文件对外接口：PairingHandler
// 文件包含：PairingHandler
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/pairing_service.dart';

class PairingHandler {
  PairingHandler({
    required PairingService pairingService,
    required String serverId,
    required String serverName,
    required String localIp,
    required int port,
  }) : _pairingService = pairingService,
       _serverId = serverId,
       _serverName = serverName,
       _localIp = localIp,
       _port = port;

  final PairingService _pairingService;
  final String _serverId;
  final String _serverName;
  final String _localIp;
  final int _port;

  Handler get handler {
    final router = Router();
    router.get('/ca-cert', getCaCert);
    router.post('/device-enroll', enrollDevice);
    return router.call;
  }

  Future<Response> getCaCert(Request request) async {
    try {
      final certPem = await _pairingService.getCaCertificatePem(
        serverId: _serverId,
        serverName: _serverName,
        localIp: _localIp,
        port: _port,
      );

      return Response.ok(
        jsonEncode({'cert': certPem}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'code': 'CERT_FETCH_ERROR', 'message': '获取证书失败: $e'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> enrollDevice(Request request) async {
    return _handleEnrollment(request);
  }

  Future<Response> _handleEnrollment(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final clientPub = data['client_pub'] as String?;
      final serverId = data['server_id'] as String?;
      final timestamp = data['timestamp'];
      final deviceId = data['device_id'] as String?;
      final deviceName = data['device_name'] as String?;
      final physicalDeviceId = data['physical_device_id'] as String?;
      final devicePlatform = data['device_platform'] as String?;
      final deviceBrand = data['device_brand'] as String?;
      final deviceModel = data['device_model'] as String?;

      if (clientPub == null || clientPub.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'code': 'MISSING_CLIENT_PUB',
            'message': '缺少客户端公钥',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (serverId == null || serverId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'code': 'MISSING_SERVER_ID', 'message': '缺少服务器标识'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final timestampSeconds = switch (timestamp) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value) ?? -1,
        _ => -1,
      };
      if (timestampSeconds <= 0) {
        return Response.badRequest(
          body: jsonEncode({
            'code': 'INVALID_TIMESTAMP',
            'message': '缺少有效的时间戳',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (deviceId == null || deviceId.trim().isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'code': 'MISSING_DEVICE_ID', 'message': '缺少设备标识'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (deviceName == null || deviceName.trim().isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'code': 'MISSING_DEVICE_NAME', 'message': '缺少设备名称'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (serverId != _serverId) {
        return Response.forbidden(
          jsonEncode({'code': 'SERVER_ID_MISMATCH', 'message': '服务器标识不匹配'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final encryptedEnrollment = await _pairingService.enrollDevice(
        serverId: serverId,
        clientPublicKeyBase64: clientPub,
        timestampSeconds: timestampSeconds,
        deviceId: deviceId,
        deviceName: deviceName,
        physicalDeviceId: physicalDeviceId,
        devicePlatform: devicePlatform,
        deviceBrand: deviceBrand,
        deviceModel: deviceModel,
      );

      return Response.ok(
        jsonEncode(encryptedEnrollment.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } on PairingException catch (e) {
      return Response.badRequest(
        body: jsonEncode({'code': 'PAIRING_ERROR', 'message': e.message}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'code': 'DEVICE_ENROLL_ERROR',
          'message': '设备注册失败: $e',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }
}
