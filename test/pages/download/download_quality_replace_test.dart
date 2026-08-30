import 'dart:io';

import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory tempDir;
  late DownloadService downloadService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'pilinara_download_quality_replace_',
    );
    downloadService = DownloadService();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  BiliDownloadEntryInfo createEntry(VideoQuality quality) {
    final entryDir = Directory(path.join(tempDir.path, 'entry'))..createSync();
    return BiliDownloadEntryInfo(
        isCompleted: true,
        totalBytes: 10,
        downloadedBytes: 10,
        title: '测试视频',
        cover: '',
        videoQuality: quality.code,
        preferedVideoQuality: quality.code,
        guessedTotalBytes: 10,
        totalTimeMilli: 1000,
        danmakuCount: 0,
        avid: 1,
        bvid: 'BV1test',
        pageData: PageInfo(
          cid: 2,
          page: 1,
          hasAlias: false,
          tid: 0,
        ),
      )
      ..pageDirPath = tempDir.path
      ..entryDirPath = entryDir.path;
  }

  test('选择相同画质时复用已下载文件', () async {
    final entry = createEntry(VideoQuality.fluent360);
    downloadService.downloadList.add(entry);

    final removed = await downloadService.removeDownloadForQualityChange(
      cid: entry.cid,
      quality: VideoQuality.fluent360.code,
    );

    expect(removed, isFalse);
    expect(downloadService.downloadList, contains(entry));
    expect(Directory(entry.entryDirPath).existsSync(), isTrue);
  });

  test('选择不同画质时移除旧文件以重新下载', () async {
    final entry = createEntry(VideoQuality.fluent360);
    downloadService.downloadList.add(entry);

    final removed = await downloadService.removeDownloadForQualityChange(
      cid: entry.cid,
      quality: VideoQuality.clear480.code,
    );

    expect(removed, isTrue);
    expect(downloadService.downloadList, isEmpty);
    expect(Directory(entry.entryDirPath).existsSync(), isFalse);
  });
}
