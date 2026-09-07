import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/pages/danmaku/danmaku_model.dart';
import 'package:PiliPlus/pages/live/huya/room/controller.dart';
import 'package:PiliPlus/pages/live/huya/room/layout.dart';
import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/utils/danmaku_options.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/common_btn.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/play_pause_btn.dart';
import 'package:PiliPlus/common/widgets/flutter/popup_menu.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HuyaLiveRoomPage extends StatefulWidget {
  const HuyaLiveRoomPage({super.key, required this.roomId});

  final String roomId;

  @override
  State<HuyaLiveRoomPage> createState() => _HuyaLiveRoomPageState();
}

class _HuyaLiveRoomPageState extends State<HuyaLiveRoomPage> {
  late final String _controllerTag;
  late final HuyaLiveRoomController _controller;
  final GlobalKey<TimeBatteryMixin> _headerKey = GlobalKey<TimeBatteryMixin>();

  @override
  void initState() {
    super.initState();
    _controllerTag = 'huya_${widget.roomId}_${identityHashCode(this)}';
    _controller = Get.put(
      HuyaLiveRoomController(roomId: widget.roomId),
      tag: _controllerTag,
    );
  }

  @override
  void dispose() {
    Get.delete<HuyaLiveRoomController>(tag: _controllerTag, force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isFullScreen = _controller.plPlayerController.isFullScreen.value;
      return PopScope(
        canPop: !isFullScreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && isFullScreen) {
            _controller.plPlayerController.triggerFullScreen(status: false);
          }
        },
        child: Scaffold(
          backgroundColor: isFullScreen ? Colors.black : null,
          appBar: isFullScreen
              ? null
              : AppBar(
                  title: Text(
                    _controller.detail.value?.title ?? '虎牙直播',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    Obx(
                      () => IconButton(
                        tooltip: _controller.followed.value ? '取消关注' : '关注主播',
                        onPressed: _controller.toggleFollow,
                        icon: Icon(
                          _controller.followed.value
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
          body: _buildBody(isFullScreen),
        ),
      );
    });
  }

  Widget _buildBody(bool isFullScreen) {
    if (_controller.loading.value) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_controller.detail.value == null) {
      return HttpError(
        isSliver: false,
        errMsg: _controller.error.value ?? '无法读取直播间',
        onReload: _controller.load,
      );
    }
    return HuyaLiveRoomLayout(
      isFullScreen: isFullScreen,
      playerBuilder: (size) => _buildPlayer(
        width: size.width,
        height: size.height,
        isFullScreen: isFullScreen,
      ),
      chatPanel: _HuyaChatPanel(controller: _controller),
    );
  }

  Widget _buildPlayer({
    required double width,
    required double height,
    required bool isFullScreen,
  }) {
    return Obx(() {
      final player = _controller.plPlayerController;
      if (player.videoController == null) {
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: _controller.error.value == null
                ? const CircularProgressIndicator.adaptive()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _controller.error.value!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: _controller.refreshPlaySource,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试播放'),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      }
      return Stack(
        children: [
          PLVideoPlayer(
            maxWidth: width,
            maxHeight: height,
            plPlayerController: player,
            headerControl: _HuyaPlayerHeader(
              key: _headerKey,
              controller: _controller,
            ),
            bottomControl: _HuyaPlayerBottomControl(controller: _controller),
            danmuWidget: _HuyaDanmakuLayer(
              controller: _controller,
              size: Size(width, height),
              isFullScreen: isFullScreen,
            ),
          ),
          if (_controller.switchingSource.value)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    });
  }
}

class _HuyaChatPanel extends StatelessWidget {
  const _HuyaChatPanel({required this.controller});

  final HuyaLiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = controller.detail.value!;
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                NetworkImgLayer(
                  src: detail.userAvatar,
                  width: 40,
                  height: 40,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        detail.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text('实时弹幕', style: theme.textTheme.titleSmall),
                const Spacer(),
                Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Obx(
                  () => Text(
                    controller.onlineText.value,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.messages.isEmpty) {
                return Center(
                  child: Text(
                    '弹幕连接中，收到消息后会显示在这里',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                );
              }
              return ListView.builder(
                controller: controller.chatScrollController,
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: 12 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                itemCount: controller.messages.length,
                itemBuilder: (context, index) {
                  final message = controller.messages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${message.userName}  ',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: message.message),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _HuyaPlayerHeader extends StatefulWidget {
  const _HuyaPlayerHeader({super.key, required this.controller});

  final HuyaLiveRoomController controller;

  @override
  State<_HuyaPlayerHeader> createState() => _HuyaPlayerHeaderState();
}

class _HuyaPlayerHeaderState extends State<_HuyaPlayerHeader>
    with TimeBatteryMixin {
  @override
  PlPlayerController get plPlayerController =>
      widget.controller.plPlayerController;

  @override
  bool get horizontalScreen => true;

  @override
  bool get isFullScreen => plPlayerController.isFullScreen.value;

  @override
  bool get isPortrait => false;

  @override
  Widget build(BuildContext context) {
    showCurrTimeIfNeeded(isFullScreen);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          if (isFullScreen)
            ComBtn(
              tooltip: '退出全屏',
              onTap: () => plPlayerController.triggerFullScreen(status: false),
              icon: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
            ),
          Expanded(
            child: Obx(
              () => Text(
                widget.controller.detail.value?.title ?? '虎牙直播',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
          ...?timeBatteryWidgets,
          if (isFullScreen) ...[
            const SizedBox(width: 12),
            Obx(
              () => Text(
                '人气 ${widget.controller.onlineText.value}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HuyaPlayerBottomControl extends StatelessWidget {
  const _HuyaPlayerBottomControl({required this.controller});

  final HuyaLiveRoomController controller;

  @override
  Widget build(BuildContext context) {
    final player = controller.plPlayerController;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          PlayOrPauseButton(plPlayerController: player),
          ComBtn(
            tooltip: '刷新播放地址',
            onTap: controller.refreshPlaySource,
            icon: const Icon(Icons.refresh, size: 19, color: Colors.white),
          ),
          Obx(
            () => ComBtn(
              tooltip: player.enableShowLiveDanmaku.value ? '关闭弹幕' : '开启弹幕',
              onTap: player.enableShowLiveDanmaku.toggle,
              icon: Icon(
                player.enableShowLiveDanmaku.value
                    ? Icons.subtitles
                    : Icons.subtitles_off_outlined,
                size: 19,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          Obx(
            () => StaticPopupMenuButton<int>(
              tooltip: '画质',
              initialValue: controller.qualityIndex.value,
              color: Colors.black.withValues(alpha: 0.86),
              itemBuilder: (context) => [
                for (
                  var index = 0;
                  index < controller.qualities.length;
                  index++
                )
                  PopupMenuItem<int>(
                    value: index,
                    onTap: () => controller.changeQuality(index),
                    child: Text(
                      controller.qualities[index].quality,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  controller.qualities.isEmpty
                      ? '画质'
                      : controller
                            .qualities[controller.qualityIndex.value]
                            .quality,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
          Obx(
            () => StaticPopupMenuButton<int>(
              tooltip: '线路',
              initialValue: controller.lineIndex.value,
              enabled: controller.playUrls.length > 1,
              color: Colors.black.withValues(alpha: 0.86),
              itemBuilder: (context) => [
                for (var index = 0; index < controller.playUrls.length; index++)
                  PopupMenuItem<int>(
                    value: index,
                    onTap: () => controller.changeLine(index),
                    child: Text(
                      '线路 ${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '线路 ${controller.lineIndex.value + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
          ComBtn(
            tooltip: player.isFullScreen.value ? '退出全屏' : '全屏',
            onTap: () =>
                player.triggerFullScreen(status: !player.isFullScreen.value),
            icon: Icon(
              player.isFullScreen.value
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              size: 24,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _HuyaDanmakuLayer extends StatefulWidget {
  const _HuyaDanmakuLayer({
    required this.controller,
    required this.size,
    required this.isFullScreen,
  });

  final HuyaLiveRoomController controller;
  final Size size;
  final bool isFullScreen;

  @override
  State<_HuyaDanmakuLayer> createState() => _HuyaDanmakuLayerState();
}

class _HuyaDanmakuLayerState extends State<_HuyaDanmakuLayer> {
  PlPlayerController get player => widget.controller.plPlayerController;

  @override
  void didUpdateWidget(covariant _HuyaDanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFullScreen != widget.isFullScreen &&
        !DanmakuOptions.sameFontScale) {
      player.danmakuController?.updateOption(
        DanmakuOptions.get(notFullscreen: !widget.isFullScreen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => AnimatedOpacity(
        opacity: player.enableShowLiveDanmaku.value
            ? player.danmakuOpacity.value
            : 0,
        duration: const Duration(milliseconds: 150),
        child: DanmakuScreen<DanmakuExtra>(
          size: widget.size,
          option: DanmakuOptions.get(notFullscreen: !widget.isFullScreen),
          createdController: (danmakuController) {
            widget.controller.danmakuController = player.danmakuController =
                danmakuController;
          },
        ),
      ),
    );
  }
}
