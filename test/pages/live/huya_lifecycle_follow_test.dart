import 'dart:io';

import 'package:PiliPlus/pages/live/huya/follow/service.dart';
import 'package:PiliPlus/pages/live/huya/room/controller.dart';
import 'package:PiliPlus/pages/live/huya/route.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final storageDir = await Directory.systemTemp.createTemp(
      'pilinara_huya_test_',
    );
    appSupportDirPath = storageDir.path;
    await GStorage.init();
  });

  test('虎牙播放器日志保留定位信息但不泄露鉴权参数', () {
    final log = buildHuyaPlaybackSignalLog(
      roomId: '518518',
      lineIndex: 1,
      lineCount: 3,
      source: 'https://al.flv.huya.com/live.flv?wsSecret=secret',
      reason: 'tcp: ffurl_read returned 403',
    );

    expect(log, contains('room=518518'));
    expect(log, contains('line=2/3'));
    expect(log, contains('host=al.flv.huya.com'));
    expect(log, contains('tcp: ffurl_read returned 403'));
    expect(log, isNot(contains('wsSecret')));
    expect(log, isNot(contains('secret')));
  });

  test('虎牙默认画质取中间档，与上游一致', () {
    expect(resolveHuyaDefaultQualityIndex(0), 0);
    expect(resolveHuyaDefaultQualityIndex(1), 0);
    expect(resolveHuyaDefaultQualityIndex(2), 1);
    expect(resolveHuyaDefaultQualityIndex(4), 2);
    expect(resolveHuyaDefaultQualityIndex(5), 2);
  });

  test('虎牙播放信号按上游规则分层处理', () {
    expect(
      classifyHuyaPlaybackSignal(
        'Could not open/initialize audio device -> no sound.',
      ),
      HuyaPlaybackSignalKind.ignore,
    );
    expect(
      classifyHuyaPlaybackSignal('h264: Invalid NAL unit size'),
      HuyaPlaybackSignalKind.restartDecoder,
    );
    expect(
      classifyHuyaPlaybackSignal('tls: mbedtls_ssl_read returned -0x7880'),
      HuyaPlaybackSignalKind.restartDecoder,
    );
    expect(
      classifyHuyaPlaybackSignal(
        'http: Stream ends prematurely at 780283, '
        'should be 18446744073709551615',
      ),
      HuyaPlaybackSignalKind.reopen,
    );
    expect(
      classifyHuyaPlaybackSignal('end of file'),
      HuyaPlaybackSignalKind.reopen,
    );
  });

  test('虎牙播放恢复沿用上游的重试、切线与回绕策略', () {
    expect(
      resolveHuyaPlaybackRecoveryAction(
        retryCount: 0,
        lineIndex: 0,
        lineCount: 3,
      ),
      HuyaPlaybackRecoveryAction.refreshCurrentLine,
    );
    expect(
      resolveHuyaPlaybackRecoveryAction(
        retryCount: 1,
        lineIndex: 0,
        lineCount: 3,
      ),
      HuyaPlaybackRecoveryAction.refreshCurrentLine,
    );
    expect(
      resolveHuyaPlaybackRecoveryAction(
        retryCount: 2,
        lineIndex: 0,
        lineCount: 3,
      ),
      HuyaPlaybackRecoveryAction.switchLine,
    );
    // 最后一条线路也失败时回绕到线路 1，不再终止播放。
    expect(
      resolveHuyaPlaybackRecoveryAction(
        retryCount: 2,
        lineIndex: 2,
        lineCount: 3,
      ),
      HuyaPlaybackRecoveryAction.restartFromFirstLine,
    );
  });

  test('虎牙关注用户会保存到本地并支持取消', () async {
    final service = HuyaFollowService.instance..load();
    final detail = LiveRoomDetail(
      roomId: '518518',
      title: '测试直播间',
      cover: 'https://example.com/cover.jpg',
      userName: '测试主播',
      userAvatar: 'https://example.com/avatar.jpg',
      online: 100,
      status: true,
      url: 'https://www.huya.com/518518',
    );

    expect(await service.toggle(detail), isTrue);
    expect(service.contains(detail.roomId), isTrue);
    expect(GStorage.localCache.get('huyaFollowUsers'), isNotEmpty);

    await service.remove(detail.roomId);

    expect(service.contains(detail.roomId), isFalse);
  });

  test('虎牙直播间路由显示悬浮返回按钮', () {
    final regularRoute = HuyaPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
    );
    final roomRoute = HuyaPageRoute<void>(
      builder: (_) => const SizedBox.shrink(),
      showGlobalBackButton: true,
    );

    expect(regularRoute.showGlobalBackButton, isFalse);
    expect(roomRoute.showGlobalBackButton, isTrue);
  });
}
