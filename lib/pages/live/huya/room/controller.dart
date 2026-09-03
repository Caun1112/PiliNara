import 'dart:async';

import 'package:PiliPlus/pages/danmaku/danmaku_model.dart' show DanmakuExtra;
import 'package:PiliPlus/pages/live/huya/follow/service.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_core/simple_live_core.dart';

bool shouldRecoverHuyaPlaybackError(String reason) {
  final normalizedReason = reason.toLowerCase();
  return normalizedReason.contains('failed to open') ||
      normalizedReason.contains('can not open') ||
      normalizedReason.contains('cannot open') ||
      normalizedReason.contains('http error') ||
      normalizedReason.contains('ffurl_read returned') ||
      normalizedReason.contains('connection reset') ||
      normalizedReason.contains('connection timed out') ||
      normalizedReason.contains('end of file');
}

enum HuyaPlaybackRecoveryAction {
  retryCurrentLine,
  refreshCurrentLine,
  switchLine,
  fail,
}

HuyaPlaybackRecoveryAction resolveHuyaPlaybackRecoveryAction({
  required int retryCount,
  required int lineIndex,
  required int lineCount,
}) {
  if (retryCount == 0) {
    return HuyaPlaybackRecoveryAction.retryCurrentLine;
  }
  if (retryCount == 1) {
    return HuyaPlaybackRecoveryAction.refreshCurrentLine;
  }
  if (lineIndex + 1 < lineCount) {
    return HuyaPlaybackRecoveryAction.switchLine;
  }
  return HuyaPlaybackRecoveryAction.fail;
}

class HuyaLiveRoomController extends GetxController {
  HuyaLiveRoomController({required this.roomId, HuyaSite? site})
    : site = site ?? HuyaLiveRepository.instance.site {
    // LiveContainer 会在画面仍可见时把宿主场景报告为 NotVisible。
    // 虎牙弹幕不受影响，但通用播放器会因此主动暂停视频。
    plPlayerController
      ..ignoreAppLifecyclePause = true
      ..livePlaybackErrorHandler = _recoverPlayback
      ..livePlaybackEndedHandler = () => _recoverPlayback('end of file');
  }

  static const int _maxChatMessages = 500;

  final String roomId;
  final HuyaSite site;
  final PlPlayerController plPlayerController = PlPlayerController.getInstance(
    isLive: true,
  );
  final ScrollController chatScrollController = ScrollController();

  final Rxn<LiveRoomDetail> detail = Rxn<LiveRoomDetail>();
  final RxList<LivePlayQuality> qualities = <LivePlayQuality>[].obs;
  final RxList<String> playUrls = <String>[].obs;
  final RxList<LiveMessage> messages = <LiveMessage>[].obs;
  final RxBool loading = true.obs;
  final RxBool switchingSource = false.obs;
  final RxnString error = RxnString();
  final RxInt qualityIndex = 0.obs;
  final RxInt lineIndex = 0.obs;
  final RxString onlineText = ''.obs;
  final RxBool followed = false.obs;

  DanmakuController<DanmakuExtra>? danmakuController;
  LiveDanmaku? _liveDanmaku;
  Map<String, String>? _playHeaders;
  int _loadGeneration = 0;
  bool _recovering = false;
  int _mediaErrorRetryCount = 0;
  Timer? _stablePlaybackTimer;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    loading.value = true;
    error.value = null;
    try {
      final roomDetail = await site.getRoomDetail(roomId: roomId);
      if (!_isCurrent(generation)) return;
      if (!roomDetail.status) {
        throw StateError('当前直播间未开播');
      }
      detail.value = roomDetail;
      onlineText.value = NumUtils.numFormat(roomDetail.online);
      followed.value = HuyaFollowService.instance.contains(roomDetail.roomId);
      if (followed.value) {
        unawaited(HuyaFollowService.instance.updateDetail(roomDetail));
      }

      final result = await site.getPlayQualites(detail: roomDetail);
      if (!_isCurrent(generation)) return;
      if (result.isEmpty) {
        throw StateError('没有可用的播放画质');
      }
      qualities.assignAll(result);
      qualityIndex.value = 0;
      lineIndex.value = 0;
      await _reloadPlaySource(generation: generation);
      if (!_isCurrent(generation)) return;
      _startDanmaku(roomDetail);
      loading.value = false;
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      loading.value = false;
      error.value = _readableError(exception);
    }
  }

  Future<void> refreshPlaySource() async {
    if (detail.value == null || qualities.isEmpty) return;
    _mediaErrorRetryCount = 0;
    await _reloadPlaySource(generation: _loadGeneration);
  }

  Future<void> changeQuality(int index) async {
    if (index < 0 || index >= qualities.length || index == qualityIndex.value) {
      return;
    }
    _mediaErrorRetryCount = 0;
    qualityIndex.value = index;
    lineIndex.value = 0;
    await _reloadPlaySource(generation: _loadGeneration);
  }

  Future<void> changeLine(int index) async {
    if (index < 0 || index >= playUrls.length || index == lineIndex.value) {
      return;
    }
    _mediaErrorRetryCount = 0;
    lineIndex.value = index;
    await _openCurrentSource();
  }

  Future<void> toggleFollow() async {
    final roomDetail = detail.value;
    if (roomDetail == null) return;
    followed.value = await HuyaFollowService.instance.toggle(roomDetail);
    SmartDialog.showToast(
      followed.value ? '已关注 ${roomDetail.userName}' : '已取消关注',
    );
  }

  Future<void> _reloadPlaySource({required int generation}) async {
    final roomDetail = detail.value;
    if (roomDetail == null || qualities.isEmpty) return;
    switchingSource.value = true;
    try {
      final playUrl = await site.getPlayUrls(
        detail: roomDetail,
        quality: qualities[qualityIndex.value],
      );
      if (!_isCurrent(generation)) return;
      if (playUrl.urls.isEmpty) {
        throw StateError('没有可用的播放线路');
      }
      playUrls.assignAll(playUrl.urls);
      _playHeaders = playUrl.headers;
      if (lineIndex.value >= playUrls.length) {
        lineIndex.value = 0;
      }
      await _openCurrentSource();
    } catch (exception) {
      if (_isCurrent(generation)) {
        error.value = _readableError(exception);
      }
    } finally {
      if (_isCurrent(generation)) {
        switchingSource.value = false;
      }
    }
  }

  Future<void> _openCurrentSource() async {
    if (playUrls.isEmpty || lineIndex.value >= playUrls.length) return;
    error.value = null;
    switchingSource.value = true;
    try {
      await plPlayerController.setDataSource(
        NetworkSource(
          videoSource: playUrls[lineIndex.value],
          audioSource: null,
          httpHeaders: _playHeaders,
        ),
        isLive: true,
        autoplay: true,
        roomId: int.tryParse(roomId),
      );
      PlPlayerController.setPlayCallBack(plPlayerController.play);
      _markPlaybackOpened();
    } finally {
      switchingSource.value = false;
    }
  }

  void _markPlaybackOpened() {
    _stablePlaybackTimer?.cancel();
    _stablePlaybackTimer = Timer(const Duration(seconds: 20), () {
      if (plPlayerController.videoPlayerController?.state.playing == true) {
        _mediaErrorRetryCount = 0;
      }
    });
  }

  Future<void> _recoverPlayback(String reason) async {
    if (isClosed || playUrls.isEmpty) return;
    if (!shouldRecoverHuyaPlaybackError(reason)) {
      return;
    }
    if (_recovering) return;
    _recovering = true;
    _stablePlaybackTimer?.cancel();
    try {
      final action = resolveHuyaPlaybackRecoveryAction(
        retryCount: _mediaErrorRetryCount,
        lineIndex: lineIndex.value,
        lineCount: playUrls.length,
      );
      switch (action) {
        case HuyaPlaybackRecoveryAction.retryCurrentLine:
          _mediaErrorRetryCount++;
          await _openCurrentSource();
        case HuyaPlaybackRecoveryAction.refreshCurrentLine:
          _mediaErrorRetryCount++;
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!isClosed) {
            await _reloadPlaySource(generation: _loadGeneration);
          }
        case HuyaPlaybackRecoveryAction.switchLine:
          _mediaErrorRetryCount = 0;
          lineIndex.value++;
          await _openCurrentSource();
        case HuyaPlaybackRecoveryAction.fail:
          error.value = '播放失败：$reason';
          SmartDialog.showToast('播放失败: $reason');
      }
    } finally {
      _recovering = false;
    }
  }

  void _startDanmaku(LiveRoomDetail roomDetail) {
    _liveDanmaku?.stop();
    final danmaku = site.getDanmaku();
    _liveDanmaku = danmaku
      ..onMessage = _onDanmakuMessage
      ..onClose = (message) {
        if (messages.isEmpty) {
          error.value = message;
        }
      };
    danmaku.start(roomDetail.danmakuData);
  }

  void _onDanmakuMessage(LiveMessage message) {
    if (message.type == LiveMessageType.online) {
      onlineText.value = NumUtils.numFormat(message.data);
      return;
    }
    if (message.type != LiveMessageType.chat || message.message.isEmpty) {
      return;
    }
    messages.add(message);
    if (messages.length > _maxChatMessages) {
      messages.removeRange(0, messages.length - _maxChatMessages);
    }

    danmakuController?.addDanmaku(
      DanmakuContentItem<DanmakuExtra>(
        message.message,
        color: Color.fromARGB(
          255,
          message.color.r,
          message.color.g,
          message.color.b,
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chatScrollController.hasClients) {
        chatScrollController.animateTo(
          chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isCurrent(int generation) {
    return !isClosed && generation == _loadGeneration;
  }

  String _readableError(Object exception) {
    if (exception is StateError) {
      return exception.message.toString();
    }
    final message = exception.toString();
    return message.startsWith('Error: ')
        ? message.substring('Error: '.length)
        : message;
  }

  @override
  void onClose() {
    _loadGeneration++;
    _stablePlaybackTimer?.cancel();
    _liveDanmaku?.stop();
    _liveDanmaku = null;
    danmakuController?.clear();
    danmakuController = null;
    chatScrollController.dispose();
    PlPlayerController.setPlayCallBack(null);
    plPlayerController.ignoreAppLifecyclePause = false;
    plPlayerController.livePlaybackErrorHandler = null;
    plPlayerController.livePlaybackEndedHandler = null;
    plPlayerController.dispose();
    super.onClose();
  }
}
