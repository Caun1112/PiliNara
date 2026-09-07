import 'package:PiliPlus/pages/live/huya/room/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('虎牙反复切换全屏和聊天布局时保持播放器与纹理挂载', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Future<void> showLayout(Size size, {required bool isFullScreen}) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: HuyaLiveRoomLayout(
            isFullScreen: isFullScreen,
            playerBuilder: (_) => const _PlaybackProbe(),
            chatPanel: const ColoredBox(
              key: Key('chat-panel'),
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    await showLayout(const Size(400, 800), isFullScreen: false);
    final playback = tester.state<_PlaybackProbeState>(
      find.byType(_PlaybackProbe),
    );
    final texture = tester.renderObject(find.byType(Texture));
    expect(tester.getSize(find.byType(Texture)), const Size(400, 225));

    for (final (size, fullScreen) in [
      (const Size(800, 400), false),
      (const Size(800, 400), true),
      (const Size(400, 800), true),
      (const Size(400, 800), false),
      (const Size(1200, 800), false),
      (const Size(1200, 800), true),
      (const Size(1200, 300), false),
      (const Size(400, 800), false),
    ]) {
      await showLayout(size, isFullScreen: fullScreen);
      expect(tester.state(find.byType(_PlaybackProbe)), same(playback));
      expect(playback.deactivations, 0);
      expect(playback.disposed, isFalse);
      expect(tester.renderObject(find.byType(Texture)), same(texture));
      expect(texture.attached, isTrue);
      expect(
        find.byKey(const Key('chat-panel')),
        fullScreen ? findsNothing : findsOneWidget,
      );
      if (fullScreen) {
        expect(tester.getRect(find.byType(Texture)), Offset.zero & size);
      }
    }

    await tester.pumpWidget(const SizedBox.shrink());
    expect(playback.disposed, isTrue);
  });
}

class _PlaybackProbe extends StatefulWidget {
  const _PlaybackProbe();

  @override
  State<_PlaybackProbe> createState() => _PlaybackProbeState();
}

class _PlaybackProbeState extends State<_PlaybackProbe> {
  int deactivations = 0;
  bool disposed = false;

  @override
  void deactivate() {
    deactivations++;
    super.deactivate();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Texture(textureId: 1);
}
