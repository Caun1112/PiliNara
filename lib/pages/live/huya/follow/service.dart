import 'package:PiliPlus/pages/live/huya/follow/model.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';

class HuyaFollowService {
  HuyaFollowService._();

  static final instance = HuyaFollowService._();

  final RxList<HuyaFollowUser> users = <HuyaFollowUser>[].obs;
  bool _loaded = false;

  void load() {
    if (_loaded) return;
    _loaded = true;
    final raw = GStorage.localCache.get(LocalCacheKey.huyaFollowUsers);
    if (raw is! List) return;
    users.assignAll(
      raw
          .whereType<Map>()
          .map(HuyaFollowUser.fromJson)
          .where((item) => item.roomId.isNotEmpty),
    );
    _sort();
  }

  bool contains(String roomId) {
    load();
    return users.any((item) => item.roomId == roomId);
  }

  Future<bool> toggle(LiveRoomDetail detail) async {
    load();
    final index = users.indexWhere((item) => item.roomId == detail.roomId);
    if (index >= 0) {
      users.removeAt(index);
      await _persist();
      return false;
    }
    users.add(HuyaFollowUser.fromDetail(detail));
    _sort();
    await _persist();
    return true;
  }

  Future<void> remove(String roomId) async {
    load();
    users.removeWhere((item) => item.roomId == roomId);
    await _persist();
  }

  Future<void> updateDetail(LiveRoomDetail detail) async {
    load();
    final index = users.indexWhere((item) => item.roomId == detail.roomId);
    if (index < 0) return;
    users[index] = users[index].updateFromDetail(detail);
    await _persist();
  }

  void _sort() {
    users.sort((a, b) => b.addTime.compareTo(a.addTime));
  }

  Future<void> _persist() {
    return GStorage.localCache.put(
      LocalCacheKey.huyaFollowUsers,
      users.map((item) => item.toJson()).toList(),
    );
  }
}
