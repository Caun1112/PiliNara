import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _FakeHuyaSite extends HuyaSite {
  int? recommendationPage;
  int? categoryPage;
  int? searchPage;
  String? searchKeyword;

  final room = LiveRoomItem(
    roomId: '123',
    title: '测试直播间',
    cover: 'https://example.com/cover.jpg',
    userName: '测试主播',
    online: 42,
  );

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    recommendationPage = page;
    return LiveCategoryResult(items: [room], hasMore: true);
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    categoryPage = page;
    return LiveCategoryResult(items: [room], hasMore: false);
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    searchKeyword = keyword;
    searchPage = page;
    return LiveSearchRoomResult(items: [room], hasMore: false);
  }
}

void main() {
  test('虎牙仓库转发分页参数并统一列表结果', () async {
    final site = _FakeHuyaSite();
    final repository = HuyaLiveRepository(site: site);
    final category = LiveSubCategory(
      id: '1',
      name: '英雄联盟',
      parentId: '网游',
    );

    final recommendations = await repository.getRecommendations(2);
    final categoryRooms = await repository.getCategoryRooms(category, 3);
    final searchRooms = await repository.searchRooms('测试', 4);

    expect(site.recommendationPage, 2);
    expect(site.categoryPage, 3);
    expect(site.searchKeyword, '测试');
    expect(site.searchPage, 4);
    expect(recommendations.items.single.roomId, '123');
    expect(recommendations.hasMore, isTrue);
    expect(categoryRooms.hasMore, isFalse);
    expect(searchRooms.items.single.userName, '测试主播');
  });

  test('网络播放源保留虎牙请求头', () {
    final source = NetworkSource(
      videoSource: 'https://example.com/live.flv',
      audioSource: null,
      httpHeaders: const {'user-agent': 'HYSDK'},
    );

    expect(source.httpHeaders, const {'user-agent': 'HYSDK'});
  });
}
