import 'dart:async' show unawaited;
import 'dart:math' show max, min, sqrt;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/icon_button.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show Mode, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliPlus/pages/music/controller.dart';
import 'package:PiliPlus/pages/save_panel/smart_reply_selector.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:clipboard/clipboard.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:protobuf/protobuf.dart';

const double _preferredCapturePixelRatio = 3;
// 控制纹理尺寸和 RGBA 中间内存，避免超长评论触发 iOS 内存终止。
const double _maxCapturePhysicalDimension = 12000;
const double _maxCapturePhysicalPixels = 16 * 1024 * 1024;

@visibleForTesting
double? calculateSavePanelPixelRatio(Size logicalSize) {
  if (logicalSize.isEmpty) return null;

  final dimensionRatio =
      _maxCapturePhysicalDimension / max(logicalSize.width, logicalSize.height);
  final pixelCountRatio = sqrt(
    _maxCapturePhysicalPixels / (logicalSize.width * logicalSize.height),
  );
  final safeRatio = min(
    _preferredCapturePixelRatio,
    min(dimensionRatio, pixelCountRatio),
  );
  return safeRatio >= 1 ? safeRatio : null;
}

@visibleForTesting
ReplyInfo buildReplyForCapture(
  ReplyInfo reply, {
  required Set<int> selectedIds,
  required List<int> selectedOrder,
}) {
  final capturedReply = reply.deepCopy();
  final selectedById = <int, ReplyInfo>{
    for (final childReply in capturedReply.replies)
      if (selectedIds.contains(childReply.id.toInt()))
        childReply.id.toInt(): childReply,
  };
  final orderedReplies = <ReplyInfo>[];
  for (final id in selectedOrder) {
    final childReply = selectedById.remove(id);
    if (childReply != null) orderedReplies.add(childReply);
  }
  orderedReplies.addAll(selectedById.values);
  capturedReply.replies
    ..clear()
    ..addAll(orderedReplies);
  capturedReply.count = Int64(orderedReplies.length);
  return capturedReply;
}

class SavePanel extends StatefulWidget {
  const SavePanel({
    required this.item,
    // reply
    this.upMid,
    super.key,
  });

  final dynamic upMid;
  final dynamic item;

  @override
  State<SavePanel> createState() => _SavePanelState();

  static void toSavePanel({dynamic upMid, dynamic item}) {
    Get.key.currentState!.push(
      PublishRoute(
        pageBuilder: (context, animation, secondaryAnimation) {
          return SavePanel(upMid: upMid, item: item);
        },
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 255),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeInOut)),
            child: child,
          );
        },
        showGlobalBackButton: true,
        settings: RouteSettings(arguments: Get.arguments),
      ),
    );
  }
}

class _SavePanelState extends State<SavePanel> {
  final boundaryKey = GlobalKey();
  final Set<int> _selectedReplyIds = <int>{};
  final List<int> _selectedReplyOrder = <int>[];
  final Map<int, String> _selectionReasons = <int, String>{};
  late final ScrollController _scrollController;

  SmartReplyMode? _smartReplyMode;
  bool _selectionOrderCustomized = false;
  bool showBottom = false;
  bool showFullImages = false;
  bool _isCapturing = false;
  bool _isActionInProgress = false;
  bool _isScrolling = false;

  // item
  late Object _item;
  bool _isLoadingReplies = false;
  bool _replyLoadIncomplete = false;
  late String viewType = '查看';
  late String itemType = '内容';

  //reply
  String? cover;
  _CoverType coverType = _CoverType.def16_9;
  String? title;
  int? pubdate;
  DateFormat dateFormat = DateFormatUtils.longFormatDs;
  String? uname;

  String uri = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      onAttach: (position) {
        position.isScrollingNotifier.addListener(_handleScrollActivity);
      },
      onDetach: (position) {
        position.isScrollingNotifier.removeListener(_handleScrollActivity);
      },
    );
    _item = widget.item;
    if (_item case final ReplyInfo reply) {
      itemType = '评论';
      final currentRoute = Get.currentRoute;
      late final hasRoot = reply.hasRoot();

      if (currentRoute == '/videoV') {
        final rootId = hasRoot ? reply.root : reply.id;

        uri =
            'https://www.bilibili.com/video/av${reply.oid}?comment_on=1&comment_root_id=$rootId${hasRoot ? '&comment_secondary_id=${reply.id}' : ''}';
        try {
          final heroTag = Get.arguments['heroTag'];
          final videoType = Get.arguments['videoType'];
          if (videoType == VideoType.pgc || videoType == VideoType.pugv) {
            final ctr = Get.find<PgcIntroController>(tag: heroTag);
            final pgcItem = ctr.pgcItem;
            final cid = ctr.cid.value;
            final episode = pgcItem.episodes!.firstWhere(
              (e) => e.cid == cid,
            );
            cover = episode.cover;
            title =
                episode.shareCopy ??
                '${pgcItem.title} ${episode.showTitle ?? episode.longTitle ?? ''}';
            pubdate = episode.pubTime;
            uname = pgcItem.upInfo?.uname;

            final oid = reply.oid;
            final type = reply.type.toInt();
            final anchor = hasRoot ? 'anchor=${reply.id}&' : '';
            uri =
                'bilibili://comment/detail/$type/$oid/$rootId/?${anchor}enterUri=bilibili://pgc/season/ep/${ctr.epId}';
          } else {
            final ctr = Get.find<UgcIntroController>(tag: heroTag);
            final videoDetail = ctr.videoDetail.value;
            cover = videoDetail.pic;
            title = videoDetail.title;
            pubdate = videoDetail.pubdate;
            uname = videoDetail.owner?.name;

            final cid = ctr.cid.value;
            final part =
                ctr.videoDetail.value.pages?.indexWhere((i) => i.cid == cid) ??
                -1;
            if (part > 0) uri += '&p=${part + 1}';
          }
        } catch (_) {}
      } else if (currentRoute.startsWith('/dynamicDetail')) {
        DynamicItemModel? dynItem;
        try {
          dynItem = Get.arguments['item'] as DynamicItemModel;
          uname = dynItem.modules.moduleAuthor?.name;
        } catch (_) {}
        final type = reply.type.toInt();
        final oid = reply.oid;
        final rootId = hasRoot ? reply.root : reply.id;

        if (type == 1) {
          uri =
              'https://www.bilibili.com/video/av$oid?comment_on=1&comment_root_id=$rootId${hasRoot ? '&comment_secondary_id=${reply.id}' : ''}';
        } else {
          final enterUri = dynItem == null
              ? ''
              : 'enterUri=${parseDyn(dynItem)}';
          uri =
              'bilibili://comment/detail/$type/$oid/$rootId/?${hasRoot ? 'anchor=${reply.id}&' : ''}$enterUri';
        }
      } else if (currentRoute.startsWith('/Scaffold')) {
        try {
          final type = reply.type.toInt();
          final oid = Get.arguments['oid'] ?? reply.oid;
          final rootId = hasRoot ? reply.root : reply.id;
          if (type == 1) {
            uri =
                'https://www.bilibili.com/video/av$oid?comment_on=1&comment_root_id=$rootId${hasRoot ? '&comment_secondary_id=${reply.id}' : ''}';
          } else {
            String enterUri = Get.arguments['enterUri'] ?? '';
            if (enterUri.isNotEmpty) {
              enterUri = 'enterUri=${Uri.encodeComponent(enterUri)}';
            } else if (const [11, 12, 17].contains(type)) {
              enterUri = 'enterUri=bilibili://following/detail/$oid';
            }
            uri =
                'bilibili://comment/detail/$type/$oid/$rootId/?${hasRoot ? 'anchor=${reply.id}&' : ''}$enterUri';
          }
        } catch (_) {}
      } else if (currentRoute.startsWith('/articlePage')) {
        try {
          final type = reply.type.toInt();
          final oid = reply.oid;
          final rootId = hasRoot ? reply.root : reply.id;
          final anchor = hasRoot ? 'anchor=${reply.id}&' : '';
          final enterUri =
              'bilibili://following/detail/${Get.parameters['id'] ?? Get.arguments?['id']}';
          uri =
              'bilibili://comment/detail/$type/$oid/$rootId/?${anchor}enterUri=$enterUri';
        } catch (_) {}
      } else if (currentRoute.startsWith('/musicDetail')) {
        final type = reply.type.toInt();
        final oid = reply.oid;
        final rootId = hasRoot ? reply.root : reply.id;
        final anchor = hasRoot ? 'anchor=${reply.id}&' : '';
        String enterUri = '';
        try {
          final ctr = Get.find<MusicDetailController>(
            tag: Get.parameters['musicId'],
          );
          enterUri =
              'enterUri=${Uri.encodeComponent(ctr.shareUrl)}'; // official client cannot parse it
          final data = ctr.infoState.value.dataOrNull;
          if (data != null) {
            coverType = _CoverType.square;
            cover = data.mvCover;
            title = data.musicTitle;
            if (data.musicPublish != null) {
              final time = DateTime.tryParse(
                data.musicPublish!,
              )?.millisecondsSinceEpoch;
              if (time != null) {
                pubdate = time ~/ 1000;
                dateFormat = DateFormatUtils.longFormat;
              }
            }
          }
        } catch (_) {}
        uri = 'bilibili://comment/detail/$type/$oid/$rootId/?$anchor$enterUri';
      }

      if (kDebugMode) debugPrint(uri);
      if (reply.hasRoot() || reply.replies.length < reply.count.toInt()) {
        _isLoadingReplies = true;
        unawaited(_loadCompleteReply(reply));
      }
    } else if (_item case final DynamicItemModel i) {
      uri = parseDyn(i);

      if (kDebugMode) debugPrint(uri);
    }
  }

  Future<void> _loadCompleteReply(ReplyInfo reply) async {
    final rootId = reply.hasRoot() ? reply.root.toInt() : reply.id.toInt();
    final replies = <int, ReplyInfo>{
      for (final item in reply.replies) item.id.toInt(): item,
      if (reply.hasRoot()) reply.id.toInt(): reply,
    };
    final seenOffsets = <String>{};
    ReplyInfo? root;
    String? offset;
    bool loadFailed = false;

    try {
      while (true) {
        final result = await ReplyGrpc.detailList(
          type: reply.type.toInt(),
          oid: reply.oid.toInt(),
          root: rootId,
          rpid: 0,
          mode: Mode.MAIN_LIST_TIME,
          offset: offset,
        );
        if (!mounted) return;
        if (result case Success(:final response)) {
          root ??= response.root;
          for (final item in response.root.replies) {
            replies[item.id.toInt()] = item;
          }

          final nextOffset = response.paginationReply.nextOffset;
          if (response.cursor.isEnd ||
              nextOffset.isEmpty ||
              !seenOffsets.add(nextOffset)) {
            break;
          }
          offset = nextOffset;
        } else {
          loadFailed = true;
          break;
        }
      }
    } catch (e) {
      loadFailed = true;
      if (kDebugMode) debugPrint('load complete reply: $e');
    }

    if (!mounted) return;
    setState(() {
      if (root case final root?) {
        final fullReply = root.deepCopy();
        fullReply.replies
          ..clear()
          ..addAll(replies.values);
        _item = fullReply;
      }
      _isLoadingReplies = false;
      _replyLoadIncomplete = loadFailed;
    });
    if (loadFailed) {
      SmartDialog.showToast('完整回复加载失败，已展示当前加载内容');
    }
  }

  String parseDyn(DynamicItemModel item) {
    String uri = '';
    try {
      switch (item.type) {
        case 'DYNAMIC_TYPE_AV':
          viewType = '观看';
          itemType = '视频';
          uri = 'bilibili://video/${item.basic!.commentIdStr}';
          break;

        case 'DYNAMIC_TYPE_ARTICLE':
          itemType = '专栏';
          uri = 'bilibili://following/detail/${item.idStr}';
          break;

        case 'DYNAMIC_TYPE_LIVE_RCMD':
          viewType = '观看';
          itemType = '直播';
          final roomId = item.modules.moduleDynamic!.major!.liveRcmd!.roomId;
          uri = 'bilibili://live/$roomId';
          break;

        case 'DYNAMIC_TYPE_UGC_SEASON':
          viewType = '观看';
          itemType = '合集';
          final aid = item.modules.moduleDynamic!.major!.ugcSeason!.aid;
          uri = 'bilibili://video/$aid';
          break;

        case 'DYNAMIC_TYPE_PGC':
        case 'DYNAMIC_TYPE_PGC_UNION':
          viewType = '观看';
          itemType =
              item.modules.moduleDynamic?.major?.pgc?.badge?.text ?? '番剧';
          final epid = item.modules.moduleDynamic!.major!.pgc!.epid;
          uri = 'bilibili://pgc/season/ep/$epid';
          break;

        // https://www.bilibili.com/medialist/detail/ml12345678
        case 'DYNAMIC_TYPE_MEDIALIST':
          itemType = '收藏夹';
          final mediaId = item.modules.moduleDynamic!.major!.medialist!.id;
          uri = 'bilibili://medialist/detail/$mediaId';
          break;

        // 纯文字动态查看
        // case 'DYNAMIC_TYPE_WORD':
        // # 装扮/剧集点评/普通分享
        // case 'DYNAMIC_TYPE_COMMON_SQUARE':
        // 转发的动态
        // case 'DYNAMIC_TYPE_FORWARD':
        // 图文动态查看
        // case 'DYNAMIC_TYPE_DRAW':
        default:
          itemType = '动态';
          uri = 'bilibili://following/detail/${item.idStr}';
          break;
      }
    } catch (_) {}
    return uri;
  }

  bool _isReplySelected(ReplyInfo reply) {
    return _selectedReplyIds.contains(reply.id.toInt());
  }

  String? _selectionReason(ReplyInfo reply) {
    return _selectionReasons[reply.id.toInt()];
  }

  int? get _upMid {
    final value = widget.upMid;
    if (value is Int64) return value.toInt();
    if (value is int) return value;
    return value == null ? null : int.tryParse(value.toString());
  }

  void _syncSelectionOrder(ReplyInfo reply) {
    if (_selectionOrderCustomized) return;
    _selectedReplyOrder
      ..clear()
      ..addAll(
        reply.replies
            .where(
              (childReply) => _selectedReplyIds.contains(childReply.id.toInt()),
            )
            .map((childReply) => childReply.id.toInt()),
      );
  }

  void _toggleReply(ReplyInfo reply) {
    if (_isCapturing || _isActionInProgress) return;
    final id = reply.id.toInt();
    setState(() {
      if (_selectedReplyIds.add(id)) {
        _selectionReasons.remove(id);
        if (_selectionOrderCustomized) {
          _selectedReplyOrder.add(id);
        } else if (_item case final ReplyInfo rootReply) {
          _syncSelectionOrder(rootReply);
        }
      } else {
        _selectedReplyIds.remove(id);
        _selectedReplyOrder.remove(id);
        _selectionReasons.remove(id);
      }
    });
  }

  void _clearReplySelection() {
    if (_isCapturing || _isActionInProgress) return;
    setState(() {
      _selectedReplyIds.clear();
      _selectedReplyOrder.clear();
      _selectionReasons.clear();
      _smartReplyMode = null;
      _selectionOrderCustomized = false;
    });
  }

  double get _smartReplyContentWidth => max(
    240.0,
    context.mediaQueryShortestSide - 64,
  );

  double _smartReplyHeightBudget(ReplyInfo reply) {
    final mediaQuery = MediaQuery.of(context);
    final usableScreenHeight =
        mediaQuery.size.height - mediaQuery.viewPadding.vertical;
    final rootHeight = estimateReplyCaptureHeight(
      reply,
      showFullImages: showFullImages,
      contentWidth: _smartReplyContentWidth,
    );
    final coverHeight = cover?.isNotEmpty == true && title?.isNotEmpty == true
        ? 81.0
        : 0.0;
    final sourceHeight = showBottom ? 112.0 : 12.0;
    final incompleteHintHeight = _replyLoadIncomplete ? 40.0 : 0.0;
    const storyHeaderAndSpacing = 98.0;
    return max(
      0,
      usableScreenHeight -
          rootHeight -
          coverHeight -
          sourceHeight -
          incompleteHintHeight -
          storyHeaderAndSpacing,
    );
  }

  void _applySmartReplySelection(SmartReplyMode mode) {
    if (_isCapturing || _isActionInProgress || _isLoadingReplies) return;
    if (_item case final ReplyInfo reply) {
      final selection = selectSmartReplies(
        root: reply,
        mode: mode,
        upMid: _upMid,
        maxEstimatedReplyHeight: _smartReplyHeightBudget(reply),
        showFullImages: showFullImages,
        contentWidth: _smartReplyContentWidth,
      );
      if (selection.recommendations.isEmpty) {
        SmartDialog.showToast('没有找到适合当前一屏长度的匹配评论，可切换目的或手动选择');
        return;
      }
      setState(() {
        _selectedReplyIds
          ..clear()
          ..addAll(
            selection.recommendations.map(
              (recommendation) => recommendation.replyId,
            ),
          );
        _selectedReplyOrder
          ..clear()
          ..addAll(
            selection.recommendations.map(
              (recommendation) => recommendation.replyId,
            ),
          );
        _selectionReasons
          ..clear()
          ..addEntries(
            selection.recommendations.map(
              (recommendation) => MapEntry(
                recommendation.replyId,
                recommendation.reason,
              ),
            ),
          );
        _smartReplyMode = mode;
        _selectionOrderCustomized = false;
      });
      SmartDialog.showToast(
        _replyLoadIncomplete
            ? '已基于当前加载内容推荐，可继续手动增删'
            : '已推荐 ${selection.recommendations.length} 条，可继续手动增删',
      );
    }
  }

  ReplyInfo _replyForCapture(ReplyInfo reply) {
    return buildReplyForCapture(
      reply,
      selectedIds: _selectedReplyIds,
      selectedOrder: _selectedReplyOrder,
    );
  }

  Future<void> _onPicAction([_PicAction action = _PicAction.save]) async {
    if (_isActionInProgress) return;
    if (_isLoadingReplies) {
      SmartDialog.showToast('正在加载完整回复');
      return;
    }
    setState(() {
      _isActionInProgress = true;
    });
    ReplyInfo? originalReply;
    try {
      if (action == _PicAction.save &&
          PlatformUtils.isMobile &&
          !await ImageUtils.checkPermissionDependOnSdkInt()) {
        return;
      }
      SmartDialog.showLoading();
      if (_item case final ReplyInfo reply) {
        originalReply = reply;
        if (mounted) {
          setState(() {
            _item = _replyForCapture(reply);
            _isCapturing = true;
          });
          await WidgetsBinding.instance.endOfFrame;
        }
      }
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final pixelRatio = calculateSavePanelPixelRatio(boundary.size);
      if (pixelRatio == null) {
        SmartDialog.dismiss();
        SmartDialog.showToast('内容过长，无法生成图片，请减少选中的评论或切换为集成展示');
        return;
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      late final Uint8List pngBytes;
      try {
        final byteData = await image.toByteData(format: .png);
        if (byteData == null) {
          throw StateError('图片编码失败');
        }
        pngBytes = byteData.buffer.asUint8List();
      } finally {
        image.dispose();
      }
      final picName =
          "${Constants.appName}_${itemType}_${DateFormat('yyyyMMddHHmmss').format(DateTime.now())}";
      switch (action) {
        case _PicAction.copy:
          await FlutterClipboard.copyImage(pngBytes);
          SmartDialog.dismiss();
          SmartDialog.showToast('已复制图片');
        case _PicAction.save:
          final result = await ImageUtils.saveByteImg(
            bytes: pngBytes,
            fileName: picName,
          );
          if (result?.isSuccess == true) {
            Get.back();
          }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('on save/share reply: $e');
      SmartDialog.dismiss();
      SmartDialog.showToast('生成图片失败，请减少选中的评论后重试');
    } finally {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          if (originalReply != null) {
            _item = originalReply;
            _isCapturing = false;
          }
        });
      } else {
        _isActionInProgress = false;
      }
    }
  }

  List<ReplyInfo> _orderedSelectedReplies(ReplyInfo reply) {
    final selectedById = <int, ReplyInfo>{
      for (final childReply in reply.replies)
        if (_selectedReplyIds.contains(childReply.id.toInt()))
          childReply.id.toInt(): childReply,
    };
    final orderedReplies = <ReplyInfo>[];
    for (final id in _selectedReplyOrder) {
      final childReply = selectedById.remove(id);
      if (childReply != null) orderedReplies.add(childReply);
    }
    orderedReplies.addAll(selectedById.values);
    return orderedReplies;
  }

  Future<void> _showReplyOrderSheet(ReplyInfo reply) async {
    if (_selectedReplyIds.length < 2 || _isActionInProgress) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: min(640, context.mediaQueryShortestSide),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final orderedReplies = _orderedSelectedReplies(reply);
            return SizedBox(
              height: min(560, MediaQuery.sizeOf(sheetContext).height * 0.72),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              Text(
                                '调整成图顺序',
                                style: Theme.of(
                                  sheetContext,
                                ).textTheme.titleMedium,
                              ),
                              Text(
                                '拖动右侧把手；默认保持原评论顺序',
                                style: TextStyle(
                                  color: Theme.of(
                                    sheetContext,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '完成调整',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.done),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: orderedReplies.length,
                      onReorderItem: (oldIndex, newIndex) {
                        final reorderedIds = orderedReplies
                            .map((item) => item.id.toInt())
                            .toList();
                        final id = reorderedIds.removeAt(oldIndex);
                        reorderedIds.insert(newIndex, id);
                        setState(() {
                          _selectedReplyOrder
                            ..clear()
                            ..addAll(reorderedIds);
                          _selectionOrderCustomized = true;
                        });
                        setSheetState(() {});
                      },
                      itemBuilder: (context, index) {
                        final item = orderedReplies[index];
                        final message = item.content.message.trim();
                        return ListTile(
                          key: ValueKey(item.id.toInt()),
                          leading: CircleAvatar(
                            radius: 15,
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            item.member.name.isEmpty
                                ? '未命名用户'
                                : item.member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            message.isNotEmpty
                                ? message
                                : item.content.pictures.isNotEmpty
                                ? '[图片评论]'
                                : '[无文字内容]',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: const Tooltip(
                              message: '拖动排序',
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSmartReplyPanel(ThemeData theme, ReplyInfo reply) {
    final mode = _smartReplyMode;
    final actionStyle = TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: theme.textTheme.labelSmall,
    );
    return Material(
      key: const Key('save-panel-smart-overlay'),
      elevation: 3,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                spacing: 4,
                children: [
                  const Expanded(
                    child: SizedBox.expand(
                      key: Key('save-panel-smart-local'),
                      child: Tooltip(
                        message: '本地分析，不上传评论',
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 3,
                            children: [
                              Icon(Icons.lock_outline, size: 14),
                              Text('本地'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox.square(
                    key: const Key('save-panel-smart-clear'),
                    dimension: 44,
                    child: TextButton(
                      style: actionStyle,
                      onPressed:
                          _selectedReplyIds.isEmpty || _isActionInProgress
                          ? null
                          : _clearReplySelection,
                      child: const Text('清空'),
                    ),
                  ),
                  SizedBox.square(
                    key: const Key('save-panel-smart-reorder'),
                    dimension: 44,
                    child: TextButton(
                      style: actionStyle,
                      onPressed:
                          _selectedReplyIds.length < 2 || _isActionInProgress
                          ? null
                          : () => unawaited(_showReplyOrderSheet(reply)),
                      child: const Text('调整'),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              key: const Key('save-panel-smart-modes'),
              spacing: 6,
              children: [
                for (final row in [
                  SmartReplyMode.values.sublist(0, 2),
                  SmartReplyMode.values.sublist(2, 4),
                ])
                  Row(
                    spacing: 6,
                    children: [
                      for (final item in row)
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: Tooltip(
                              message: item == SmartReplyMode.knowledge
                                  ? '${item.description}；只做文本规则推荐，不代表事实核验'
                                  : item.description,
                              child: ChoiceChip(
                                label: SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                                selected: mode == item,
                                showCheckmark: false,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                labelPadding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                onSelected: _isActionInProgress
                                    ? null
                                    : (_) => _applySmartReplySelection(item),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryCardHeader(ThemeData theme) {
    final mode = _smartReplyMode;
    if (mode == null || _selectedReplyIds.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      header: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        color: theme.colorScheme.surfaceContainerLow,
        child: Row(
          children: [
            Icon(
              mode.icon,
              color: theme.colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 1,
                children: [
                  Text('评论故事卡', style: theme.textTheme.titleSmall),
                  Text(
                    '${mode.label} · 原文未改写',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: theme.textTheme.labelMedium!.fontSize,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_selectedReplyIds.length} 条',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleScrollActivity() {
    final isScrolling =
        _scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value;
    if (mounted && _isScrolling != isScrolling) {
      setState(() {
        _isScrolling = isScrolling;
      });
    }
  }

  void _stopActiveScroll() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final maxWidth = context.mediaQueryShortestSide;
    final hasSmartReplyControls = !_isLoadingReplies && _item is ReplyInfo;
    final previewBottomPadding = hasSmartReplyControls ? 256.0 : 80.0;
    late final coverSize = MediaQuery.textScalerOf(context).scale(65);
    return Stack(
      clipBehavior: .none,
      alignment: .center,
      children: [
        SingleChildScrollView(
          controller: _scrollController,
          // 惯性滚动时仍接收点击，以便暂停滚动并阻止事件穿透路由遮罩。
          hitTestBehavior: .opaque,
          padding: .only(
            top: 12 + padding.top,
            bottom: previewBottomPadding + padding.bottom,
          ),
          child: Container(
            width: maxWidth,
            padding: const .symmetric(horizontal: 12),
            child: KeyedSubtree(
              key: const Key('save-panel-capture-boundary'),
              child: RepaintBoundary(
                key: boundaryKey,
                child: Container(
                  clipBehavior: .hardEdge,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const .all(.circular(12)),
                  ),
                  child: AnimatedSize(
                    curve: Curves.easeInOut,
                    alignment: .topCenter,
                    duration: _isCapturing
                        ? Duration.zero
                        : const Duration(milliseconds: 255),
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: [
                        _buildStoryCardHeader(theme),
                        _isLoadingReplies
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 48),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: 12,
                                    children: [
                                      CircularProgressIndicator(),
                                      Text('正在加载完整回复'),
                                    ],
                                  ),
                                ),
                              )
                            : switch (_item) {
                                ReplyInfo reply => IgnorePointer(
                                  ignoring: _isCapturing || _isActionInProgress,
                                  child: ReplyItemGrpc(
                                    replyItem: reply,
                                    replyLevel: 0,
                                    needDivider: false,
                                    upMid: widget.upMid,
                                    showFullImages: showFullImages,
                                    showReplies: true,
                                    selectionMode: !_isCapturing,
                                    isReplySelected: _isReplySelected,
                                    onToggleReply: _toggleReply,
                                    selectionReason: _selectionReason,
                                    fullWidthReplies: true,
                                  ),
                                ),
                                DynamicItemModel dyn => IgnorePointer(
                                  child: DynamicPanel(
                                    item: dyn,
                                    isDetail: true,
                                    isSave: true,
                                  ),
                                ),
                                _ => throw UnsupportedError(_item.toString()),
                              },
                        if (_replyLoadIncomplete)
                          Padding(
                            padding: const .fromLTRB(12, 0, 12, 12),
                            child: Text(
                              '完整回复加载不完整，已保留当前可用内容',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        if (cover?.isNotEmpty == true &&
                            title?.isNotEmpty == true)
                          Container(
                            height: 81,
                            margin: const .symmetric(horizontal: 12),
                            padding: const .all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onInverseSurface,
                              borderRadius: const .all(.circular(8)),
                            ),
                            child: Row(
                              spacing: 10,
                              children: [
                                NetworkImgLayer(
                                  src: cover!,
                                  height: coverSize,
                                  width: coverType == .def16_9
                                      ? coverSize * Style.aspectRatio16x9
                                      : coverSize,
                                  quality: 100,
                                  borderRadius: const .all(.circular(6)),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: .start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$title\n',
                                          maxLines: 2,
                                          overflow: .ellipsis,
                                        ),
                                      ),
                                      if (pubdate != null)
                                        Text(
                                          DateFormatUtils.format(
                                            pubdate,
                                            format: dateFormat,
                                          ),
                                          style: TextStyle(
                                            color: theme.colorScheme.outline,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        showBottom
                            ? Stack(
                                clipBehavior: .none,
                                children: [
                                  if (uri.isNotEmpty)
                                    Align(
                                      alignment: .centerRight,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              mainAxisSize: .min,
                                              crossAxisAlignment: .end,
                                              spacing: 4,
                                              children: [
                                                if (uname?.isNotEmpty == true)
                                                  Text(
                                                    '@$uname',
                                                    maxLines: 1,
                                                    overflow: .ellipsis,
                                                    style: TextStyle(
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                                  ),
                                                Text(
                                                  '识别二维码，$viewType$itemType',
                                                  textAlign: .end,
                                                  style: TextStyle(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                Text(
                                                  DateFormatUtils.longFormatDs
                                                      .format(.now()),
                                                  textAlign: .end,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: theme
                                                        .colorScheme
                                                        .outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => Utils.copyText(uri),
                                            child: Container(
                                              width: 88,
                                              height: 88,
                                              margin: const .all(12),
                                              padding: const .all(3),
                                              color: theme.isDark
                                                  ? Colors.white
                                                  : theme.colorScheme.surface,
                                              child: PrettyQrView.data(
                                                data: uri,
                                                decoration:
                                                    const PrettyQrDecoration(
                                                      shape:
                                                          PrettyQrSquaresSymbol(),
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Align(
                                    alignment: .centerLeft,
                                    child: Image.asset(
                                      Assets.logo2,
                                      width: 100,
                                      cacheWidth: 100.cacheSize(context),
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!_isScrolling && !_isCapturing && hasSmartReplyControls)
          Positioned(
            right: max(8.0, padding.right),
            bottom: 80 + padding.bottom,
            width: min(360.0, maxWidth * 0.6),
            child: _buildSmartReplyPanel(theme, _item as ReplyInfo),
          ),
        if (!_isScrolling)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: .topCenter,
                  end: .bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black54,
                  ],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: padding.left,
                  right: padding.right,
                  bottom: 25 + padding.bottom,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    key: const Key('save-panel-bottom-actions'),
                    widthFactor: 0.55,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final buttonSize = min(42.0, constraints.maxWidth / 5);
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            iconButton(
                              size: buttonSize,
                              tooltip: showBottom ? '隐藏二维码' : '显示二维码',
                              context: context,
                              icon: showBottom
                                  ? const Icon(Icons.visibility_off)
                                  : const Icon(Icons.visibility),
                              onPressed: _isActionInProgress
                                  ? null
                                  : () => setState(() {
                                      showBottom = !showBottom;
                                    }),
                            ),
                            iconButton(
                              size: buttonSize,
                              tooltip: '关闭',
                              icon: const Icon(Icons.clear),
                              onPressed: _isActionInProgress ? null : Get.back,
                              bgColor: theme.colorScheme.onInverseSurface,
                              iconColor: theme.colorScheme.onSurfaceVariant,
                            ),
                            iconButton(
                              size: buttonSize,
                              tooltip: '保存',
                              context: context,
                              icon: const Icon(Icons.save_alt),
                              onPressed: _isActionInProgress
                                  ? null
                                  : _onPicAction,
                            ),
                            iconButton(
                              size: buttonSize,
                              tooltip: showFullImages ? '切换为集成展示' : '切换为全图展示',
                              context: context,
                              icon: Icon(
                                showFullImages
                                    ? Icons.grid_view_outlined
                                    : Icons.view_agenda_outlined,
                              ),
                              onPressed: _isActionInProgress
                                  ? null
                                  : () => setState(() {
                                      showFullImages = !showFullImages;
                                    }),
                            ),
                            iconButton(
                              size: buttonSize,
                              tooltip: '复制图片',
                              context: context,
                              icon: const Icon(Icons.copy_outlined),
                              onPressed: _isActionInProgress
                                  ? null
                                  : () => _onPicAction(_PicAction.copy),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_isScrolling)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _stopActiveScroll(),
            ),
          ),
      ],
    );
  }
}

enum _CoverType { def16_9, square }

enum _PicAction { save, copy }

extension _SmartReplyModeUi on SmartReplyMode {
  IconData get icon => switch (this) {
    SmartReplyMode.highlight => Icons.auto_awesome_outlined,
    SmartReplyMode.debate => Icons.forum_outlined,
    SmartReplyMode.knowledge => Icons.lightbulb_outline,
    SmartReplyMode.humor => Icons.sentiment_very_satisfied_outlined,
  };
}
