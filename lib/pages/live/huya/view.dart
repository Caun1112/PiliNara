import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/live/huya/category/view.dart';
import 'package:PiliPlus/pages/live/huya/follow/service.dart';
import 'package:PiliPlus/pages/live/huya/follow/view.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/pages/live/huya/route.dart';
import 'package:PiliPlus/pages/live/huya/search/view.dart';
import 'package:PiliPlus/pages/live/huya/widgets/paged_room_grid.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HuyaLivePage extends StatelessWidget {
  const HuyaLivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = HuyaLiveRepository.instance;
    return Container(
      clipBehavior: Clip.hardEdge,
      margin: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Text('推荐直播', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: '搜索虎牙直播',
                  onPressed: () => openHuyaPage(
                    context,
                    (_) => const HuyaSearchPage(),
                  ),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: HuyaPagedRoomGrid(
                    loadPage: repository.getRecommendations,
                    bottomPadding:
                        300 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 160 + MediaQuery.viewPaddingOf(context).bottom,
                  child: const _HuyaQuickActions(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HuyaQuickActions extends StatelessWidget {
  const _HuyaQuickActions();

  @override
  Widget build(BuildContext context) {
    final followService = HuyaFollowService.instance..load();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'huya-category-action',
          tooltip: '虎牙分类',
          onPressed: () =>
              openHuyaPage(context, (_) => const HuyaCategoryPage()),
          child: const Icon(Icons.widgets_outlined),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final count = followService.users.length;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              FloatingActionButton(
                heroTag: 'huya-follow-action',
                tooltip: '关注用户',
                onPressed: () =>
                    openHuyaPage(context, (_) => const HuyaFollowPage()),
                child: const Icon(Icons.favorite_border),
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: const BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}
