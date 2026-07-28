import 'package:PiliPlus/common/widgets/global_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('浮动返回按钮中心位于屏幕自上而下55%的位置', () {
    const height = 932.0;
    final withoutSafeArea = calculateFloatingBackButtonBottom(
      height: 932,
      safeTop: 0,
      safeBottom: 0,
    );
    final withSafeArea = calculateFloatingBackButtonBottom(
      height: 932,
      safeTop: 47,
      safeBottom: 34,
    );

    expect(height - withoutSafeArea - 28, height * 0.55);
    expect(withSafeArea, withoutSafeArea);
  });

  test('矮屏会保留返回按钮顶部安全边距', () {
    final bottom = calculateFloatingBackButtonBottom(
      height: 160,
      safeTop: 50,
      safeBottom: 0,
    );

    expect(160 - bottom - 56 - 50, kFloatingActionButtonMargin);
  });
}
