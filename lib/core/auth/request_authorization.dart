import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'account_models.dart';
import 'auth_session_store.dart';
import 'bearer_auth_middleware.dart';

Response? ensureAuthenticatedRequestContext(Request request) {
  final context = authenticatedRequestContextFromRequest(request);
  if (context != null) {
    return null;
  }

  return buildRequestAuthorizationErrorResponse(
    statusCode: 401,
    code: 'AUTH_REQUIRED',
    message: 'Bearer token is required',
  );
}

Response? ensureRequestHasAnyRole(
  Request request, {
  required Set<AccountRole> allowedRoles,
  String message = 'This account is not allowed to perform this action',
}) {
  final missingAuthResponse = ensureAuthenticatedRequestContext(request);
  if (missingAuthResponse != null) {
    return missingAuthResponse;
  }

  if (requestHasAnyRole(request, allowedRoles)) {
    return null;
  }

  return buildRequestAuthorizationErrorResponse(
    statusCode: 403,
    code: 'AUTH_FORBIDDEN',
    message: message,
  );
}

bool requestHasAnyRole(Request request, Set<AccountRole> allowedRoles) {
  final context = authenticatedRequestContextFromRequest(request);
  return context != null && allowedRoles.contains(context.role);
}

AuthenticatedRequestContext? requireAuthenticatedRequestContext(
  Request request,
) {
  return authenticatedRequestContextFromRequest(request);
}

Response buildRequestAuthorizationErrorResponse({
  required int statusCode,
  required String code,
  required String message,
}) {
  return Response(
    statusCode,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'code': code, 'message': message, 'details': {}}),
  );
}
