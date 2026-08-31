import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/pages/live/huya/widgets/paged_room_grid.dart';
import 'package:material_ui/material_ui.dart';

class HuyaSearchPage extends StatefulWidget {
  const HuyaSearchPage({super.key});

  @override
  State<HuyaSearchPage> createState() => _HuyaSearchPageState();
}

class _HuyaSearchPageState extends State<HuyaSearchPage> {
  final TextEditingController _textController = TextEditingController();
  String _keyword = '';

  void _search(String value) {
    final keyword = value.trim();
    if (keyword.isEmpty || keyword == _keyword) {
      return;
    }
    setState(() => _keyword = keyword);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _textController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: '搜索虎牙直播间',
            border: InputBorder.none,
            suffixIcon: IconButton(
              tooltip: '清空',
              onPressed: () {
                _textController.clear();
                setState(() => _keyword = '');
              },
              icon: const Icon(Icons.clear),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _search(_textController.text),
            child: const Text('搜索'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
        child: _keyword.isEmpty
            ? const _SearchHint()
            : HuyaPagedRoomGrid(
                key: ValueKey(_keyword),
                loadPage: (page) =>
                    HuyaLiveRepository.instance.searchRooms(_keyword, page),
                emptyMessage: '没有找到相关直播间',
              ),
      ),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 52, color: color),
          const SizedBox(height: 12),
          Text('输入房间名或主播名', style: TextStyle(color: color)),
        ],
      ),
    );
  }
}
