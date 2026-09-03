import 'dart:async';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/pages/live/huya/follow/model.dart';
import 'package:PiliPlus/pages/live/huya/follow/service.dart';
import 'package:PiliPlus/pages/live/huya/room/view.dart';
import 'package:PiliPlus/pages/live/huya/route.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_core/simple_live_core.dart';

class HuyaFollowPage extends StatefulWidget {
  const HuyaFollowPage({super.key});

  @override
  State<HuyaFollowPage> createState() => _HuyaFollowPageState();
}

class _HuyaFollowPageState extends State<HuyaFollowPage> {
  final HuyaFollowService _service = HuyaFollowService.instance;
  final Map<String, LiveRoomDetail> _details = {};
  bool _refreshing = false;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    _service.load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing || _service.users.isEmpty) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    final updated = <String, LiveRoomDetail>{};
    var failed = 0;
    final users = _service.users.toList();
    for (var start = 0; start < users.length; start += 4) {
      final end = (start + 4).clamp(0, users.length);
      await Future.wait(
        users.sublist(start, end).map((user) async {
          try {
            final detail = await HuyaLiveRepository.instance.site
                .getRoomDetail(roomId: user.roomId)
                .timeout(const Duration(seconds: 8));
            updated[user.roomId] = detail;
            unawaited(_service.updateDetail(detail));
          } catch (_) {
            failed++;
          }
        }),
      );
    }
    if (!mounted) return;
    setState(() {
      _details.addAll(updated);
      _refreshing = false;
      _refreshError = failed == 0 ? null : '$failed 个关注状态刷新失败';
    });
  }

  Future<void> _remove(HuyaFollowUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消关注'),
        content: Text('确定取消关注 ${user.userName}？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消关注'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.remove(user.roomId);
    _details.remove(user.roomId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关注用户'),
        actions: [
          IconButton(
            tooltip: '刷新开播状态',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        if (_service.users.isEmpty) {
          return const _EmptyFollowState();
        }
        final users = _service.users.toList()
          ..sort((a, b) {
            final aLive = _details[a.roomId]?.status == true;
            final bLive = _details[b.roomId]?.status == true;
            if (aLive != bLive) return aLive ? -1 : 1;
            return b.addTime.compareTo(a.addTime);
          });
        return RefreshIndicator.adaptive(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              Style.safeSpace,
              8,
              Style.safeSpace,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: users.length + (_refreshError == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == users.length) {
                return _RefreshError(message: _refreshError!);
              }
              final user = users[index];
              return _FollowUserItem(
                user: user,
                detail: _details[user.roomId],
                onOpen: () => openHuyaPage(
                  context,
                  (_) => HuyaLiveRoomPage(roomId: user.roomId),
                  showGlobalBackButton: true,
                ),
                onRemove: () => _remove(user),
              );
            },
          ),
        );
      }),
    );
  }
}

class _FollowUserItem extends StatelessWidget {
  const _FollowUserItem({
    required this.user,
    required this.detail,
    required this.onOpen,
    required this.onRemove,
  });

  final HuyaFollowUser user;
  final LiveRoomDetail? detail;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = detail?.status == true;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: Style.mdRadius,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        leading: NetworkImgLayer(
          src: detail?.userAvatar ?? user.face,
          width: 48,
          height: 48,
          borderRadius: const BorderRadius.all(Radius.circular(24)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                detail?.userName ?? user.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _LiveStatus(isLive: isLive, loaded: detail != null),
          ],
        ),
        subtitle: Text(
          detail?.title ?? user.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: '取消关注',
          onPressed: onRemove,
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.isLive, required this.loaded});

  final bool isLive;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isLive
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Text(
        !loaded
            ? '未刷新'
            : isLive
            ? '直播中'
            : '未开播',
        style: TextStyle(
          color: isLive
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _RefreshError extends StatelessWidget {
  const _RefreshError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _EmptyFollowState extends StatelessWidget {
  const _EmptyFollowState();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border, size: 56, color: color),
            const SizedBox(height: 16),
            Text('还没有关注的虎牙主播', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '进入直播间后，点击右上角的关注按钮即可添加。',
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
