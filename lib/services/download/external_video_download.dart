import 'dart:async';

import 'package:PiliPlus/http/download.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/account_type.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/pages/download/utils/cache_share.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/external_download_request.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

final externalVideoDownload = ExternalVideoDownload();

/// Imports a part directly into the download queue without creating a player.
class ExternalVideoDownload {
  ExternalVideoDownload({
    DownloadService Function()? findService,
    Future<LoadingState<VideoDetailData>> Function(ExternalDownloadRequest)?
    fetchDetail,
    Future<LoadingState<PlayUrlModel>> Function(ExternalDownloadRequest)?
    fetchPlayUrl,
    Future<void> Function()? navigate,
    Future<void> Function(DownloadService, int)? share,
    Future<void> Function(String)? toast,
  }) : _findService = findService ?? (() => Get.find<DownloadService>()),
       _fetchDetail =
           fetchDetail ??
           ((request) => VideoHttp.videoIntro(bvid: request.bvid)),
       _fetchPlayUrl = fetchPlayUrl ?? _defaultFetchPlayUrl,
       _navigate = navigate ?? _defaultNavigate,
       _share =
           share ??
           ((service, cid) => CacheShare.shareAfterDownload(
             service,
             cid,
             requiredQuality: ExternalDownloadRequest.quality,
           )),
       _toast = toast ?? SmartDialog.showToast;

  final DownloadService Function() _findService;
  final Future<LoadingState<VideoDetailData>> Function(ExternalDownloadRequest)
  _fetchDetail;
  final Future<LoadingState<PlayUrlModel>> Function(ExternalDownloadRequest)
  _fetchPlayUrl;
  final Future<void> Function() _navigate;
  final Future<void> Function(DownloadService, int) _share;
  final Future<void> Function(String) _toast;
  final _requests = ExternalDownloadRequestGate();

  static Future<void> _defaultNavigate() async {
    // Cold-start links can arrive while MainPage is still building.
    await WidgetsBinding.instance.endOfFrame;
    // A navigation Future completes when the page is popped; never await it.
    if (Get.currentRoute != '/download') {
      unawaited(Get.toNamed<void>('/download'));
    }
  }

  static Future<LoadingState<PlayUrlModel>> _defaultFetchPlayUrl(
    ExternalDownloadRequest request,
  ) => VideoHttp.videoUrl(
    avid: request.aid,
    bvid: request.bvid,
    cid: request.cid,
    qn: ExternalDownloadRequest.quality,
    tryLook: !Accounts.get(AccountType.video).isLogin && Pref.p1080,
    videoType: VideoType.ugc,
  );

  Future<void> open(ExternalDownloadRequest request) async {
    if (!_requests.begin(request)) return;
    try {
      await _navigate();
      final service = _findService();
      await service.waitForInitialization;
      if (await _reuseExisting(service, request)) return;

      final detailResult = await _fetchDetail(request);
      final detail = detailResult.dataOrNull;
      if (detail == null) {
        await _toast(detailResult.toString());
        return;
      }
      if (detail.aid != request.aid || detail.bvid != request.bvid) {
        await _toast('视频信息与下载请求不一致，请重试');
        return;
      }
      final part = detail.pages?.firstWhereOrNull(
        (part) => part.cid == request.cid,
      );
      if (part == null || (part.page ?? 0) <= 0) {
        await _toast('未找到当前分P，未开始下载');
        return;
      }

      final response = await _fetchPlayUrl(request);
      final playUrl = response.dataOrNull;
      if (playUrl == null) {
        await _toast(response.toString());
        return;
      }
      DownloadHttp.selectVideoQuality(
        playUrl,
        preferredQuality: ExternalDownloadRequest.quality,
        requiredQuality: ExternalDownloadRequest.quality,
      );
      // A manual download may have been added while the API calls were pending.
      if (await _reuseExisting(service, request)) return;
      final entry = await service.downloadVideo(
        index: part.page! - 1,
        page: part,
        videoDetail: detail,
        videoQuality: VideoQuality.clear480,
        requiredVideoQuality: ExternalDownloadRequest.quality,
      );
      if (entry == null) {
        await _toast('未能创建下载任务，请在下载页重试');
        return;
      }
      if (!_isExactQuality(entry, request)) {
        await _showQualityConflict();
        return;
      }
      if (!entry.isCompleted &&
          entry.requiredVideoQuality != ExternalDownloadRequest.quality) {
        await service.requireVideoQuality(
          entry,
          ExternalDownloadRequest.quality,
        );
      }
      if (request.share) {
        await _share(service, request.cid);
      } else {
        await _toast('已加入480P下载队列');
      }
    } on DownloadQualityUnavailableException catch (error) {
      await _toast(error.toString());
    } catch (error, stack) {
      if (kDebugMode) debugPrint('External video download: $error\n$stack');
      await _toast('自动下载失败：$error');
    } finally {
      _requests.finish(request);
    }
  }

  bool _isExactQuality(
    BiliDownloadEntryInfo entry,
    ExternalDownloadRequest request,
  ) =>
      entry.cid == request.cid &&
      entry.avid == request.aid &&
      entry.bvid == request.bvid &&
      (entry.videoQuality ??
              (entry.isCompleted ? null : entry.preferedVideoQuality)) ==
          ExternalDownloadRequest.quality;

  Future<bool> _reuseExisting(
    DownloadService service,
    ExternalDownloadRequest request,
  ) async {
    final entry = [
      ?service.curDownload.value,
      ...service.waitDownloadQueue,
      ...service.downloadList,
    ].firstWhereOrNull((entry) => entry.cid == request.cid);
    if (entry == null) return false;
    if (!_isExactQuality(entry, request)) {
      await _showQualityConflict();
    } else {
      if (!entry.isCompleted &&
          entry.requiredVideoQuality != ExternalDownloadRequest.quality) {
        await service.requireVideoQuality(
          entry,
          ExternalDownloadRequest.quality,
        );
      }
      final restart =
          !entry.isCompleted &&
          (entry.status == DownloadStatus.wait ||
              entry.status == DownloadStatus.pause ||
              entry.status.isFailure);
      if (restart) entry.status = DownloadStatus.wait;
      if (request.share) {
        await _share(service, request.cid);
      } else {
        await _toast('该分P已有480P下载任务或缓存');
      }
      if (restart && !entry.isCompleted) {
        if (!service.waitDownloadQueue.contains(entry)) {
          service.waitDownloadQueue.add(entry);
        }
        if (service.curDownload.value?.status.isDownloading != true) {
          unawaited(service.startDownload(entry));
        } else {
          service.waitDownloadQueue.refresh();
        }
      }
    }
    return true;
  }

  Future<void> _showQualityConflict() => _toast('已有其他画质缓存，请在下载页删除后重试');
}
