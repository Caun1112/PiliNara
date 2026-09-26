import 'package:PiliPlus/pages/live/bilibili/follow/service.dart';
import 'package:PiliPlus/pages/live/bilibili/follow/view.dart';
import 'package:PiliPlus/pages/live_area/view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class BiliLiveQuickActions extends StatelessWidget {
  const BiliLiveQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final service = BiliFollowService.instance..load();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'bili-category-action',
          tooltip: 'B站直播分类',
          onPressed: () => Get.to(() => const LiveAreaPage()),
          child: const Icon(Icons.widgets_outlined),
        ),
        const SizedBox(height: 12),
        Obx(
          () => Badge(
            isLabelVisible: service.rooms.isNotEmpty,
            label: Text(
              service.rooms.length > 99 ? '99+' : '${service.rooms.length}',
            ),
            child: FloatingActionButton(
              heroTag: 'bili-local-follow-action',
              tooltip: 'B站本地关注',
              onPressed: () => Get.to(() => const BiliFollowPage()),
              child: const Icon(Icons.favorite_border),
            ),
          ),
        ),
      ],
    );
  }
}
