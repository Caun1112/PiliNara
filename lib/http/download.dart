import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/download/bili_download_media_file_info.dart';
import 'package:PiliPlus/models_new/sponsor_block/segment_item.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:collection/collection.dart';

abstract final class DownloadHttp {
  static const String referer = "https://www.bilibili.com/";
  static const String userAgent = "Bilibili Freedoooooom/MarkII";

  /// Validates actual streams, rather than advertised formats or quality names.
  /// An exact requirement must survive account changes and URL refreshes.
  static int selectVideoQuality(
    PlayUrlModel response, {
    required int preferredQuality,
    int? requiredQuality,
  }) {
    if (requiredQuality != null) {
      // The current downloader consumes only the first durl segment. Never
      // export a partial video as a completed exact-quality download.
      if (response.dash == null && (response.durl?.length ?? 0) > 1) {
        throw StateError('当前480P资源包含多个视频分段，暂不支持自动下载分享');
      }
      final available = response.dash != null
          ? response.dash!.video?.any(
                  (video) => video.quality.code == requiredQuality,
                ) ==
                true
          : response.quality == requiredQuality &&
                response.durl?.isNotEmpty == true;
      if (!available) {
        throw DownloadQualityUnavailableException(requiredQuality);
      }
      return requiredQuality;
    }
    if (response.dash != null) {
      final videos = response.dash!.video!;
      final qualities =
          videos.map((video) => video.quality.code).toSet().toList()
            ..sort((a, b) => b.compareTo(a));
      return qualities.firstWhere(
        (quality) => quality <= preferredQuality,
        orElse: () => qualities.last,
      );
    }
    // durl reports its actual quality directly; absent metadata must never
    // turn an unknown or higher-quality cache into a claimed 480P file.
    return response.quality ?? (throw StateError('播放地址未提供实际画质，无法缓存'));
  }

  /// Exact downloads choose a codec from returned tracks even when optional
  /// support_formats metadata is absent, empty, or out of date.
  static VideoItem selectExactDashVideo(
    PlayUrlModel response, {
    required int quality,
    required List<VideoDecodeFormatType> preferredCodecs,
  }) {
    final videos = response.dash?.video
        ?.where((video) => video.quality.code == quality)
        .toList();
    if (videos == null || videos.isEmpty) {
      throw DownloadQualityUnavailableException(quality);
    }
    for (final codec in preferredCodecs) {
      final video = videos.firstWhereOrNull(
        (video) =>
            video.codecs != null && codec.codes.any(video.codecs!.startsWith),
      );
      if (video != null) return video;
    }
    return videos.first;
  }

  static Future<DownloadVideoUrlResult> getVideoUrl({
    required BiliDownloadEntryInfo entry,
    SourceInfo? source,
    PageInfo? pageData,
    EpInfo? ep,
  }) async {
    final isLogin = Accounts.get(AccountType.video).isLogin;
    final res = await VideoHttp.videoUrl(
      avid: entry.avid,
      bvid: entry.bvid,
      cid: entry.cid,
      seasonId: entry.seasonId,
      epid: ep?.episodeId,
      qn: entry.requiredVideoQuality ?? entry.preferedVideoQuality,
      tryLook: !isLogin && Pref.p1080,
      videoType: switch (ep?.from) {
        'pugv' => VideoType.pugv,
        != null when isLogin => VideoType.pgc,
        _ => VideoType.ugc,
      },
    );
    if (res case Success(:final response)) {
      final dash = response.dash;
      // Validate before mutating the entry, including its segment metadata.
      final targetVideoQa = selectVideoQuality(
        response,
        preferredQuality: entry.preferedVideoQuality,
        requiredQuality: entry.requiredVideoQuality,
      );

      // segments
      entry.segments = response.clipInfoList;

      if (dash != null) {
        final int targetQuality;
        final FormatItem? targetFormat;
        final VideoItem videoDash;
        if (entry.requiredVideoQuality != null) {
          targetQuality = targetVideoQa;
          targetFormat = response.supportFormats?.firstWhereOrNull(
            (format) => format.quality == targetQuality,
          );
          videoDash = selectExactDashVideo(
            response,
            quality: targetQuality,
            preferredCodecs: Pref.preferCodecs,
          );
        } else {
          final result = VideoUtils.findTargetVideo(
            dash.video!,
            entry.preferedVideoQuality,
            response.acceptQuality,
            response.supportFormats!,
            Pref.preferCodecs,
          );
          targetQuality = result.$1;
          targetFormat = result.$2;
          videoDash = result.$4;
        }
        final videoUrl = VideoUtils.getCdnUrl(videoDash.playUrls);

        entry
          ..typeTag = targetQuality.toString()
          ..videoQuality = targetQuality
          ..preferedVideoQuality = targetQuality
          ..qualityPithyDescription =
              targetFormat?.displayDesc ??
              VideoQuality.fromCode(targetQuality).shortDesc;

        final Type2File videoFile = Type2File(
          id: videoDash.id,
          baseUrl: videoUrl,
          bandwidth: videoDash.bandWidth!,
          codecid: videoDash.codecid!,
          size: 0,
          md5: '',
          noRexcode: false,
          frameRate: videoDash.frameRate ?? '',
          width: videoDash.width!,
          height: videoDash.height!,
          dashDrmType: 0,
        );
        List<Type2File>? audioFileList;
        final List<AudioItem>? audioList = dash.audio;
        if (audioList != null && audioList.isNotEmpty) {
          final preferAudioQa =
              entry.preferedAudioQuality ?? Pref.defaultAudioQa;
          final audioDash = VideoUtils.findTargetAudio(
            audioList,
            preferAudioQa,
          );
          final audioUrl = VideoUtils.getCdnUrl(
            audioDash.playUrls,
            isAudio: true,
          );
          audioFileList = [
            Type2File(
              id: audioDash.id,
              baseUrl: audioUrl,
              bandwidth: audioDash.bandWidth!,
              codecid: audioDash.codecid!,
              size: 0,
              md5: '',
              noRexcode: false,
              frameRate: audioDash.frameRate!,
              width: audioDash.width!,
              height: audioDash.height!,
              dashDrmType: 0,
            ),
          ];
          entry.hasDashAudio = true;
        }
        return DownloadVideoUrlResult(
          mediaFileInfo: Type2(
            duration: dash.duration!,
            video: [videoFile],
            audio: audioFileList,
            referer: referer,
            userAgent: userAgent,
          ),
          clipInfoList: response.clipInfoList,
        );
      } else {
        final first = response.durl!.first;
        final List<Type1Segment> segmentList = [
          Type1Segment(
            backupUrls: [],
            bytes: first.size!,
            duration: first.length!,
            md5: '',
            metaUrl: '',
            order: first.order!,
            url: VideoUtils.getCdnUrl(first.playUrls),
          ),
        ];
        final FormatItem? formatItem = response.supportFormats
            ?.firstWhereOrNull((e) => e.quality == response.quality);
        final String description =
            formatItem?.displayDesc ??
            VideoQuality.fromCode(targetVideoQa).shortDesc;

        entry
          ..mediaType = 1
          ..typeTag = targetVideoQa.toString()
          ..videoQuality = targetVideoQa
          ..preferedVideoQuality = targetVideoQa
          ..qualityPithyDescription = description;

        final List<Type1PlayerCodecConfig> playerCodecConfigList = [
          Type1PlayerCodecConfig(player: "IJK_PLAYER", useIjkMediaCodec: false),
          Type1PlayerCodecConfig(
            player: "ANDROID_PLAYER",
            useIjkMediaCodec: false,
          ),
        ];

        return DownloadVideoUrlResult(
          mediaFileInfo: Type1(
            from: pageData?.from ?? ep?.from,
            quality: entry.preferedVideoQuality,
            typeTag: entry.typeTag,
            description: description,
            playerCodecConfigList: playerCodecConfigList,
            segmentList: segmentList,
            parseTimestampMilli: 0,
            availablePeriodMilli: 0,
            isDownloaded: false,
            isResolved: true,
            timeLength: 0,
            marlinToken: '',
            videoCodecId: 0,
            videoProject: true,
            format: response.format!,
            playerError: 0,
            needVip: false,
            needLogin: false,
            intact: false,
            referer: referer,
            userAgent: userAgent,
          ),
          clipInfoList: response.clipInfoList,
        );
      }
    } else {
      throw res.toString();
    }
  }
}

class DownloadQualityUnavailableException implements Exception {
  const DownloadQualityUnavailableException(this.quality);

  final int quality;

  @override
  String toString() {
    final description = VideoQuality.values
        .firstWhereOrNull((value) => value.code == quality)
        ?.shortDesc;
    return '当前视频或当前播放账号未提供 ${description ?? '画质 $quality'}，未开始下载';
  }
}

class DownloadVideoUrlResult {
  final BiliDownloadMediaInfo mediaFileInfo;
  final List<SegmentItemModel>? clipInfoList;

  const DownloadVideoUrlResult({
    required this.mediaFileInfo,
    this.clipInfoList,
  });
}
