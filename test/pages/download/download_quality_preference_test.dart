import 'dart:io';

import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final storageDir = await Directory.systemTemp.createTemp(
      'pilinara_download_quality_test_',
    );
    appSupportDirPath = storageDir.path;
    await GStorage.init();
  });

  setUp(() => GStorage.setting.delete(SettingBoxKey.defaultDownloadVideoQa));

  test('下载画质首次默认使用720P准高清', () {
    expect(Pref.defaultDownloadVideoQa, VideoQuality.high720.code);
  });

  test('下载画质选择会在不同视频面板之间持久化', () async {
    await Pref.setDefaultDownloadVideoQa(VideoQuality.high108060.code);

    expect(Pref.defaultDownloadVideoQa, VideoQuality.high108060.code);
  });
}
