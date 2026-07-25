import 'dart:io';

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
    expect(find.text('已选0/120条回复'), findsOneWidget);
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
    expect(find.text('已选0/120条回复'), findsOneWidget);

    final replyInkWells = find.descendant(
      of: find.byType(ReplyItemGrpc),
      matching: find.byType(InkWell),
    );
    final selectableReply = replyInkWells
        .evaluate()
        .map((element) => element.widget)
        .whereType<InkWell>()
        .firstWhere((widget) => widget.onTap != null);

    await tester.tap(find.byWidget(selectableReply));
    await tester.pump();

    expect(find.text('已选1/120条回复'), findsOneWidget);
  });

  testWidgets('保存评论页仍可通过关闭按钮退出', (tester) async {
    await _openSavePanel(tester, _longReply());

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.byType(SavePanel), findsNothing);
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
