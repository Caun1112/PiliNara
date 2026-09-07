import 'package:PiliPlus/common/widgets/global_back_button.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/live/huya/route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('虎牙直播横屏隐藏悬浮返回按钮，转回竖屏后恢复并可返回', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = GlobalBackButtonObserver();
    await tester.pumpWidget(_app(navigatorKey, observer));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.push(
      HuyaPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('虎牙直播间')),
        showGlobalBackButton: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);

    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpAndSettle();
    expect(find.text('虎牙直播间'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
  });

  testWidgets('横屏进入虎牙直播隐藏悬浮返回，其他页面和弹层保持原有行为', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = GlobalBackButtonObserver();
    await tester.pumpWidget(_app(navigatorKey, observer));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('普通页面')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);

    navigatorKey.currentState!.push(
      HuyaPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('虎牙直播间')),
        showGlobalBackButton: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsNothing);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('普通页面'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    for (final showBackButton in [true, false]) {
      navigatorKey.currentState!.push(
        PublishRoute<void>(
          pageBuilder: (_, _, _) => const SizedBox.expand(),
          showGlobalBackButton: showBackButton,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('返回'),
        showBackButton ? findsOneWidget : findsNothing,
      );
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
    }
  });
}

Widget _app(
  GlobalKey<NavigatorState> navigatorKey,
  GlobalBackButtonObserver observer,
) {
  return GetMaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [observer],
    builder: (context, child) => Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (_) => GlobalBackButtonOverlay(
            observer: observer,
            onBack: () => navigatorKey.currentState!.maybePop(),
            child: child!,
          ),
        ),
      ],
    ),
    home: const Scaffold(body: Text('首页')),
  );
}
