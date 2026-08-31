import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/pages/live/huya/category/rooms_view.dart';
import 'package:PiliPlus/pages/live/huya/repository.dart';
import 'package:PiliPlus/pages/live/huya/route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_live_core/simple_live_core.dart';

class HuyaCategoryPage extends StatefulWidget {
  const HuyaCategoryPage({super.key});

  @override
  State<HuyaCategoryPage> createState() => _HuyaCategoryPageState();
}

class _HuyaCategoryPageState extends State<HuyaCategoryPage> {
  late Future<List<LiveCategory>> _future = _load();

  Future<List<LiveCategory>> _load() {
    return HuyaLiveRepository.instance.getCategories();
  }

  void _retry() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('虎牙分类')),
      body: FutureBuilder<List<LiveCategory>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError) {
            return HttpError(
              isSliver: false,
              errMsg: snapshot.error.toString(),
              onReload: _retry,
            );
          }
          final categories = snapshot.data ?? const [];
          if (categories.isEmpty) {
            return HttpError(
              isSliver: false,
              errMsg: '暂无可用分类',
              onReload: _retry,
            );
          }
          return ListView.builder(
            padding: EdgeInsets.only(
              left: Style.safeSpace,
              right: Style.safeSpace,
              bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) =>
                _CategorySection(category: categories[index]),
          );
        },
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category});

  final LiveCategory category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              category.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisExtent: 68,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: category.children.length,
            itemBuilder: (context, index) =>
                _CategoryItem(category: category.children[index]),
          ),
        ],
      ),
    );
  }
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({required this.category});

  final LiveSubCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: Style.mdRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openHuyaPage(
          context,
          (_) => HuyaCategoryRoomsPage(category: category),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              if (category.pic case final pic? when pic.isNotEmpty) ...[
                NetworkImgLayer(
                  src: pic,
                  width: 48,
                  height: 48,
                  borderRadius: Style.mdRadius,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
