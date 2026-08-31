import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/pages/live/huya/widgets/paged_room_grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_core/simple_live_core.dart';

class HuyaCategoryRoomsPage extends StatelessWidget {
  const HuyaCategoryRoomsPage({super.key, required this.category});

  final LiveSubCategory category;

  @override
  Widget build(BuildContext context) {
    final repository = HuyaLiveRepository.instance;
    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
        child: HuyaPagedRoomGrid(
          loadPage: (page) => repository.getCategoryRooms(category, page),
          emptyMessage: '该分类暂时没有正在直播的房间',
        ),
      ),
    );
  }
}
