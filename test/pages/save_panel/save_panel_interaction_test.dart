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

  testWidgets('惯性滚动期间点击跟评只会暂停，不会误选或退出', (tester) async {
    await _openSavePanel(tester, _longReply());

    final scrollViewFinder = find.byType(SingleChildScrollView);
    final scrollableFinder = find.descendant(
      of: scrollViewFinder,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollableFinder).position;
    final selectableReplyFinder = find
        .descendant(
          of: find.byType(ReplyItemGrpc),
          matching: find.byWidgetPredicate(
            (widget) => widget is InkWell && widget.onTap != null,
          ),
        )
        .hitTestable()
        .first;
    final tapPosition = tester.getCenter(selectableReplyFinder);

    await tester.fling(scrollViewFinder, const Offset(0, -900), 8000);
    await tester.pump(const Duration(milliseconds: 32));
    final scrollingOffset = position.pixels;
    await tester.pump(const Duration(milliseconds: 32));
    expect(position.pixels, greaterThan(scrollingOffset));

    await tester.tapAt(tapPosition);
    await tester.pump(const Duration(milliseconds: 200));

    final stoppedOffset = position.pixels;
    await tester.pump(const Duration(milliseconds: 200));
    expect(position.pixels, closeTo(stoppedOffset, 0.1));
    expect(find.byType(SavePanel), findsOneWidget);
    expect(find.text('主评论保留 · 已选0/120条跟评'), findsOneWidget);

    await tester.tap(
      find
          .descendant(
            of: find.byType(ReplyItemGrpc),
            matching: find.byWidgetPredicate(
              (widget) => widget is InkWell && widget.onTap != null,
            ),
          )
          .hitTestable()
          .first,
    );
    await tester.pump();

    expect(find.text('主评论保留 · 已选1/120条跟评'), findsOneWidget);
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

    await tester.tap(
      find
          .ancestor(
            of: find.text('已选入图片'),
            matching: find.byType(InkWell),
          )
          .first,
    );
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

  testWidgets('点击图片跟评只切换选择，不会退出保存页', (tester) async {
    await _openSavePanel(tester, _replyWithPicture());

    final imageFinder = find.byWidgetPredicate(
      (widget) =>
          widget is NetworkImgLayer &&
          widget.src == 'https://example.invalid/child.png',
    );
    await tester.tap(imageFinder);
    await tester.pump();

    expect(find.byType(SavePanel), findsOneWidget);
    expect(find.text('主评论保留 · 已选1/1条跟评'), findsOneWidget);
  });

  testWidgets('智能选评会给出理由、故事卡和成图排序入口', (tester) async {
    await _openSavePanel(tester, _smartReply());

    expect(find.text('智能选评'), findsOneWidget);
    expect(find.byTooltip('本地分析，不上传评论'), findsOneWidget);

    await tester.tap(find.text('精彩观点'));
    await tester.pumpAndSettle();

    final highlightChip = find.ancestor(
      of: find.text('精彩观点'),
      matching: find.byType(ChoiceChip),
    );
    expect(tester.widget<ChoiceChip>(highlightChip).selected, isTrue);
    expect(find.text('评论故事卡'), findsOneWidget);
    expect(find.text('精彩观点 · 原文未改写'), findsOneWidget);
    expect(find.text('主评论保留 · 已选4/5条跟评'), findsOneWidget);
    expect(find.textContaining('互动较高'), findsWidgets);

    await tester.tap(find.byTooltip('选评操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('调整顺序'));
    await tester.pumpAndSettle();

    expect(find.text('调整成图顺序'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(4));

    await tester.tap(find.byTooltip('完成调整'));
    await tester.pumpAndSettle();
    expect(find.text('调整成图顺序'), findsNothing);
  });

  testWidgets('智能选评固定在右下控制区且不进入截图预览', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _openSavePanel(tester, _smartReply());

    final capture = find.byKey(const Key('save-panel-capture-boundary'));
    final overlay = find.byKey(const Key('save-panel-smart-overlay'));
    final modes = find.byKey(const Key('save-panel-smart-modes'));
    final bottomActions = find.byKey(
      const Key('save-panel-bottom-actions'),
    );

    expect(capture, findsOneWidget);
    expect(overlay, findsOneWidget);
    expect(modes, findsOneWidget);
    expect(bottomActions, findsOneWidget);

    final overlayRect = tester.getRect(overlay);
    final modesRect = tester.getRect(modes);
    final bottomActionsRect = tester.getRect(bottomActions);
    expect(modesRect.left, greaterThanOrEqualTo(400 * 0.4));
    expect(modesRect.width, lessThanOrEqualTo(400 * 0.6));
    expect(modesRect.right, closeTo(bottomActionsRect.right - 16, 0.1));
    expect(overlayRect.right, closeTo(400 - 8, 0.1));
    expect(overlayRect.center.dy, greaterThan(400));
    expect(overlayRect.bottom, lessThanOrEqualTo(bottomActionsRect.top));
    expect(bottomActionsRect.top - overlayRect.bottom, lessThanOrEqualTo(16));
    for (final label in ['精彩观点', '正反讨论', '科普补充', '搞笑瞬间']) {
      expect(tester.getCenter(find.text(label)).dx, greaterThanOrEqualTo(160));
    }
    expect(
      find.descendant(of: capture, matching: overlay),
      findsNothing,
    );

    await tester.tap(find.text('精彩观点'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: capture, matching: find.text('评论故事卡')),
      findsOneWidget,
    );
  });

  testWidgets('预览末条评论可滚动到智能选评浮层上方', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _openSavePanel(tester, _longReply());
    final overlay = find.byKey(const Key('save-panel-smart-overlay'));
    final initialOverlayRect = tester.getRect(overlay);
    final scrollableFinder = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollableFinder).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    final overlayRect = tester.getRect(overlay);
    expect(overlayRect.left, closeTo(initialOverlayRect.left, 0.1));
    expect(overlayRect.top, closeTo(initialOverlayRect.top, 0.1));
    expect(overlayRect.right, closeTo(initialOverlayRect.right, 0.1));
    expect(overlayRect.bottom, closeTo(initialOverlayRect.bottom, 0.1));
    final previewEnd = find.text('主评论保留 · 已选0/120条跟评');
    expect(previewEnd.hitTestable(), findsOneWidget);
    final previewEndRect = tester.getRect(previewEnd);
    expect(previewEndRect.bottom, lessThanOrEqualTo(overlayRect.top));
  });

  testWidgets('智能选评在小屏和较大字体下不会布局溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await _openSavePanel(tester, _smartReply());
    await tester.tap(find.text('精彩观点'));
    await tester.pumpAndSettle();

    final overlayRect = tester.getRect(
      find.byKey(const Key('save-panel-smart-overlay')),
    );
    final bottomActionsRect = tester.getRect(
      find.byKey(const Key('save-panel-bottom-actions')),
    );
    expect(overlayRect.top, greaterThanOrEqualTo(0));
    expect(overlayRect.bottom, lessThanOrEqualTo(bottomActionsRect.top));
    final bottomActions = find.byKey(const Key('save-panel-bottom-actions'));
    expect(
      find.descendant(
        of: bottomActions,
        matching: find.byTooltip('保存'),
      ).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomActions,
        matching: find.byTooltip('复制图片'),
      ).hitTestable(),
      findsOneWidget,
    );
    for (final label in ['精彩观点', '正反讨论', '科普补充', '搞笑瞬间']) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(ChoiceChip),
      );
      expect(chip, findsOneWidget);
      expect(chip.hitTestable(), findsOneWidget);
      expect(tester.widget<ChoiceChip>(chip).onSelected, isNotNull);
      final rect = tester.getRect(chip);
      expect(rect.left, greaterThanOrEqualTo(320 * 0.4));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('智能选评会按当前屏幕扣除主评论后的高度控制数量', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await _openSavePanel(tester, _smartReply());
    await tester.tap(find.text('精彩观点'));
    await tester.pumpAndSettle();

    final highlightChip = find.ancestor(
      of: find.text('精彩观点'),
      matching: find.byType(ChoiceChip),
    );
    expect(tester.widget<ChoiceChip>(highlightChip).selected, isTrue);
    expect(find.text('主评论保留 · 已选2/5条跟评'), findsOneWidget);
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

  test('成图只保留已选跟评并使用用户调整后的顺序', () {
    final original = _longReply();

    final captured = buildReplyForCapture(
      original,
      selectedIds: const {2, 4},
      selectedOrder: const [4, 2],
    );

    expect(captured.replies.map((item) => item.id.toInt()), [4, 2]);
    expect(captured.count.toInt(), 2);
    expect(original.replies.length, 120);
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

ReplyInfo _smartReply() {
  final rootId = Int64(1);
  final replies = <ReplyInfo>[
    _smartChild(
      id: 2,
      mid: 20,
      like: 80,
      message: '我认为关键是区分滚动和点击，因为状态明确后就不会误触退出。',
    ),
    _smartChild(
      id: 3,
      mid: 30,
      like: 60,
      message: '例如先做本地推荐，再让用户手动增删，效率和控制权可以同时保留。',
    ),
    _smartChild(
      id: 4,
      mid: 40,
      like: 40,
      message: '但是最终图片仍需限制长度，否则长图既难阅读，也可能增加编码内存。',
    ),
    _smartChild(
      id: 5,
      mid: 50,
      like: 20,
      message: '所以推荐理由必须可见，用户才能判断系统为什么选择这条评论。',
    ),
    _smartChild(id: 6, mid: 60, like: 1000, message: '好'),
  ];
  return ReplyInfo(
    id: rootId,
    count: Int64(replies.length),
    replies: replies,
    member: Member(name: '根评论用户'),
    content: Content(message: '用于测试智能选评界面的根评论'),
    replyControl: ReplyControl(),
  );
}

ReplyInfo _smartChild({
  required int id,
  required int mid,
  required int like,
  required String message,
}) {
  return ReplyInfo(
    id: Int64(id),
    root: Int64(1),
    parent: Int64(1),
    mid: Int64(mid),
    like: Int64(like),
    member: Member(mid: Int64(mid), name: '用户$mid'),
    content: Content(message: message),
    replyControl: ReplyControl(),
  );
}
