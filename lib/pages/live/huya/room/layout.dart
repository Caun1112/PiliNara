import 'dart:math' as math;

import 'package:PiliPlus/common/style.dart';
import 'package:flutter/widgets.dart';

class HuyaLiveRoomLayout extends StatelessWidget {
  const HuyaLiveRoomLayout({
    super.key,
    required this.isFullScreen,
    required this.playerBuilder,
    required this.chatPanel,
  });

  final bool isFullScreen;
  final Widget Function(Size size) playerBuilder;
  final Widget chatPanel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSidePanel = !isFullScreen && constraints.maxWidth >= 900;
        final sideWidth = useSidePanel
            ? math.min(380.0, constraints.maxWidth * 0.34)
            : 0.0;
        final availableWidth = constraints.maxWidth - sideWidth;
        final playerWidth = useSidePanel
            ? math.min(
                availableWidth,
                constraints.maxHeight * Style.aspectRatio16x9,
              )
            : availableWidth;
        final playerHeight = isFullScreen
            ? constraints.maxHeight
            : useSidePanel
            ? playerWidth / Style.aspectRatio16x9
            : math.min(
                playerWidth / Style.aspectRatio16x9,
                constraints.maxHeight * 0.62,
              );
        // 切换布局只更新播放器的位置和尺寸，保留播放状态和纹理。
        return Stack(
          children: [
            Positioned(
              left: (availableWidth - playerWidth) / 2,
              top: useSidePanel
                  ? (constraints.maxHeight - playerHeight) / 2
                  : 0,
              width: playerWidth,
              height: playerHeight,
              child: playerBuilder(Size(playerWidth, playerHeight)),
            ),
            if (!isFullScreen)
              Positioned(
                left: useSidePanel ? availableWidth : 0,
                top: useSidePanel ? 0 : playerHeight,
                right: 0,
                bottom: 0,
                child: chatPanel,
              ),
          ],
        );
      },
    );
  }
}
