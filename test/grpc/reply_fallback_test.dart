import 'package:PiliPlus/grpc/reply_fallback.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP failure on primary automatically uses fallback', () async {
    final result = await ReplyFallback.request<int>(
      offset: null,
      primary: () async => throw Exception('HTTP 503'),
      fallback: () async => const Success(42),
    );
    expect(result.data, 42);
  });
  test('gRPC error automatically uses fallback', () async {
    final result = await ReplyFallback.request<int>(
      offset: null,
      primary: () async => const Error('unavailable'),
      fallback: () async => const Success(42),
    );
    expect(result.data, 42);
  });
  test('successful primary does not call fallback', () async {
    final result = await ReplyFallback.request<int>(
      offset: null,
      primary: () async => const Success(7),
      fallback: () async => throw StateError('must not call'),
    );
    expect(result.data, 7);
  });
  test(
    'web next page stays on web and does not send its token to gRPC',
    () async {
      final result = await ReplyFallback.request<int>(
        offset: 'web-reply:2',
        primary: () async => throw StateError('must not call'),
        fallback: () async => Success(ReplyFallback.page('web-reply:2')),
      );
      expect(result.data, 2);
    },
  );
  Map<String, dynamic> item(int id) => {
    'rpid': id,
    'oid': 170001,
    'type': 1,
    'mid': 99,
    'rcount': 2,
    'member': {
      'mid': '99',
      'uname': '评论者',
      'level_info': {'current_level': 6},
    },
    'content': {
      'message': '评论 [开心]',
      'emote': {
        '[开心]': {
          'url': 'https://example.com/emote.png',
          'meta': {'size': 1},
        },
      },
      'pictures': [
        {
          'img_src': 'https://example.com/pic.png',
          'img_width': 100,
          'img_height': 200,
        },
      ],
    },
    'replies': [
      {
        'rpid': 3,
        'root': id,
        'content': {'message': '回复'},
      },
    ],
  };
  test('web comments preserve top, author, children, images and next page', () {
    final result = ReplyFallback.parseMain(
      {
        'page': {'count': 86},
        'upper': {'mid': 99, 'top': item(1)},
        'replies': [item(1), item(2)],
      },
      1,
      Mode.MAIN_LIST_HOT,
    );
    expect(result.upTop.id.toInt(), 1);
    expect(result.upTop.replyControl.isUpTop, isTrue);
    expect(result.replies.single.id.toInt(), 2);
    expect(result.replies.single.member.name, '评论者');
    expect(result.replies.single.replies.single.content.message, '回复');
    expect(result.replies.single.content.pictures.single.imgHeight, 200);
    expect(
      result.replies.single.content.emotes['[开心]']!.url,
      contains('emote.png'),
    );
    expect(result.paginationReply.nextOffset, 'web-reply:2');
    expect(result.subjectControl.count.toInt(), 86);
  });
  test('last page ends pagination and does not repeat top', () {
    final result = ReplyFallback.parseMain(
      {
        'page': {'count': 21},
        'upper': {'top': item(1)},
        'replies': [item(2)],
      },
      2,
      Mode.MAIN_LIST_TIME,
    );
    expect(result.cursor.isEnd, isTrue);
    expect(result.paginationReply.nextOffset, isEmpty);
    expect(result.hasUpTop(), isFalse);
  });
}
