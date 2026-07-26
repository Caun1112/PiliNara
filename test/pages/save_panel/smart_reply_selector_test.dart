import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/pages/save_panel/smart_reply_selector.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('精彩观点优先完整表达，并去除近似重复内容', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(
          2,
          '我认为关键不是速度，而是因为流程缺少暂停状态，所以点击才会被错误处理。',
          like: 80,
        ),
        _reply(
          3,
          '我认为关键不是速度，而是因为流程缺少暂停状态，所以点击才会被错误处理！',
          like: 20,
        ),
        _reply(
          4,
          '例如把选择和截图拆成两个状态，用户就能先确认内容，再执行保存。',
          like: 30,
        ),
        _reply(
          5,
          '但是长图也需要限制物理像素，否则图片编码时可能占用过多内存。',
          like: 18,
        ),
        _reply(6, '好', like: 1000),
      ]),
      mode: SmartReplyMode.highlight,
    );

    final ids = selection.recommendations.map((item) => item.replyId).toSet();
    expect(ids, containsAll(<int>[2, 4, 5]));
    expect(ids.contains(2) && ids.contains(3), isFalse);
    expect(ids, isNot(contains(6)));
    expect(
      selection.recommendations.every((item) => item.reason.isNotEmpty),
      isTrue,
    );
  });

  test('科普补充偏向证据和解释结构，并降低传闻式表达', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(
          2,
          '根据文档，图片像素数等于宽度乘以高度；例如 430×10000 在三倍倍率下会显著增加内存。',
          like: 12,
        ),
        _reply(
          3,
          '准确地说，限制纹理尺寸和总像素量是两个不同条件，所以需要分别计算。',
          like: 8,
        ),
        _reply(
          4,
          '听说这个方案百分之百不会崩，数值设成 999 就行。',
          like: 50,
        ),
        _reply(
          5,
          '补充一个例子：如果图片包含多张大图，编码阶段还会产生额外内存。',
          like: 6,
        ),
      ]),
      mode: SmartReplyMode.knowledge,
    );

    final ids = selection.recommendations.map((item) => item.replyId).toSet();
    expect(ids, containsAll(<int>[2, 3, 5]));
    expect(ids, isNot(contains(4)));
  });

  test('搞笑瞬间保留完整包袱，过滤纯刷屏笑声', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(2, '哈哈哈哈哈哈哈哈', like: 500),
        _reply(3, '本以为是保存评论，没想到保存的是我的手指运动轨迹。', like: 80),
        _reply(4, '当评论有一百条时：选择两条，顺便完成九十八次点击训练。', like: 60),
        _reply(5, '属于是图片还没生成，拇指先生成肌肉记忆了。', like: 40),
      ]),
      mode: SmartReplyMode.humor,
    );

    final ids = selection.recommendations.map((item) => item.replyId).toSet();
    expect(ids, containsAll(<int>[3, 4, 5]));
    expect(ids, isNot(contains(2)));
  });

  test('正反讨论只组合真实回复链，并保留对话起点', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(2, '我认为所有评论默认选中会更方便。', mid: 20),
        _reply(
          3,
          '但是这不对，评论很多时会产生大量取消操作，反而应该默认不选。',
          parent: 2,
          mid: 30,
          like: 30,
        ),
        _reply(4, '确实，默认不选更适合少量分享。', parent: 3, mid: 40),
      ]),
      mode: SmartReplyMode.debate,
    );

    expect(selection.recommendations.map((item) => item.replyId), [2, 3, 4]);
  });

  test('正反讨论不会拼凑没有父子或对话关系的句子', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(2, '我同意这个设计。', parent: 99, mid: 20),
        _reply(3, '但是我不同意另一个完全无关的观点。', parent: 98, mid: 30),
      ]),
      mode: SmartReplyMode.debate,
    );

    expect(selection.recommendations, isEmpty);
  });

  test('正反讨论不会把对话起点重复当成后续回复', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(
          2,
          '但是我认为原来的方案不对，因为默认全选会增加大量取消操作。',
          mid: 20,
          dialog: 99,
        ),
        _reply(
          3,
          '不过你忽略了评论很多的情况，所以应该默认不选，再由用户主动添加。',
          parent: 2,
          mid: 30,
          like: 30,
          dialog: 99,
        ),
      ]),
      mode: SmartReplyMode.debate,
    );

    final ids = selection.recommendations.map((item) => item.replyId).toList();
    expect(ids, [2, 3]);
    expect(ids.toSet().length, ids.length);
    expect(selection.recommendations.first.reason, contains('对话起点'));
  });

  test('依赖前文的高分回复会自动带上已加载的父评论', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(2, '这个按钮应该继续放在原来的位置。', mid: 20),
        _reply(
          3,
          '但是你说的情况忽略了底部安全区，因为不同设备的可用高度并不相同。',
          parent: 2,
          mid: 30,
          like: 100,
        ),
        _reply(
          4,
          '所以固定偏移还需要在小屏和横屏下验证，避免遮挡正文。',
          mid: 40,
          like: 40,
        ),
      ]),
      mode: SmartReplyMode.highlight,
    );

    final ids = selection.recommendations.map((item) => item.replyId).toList();
    expect(ids, containsAllInOrder(<int>[2, 3]));
    expect(
      selection.recommendations.firstWhere((item) => item.replyId == 2).reason,
      contains('上下文'),
    );
  });

  test('上下文组合加入失败时不会留下孤立的低分父评论', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(2, '这是前一条。', mid: 20),
        _reply(
          3,
          '但是你说的情况忽略了安全区，因为滚动中的按钮仍可能接收到点击。',
          parent: 2,
          mid: 20,
          like: 100,
        ),
        _reply(4, '因为状态已经拆分，所以轻点只会暂停滚动。', mid: 40, like: 50),
        _reply(5, '例如保存期间锁定选择，可以避免截图内容变化。', mid: 50, like: 40),
        _reply(6, '关键是保留已加载回复，分页失败也不能丢失入口评论。', mid: 60, like: 30),
      ]),
      mode: SmartReplyMode.highlight,
    );

    final ids = selection.recommendations.map((item) => item.replyId).toSet();
    expect(ids, isNot(contains(2)));
    expect(ids, isNot(contains(3)));
    expect(ids, containsAll(<int>[4, 5, 6]));
  });

  test('高度预算从第一条起生效，并按图片展示方式保守估算', () {
    final reply = _reply(
      2,
      '因为图片使用全图展示，所以需要按照真实宽高比估算高度，避免最终故事卡超过一屏。',
      like: 100,
      pictures: [Picture(imgWidth: 100, imgHeight: 300)],
    );
    final gridHeight = estimateReplyCaptureHeight(reply);
    final fullHeight = estimateReplyCaptureHeight(
      reply,
      showFullImages: true,
    );
    expect(fullHeight, greaterThan(gridHeight));

    final gridSelection = selectSmartReplies(
      root: _root([reply]),
      mode: SmartReplyMode.highlight,
      maxEstimatedReplyHeight: gridHeight + 1,
    );
    final fullSelection = selectSmartReplies(
      root: _root([reply]),
      mode: SmartReplyMode.highlight,
      maxEstimatedReplyHeight: gridHeight + 1,
      showFullImages: true,
    );
    expect(gridSelection.recommendations.map((item) => item.replyId), [2]);
    expect(fullSelection.recommendations, isEmpty);
  });

  test('长文本高度估算不会截断为固定八行', () {
    final longReply = _reply(
      2,
      List.generate(
        24,
        (index) => '第$index段说明滚动、选择和截图之间的状态边界。',
      ).join(),
    );

    expect(
      estimateReplyCaptureHeight(longReply),
      greaterThan(44 + 8 * 24),
    );
  });

  test('滚动等中性词不会被当作辱骂词过滤', () {
    final selection = selectSmartReplies(
      root: _root([
        _reply(2, '因为页面仍在滚动，所以轻点时只应该停止当前惯性。'),
      ]),
      mode: SmartReplyMode.highlight,
    );

    expect(selection.recommendations.map((item) => item.replyId), [2]);
  });

  test('纯 ASCII 笑声 hhh 不会进入搞笑推荐', () {
    final selection = selectSmartReplies(
      root: _root([_reply(2, 'hhh', like: 1000)]),
      mode: SmartReplyMode.humor,
    );

    expect(selection.recommendations, isEmpty);
  });

  test('同一输入的推荐结果稳定且不依赖评分遍历顺序', () {
    final replies = [
      _reply(2, '因为交互状态明确，所以点击暂停不会再触发退出。', like: 20, ctime: 2),
      _reply(3, '关键是保存期间锁定选择，避免截图内容在编码时变化。', like: 20, ctime: 1),
      _reply(4, '例如分页失败时保留已加载内容，用户仍然可以继续选择。', like: 10, ctime: 3),
    ];
    final first = selectSmartReplies(
      root: _root(replies),
      mode: SmartReplyMode.highlight,
    );
    final second = selectSmartReplies(
      root: _root(replies.reversed.toList()),
      mode: SmartReplyMode.highlight,
    );

    expect(
      first.recommendations.map((item) => item.replyId).toSet(),
      second.recommendations.map((item) => item.replyId).toSet(),
    );
  });
}

ReplyInfo _root(List<ReplyInfo> replies) {
  return ReplyInfo(
    id: Int64(1),
    count: Int64(replies.length),
    replies: replies,
    member: Member(name: '根评论用户'),
    content: Content(message: '用于测试智能选评的根评论'),
    replyControl: ReplyControl(),
  );
}

ReplyInfo _reply(
  int id,
  String message, {
  int? parent,
  int mid = 10,
  int like = 0,
  int ctime = 0,
  int dialog = 0,
  List<Picture> pictures = const [],
}) {
  return ReplyInfo(
    id: Int64(id),
    root: Int64(1),
    parent: Int64(parent ?? 1),
    mid: Int64(mid),
    like: Int64(like),
    ctime: Int64(ctime),
    dialog: Int64(dialog),
    member: Member(mid: Int64(mid), name: '用户$mid'),
    content: Content(message: message, pictures: pictures),
    replyControl: ReplyControl(),
  );
}
