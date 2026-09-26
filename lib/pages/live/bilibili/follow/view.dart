import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/live/bilibili/follow/service.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class BiliFollowPage extends StatefulWidget {
  const BiliFollowPage({super.key});

  @override
  State<BiliFollowPage> createState() => _BiliFollowPageState();
}

class _BiliFollowPageState extends State<BiliFollowPage> {
  final _service = BiliFollowService.instance;
  final Map<int, int?> _statuses = {};
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.load();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    final rooms = _service.rooms.toList();
    var failed = 0;
    final statuses = <int, int?>{};
    for (var start = 0; start < rooms.length; start += 4) {
      await Future.wait(
        rooms.sublist(start, (start + 4).clamp(0, rooms.length)).map((
          room,
        ) async {
          try {
            final result = await LiveHttp.liveRoomInfoH5(roomId: room.roomId)
                .timeout(const Duration(seconds: 8));
            if (result case Success(:final response)) {
              statuses[room.roomId] = response.roomInfo?.liveStatus;
              await _service.updateDetail(room.roomId, response);
            } else {
              failed++;
            }
          } catch (_) {
            failed++;
          }
        }),
      );
    }
    if (!mounted) return;
    setState(() {
      _statuses
        ..clear()
        ..addAll(statuses);
      _refreshing = false;
      _error = failed == 0 ? null : '$failed 个直播间刷新失败，仍可点击进入';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('B站本地关注'),
      actions: [
        IconButton(
          tooltip: '刷新直播间',
          onPressed: _refreshing ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('仅保存在本机，不会关注 B 站账号。进入直播间点击爱心即可添加。'),
        ),
        if (_refreshing) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!),
          ),
        Expanded(
          child: Obx(() {
            final rooms = _service.rooms.toList()
              ..sort((a, b) {
                final aLive = _statuses[a.roomId] == 1;
                final bLive = _statuses[b.roomId] == 1;
                return aLive != bLive
                    ? (aLive ? -1 : 1)
                    : b.addTime.compareTo(a.addTime);
              });
            if (rooms.isEmpty) {
              return const Center(child: Text('还没有本地关注的直播间'));
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final room = rooms[index];
                  final status = switch (_statuses[room.roomId]) {
                    1 => '直播中',
                    0 => '未开播',
                    2 => '轮播中',
                    _ => '状态待更新',
                  };
                  return ListTile(
                    leading: room.face.isEmpty
                        ? const CircleAvatar(child: Icon(Icons.live_tv))
                        : NetworkImgLayer(
                            src: room.face,
                            width: 44,
                            height: 44,
                            type: .avatar,
                          ),
                    title: Text(room.userName),
                    subtitle: Text(
                      '$status · ${room.title}\n房间号 ${room.roomId}',
                    ),
                    isThreeLine: true,
                    onTap: () => PageUtils.toLiveRoom(room.roomId),
                    trailing: IconButton(
                      tooltip: '取消本地关注',
                      icon: const Icon(Icons.favorite),
                      onPressed: () => _service.remove(room.roomId),
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ],
    ),
  );
}
