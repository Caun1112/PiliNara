import 'dart:io';

import 'package:PiliPlus/pages/search/view.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  setUpAll(() async {
    final storageDir = await Directory.systemTemp.createTemp(
      'pilinara_search_test_',
    );
    appSupportDirPath = storageDir.path;
    await GStorage.init();
  });

  setUp(() async {
    Get.testMode = true;
    await GStorage.setting.putAll({
      SettingBoxKey.enableHotKey: false,
      SettingBoxKey.enableSearchRcmd: false,
    });
  });

  tearDown(Get.reset);

  testWidgets('主导航搜索输入框保留左侧间距并可自动获得焦点', (tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(
        home: SearchPage(
          key: mainNavigationSearchPageKey,
          autofocus: false,
          embedded: true,
        ),
      ),
    );
    await tester.pump();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.titleSpacing, 16);
    expect(appBar.primary, isFalse);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.focusNode!.hasFocus, isFalse);
    expect(mainNavigationSearchPageKey.currentState, isNotNull);

    focusMainNavigationSearch();
    await tester.pump();
    await tester.pump();

    expect(textField.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
