import 'package:PiliPlus/models_new/live/live_room_info_h5/data.dart';
import 'package:PiliPlus/pages/live/bilibili/follow/model.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:get/get.dart';

/// 只收藏直播间，不读取或修改 B 站账号的关注关系。
class BiliFollowService {
  BiliFollowService();
  static final instance = BiliFollowService();

  final RxList<BiliFollowRoom> rooms = <BiliFollowRoom>[].obs;
  bool _loaded = false;

  void load() {
    if (_loaded) return;
    _loaded = true;
    final raw = GStorage.localCache.get(LocalCacheKey.biliFollowRooms);
    if (raw is! List) return;
    rooms.assignAll(
      raw
          .whereType<Map>()
          .map(BiliFollowRoom.fromJson)
          .where((room) => room.roomId > 0),
    );
    rooms.sort((a, b) => b.addTime.compareTo(a.addTime));
  }

  bool contains(int roomId) {
    load();
    return rooms.any((room) => room.roomId == roomId);
  }

  Future<bool> toggle(int roomId, RoomInfoH5Data detail) async {
    load();
    final canonicalId = detail.roomInfo?.roomId ?? roomId;
    if (contains(canonicalId)) {
      await remove(canonicalId);
      return false;
    }
    if (canonicalId <= 0) return false;
    rooms.insert(0, BiliFollowRoom.fromDetail(canonicalId, detail));
    await _persist();
    return true;
  }

  Future<void> remove(int roomId) async {
    load();
    rooms.removeWhere((room) => room.roomId == roomId);
    await _persist();
  }

  Future<void> updateDetail(int roomId, RoomInfoH5Data detail) async {
    load();
    final index = rooms.indexWhere((room) => room.roomId == roomId);
    if (index < 0) return;
    rooms[index] = BiliFollowRoom.fromDetail(
      roomId,
      detail,
      addTime: rooms[index].addTime,
    );
    await _persist();
  }

  Future<void> _persist() => GStorage.localCache.put(
    LocalCacheKey.biliFollowRooms,
    rooms.map((room) => room.toJson()).toList(),
  );
}
