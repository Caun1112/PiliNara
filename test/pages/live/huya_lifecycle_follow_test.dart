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

  test('虎牙播放地址使用 HTTPS 且不改写鉴权参数', () {
    const source =
        'http://al.flv.huya.com/live.flv?wsSecret=abc%2B123&ratio=2000';

    expect(
      normalizeHuyaPlaybackUrl(source),
      'https://al.flv.huya.com/live.flv?wsSecret=abc%2B123&ratio=2000',
    );
  });

  test('虎牙播放恢复沿用上游的同线路重试后切线策略', () {
    expect(
      resolveHuyaPlaybackRecoveryAction(
        retryCount: 0,
        lineIndex: 0,
        lineCount: 3,
      ),
      HuyaPlaybackRecoveryAction.retryCurrentLine,
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
    expect(
      resolveHuyaPlaybackRecoveryAction(
        retryCount: 2,
        lineIndex: 2,
        lineCount: 3,
      ),
      HuyaPlaybackRecoveryAction.fail,
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
