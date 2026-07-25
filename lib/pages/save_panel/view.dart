import 'dart:async' show unawaited;
import 'dart:math' show min;

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
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:protobuf/protobuf.dart';

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

  bool showBottom = false;
  bool showFullImages = false;
  bool _isCapturing = false;
  bool _isActionInProgress = false;

  // item
  late Object _item;
  bool _isLoadingReplies = false;
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
    final replies = <int, ReplyInfo>{};
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

  void _toggleReply(ReplyInfo reply) {
    if (_isCapturing) return;
    final id = reply.id.toInt();
    setState(() {
      if (!_selectedReplyIds.add(id)) {
        _selectedReplyIds.remove(id);
      }
    });
  }

  ReplyInfo _replyForCapture(ReplyInfo reply) {
    final capturedReply = reply.deepCopy();
    capturedReply.replies.removeWhere(
      (childReply) => !_selectedReplyIds.contains(childReply.id.toInt()),
    );
    capturedReply.count = Int64(capturedReply.replies.length);
    return capturedReply;
  }

  Future<void> _onPicAction([_PicAction action = _PicAction.save]) async {
    if (_isActionInProgress) return;
    if (_isLoadingReplies) {
      SmartDialog.showToast('正在加载完整回复');
      return;
    }
    _isActionInProgress = true;
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
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: .png);
      image.dispose();
      final pngBytes = byteData!.buffer.asUint8List();
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
    } finally {
      _isActionInProgress = false;
      if (originalReply != null && mounted) {
        setState(() {
          _item = originalReply!;
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    final maxWidth = context.mediaQueryShortestSide;
    late final coverSize = MediaQuery.textScalerOf(context).scale(65);
    return Stack(
      clipBehavior: .none,
      alignment: .center,
      children: [
        SingleChildScrollView(
          hitTestBehavior: .deferToChild,
          padding: .only(
            top: 12 + padding.top,
            bottom: 80 + padding.bottom,
          ),
          child: Container(
            width: maxWidth,
            padding: const .symmetric(horizontal: 12),
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
                                ignoring: _isCapturing,
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
                      if (cover?.isNotEmpty == true &&
                          title?.isNotEmpty == true)
                        Container(
                          height: 81,
                          clipBehavior: Clip.hardEdge,
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
                                                  color:
                                                      theme.colorScheme.outline,
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
                            onPressed: () => setState(() {
                              showBottom = !showBottom;
                            }),
                          ),
                          iconButton(
                            size: buttonSize,
                            tooltip: '关闭',
                            icon: const Icon(Icons.clear),
                            onPressed: Get.back,
                            bgColor: theme.colorScheme.onInverseSurface,
                            iconColor: theme.colorScheme.onSurfaceVariant,
                          ),
                          iconButton(
                            size: buttonSize,
                            tooltip: '保存',
                            context: context,
                            icon: const Icon(Icons.save_alt),
                            onPressed: _onPicAction,
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
                            onPressed: () => setState(() {
                              showFullImages = !showFullImages;
                            }),
                          ),
                          iconButton(
                            size: buttonSize,
                            tooltip: '复制图片',
                            context: context,
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () => _onPicAction(_PicAction.copy),
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
      ],
    );
  }
}

enum _CoverType { def16_9, square }

enum _PicAction { save, copy }
