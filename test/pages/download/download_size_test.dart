import 'package:PiliPlus/pages/video/download_panel/view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('下载视频大小以MB或GB显示', () {
    expect(formatDownloadSize(10 * 1024 * 1024), '10.0 MB');
    expect(formatDownloadSize(15 * 1024 * 1024 ~/ 2), '7.5 MB');
    expect(formatDownloadSize(1024 * 1024 * 1024), '1.00 GB');
  });

  test('下载大小包含视频和音频码率', () {
    expect(
      estimateDownloadSizeBytes(
        durationSeconds: 100,
        videoBandwidth: 800000,
        audioBandwidth: 160000,
      ),
      12000000,
    );
  });
}
