import 'dart:async';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/flutter/popup_menu.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models/common/video/audio_quality.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/download/view.dart';
import 'package:PiliPlus/pages/download/utils/cache_share.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class DownloadPanel extends StatefulWidget {
  const DownloadPanel({
    super.key,
    required this.index,
    this.pgcItem,
    this.videoDetail,
    required this.episodes,
    required this.scrollController,
    required this.videoDetailController,
    required this.heroTag,
    this.ugcIntroController,
    required this.cidSet,
    this.shareAfterDownload = false,
  });

  final int index;
  final PgcInfoModel? pgcItem;
  final VideoDetailData? videoDetail;
  final List<ugc.BaseEpisodeItem> episodes;
  final ScrollController scrollController;
  final VideoDetailController videoDetailController;
  final String heroTag;
  final UgcIntroController? ugcIntroController;
  final Set<int> cidSet;
  final bool shareAfterDownload;

  @override
  State<DownloadPanel> createState() => _DownloadPanelState();
}

@visibleForTesting
String formatDownloadSize(int bytes) {
  const megabyte = 1024 * 1024;
  const gigabyte = 1024 * megabyte;
  if (bytes >= gigabyte) {
    return '${(bytes / gigabyte).toStringAsFixed(2)} GB';
  }
  return '${(bytes / megabyte).toStringAsFixed(1)} MB';
}

@visibleForTesting
int estimateDownloadSizeBytes({
  required int durationSeconds,
  required int videoBandwidth,
  required int audioBandwidth,
}) => ((videoBandwidth + audioBandwidth) * durationSeconds / 8).round();

typedef _DownloadQualityOption = ({
  VideoQuality quality,
  VideoItem? video,
  AudioItem? audio,
  int estimatedBytes,
});

class _DownloadPanelState extends State<DownloadPanel> {
  final DownloadService _downloadService = Get.find<DownloadService>();
  final ListController _listController = ListController();

  late final cidSet = widget.cidSet;
  VideoQuality _quality = VideoQuality.fromCode(Pref.defaultDownloadVideoQa);
  List<_DownloadQualityOption> _qualityOptions = const [];
  final Map<int, int> _resolvedSizes = {};
  int? _selectingQualityCode;

  ({String title, String sourceKey})? get _autoFolderInfo {
    final ugcSeason = widget.videoDetail?.ugcSeason;
    final title = ugcSeason?.title?.trim();
    final seasonId = ugcSeason?.id;
    if (title == null || title.isEmpty || seasonId == null) {
      return null;
    }
    return (
      title: title,
      sourceKey: 'ugc-season:$seasonId',
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.shareAfterDownload) {
      _qualityOptions = _buildQualityOptions();
      unawaited(_resolveQualitySizes());
    }
    if (widget.index != -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listController.jumpToItem(
          index: widget.index,
          scrollController: widget.scrollController,
          alignment: 0,
        );
      });
    }
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.shareAfterDownload) {
      return _buildQualityPicker(theme);
    }
    final dividerColor = theme.colorScheme.outline.withValues(alpha: 0.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildHeader(theme),
        _buildBody(theme),
        Divider(height: 1, color: dividerColor),
        _buildFooter(theme, dividerColor),
      ],
    );
  }

  List<_DownloadQualityOption> _buildQualityOptions() {
    final data = widget.videoDetailController.data;
    if (data.dash case final dash?) {
      final duration = dash.duration ?? (data.timeLength ?? 0) ~/ 1000;
      final audio = _selectAudio(dash.audio);
      final audioBandwidth = audio?.bandWidth ?? 0;
      return VideoQuality.values
          .map((quality) {
            final videos = dash.video
                ?.where((video) => video.quality == quality)
                .toList();
            if (videos == null || videos.isEmpty) {
              return null;
            }
            final codecs = data.supportFormats
                ?.firstWhereOrNull((format) => format.quality == quality.code)
                ?.codecs;
            final preferredCodecs = codecs?.isNotEmpty == true
                ? VideoUtils.selectCodec(codecs!, Pref.preferCodecs).codes
                : const <String>[];
            final video = videos.firstWhere(
              (video) => preferredCodecs.any(video.codecs!.startsWith),
              orElse: () => videos.first,
            );
            return (
              quality: quality,
              video: video,
              audio: audio,
              estimatedBytes: estimateDownloadSizeBytes(
                durationSeconds: duration,
                videoBandwidth: video.bandWidth ?? 0,
                audioBandwidth: audioBandwidth,
              ),
            );
          })
          .nonNulls
          .toList();
    }

    final durl = data.durl;
    final qualityCode = data.quality;
    if (durl?.isNotEmpty == true && qualityCode != null) {
      return [
        (
          quality: VideoQuality.fromCode(qualityCode),
          video: null,
          audio: null,
          estimatedBytes: durl!.fold(0, (sum, item) => sum + (item.size ?? 0)),
        ),
      ];
    }
    return const [];
  }

  AudioItem? _selectAudio(List<AudioItem>? audioList) {
    if (audioList == null || audioList.isEmpty) {
      return null;
    }
    final preferAudioQa = Pref.defaultAudioQa;
    final audioIds = audioList.map((audio) => audio.id!).toList();
    int closestNumber = audioIds.findClosestTarget(
      (id) => id <= preferAudioQa,
      (a, b) => a > b ? a : b,
    );
    if (!audioIds.contains(preferAudioQa) &&
        audioIds.any((id) => id > preferAudioQa)) {
      closestNumber = AudioQuality.k192.code;
    }
    return audioList.firstWhere(
      (audio) => audio.id == closestNumber,
      orElse: () => audioList.first,
    );
  }

  Future<void> _resolveQualitySizes() async {
    final audioSizes = <AudioItem, Future<int?>>{};
    final futures = _qualityOptions.map((option) async {
      final video = option.video;
      if (video == null) {
        return;
      }
      final audioSize = option.audio == null
          ? 0
          : await audioSizes.putIfAbsent(
              option.audio!,
              () => _resolveMediaSize(option.audio!, isAudio: true),
            );
      final videoSize = await _resolveMediaSize(video);
      if (videoSize != null && audioSize != null && mounted) {
        setState(() {
          _resolvedSizes[option.quality.code] = videoSize + audioSize;
        });
      }
    });
    await Future.wait(futures);
  }

  Future<int?> _resolveMediaSize(
    BaseItem item, {
    bool isAudio = false,
  }) async {
    final cancelToken = CancelToken();
    try {
      final response = await Request.http11Dio.get<ResponseBody>(
        VideoUtils.getCdnUrl(item.playUrls, isAudio: isAudio),
        options: Options(
          headers: const {'range': 'bytes=0-0'},
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
        cancelToken: cancelToken,
      );
      final contentRange = response.headers.value('content-range');
      final total = contentRange == null
          ? null
          : int.tryParse(contentRange.split('/').last);
      if (total != null) {
        return total;
      }
      if (response.statusCode == 200) {
        return response.data?.contentLength;
      }
    } catch (_) {
      return null;
    } finally {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel();
      }
    }
    return null;
  }

  Widget _buildQualityPicker(ThemeData theme) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 248, maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text('下载画质', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          if (_qualityOptions.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Text('暂无可下载的画质'),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 4),
                itemCount: _qualityOptions.length,
                itemBuilder: (context, index) {
                  final option = _qualityOptions[index];
                  final bytes =
                      _resolvedSizes[option.quality.code] ??
                      option.estimatedBytes;
                  final isSelecting =
                      _selectingQualityCode == option.quality.code;
                  return InkWell(
                    onTap: _selectingQualityCode == null
                        ? () => _onQualitySelected(option.quality)
                        : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Text(
                              option.quality.shortDesc,
                              style: theme.textTheme.labelLarge,
                            ),
                            const Spacer(),
                            if (isSelecting)
                              const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Text(
                                formatDownloadSize(bytes),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
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
  }

  Future<void> _onQualitySelected(VideoQuality quality) async {
    if (_selectingQualityCode != null) {
      return;
    }
    setState(() => _selectingQualityCode = quality.code);
    try {
      await Pref.setDefaultDownloadVideoQa(quality.code);
      _quality = quality;
      final currentCid =
          widget.videoDetailController.seasonCid ??
          widget.videoDetailController.cid.value;
      final removed = await _downloadService.removeDownloadForQualityChange(
        cid: currentCid,
        quality: quality.code,
      );
      if (removed) {
        cidSet.remove(currentCid);
      }
      final wasCached = cidSet.contains(currentCid);
      final started = _downloadCurrent(currentCid);
      if ((started || wasCached) && mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _selectingQualityCode = null);
      }
    }
  }

  bool _downloadCurrent(int currentCid) {
    final episode = widget.episodes.first;
    if (episode case ugc.EpisodeItem(:final pages?)) {
      final part = pages.firstWhereOrNull((part) => part.cid == currentCid);
      if (part != null) {
        return _onDownload(
          index: part.page ?? widget.index,
          episode: part,
          parent: episode,
        );
      }
    }
    return _onDownload(index: widget.index, episode: episode);
  }

  Widget _buildHeader(ThemeData theme) {
    final textStyle = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Row(
        spacing: 16,
        children: [
          if (kDebugMode || PlatformUtils.isMobile) ...[
            const Spacer(),
            StreamBuilder(
              stream: Connectivity().onConnectivityChanged,
              builder: (context, snapshot) {
                if (snapshot.data case final data?) {
                  final network = data.contains(ConnectivityResult.wifi)
                      ? 'WIFI'
                      : '数据';
                  return Text('当前网络：$network', style: textStyle);
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final episodes = widget.episodes;
    return Expanded(
      child: Material(
        type: MaterialType.transparency,
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: SuperSliverList.builder(
                itemCount: episodes.length,
                listController: _listController,
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final hasParts =
                      episode is ugc.EpisodeItem && episode.pages!.length > 1;
                  Widget child = _buildItem(
                    theme: theme,
                    index: index,
                    hasParts: hasParts,
                    episode: episode,
                    isCurrentIndex: index == widget.index,
                  );
                  if (hasParts) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        child,
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: PagesPanel(
                            list: episode.pages,
                            cover: episode.arc?.pic,
                            heroTag: widget.heroTag,
                            ugcIntroController: widget.ugcIntroController!,
                            bvid: episode.bvid ?? IdUtils.av2bv(episode.aid!),
                            cidSet: cidSet,
                            onDownload: (Part part) => _onDownload(
                              index: index,
                              episode: part,
                              parent: episode,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return child;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final int? vipStatus = Pref.userInfoCache?.vipStatus;
  @pragma('vm:notify-debugger-on-exception')
  bool _onDownload({
    required int index,
    required ugc.BaseEpisodeItem episode,
    bool isFromList = false,
    bool isDownloadAll = false,
    ugc.EpisodeItem? parent,
  }) {
    final cid = episode.cid;
    // on download
    if (cid == null) {
      SmartDialog.showToast('null cid');
      return false;
    }

    if (cidSet.contains(cid)) {
      if (widget.shareAfterDownload) {
        CacheShare.shareAfterDownload(_downloadService, cid);
      }
      if (kDebugMode) {
        SmartDialog.showToast('downloaded');
      }
      return false;
    }

    if (kReleaseMode && episode.badge == '会员' && Accounts.mainEqVideo) {
      if (vipStatus != 1) {
        if (!isDownloadAll) {
          SmartDialog.showToast('需要大会员');
        }
        return false;
      }
    }

    if (episode is ugc.EpisodeItem) {
      final pages = episode.pages!;
      if (pages.length > 1) {
        if (isFromList && kDebugMode) {
          SmartDialog.showToast('hasParts');
        }
        if (isDownloadAll) {
          for (int i = 0; i < pages.length; i++) {
            _onDownload(
              index: i,
              episode: pages[i],
              parent: episode,
            );
          }
          return true;
        }
        return false;
      }
    }

    try {
      final autoFolderInfo = _autoFolderInfo;
      switch (episode) {
        case Part part:
          _downloadService.downloadVideo(
            part,
            parent == null ? widget.videoDetail : null,
            parent,
            _quality,
            autoFolderTitle: autoFolderInfo?.title,
            autoFolderSourceKey: autoFolderInfo?.sourceKey,
          );
          break;
        case ugc.EpisodeItem episode:
          _downloadService.downloadVideo(
            episode.pages!.first,
            null,
            episode,
            _quality,
            autoFolderTitle: autoFolderInfo?.title,
            autoFolderSourceKey: autoFolderInfo?.sourceKey,
          );
          break;
        case pgc.EpisodeItem episode:
          _downloadService.downloadBangumi(
            index,
            widget.pgcItem!,
            episode,
            _quality,
          );
          break;
      }
      cidSet.add(cid);
      if (widget.shareAfterDownload) {
        CacheShare.shareAfterDownload(_downloadService, cid);
      }
      return true;
    } catch (e, s) {
      Utils.reportError(e, s);
      SmartDialog.showToast(e.toString());
    }
    return false;
  }

  Widget _buildItem({
    required ThemeData theme,
    required int index,
    required bool hasParts,
    required bool isCurrentIndex,
    required ugc.BaseEpisodeItem episode,
  }) {
    late String title;
    num? duration;
    int? pubdate;
    int? view;
    int? danmaku;
    bool? isCharging;
    int? cid;

    String? cover;
    bool? cacheWidth;

    switch (episode) {
      case Part part:
        cid = part.cid;
        cover = part.firstFrame ?? widget.videoDetail?.pic;
        title = part.part ?? widget.videoDetail!.title!;
        duration = part.duration;
        pubdate = part.ctime;
        cacheWidth = part.dimension?.cacheWidth;
        break;
      case ugc.EpisodeItem item:
        cid = item.cid;
        title = item.title!;
        if (item.arc case final arc?) {
          cover = arc.pic;
          duration = arc.duration;
          pubdate = arc.pubdate;
          if (arc.stat case final stat?) {
            view = stat.view;
            danmaku = stat.danmaku;
          }
          cacheWidth = arc.dimension?.cacheWidth;
        }
        if (item.attribute == 8) {
          isCharging = true;
        }
        break;
      case pgc.EpisodeItem item:
        cid = item.cid;
        title = item.showTitle ?? item.title!;
        cover = item.cover;
        if (item.from == 'pugv') {
          duration = item.duration;
          view = item.play;
        } else {
          duration = item.duration == null ? null : item.duration! ~/ 1000;
        }
        pubdate = item.pubTime;
        cacheWidth = item.dimension?.cacheWidth;
        break;
    }
    late final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: 110,
        child: Builder(
          builder: (context) {
            return Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  if (_onDownload(
                    index: index,
                    episode: episode,
                    isFromList: true,
                  )) {
                    (context as Element).markNeedsBuild();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Style.safeSpace,
                    vertical: 5,
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      if (cover?.isNotEmpty == true)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            NetworkImgLayer(
                              src: cover,
                              width: 160,
                              height: 100,
                              cacheWidth: cacheWidth,
                            ),
                            if (duration != null && duration > 0)
                              PBadge(
                                text: DurationUtils.formatDuration(duration),
                                right: 6.0,
                                bottom: 6.0,
                                type: PBadgeType.gray,
                              ),
                            if (isCharging == true)
                              const PBadge(
                                text: '充电专属',
                                top: 6,
                                right: 6,
                                type: PBadgeType.error,
                              )
                            else if (episode.badge != null)
                              PBadge(
                                text: episode.badge,
                                top: 6,
                                right: 6,
                                type: switch (episode.badge) {
                                  '预告' => PBadgeType.gray,
                                  '限免' => PBadgeType.free,
                                  _ => PBadgeType.primary,
                                },
                              ),
                          ],
                        )
                      else if (isCurrentIndex)
                        Image.asset(
                          Assets.livingStatic,
                          color: primary,
                          height: 12,
                          cacheHeight: 12.cacheSize(context),
                          semanticLabel: '正在播放：',
                        ),
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      fontSize:
                                          theme.textTheme.bodyMedium!.fontSize,
                                      height: 1.42,
                                      letterSpacing: 0.3,
                                      fontWeight: isCurrentIndex
                                          ? FontWeight.bold
                                          : null,
                                      color: isCurrentIndex ? primary : null,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (pubdate != null)
                                  Text(
                                    DateFormatUtils.format(pubdate),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1,
                                      color: theme.colorScheme.outline,
                                      overflow: TextOverflow.clip,
                                    ),
                                  ),
                                const SizedBox(height: 2),
                                Row(
                                  spacing: 8,
                                  children: [
                                    if (view != null)
                                      StatWidget(
                                        value: view,
                                        type: StatType.play,
                                      ),
                                    if (danmaku != null)
                                      StatWidget(
                                        value: danmaku,
                                        type: StatType.danmaku,
                                      ),
                                    if (cid != null &&
                                        cidSet.contains(cid)) ...[
                                      const Spacer(),
                                      _buildDownloadSize(cid, theme),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            if (!hasParts && cidSet.contains(cid))
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Icon(
                                  size: 13,
                                  color: theme.colorScheme.secondary.withValues(
                                    alpha: 0.8,
                                  ),
                                  FontAwesomeIcons.circleDown,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDownloadSize(int cid, ThemeData theme) {
    return Obx(() {
      final current = _downloadService.curDownload.value;
      final entry = current?.cid == cid
          ? current
          : _downloadService.waitDownloadQueue.firstWhereOrNull(
                  (entry) => entry.cid == cid,
                ) ??
                _downloadService.downloadList.firstWhereOrNull(
                  (entry) => entry.cid == cid,
                );
      final totalBytes = entry?.totalBytes ?? 0;
      return Text(
        totalBytes > 0 ? formatDownloadSize(totalBytes) : '大小计算中…',
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          height: 1,
          color: theme.colorScheme.outline,
        ),
      );
    });
  }

  Widget _buildFooter(ThemeData theme, Color dividerColor) {
    return Container(
      color: theme.hoverColor,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Row(
        children: [
          if (!widget.shareAfterDownload) ...[
            _buildBottomBtn(
              text: '缓存全部',
              onTap: () {
                showConfirmDialog(
                  context: context,
                  title: const Text('确定缓存全部？'),
                  onConfirm: () {
                    for (int i = 0; i < widget.episodes.length; i++) {
                      _onDownload(
                        index: i,
                        episode: widget.episodes[i],
                        isDownloadAll: true,
                      );
                    }
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
            SizedBox(
              height: 20,
              child: VerticalDivider(
                width: 1,
                color: dividerColor,
              ),
            ),
          ],
          _buildBottomBtn(
            text: '查看缓存',
            onTap: () => Navigator.of(context).push(
              GetPageRoute(page: () => const DownloadPage()),
            ),
          ),
          SizedBox(
            height: 20,
            child: VerticalDivider(
              width: 1,
              color: dividerColor,
            ),
          ),
          _buildQualityBtn(theme),
        ],
      ),
    );
  }

  Widget _buildQualityBtn(ThemeData theme) {
    return Expanded(
      child: Builder(
        builder: (context) => StaticPopupMenuButton<VideoQuality>(
          initialValue: _quality,
          onSelected: (value) async {
            await Pref.setDefaultDownloadVideoQa(value.code);
            if (mounted) {
              setState(() => _quality = value);
            }
          },
          itemBuilder: (context) => VideoQuality.values
              .map(
                (e) => PopupMenuItem(
                  value: e,
                  child: Text(e.desc),
                ),
              )
              .toList(),
          child: SizedBox(
            height: 40,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _quality.desc,
                  style: const TextStyle(height: 1),
                  strutStyle: const StrutStyle(height: 1, leading: 0),
                ),
                Icon(
                  size: 18,
                  Icons.keyboard_arrow_down,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBtn({
    required String text,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
