import 'dart:io';

import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/pages/save_panel/view.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  setUpAll(() async {
    final storageDir = await Directory.systemTemp.createTemp(
      'pilinara_save_panel_test_',
    );
    appSupportDirPath = storageDir.path;
    await GStorage.init();
  });

  setUp(() {
    Get.testMode = true;
  });

  tearDown(Get.reset);

  testWidgets('保存评论滚动区在惯性滚动期间仍可接收点击', (tester) async {
    await _openSavePanel(tester, _longReply());

    final scrollViewFinder = find.byType(SingleChildScrollView);
    final scrollView = tester.widget<SingleChildScrollView>(scrollViewFinder);
    expect(scrollView.hitTestBehavior, HitTestBehavior.opaque);

    final scrollableFinder = find.descendant(
      of: scrollViewFinder,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollableFinder).position;

    await tester.fling(scrollViewFinder, const Offset(0, -900), 8000);
    await tester.pump(const Duration(milliseconds: 16));
    final firstOffset = position.pixels;
    await tester.pump(const Duration(milliseconds: 32));
    expect(position.pixels, greaterThan(firstOffset));

    final tapPosition =
        tester.getTopLeft(scrollViewFinder) + const Offset(24, 200);
    final gesture = await tester.startGesture(tapPosition);
    await tester.pump(const Duration(milliseconds: 16));
    final heldOffset = position.pixels;
    await tester.pump(const Duration(milliseconds: 200));

    expect(position.pixels, closeTo(heldOffset, 0.1));
    expect(find.byType(SavePanel), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(position.pixels, closeTo(heldOffset, 0.1));
    expect(find.byType(SavePanel), findsOneWidget);
    expect(find.text('主评论保留 · 已选0/120条跟评'), findsOneWidget);
  });

  testWidgets('惯性滚动期间点击底部按钮区域只会暂停滚动', (tester) async {
    await _openSavePanel(tester, _longReply());

    final scrollViewFinder = find.byType(SingleChildScrollView);
    final scrollableFinder = find.descendant(
      of: scrollViewFinder,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollableFinder).position;
    final closeButtonCenter = tester.getCenter(find.byIcon(Icons.clear));

    await tester.fling(scrollViewFinder, const Offset(0, -900), 8000);
    await tester.pump(const Duration(milliseconds: 16));
    final firstOffset = position.pixels;
    await tester.pump(const Duration(milliseconds: 32));
    expect(position.pixels, greaterThan(firstOffset));

    final gesture = await tester.startGesture(closeButtonCenter);
    await tester.pump(const Duration(milliseconds: 16));
    final heldOffset = position.pixels;
    await tester.pump(const Duration(milliseconds: 200));

    expect(position.pixels, closeTo(heldOffset, 0.1));
    expect(find.byType(SavePanel), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SavePanel), findsOneWidget);
    expect(find.text('主评论保留 · 已选0/120条跟评'), findsOneWidget);
  });

  testWidgets('保存评论页不能通过点击遮罩退出', (tester) async {
    await _openSavePanel(tester, _longReply());

    final barriers = tester
        .widgetList<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier))
        .toList();

    expect(barriers, isNotEmpty);
    expect(barriers.last.dismissible, isFalse);
  });

  testWidgets('保存评论静止时仍可选择跟评', (tester) async {
    await _openSavePanel(tester, _longReply());
    expect(find.text('主评论保留 · 已选0/120条跟评'), findsOneWidget);

    final replyInkWells = find.descendant(
      of: find.byType(ReplyItemGrpc),
      matching: find.byType(InkWell),
    );
    final selectableReply = replyInkWells
        .evaluate()
        .map((element) => element.widget)
        .whereType<InkWell>()
        .firstWhere((widget) => widget.onTap != null);

    final tapPosition = tester.getCenter(find.byWidget(selectableReply));
    await tester.tapAt(tapPosition);
    await tester.pump();

    expect(find.text('主评论保留 · 已选1/120条跟评'), findsOneWidget);

    await tester.tapAt(tapPosition);
    await tester.pump();

    expect(find.text('主评论保留 · 已选0/120条跟评'), findsOneWidget);
  });

  testWidgets('图片跟评会显示在保存评论页中', (tester) async {
    await _openSavePanel(tester, _replyWithPicture());

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is NetworkImgLayer &&
            widget.src == 'https://example.invalid/child.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('保存评论页仍可通过关闭按钮退出', (tester) async {
    await _openSavePanel(tester, _longReply());

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.byType(SavePanel), findsNothing);
  });

  test('超长截图会降低倍率或被安全阻止', () {
    expect(calculateSavePanelPixelRatio(const Size(430, 932)), 3);
    expect(
      calculateSavePanelPixelRatio(const Size(430, 10000)),
      closeTo(1.2, 0.001),
    );
    expect(calculateSavePanelPixelRatio(const Size(430, 20000)), isNull);
  });
}

Future<void> _openSavePanel(WidgetTester tester, ReplyInfo reply) async {
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => SavePanel.toSavePanel(item: reply),
            child: const Text('打开保存评论'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('打开保存评论'));
  await tester.pumpAndSettle();
  expect(find.byType(SavePanel), findsOneWidget);
}

ReplyInfo _longReply() {
  final rootId = Int64(1);
  final replies = List.generate(120, (index) {
    return ReplyInfo(
      id: Int64(index + 2),
      root: rootId,
      parent: rootId,
      member: Member(name: '用户$index'),
      content: Content(message: '第 $index 条用于验证滚动停止行为的回复'),
      replyControl: ReplyControl(),
    );
  });

  return ReplyInfo(
    id: rootId,
    count: Int64(replies.length),
    replies: replies,
    member: Member(name: '根评论用户'),
    content: Content(message: '用于测试保存评论交互的根评论'),
    replyControl: ReplyControl(),
  );
}

ReplyInfo _replyWithPicture() {
  final rootId = Int64(1);
  final child = ReplyInfo(
    id: Int64(2),
    root: rootId,
    parent: rootId,
    member: Member(name: '图片用户'),
    content: Content(
      pictures: [
        Picture(
          imgSrc: 'https://example.invalid/child.png',
          imgWidth: 100,
          imgHeight: 100,
        ),
      ],
    ),
    replyControl: ReplyControl(),
  );

  return ReplyInfo(
    id: rootId,
    count: Int64(1),
    replies: [child],
    member: Member(name: '根评论用户'),
    content: Content(message: '包含图片跟评的根评论'),
    replyControl: ReplyControl(),
  );
}
