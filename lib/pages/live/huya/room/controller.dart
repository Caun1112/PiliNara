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
  return !normalizedReason.contains('audio device') &&
      !normalizedReason.startsWith('could not open codec');
}

class HuyaLiveRoomController extends GetxController {
  HuyaLiveRoomController({required this.roomId, HuyaSite? site})
    : site = site ?? HuyaLiveRepository.instance.site {
    // LiveContainer 会在画面仍可见时把宿主场景报告为 NotVisible。
    // 虎牙弹幕不受影响，但通用播放器会因此主动暂停视频。
    plPlayerController
      ..ignoreAppLifecyclePause = true
      ..livePlaybackErrorHandler = _recoverPlayback
      ..livePlaybackEndedHandler = () => _recoverPlayback('直播流已结束');
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
  String? _pendingRecoveryReason;
  int _recoveryCycles = 0;
  StreamSubscription<Duration>? _positionSubscription;
  Timer? _stallTimer;
  Timer? _stablePlaybackTimer;
  Duration _lastPosition = Duration.zero;
  DateTime _lastProgressAt = DateTime.now();

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
    _recoveryCycles = 0;
    await _reloadPlaySource(generation: _loadGeneration);
  }

  Future<void> changeQuality(int index) async {
    if (index < 0 || index >= qualities.length || index == qualityIndex.value) {
      return;
    }
    _recoveryCycles = 0;
    qualityIndex.value = index;
    lineIndex.value = 0;
    await _reloadPlaySource(generation: _loadGeneration);
  }

  Future<void> changeLine(int index) async {
    if (index < 0 || index >= playUrls.length || index == lineIndex.value) {
      return;
    }
    _recoveryCycles = 0;
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
      _watchPlaybackProgress();
    } finally {
      switchingSource.value = false;
    }
  }

  void _watchPlaybackProgress() {
    final player = plPlayerController.videoPlayerController;
    if (player == null) return;
    _lastPosition = player.state.position;
    _lastProgressAt = DateTime.now();
    _positionSubscription ??= player.stream.position.listen((position) {
      if (position != _lastPosition) {
        _lastPosition = position;
        _lastProgressAt = DateTime.now();
      }
    });
    _stallTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      final currentPlayer = plPlayerController.videoPlayerController;
      if (currentPlayer == null ||
          !currentPlayer.state.playing ||
          switchingSource.value ||
          _recovering) {
        return;
      }
      if (DateTime.now().difference(_lastProgressAt) >=
          const Duration(seconds: 8)) {
        unawaited(_recoverPlayback('播放进度长时间没有变化'));
      }
    });
    _stablePlaybackTimer?.cancel();
    _stablePlaybackTimer = Timer(const Duration(seconds: 12), () {
      if (plPlayerController.videoPlayerController?.state.playing == true) {
        _recoveryCycles = 0;
      }
    });
  }

  Future<void> _recoverPlayback(String reason) async {
    if (isClosed || playUrls.isEmpty) return;
    if (!shouldRecoverHuyaPlaybackError(reason)) {
      return;
    }
    if (_recovering) {
      _pendingRecoveryReason = reason;
      return;
    }
    _recovering = true;
    _stablePlaybackTimer?.cancel();
    try {
      final nextLine = lineIndex.value + 1;
      if (nextLine < playUrls.length) {
        lineIndex.value = nextLine;
        SmartDialog.showToast('当前线路不可用，切换到线路 ${nextLine + 1}');
        await _openCurrentSource();
        return;
      }
      if (_recoveryCycles < 2) {
        _recoveryCycles++;
        lineIndex.value = 0;
        SmartDialog.showToast('正在刷新虎牙播放地址');
        await _reloadPlaySource(generation: _loadGeneration);
        return;
      }
      error.value = '播放线路连续失败：$reason';
      SmartDialog.showToast('所有播放线路均不可用，请稍后重试');
    } finally {
      _recovering = false;
      final pendingReason = _pendingRecoveryReason;
      _pendingRecoveryReason = null;
      if (pendingReason != null && !isClosed) {
        unawaited(
          Future.delayed(
            const Duration(milliseconds: 250),
            () => _recoverPlayback(pendingReason),
          ),
        );
      }
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
    _positionSubscription?.cancel();
    _stallTimer?.cancel();
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
