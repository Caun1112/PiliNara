import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/live/huya/category/view.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/pages/live/huya/route.dart';
import 'package:PiliPlus/pages/live/huya/search/view.dart';
import 'package:PiliPlus/pages/live/huya/widgets/paged_room_grid.dart';
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
                TextButton.icon(
                  onPressed: () => openHuyaPage(
                    context,
                    (_) => const HuyaCategoryPage(),
                  ),
                  icon: const Icon(Icons.widgets_outlined, size: 18),
                  label: const Text('分类'),
                ),
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
            child: HuyaPagedRoomGrid(loadPage: repository.getRecommendations),
          ),
        ],
      ),
    );
  }
}
