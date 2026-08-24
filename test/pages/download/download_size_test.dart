import 'package:PiliPlus/pages/video/download_panel/view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('下载视频大小统一以MB显示并保留一位小数', () {
    expect(formatDownloadSizeMb(10 * 1024 * 1024), '10.0 MB');
    expect(formatDownloadSizeMb(15 * 1024 * 1024 ~/ 2), '7.5 MB');
  });
}
