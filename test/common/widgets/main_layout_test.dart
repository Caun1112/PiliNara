import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('浮动底栏靠屏幕右侧放置', (tester) async {
    const bottomNavKey = Key('bottom-nav');
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MainLayout(
          sideBar: null,
          bottomNavAlignment: Alignment.bottomRight,
          bottomNav: SizedBox(
            key: bottomNavKey,
            width: 200,
            height: 64,
          ),
          body: SizedBox.expand(),
        ),
      ),
    );

    expect(tester.getTopRight(find.byKey(bottomNavKey)).dx, 400);
    expect(tester.getBottomRight(find.byKey(bottomNavKey)).dy, 800);
  });
}
