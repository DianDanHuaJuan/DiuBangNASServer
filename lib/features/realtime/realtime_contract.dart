const String realtimeWebSocketPath = '/api/v1/realtime/ws';
const Duration realtimeHelloTimeout = Duration(seconds: 10);
const Duration realtimeHeartbeatInterval = Duration(seconds: 15);
const Duration realtimeHeartbeatTimeout = Duration(seconds: 45);
const int realtimeCloseCodePolicyViolation = 4000;
const int realtimeCloseCodeSessionRevoked = 4001;
const int realtimeCloseCodeHelloTimeout = 4002;
const int realtimeCloseCodeInvalidMessage = 4003;
const int realtimeCloseCodeConnectionReplaced = 4004;
const int realtimeCloseCodeHeartbeatTimeout = 4005;
const int realtimeCloseCodeServerShutdown = 4006;

abstract final class RealtimeMessageType {
  static const String hello = 'hello';
  static const String helloAck = 'hello.ack';
  static const String heartbeat = 'heartbeat';
  static const String heartbeatAck = 'heartbeat.ack';
  static const String presenceChanged = 'presence.changed';
  static const String dashboardUpdated = 'dashboard.updated';
  static const String serverStateChanged = 'server.state.changed';
  static const String sessionRevoked = 'session.revoked';
  static const String connectionReplaced = 'connection.replaced';
  static const String transferCreated = 'transfer.created';
  static const String transferUploadProgress = 'transfer.upload.progress';
  static const String transferReady = 'transfer.ready';
  static const String transferDownloadProgress = 'transfer.download.progress';
  static const String transferCompleted = 'transfer.completed';
  static const String transferFailed = 'transfer.failed';
  static const String transferCancelled = 'transfer.cancelled';
  static const String error = 'error';
}
