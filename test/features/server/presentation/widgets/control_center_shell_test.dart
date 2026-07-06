import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_server/features/server/presentation/widgets/control_center_shell.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    required TargetPlatform platform,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: ControlCenterShell(
          serviceChild: const Center(child: Text('服务区域')),
          backupFilesChild: const Center(child: Text('文件区域')),
          devicesChild: const Center(child: Text('设备区域')),
          settingsChild: const Center(child: Text('设置区域')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('switches between the service and devices tabs on desktop', (
    tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1280, 800),
      platform: TargetPlatform.windows,
    );

    expect(find.text('控制中心'), findsOneWidget);
    expect(find.text('服务区域'), findsOneWidget);
    expect(find.text('设备区域'), findsNothing);

    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();

    expect(find.text('服务区域'), findsNothing);
    expect(find.text('设备区域'), findsOneWidget);
  });

  testWidgets('reveals the sidebar from the screen edge on narrow desktop', (
    tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1000, 800),
      platform: TargetPlatform.windows,
    );

    final sidebar = find.byKey(
      const ValueKey<String>('control-center-sidebar-panel'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(400, 200));
    await tester.pump();

    expect(tester.getTopLeft(sidebar).dx, lessThan(0));

    await mouse.moveTo(const Offset(26, 200));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(sidebar).dx, 24);

    await mouse.moveTo(const Offset(400, 200));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(sidebar).dx, lessThan(0));
  });

  testWidgets('keeps bottom navigation on touch layouts', (tester) async {
    await pumpShell(
      tester,
      size: const Size(800, 800),
      platform: TargetPlatform.android,
    );

    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();

    expect(find.text('设备区域'), findsOneWidget);
  });

  testWidgets('switches to the files tab from desktop navigation', (
    tester,
  ) async {
    await pumpShell(
      tester,
      size: const Size(1280, 800),
      platform: TargetPlatform.windows,
    );

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();

    expect(find.text('文件区域'), findsOneWidget);
    expect(find.text('服务区域'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
