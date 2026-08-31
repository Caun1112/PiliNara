import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/pages/live/huya/view.dart';
import 'package:PiliPlus/pages/live/view.dart';
import 'package:material_ui/material_ui.dart';

class LivePlatformPage extends StatefulWidget {
  const LivePlatformPage({super.key});

  @override
  State<LivePlatformPage> createState() => _LivePlatformPageState();
}

class _LivePlatformPageState extends State<LivePlatformPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  )..addListener(_onTabChanged);

  final List<Widget> _pages = [const LivePage(), const SizedBox.shrink()];
  int _index = 0;

  @override
  bool get wantKeepAlive => true;

  void _onTabChanged() {
    if (_tabController.indexIsChanging || _index == _tabController.index) {
      return;
    }
    setState(() {
      _index = _tabController.index;
      if (_index == 1 && _pages[1] is SizedBox) {
        _pages[1] = const HuyaLivePage();
      }
    });
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
          child: TabBar.secondary(
            controller: _tabController,
            dividerHeight: 0,
            tabs: const [
              Tab(text: 'B站'),
              Tab(text: '虎牙'),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(index: _index, children: _pages),
        ),
      ],
    );
  }
}
