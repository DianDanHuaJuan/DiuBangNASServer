import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/app/router/app_router.dart';
import 'package:nas_server/app/router/route_names.dart';

void main() {
  testWidgets('resolves the server management route', (tester) async {
    final router = AppRouter(
      serverManagementPageBuilder: (_) =>
          const SizedBox(key: Key('server-page')),
    );

    await tester.pumpWidget(
      MaterialApp(
        initialRoute: RouteNames.serverManagement,
        onGenerateRoute: router.generateRoute,
      ),
    );

    expect(find.byKey(const Key('server-page')), findsOneWidget);
  });
}
