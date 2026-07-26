import 'package:PiliPlus/pages/video/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('视频页浮动返回按钮在当前基础上向上移动80逻辑像素', () {
    final withoutSafeArea = calculateVideoFloatingBackButtonBottom(
      height: 932,
      safeTop: 0,
      safeBottom: 0,
    );
    final withSafeArea = calculateVideoFloatingBackButtonBottom(
      height: 932,
      safeTop: 47,
      safeBottom: 34,
    );

    expect(withoutSafeArea - kFloatingActionButtonMargin, 312);
    expect(withSafeArea - withoutSafeArea, 34);
  });

  test('矮屏会保留返回按钮顶部可见边距', () {
    final bottom = calculateVideoFloatingBackButtonBottom(
      height: 390,
      safeTop: 0,
      safeBottom: 21,
    );

    expect(390 - bottom - 56, kFloatingActionButtonMargin);
  });
}
