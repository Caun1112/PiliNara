import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/pages/live/huya/widgets/room_card.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_core/simple_live_core.dart';

typedef HuyaRoomPageLoader = Future<HuyaRoomPageData> Function(int page);

class HuyaPagedRoomGrid extends StatefulWidget {
  const HuyaPagedRoomGrid({
    super.key,
    required this.loadPage,
    this.emptyMessage = '暂时没有正在直播的房间',
    this.bottomPadding = 100,
  });

  final HuyaRoomPageLoader loadPage;
  final String emptyMessage;
  final double bottomPadding;

  @override
  State<HuyaPagedRoomGrid> createState() => _HuyaPagedRoomGridState();
}

class _HuyaPagedRoomGridState extends State<HuyaPagedRoomGrid>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final List<LiveRoomItem> _items = [];

  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextPage = 1;
  int _requestGeneration = 0;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 600) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _requestGeneration++;
      setState(() {
        _initialLoading = true;
        _loadingMore = false;
        _hasMore = true;
        _nextPage = 1;
        _error = null;
      });
    } else if (_initialLoading || _loadingMore || !_hasMore) {
      return;
    } else {
      setState(() => _loadingMore = true);
    }

    final generation = _requestGeneration;
    final page = reset ? 1 : _nextPage;
    try {
      final result = await widget.loadPage(page);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
        } else {
          _items.addAll(result.items);
        }
        _nextPage = page + 1;
        _hasMore = result.hasMore;
        _initialLoading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _initialLoading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator.adaptive(
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              top: Style.cardSpace,
              bottom: widget.bottomPadding,
            ),
            sliver: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final gridDelegate = SliverGridDelegateWithExtentAndRatio(
      mainAxisSpacing: Style.cardSpace,
      crossAxisSpacing: Style.cardSpace,
      maxCrossAxisExtent: Grid.smallCardWidth,
      childAspectRatio: Style.aspectRatio,
      mainAxisExtent: 90,
    );
    if (_initialLoading) {
      return SliverGrid(
        gridDelegate: gridDelegate,
        delegate: const SliverSingleChildDelegate(
          count: 10,
          child: VideoCardVSkeleton(),
        ),
      );
    }
    if (_items.isEmpty) {
      return HttpError(
        errMsg: _error ?? widget.emptyMessage,
        onReload: () => _load(reset: true),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverGrid.builder(
          gridDelegate: gridDelegate,
          itemCount: _items.length,
          itemBuilder: (context, index) => HuyaRoomCard(item: _items[index]),
        ),
        if (_loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          )
        else if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('加载失败，点击重试'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
