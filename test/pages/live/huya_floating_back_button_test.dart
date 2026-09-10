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
        builder: (_) => const Scaffold(
          body: Column(
            children: [
              Text('虎牙直播间'),
              Expanded(child: _PlaybackProbe()),
            ],
          ),
        ),
        showGlobalBackButton: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    final playback = tester.state<_PlaybackProbeState>(
      find.byType(_PlaybackProbe),
    );
    final texture = tester.renderObject(find.byType(Texture));

    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpAndSettle();
    expect(find.text('虎牙直播间'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
    expect(playback.deactivations, 0);
    expect(playback.disposed, isFalse);
    expect(tester.renderObject(find.byType(Texture)), same(texture));

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(playback.deactivations, 0);
    expect(playback.disposed, isFalse);
    expect(tester.renderObject(find.byType(Texture)), same(texture));
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
    expect(playback.disposed, isTrue);
  });

  testWidgets('B站直播横屏隐藏悬浮返回，恢复竖屏后可正常返回', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = GlobalBackButtonObserver();
    await tester.pumpWidget(_app(navigatorKey, observer));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/liveRoom'),
        builder: (_) => const Scaffold(body: Text('B站直播间')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);

    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpAndSettle();
    expect(find.text('B站直播间'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);

    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
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

class _PlaybackProbe extends StatefulWidget {
  const _PlaybackProbe();

  @override
  State<_PlaybackProbe> createState() => _PlaybackProbeState();
}

class _PlaybackProbeState extends State<_PlaybackProbe> {
  int deactivations = 0;
  bool disposed = false;

  @override
  void deactivate() {
    deactivations++;
    super.deactivate();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Texture(textureId: 1);
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
