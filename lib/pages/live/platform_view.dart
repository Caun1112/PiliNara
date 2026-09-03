import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/pages/live/huya/view.dart';
import 'package:PiliPlus/pages/live/view.dart';
import 'package:material_ui/material_ui.dart';

class LivePlatformPage extends StatefulWidget {
  const LivePlatformPage({super.key});

  @override
  State<LivePlatformPage> createState() => _LivePlatformPageState();
}

class _LivePlatformPageState extends State<LivePlatformPage>
    with AutomaticKeepAliveClientMixin {
  final List<Widget> _pages = [const LivePage(), const SizedBox.shrink()];
  int _index = 0;

  @override
  bool get wantKeepAlive => true;

  void _selectPlatform(int index) {
    if (_index == index) return;
    setState(() {
      _index = index;
      if (_index == 1 && _pages[1] is SizedBox) {
        _pages[1] = const HuyaLivePage();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(index: _index, children: _pages),
        ),
        Positioned.fill(
          child: FloatingNavigationBar(
            animationDuration: const Duration(milliseconds: 200),
            alignment: Alignment.bottomRight,
            bottomPadding: 80,
            selectedIndex: _index,
            onDestinationSelected: _selectPlatform,
            destinations: const [
              FloatingNavigationDestination(
                label: 'B站',
                tooltip: '切换到 B 站直播',
                icon: Icon(Icons.live_tv_outlined),
                selectedIcon: Icon(Icons.live_tv_rounded),
              ),
              FloatingNavigationDestination(
                label: '虎牙',
                tooltip: '切换到虎牙直播',
                icon: Icon(Icons.videocam_outlined),
                selectedIcon: Icon(Icons.videocam_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
