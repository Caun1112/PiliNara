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

/// 播放器信号的处理层级，与上游 simple_live 的两层恢复保持一致。
enum HuyaPlaybackSignalKind {
  /// 与画面无关，直接忽略。
  ignore,

  /// 解码/传输抖动，原地重启解码器即可。
  restartDecoder,

  /// 连接已不可用，需要换新的签名地址重开。
  reopen,
}

const List<String> _decoderJitterSignals = [
  'mbedtls_ssl_read',
  'Packet corrupt',
  'Packet corupt',
  'tls:',
  'Invalid NAL unit',
  'missing picture',
];

HuyaPlaybackSignalKind classifyHuyaPlaybackSignal(String reason) {
  if (reason.contains('no sound.') || reason.contains('audio device')) {
    return HuyaPlaybackSignalKind.ignore;
  }
  for (final signal in _decoderJitterSignals) {
    if (reason.contains(signal)) {
      return HuyaPlaybackSignalKind.restartDecoder;
    }
  }
  return HuyaPlaybackSignalKind.reopen;
}

enum HuyaPlaybackRecoveryAction {
  /// 同线路重新获取签名地址后重开。
  refreshCurrentLine,

  /// 换到下一条线路。
  switchLine,

  /// 已是最后一条线路，回绕到第一条重新开始。
  restartFromFirstLine,
}

/// 默认画质与上游一致，取中间档而非最高档：
/// 虎牙最高画质可达 8~12 Mbps，移动网络上很难稳定拉满。
int resolveHuyaDefaultQualityIndex(int qualityCount) {
  if (qualityCount <= 1) return 0;
  return qualityCount ~/ 2;
}

HuyaPlaybackRecoveryAction resolveHuyaPlaybackRecoveryAction({
  required int retryCount,
  required int lineIndex,
  required int lineCount,
}) {
  if (retryCount < 2) {
    return HuyaPlaybackRecoveryAction.refreshCurrentLine;
  }
  if (lineIndex + 1 < lineCount) {
    return HuyaPlaybackRecoveryAction.switchLine;
  }
  return HuyaPlaybackRecoveryAction.restartFromFirstLine;
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
  DateTime? _lastPlaybackLogAt;
  int _mediaErrorRetryCount = 0;
  int _decoderRestartCount = 0;
  bool _recoveringPlayback = false;
  Timer? _stablePlaybackTimer;
  Timer? _recoveryRetryTimer;

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
      qualityIndex.value = resolveHuyaDefaultQualityIndex(result.length);
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

  Future<void> _reloadPlaySource({
    required int generation,
    bool silent = false,
  }) async {
    final roomDetail = detail.value;
    if (roomDetail == null || qualities.isEmpty) return;
    if (!silent) {
      switchingSource.value = true;
    }
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
      await _openCurrentSource(silent: silent);
    } catch (exception) {
      // 静默恢复失败交给调用方安排下一次重试，不打断当前画面。
      if (silent) rethrow;
      if (_isCurrent(generation)) {
        error.value = _readableError(exception);
      }
    } finally {
      if (!silent && _isCurrent(generation)) {
        switchingSource.value = false;
      }
    }
  }

  Future<void> _openCurrentSource({bool silent = false}) async {
    if (playUrls.isEmpty || lineIndex.value >= playUrls.length) return;
    error.value = null;
    if (!silent) {
      switchingSource.value = true;
    }
    try {
      final source = NetworkSource(
        videoSource: playUrls[lineIndex.value],
        audioSource: null,
        httpHeaders: _playHeaders,
      );
      final reopened = await plPlayerController.reopenLiveSource(source);
      if (!reopened) {
        await plPlayerController.setDataSource(
          source,
          isLive: true,
          autoplay: true,
          roomId: int.tryParse(roomId),
        );
      }
      PlPlayerController.setPlayCallBack(plPlayerController.play);
      _markPlaybackOpened();
    } finally {
      if (!silent) {
        switchingSource.value = false;
      }
    }
  }

  void _markPlaybackOpened() {
    _stablePlaybackTimer?.cancel();
    // 稳定播放一段时间后重置重试预算，等价于上游“播放成功即清零”。
    _stablePlaybackTimer = Timer(const Duration(seconds: 10), () {
      if (plPlayerController.videoPlayerController?.state.playing == true) {
        _mediaErrorRetryCount = 0;
        _decoderRestartCount = 0;
      }
    });
  }

  Future<void> _recordPlaybackSignal(String reason) async {
    if (isClosed) return;
    final kind = classifyHuyaPlaybackSignal(reason);
    if (kind == HuyaPlaybackSignalKind.ignore) return;

    final now = DateTime.now();
    if (_lastPlaybackSignalAt != null &&
        now.difference(_lastPlaybackSignalAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastPlaybackSignalAt = now;
    _logPlaybackSignal(now, reason);

    if (kind == HuyaPlaybackSignalKind.restartDecoder &&
        _decoderRestartCount < 3) {
      _decoderRestartCount++;
      unawaited(_restartDecoder());
      return;
    }
    unawaited(_recoverPlayback(reason));
  }

  void _logPlaybackSignal(DateTime now, String reason) {
    if (_lastPlaybackLogAt != null &&
        now.difference(_lastPlaybackLogAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastPlaybackLogAt = now;
    final source = lineIndex.value >= 0 && lineIndex.value < playUrls.length
        ? playUrls[lineIndex.value]
        : null;
    logger.e(
      '虎牙播放器报告异常信号，开始恢复',
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

  /// 传输抖动：沿用上游做法，暂停后重开同一地址，只重启解码器。
  Future<void> _restartDecoder() async {
    if (_recoveringPlayback || isClosed) return;
    _recoveringPlayback = true;
    _stablePlaybackTimer?.cancel();
    try {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (isClosed) return;
      await plPlayerController.pause();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (isClosed) return;
      await _openCurrentSource(silent: true);
    } catch (exception, stackTrace) {
      logger.e('虎牙解码器重启失败', error: '$exception', stackTrace: stackTrace);
      _scheduleRecovery('解码器重启失败');
    } finally {
      _recoveringPlayback = false;
    }
  }

  Future<void> _recoverPlayback(String reason) async {
    if (_recoveringPlayback || isClosed || playUrls.isEmpty) return;
    _recoveringPlayback = true;
    _recoveryRetryTimer?.cancel();
    _stablePlaybackTimer?.cancel();
    try {
      final action = resolveHuyaPlaybackRecoveryAction(
        retryCount: _mediaErrorRetryCount,
        lineIndex: lineIndex.value,
        lineCount: playUrls.length,
      );
      switch (action) {
        case HuyaPlaybackRecoveryAction.refreshCurrentLine:
          if (_mediaErrorRetryCount == 1) {
            await Future<void>.delayed(const Duration(seconds: 1));
            if (isClosed) return;
          }
          _mediaErrorRetryCount++;
          // 虎牙签名地址断开后不可复用，必须重新取一份。
          await _reloadPlaySource(generation: _loadGeneration, silent: true);
        case HuyaPlaybackRecoveryAction.switchLine:
          _mediaErrorRetryCount = 0;
          _decoderRestartCount = 0;
          lineIndex.value++;
          await _openCurrentSource(silent: true);
        case HuyaPlaybackRecoveryAction.restartFromFirstLine:
          _mediaErrorRetryCount = 0;
          _decoderRestartCount = 0;
          lineIndex.value = 0;
          await Future<void>.delayed(const Duration(seconds: 2));
          if (isClosed) return;
          if (!await _ensureStillLive()) return;
          await _reloadPlaySource(generation: _loadGeneration, silent: true);
      }
    } catch (exception, stackTrace) {
      logger.e(
        '虎牙播放恢复失败',
        error: '$reason; $exception',
        stackTrace: stackTrace,
      );
      _scheduleRecovery(reason);
    } finally {
      _recoveringPlayback = false;
    }
  }

  void _scheduleRecovery(String reason) {
    _recoveryRetryTimer?.cancel();
    _recoveryRetryTimer = Timer(const Duration(seconds: 3), () {
      if (isClosed) return;
      unawaited(_recoverPlayback(reason));
    });
  }

  /// 线路全部轮完后确认是否仍在直播，避免下播后无限重试。
  Future<bool> _ensureStillLive() async {
    try {
      final roomDetail = await site.getRoomDetail(roomId: roomId);
      if (isClosed) return false;
      if (!roomDetail.status) {
        error.value = '主播已下播';
        return false;
      }
      detail.value = roomDetail;
      return true;
    } catch (_) {
      return true;
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
    _recoveryRetryTimer?.cancel();
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
