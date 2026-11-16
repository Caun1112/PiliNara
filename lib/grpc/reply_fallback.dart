import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:fixnum/fixnum.dart';

/// Keep web pagination separate from opaque gRPC pagination tokens.
abstract final class ReplyFallback {
  static const prefix = 'web-reply:';
  static int page(String? offset) => offset != null && offset.startsWith(prefix)
      ? int.tryParse(offset.substring(prefix.length)) ?? 1
      : 1;

  static Future<LoadingState<T>> request<T>({
    required String? offset,
    required Future<LoadingState<T>> Function() primary,
    required Future<LoadingState<T>> Function() fallback,
  }) async {
    if (offset?.startsWith(prefix) == true) return fallback();
    try {
      final result = await primary();
      if (result is Success<T>) return result;
    } catch (_) {
      // HTTP failures can throw before the gRPC response parser runs.
    }
    return fallback();
  }

  static Future<LoadingState<MainListReply>> mainList({
    required int oid,
    required int type,
    required Mode mode,
    String? offset,
  }) async {
    try {
      final pn = page(offset);
      final response = await Request().get(
        Api.replyList,
        queryParameters: {
          'oid': oid,
          'type': type,
          'pn': pn,
          'ps': 20,
          'sort': mode == Mode.MAIN_LIST_TIME ? 0 : 1,
        },
      );
      final json = response.data;
      if (json is! Map || json['code'] != 0) {
        return Error(json is Map ? json['message']?.toString() : '评论响应无效');
      }
      return Success(parseMain(json['data'] as Map, pn, mode));
    } catch (e) {
      return Error('评论加载失败，请重试：$e');
    }
  }

  static MainListReply parseMain(Map data, int page, Mode mode) {
    final items = (data['replies'] as List? ?? const []).cast<Map>();
    final count = _int(data['page']?['count']);
    final end = items.isEmpty || (count > 0 && page * 20 >= count);
    final top = data['upper']?['top'] ?? data['top']?['upper'];
    final result = MainListReply(
      mode: mode,
      replies: items.map(reply),
      subjectControl: SubjectControl(
        upMid: _id(data['upper']?['mid']),
        count: Int64(count),
        inputDisable: data['control']?['input_disable'] == true,
        rootText: data['control']?['root_input_text']?.toString(),
      ),
      cursor: CursorReply(isEnd: end),
      paginationReply: FeedPaginationReply(
        nextOffset: end ? '' : '$prefix${page + 1}',
      ),
    );
    if (page == 1 && top is Map) {
      result.upTop = reply(top)..replyControl.isUpTop = true;
      result.replies.removeWhere((item) => item.id == result.upTop.id);
    }
    return result;
  }

  static Future<LoadingState<DetailListReply>> detailList({
    required int oid,
    required int type,
    required int root,
    required Mode mode,
    String? offset,
  }) async {
    try {
      final pn = page(offset);
      final response = await Request().get(
        Api.replyReplyList,
        queryParameters: {
          'oid': oid,
          'type': type,
          'root': root,
          'pn': pn,
          'ps': 20,
          'sort': mode == Mode.MAIN_LIST_TIME ? 0 : 1,
        },
      );
      final json = response.data;
      if (json is! Map || json['code'] != 0) {
        return Error(json is Map ? json['message']?.toString() : '回复响应无效');
      }
      final data = json['data'] as Map;
      final items = (data['replies'] as List? ?? const []).cast<Map>();
      final count = _int(data['page']?['count']);
      final end = items.isEmpty || (count > 0 && pn * 20 >= count);
      final rootReply = reply(
        data['root'] as Map? ?? {'rpid': root, 'oid': oid, 'type': type},
      );
      rootReply.replies
        ..clear()
        ..addAll(items.map(reply));
      return Success(
        DetailListReply(
          root: rootReply,
          mode: mode,
          subjectControl: SubjectControl(count: Int64(count)),
          cursor: CursorReply(isEnd: end),
          paginationReply: FeedPaginationReply(
            nextOffset: end ? '' : '$prefix${pn + 1}',
          ),
        ),
      );
    } catch (e) {
      return Error('回复加载失败，请重试：$e');
    }
  }

  static int _int(dynamic value) => int.tryParse('$value') ?? 0;
  static Int64 _id(dynamic value) => Int64.parseInt(value?.toString() ?? '0');
  static ReplyInfo reply(Map data) {
    final member = data['member'] as Map? ?? const {};
    final content = data['content'] as Map? ?? const {};
    final control = data['reply_control'] as Map? ?? const {};
    final emotes = content['emote'] as Map? ?? const {};
    return ReplyInfo(
      id: _id(data['rpid']),
      oid: _id(data['oid']),
      type: _id(data['type']),
      mid: _id(data['mid'] ?? member['mid']),
      root: _id(data['root']),
      parent: _id(data['parent']),
      dialog: _id(data['dialog']),
      like: _id(data['like']),
      ctime: _id(data['ctime']),
      count: _id(data['rcount'] ?? data['count']),
      member: Member(
        mid: _id(member['mid']),
        name: member['uname']?.toString(),
        face: member['avatar']?.toString(),
        level: _id(member['level_info']?['current_level']),
        vipType: _id(member['vip']?['vipType']),
        vipStatus: _id(member['vip']?['vipStatus']),
      ),
      content: Content(
        message: content['message']?.toString(),
        urls: (content['jump_url'] as Map? ?? const {}).entries.map((e) {
          final value = e.value as Map;
          final extra = value['extra'] as Map?;
          return MapEntry(
            e.key.toString(),
            Url(
              title: value['title']?.toString(),
              pcUrl: e.key.toString(),
              appUrlSchema: value['app_url_schema']?.toString(),
              extra: extra == null
                  ? null
                  : Url_Extra(
                      goodsItemId: extra['goods_item_id'] == null
                          ? null
                          : _id(extra['goods_item_id']),
                      goodsCmControl: extra['goods_cm_control'] == null
                          ? null
                          : _id(extra['goods_cm_control']),
                    ),
            ),
          );
        }),
        emotes: emotes.entries.map(
          (e) => MapEntry(
            e.key.toString(),
            Emote(
              url: e.value['url']?.toString(),
              size: _id(e.value['meta']?['size']),
            ),
          ),
        ),
        pictures: (content['pictures'] as List? ?? const []).map(
          (p) => Picture(
            imgSrc: p['img_src']?.toString(),
            imgWidth: (p['img_width'] as num?)?.toDouble(),
            imgHeight: (p['img_height'] as num?)?.toDouble(),
            imgSize: (p['img_size'] as num?)?.toDouble(),
          ),
        ),
        atNameToMid: (content['members'] as List? ?? const []).map(
          (m) => MapEntry(m['uname'].toString(), _id(m['mid'])),
        ),
      ),
      replyControl: ReplyControl(
        action: _id(data['action']),
        upLike: data['up_action']?['like'] == true,
        upReply: data['up_action']?['reply'] == true,
        following: member['is_followed'] == true,
        location: control['location']?.toString(),
        subReplyEntryText: control['sub_reply_entry_text']?.toString(),
        subReplyTitleText: control['sub_reply_title_text']?.toString(),
      ),
      replies: (data['replies'] as List? ?? const []).cast<Map>().map(reply),
    );
  }
}
