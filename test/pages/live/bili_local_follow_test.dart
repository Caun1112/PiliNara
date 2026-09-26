import 'dart:io';

import 'package:PiliPlus/models_new/live/live_room_info_h5/data.dart';
import 'package:PiliPlus/pages/live/bilibili/follow/service.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    appSupportDirPath = (await Directory.systemTemp.createTemp(
      'bili_follow_test_',
    )).path;
    await GStorage.init();
  });

  setUp(() => GStorage.localCache.delete(LocalCacheKey.biliFollowRooms));

  RoomInfoH5Data detail({String title = '测试直播间', int status = 0}) =>
      RoomInfoH5Data.fromJson({
        'room_info': {
          'room_id': 123456,
          'uid': 999,
          'title': title,
          'live_status': status,
        },
        'anchor_info': {
          'base_info': {'uname': '测试主播', 'face': ''},
        },
      });

  test('无需登录即可本地关注，短房间号归一化且重启后保留', () async {
    final service = BiliFollowService();
    expect(await service.toggle(12, detail()), isTrue);
    expect(service.contains(123456), isTrue);
    expect(service.rooms.single.roomId, 123456);
    final restored = BiliFollowService()..load();
    expect(restored.rooms.single.userName, '测试主播');
    expect(restored.contains(123456), isTrue);
    expect(await restored.toggle(12, detail()), isFalse);
    expect((BiliFollowService()..load()).rooms, isEmpty);
  });

  test('刷新资料保留关注时间，已取消的房间不会被异步刷新重新加入', () async {
    final service = BiliFollowService();
    await service.toggle(123456, detail());
    final time = service.rooms.single.addTime;
    await service.updateDetail(123456, detail(title: '新标题', status: 1));
    expect(service.rooms.single.title, '新标题');
    expect(service.rooms.single.addTime, time);
    await service.remove(123456);
    await service.updateDetail(123456, detail());
    expect((BiliFollowService()..load()).rooms, isEmpty);
  });
}
