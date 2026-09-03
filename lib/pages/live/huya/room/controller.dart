import 'dart:async';

import 'package:PiliPlus/pages/danmaku/danmaku_model.dart' show DanmakuExtra;
import 'package:PiliPlus/pages/live/huya/follow/service.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/services/logger.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_core/simple_live_core.dart';

String buildHuyaPlaybackSignalLog({
  required String roomId,
  required int lineIndex,
  required int lineCount,
  required String? source,
  required String reason,
}) {
  final host = source == null ? '' : Uri.tryParse(source)?.host ?? '';
  return 'room=$roomId, line=${lineIndex + 1}/$lineCount, '
      'host=${host.isEmpty ? 'unknown' : host}, signal=$reason';
}

String normalizeHuyaPlaybackUrl(String source) {
  if (source.toLowerCase().startsWith('http://')) {
    return 'https://${source.substring('http://'.length)}';
  }
  return source;
}

bool shouldRecoverHuyaPlayback({
  required bool completed,
  required bool playing,
  required Duration positionBefore,
  required Duration positionAfter,
}) {
  if (completed || !playing) return true;
  return positionAfter <= positionBefore + const Duration(milliseconds: 250);
}

class HuyaLiveRoomController extends GetxController {
  HuyaLiveRoomController({required this.roomId, HuyaSite? site})
    : site = site ?? HuyaLiveRepository.instance.site {
    plPlayerController
      ..livePlaybackErrorHandler = _recordPlaybackSignal
      ..livePlaybackEndedHandler = () => _recordPlaybackSignal('end of file');
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
  DateTime? _lastPlaybackSignalAt;
  Timer? _recoveryCheckTimer;
  bool _recoveringPlayback = false;

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
    _cancelPlaybackRecoveryCheck();
    await _reloadPlaySource(generation: _loadGeneration);
  }

  Future<void> changeQuality(int index) async {
    if (index < 0 || index >= qualities.length || index == qualityIndex.value) {
      return;
    }
    _cancelPlaybackRecoveryCheck();
    qualityIndex.value = index;
    lineIndex.value = 0;
    await _reloadPlaySource(generation: _loadGeneration);
  }

  Future<void> changeLine(int index) async {
    if (index < 0 || index >= playUrls.length || index == lineIndex.value) {
      return;
    }
    _cancelPlaybackRecoveryCheck();
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
      playUrls.assignAll(playUrl.urls.map(normalizeHuyaPlaybackUrl));
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
    } finally {
      switchingSource.value = false;
    }
  }

  Future<void> _recordPlaybackSignal(String reason) async {
    if (isClosed) return;
    _schedulePlaybackRecoveryCheck(reason);
    final now = DateTime.now();
    if (_lastPlaybackSignalAt != null &&
        now.difference(_lastPlaybackSignalAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastPlaybackSignalAt = now;
    final source = lineIndex.value >= 0 && lineIndex.value < playUrls.length
        ? playUrls[lineIndex.value]
        : null;
    logger.e(
      '虎牙播放器报告异常信号；等待确认播放是否停止',
      error: buildHuyaPlaybackSignalLog(
        roomId: roomId,
        lineIndex: lineIndex.value,
        lineCount: playUrls.length,
        source: source,
        reason: reason,
      ),
      stackTrace: StackTrace.current,
    );
  }

  void _schedulePlaybackRecoveryCheck(String reason) {
    if (_recoveryCheckTimer != null || _recoveringPlayback) return;
    final player = plPlayerController.videoPlayerController;
    if (player == null) return;
    final positionBefore = player.state.position;
    _recoveryCheckTimer = Timer(const Duration(seconds: 3), () {
      _recoveryCheckTimer = null;
      final currentPlayer = plPlayerController.videoPlayerController;
      if (isClosed ||
          switchingSource.value ||
          !identical(player, currentPlayer)) {
        return;
      }
      final state = player.state;
      if (!shouldRecoverHuyaPlayback(
        completed: state.completed,
        playing: state.playing,
        positionBefore: positionBefore,
        positionAfter: state.position,
      )) {
        return;
      }
      unawaited(_recoverStalledPlayback(reason));
    });
  }

  Future<void> _recoverStalledPlayback(String reason) async {
    if (_recoveringPlayback || isClosed || playUrls.isEmpty) return;
    _recoveringPlayback = true;
    try {
      final nextLine = lineIndex.value + 1;
      if (nextLine < playUrls.length) {
        lineIndex.value = nextLine;
        await _openCurrentSource();
        return;
      }
      lineIndex.value = 0;
      await _reloadPlaySource(generation: _loadGeneration);
    } catch (exception, stackTrace) {
      logger.e(
        '虎牙播放恢复失败',
        error: '$reason; $exception',
        stackTrace: stackTrace,
      );
    } finally {
      _recoveringPlayback = false;
    }
  }

  void _cancelPlaybackRecoveryCheck() {
    _recoveryCheckTimer?.cancel();
    _recoveryCheckTimer = null;
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
    _cancelPlaybackRecoveryCheck();
    _liveDanmaku?.stop();
    _liveDanmaku = null;
    danmakuController?.clear();
    danmakuController = null;
    chatScrollController.dispose();
    PlPlayerController.setPlayCallBack(null);
    plPlayerController.livePlaybackErrorHandler = null;
    plPlayerController.livePlaybackEndedHandler = null;
    plPlayerController.dispose();
    super.onClose();
  }
}
