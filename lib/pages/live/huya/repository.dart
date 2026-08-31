import 'package:simple_live_core/simple_live_core.dart';

class HuyaRoomPageData {
  const HuyaRoomPageData({required this.items, required this.hasMore});

  final List<LiveRoomItem> items;
  final bool hasMore;
}

class HuyaLiveRepository {
  HuyaLiveRepository({HuyaSite? site}) : site = site ?? HuyaSite() {
    CoreLog.enableLog = false;
  }

  static final instance = HuyaLiveRepository();

  final HuyaSite site;

  Future<HuyaRoomPageData> getRecommendations(int page) async {
    final result = await site.getRecommendRooms(page: page);
    return HuyaRoomPageData(items: result.items, hasMore: result.hasMore);
  }

  Future<HuyaRoomPageData> getCategoryRooms(
    LiveSubCategory category,
    int page,
  ) async {
    final result = await site.getCategoryRooms(category, page: page);
    return HuyaRoomPageData(items: result.items, hasMore: result.hasMore);
  }

  Future<HuyaRoomPageData> searchRooms(String keyword, int page) async {
    final result = await site.searchRooms(keyword, page: page);
    return HuyaRoomPageData(items: result.items, hasMore: result.hasMore);
  }

  Future<List<LiveCategory>> getCategories() => site.getCategores();
}
