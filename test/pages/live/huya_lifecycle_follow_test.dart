import 'dart:io';

import 'package:PiliPlus/pages/live/huya/follow/service.dart';
import 'package:PiliPlus/pages/live/huya/room/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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

  test('虎牙直播可忽略 LiveContainer 的场景隐藏误报', () {
    final player = PlPlayerController.getInstance(isLive: true);
    player.continuePlayInBackground.value = false;

    expect(
      player.shouldAutoPauseForLifecycle(AppLifecycleState.paused),
      isTrue,
    );

    player.ignoreAppLifecyclePause = true;

    expect(
      player.shouldAutoPauseForLifecycle(AppLifecycleState.paused),
      isFalse,
    );
    expect(
      player.shouldAutoPauseForLifecycle(AppLifecycleState.detached),
      isFalse,
    );
  });

  test('虎牙线路错误会触发恢复，但音频设备告警不会误切线', () {
    expect(
      shouldRecoverHuyaPlaybackError(
        'Failed to open http://al.flv.huya.com/live.flv',
      ),
      isTrue,
    );
    expect(
      shouldRecoverHuyaPlaybackError('tcp: ffurl_read returned 403'),
      isTrue,
    );
    expect(
      shouldRecoverHuyaPlaybackError(
        'Could not open/initialize audio device -> no sound.',
      ),
      isFalse,
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
}
