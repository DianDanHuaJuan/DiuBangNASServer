import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../../../core/device/system_status_cache.dart';
import 'dashboard_payload_builder.dart';

class DashboardHandler {
  DashboardHandler({
    DashboardPayloadBuilder? payloadBuilder,
    SystemStatusCache? systemStatusCache,
    int? port,
    DateTime? startedAt,
  }) : _payloadBuilder =
           payloadBuilder ??
           DashboardPayloadBuilder(
             systemStatusCache: systemStatusCache!,
             port: port!,
             startedAt: startedAt!,
           );

  final DashboardPayloadBuilder _payloadBuilder;

  Handler get handler {
    return (Request request) async {
      return Response.ok(
        jsonEncode(_payloadBuilder.build()),
        headers: {'Content-Type': 'application/json'},
      );
    };
  }
}
