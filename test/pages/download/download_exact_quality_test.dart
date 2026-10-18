import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/http/download.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';

VideoItem video(VideoQuality quality, {String? codec = 'avc1.64001E'}) =>
    VideoItem(
      id: quality.code,
      quality: quality,
      codecs: codec,
      baseUrl: 'https://example.com/${quality.code}.m4s',
    );

PlayUrlModel dashResponse(
  List<VideoItem> videos, {
  List<int>? advertised,
  List<FormatItem>? formats,
}) => PlayUrlModel(
  dash: Dash(video: videos),
  acceptQuality: advertised,
  supportFormats: formats,
);

int select480(PlayUrlModel response) => DownloadHttp.selectVideoQuality(
  response,
  preferredQuality: VideoQuality.high1080.code,
  requiredQuality: VideoQuality.clear480.code,
);

void main() {
  late Directory storageDir;
  setUpAll(() async {
    storageDir = await Directory.systemTemp.createTemp(
      'download_exact_quality_',
    );
    appSupportDirPath = storageDir.path;
    await GStorage.init();
  });
  tearDownAll(() async {
    await GStorage.close();
    await storageDir.delete(recursive: true);
  });

  test(
    '480P is qn32 and exact selection ignores preferred or highest quality',
    () {
      expect(VideoQuality.clear480.code, 32);
      final response = dashResponse([
        video(VideoQuality.high1080),
        video(VideoQuality.clear480),
        video(VideoQuality.fluent360),
      ]);
      expect(select480(response), 32);
    },
  );

  test('advertised480P without a real480P track is rejected', () {
    final response = dashResponse(
      [video(VideoQuality.high720)],
      advertised: [64, 32],
      formats: [FormatItem(quality: 32, newDesc: '480P 标清')],
    );
    expect(
      () => select480(response),
      throwsA(
        isA<DownloadQualityUnavailableException>().having(
          (error) => error.toString(),
          'actionable message',
          contains('480P'),
        ),
      ),
    );
  });

  for (final quality in [VideoQuality.high720, VideoQuality.fluent360]) {
    test('only${quality.shortDesc} never silently replaces480P', () {
      expect(
        () => select480(dashResponse([video(quality)])),
        throwsA(isA<DownloadQualityUnavailableException>()),
      );
    });
  }

  test('missing or empty DASH track list is rejected', () {
    for (final dash in [Dash(), Dash(video: [])]) {
      expect(
        () => select480(PlayUrlModel(dash: dash, acceptQuality: [32])),
        throwsA(isA<DownloadQualityUnavailableException>()),
      );
    }
  });

  test('durl must report exactly480P even when metadata advertises480P', () {
    final response = PlayUrlModel(
      quality: 64,
      supportFormats: [FormatItem(quality: 32)],
    )..durl = [Durl(url: 'https://example.com/video.mp4')];
    expect(
      () => select480(response),
      throwsA(isA<DownloadQualityUnavailableException>()),
    );
    response.quality = null;
    expect(
      () => select480(response),
      throwsA(isA<DownloadQualityUnavailableException>()),
    );
  });

  test('actual480P durl does not need supportFormats metadata', () {
    final response = PlayUrlModel(quality: 32)
      ..durl = [Durl(url: 'https://example.com/video.mp4')];
    expect(select480(response), 32);
    response.durl = [];
    expect(
      () => select480(response),
      throwsA(isA<DownloadQualityUnavailableException>()),
    );
  });

  test('strict480P rejects multi-segment durl instead of exporting a partial video', () {
    final response = PlayUrlModel(quality: 32)
      ..durl = [
        Durl(url: 'https://example.com/segment1.mp4'),
        Durl(url: 'https://example.com/segment2.mp4'),
      ];
    expect(
      () => select480(response),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'unsupported segmented download',
          contains('多个视频分段'),
        ),
      ),
    );
    expect(
      DownloadHttp.selectVideoQuality(response, preferredQuality: 32),
      32,
    );
  });

  test('strict codecs use actual tracks despite missing or stale metadata', () {
    final avc = video(VideoQuality.clear480);
    final hevc = video(VideoQuality.clear480, codec: 'hvc1.1.6.L93.B0');
    for (final formats in <List<FormatItem>?>[
      null,
      [],
      [
        FormatItem(quality: 32, codecs: ['av01.0.04M.08']),
      ],
    ]) {
      final response = dashResponse([avc, hevc], formats: formats);
      expect(
        DownloadHttp.selectExactDashVideo(
          response,
          quality: 32,
          preferredCodecs: [VideoDecodeFormatType.HEVC],
        ),
        same(hevc),
      );
    }
  });

  test('missing codec names safely retain an actual480P track', () {
    final track = video(VideoQuality.clear480, codec: null);
    expect(
      DownloadHttp.selectExactDashVideo(
        dashResponse([track]),
        quality: 32,
        preferredCodecs: [VideoDecodeFormatType.AVC],
      ),
      same(track),
    );
  });

  test('ordinary downloads keep their existing quality fallback', () {
    final response = dashResponse(
      [video(VideoQuality.high720), video(VideoQuality.fluent360)],
      advertised: [64, 16],
    );
    expect(
      DownloadHttp.selectVideoQuality(response, preferredQuality: 32),
      16,
    );
  });

  test(
    'exact quality persists without changing the global download default',
    () async {
      await Pref.setDefaultDownloadVideoQa(VideoQuality.high108060.code);
      final entry = BiliDownloadEntryInfo(
        isCompleted: false,
        totalBytes: 0,
        downloadedBytes: 0,
        title: 'Exact480P',
        cover: '',
        preferedVideoQuality: VideoQuality.high720.code,
        requiredVideoQuality: VideoQuality.clear480.code,
        guessedTotalBytes: 0,
        totalTimeMilli: 1000,
        danmakuCount: 0,
        avid: 1,
        bvid: 'BV1test',
        pageData: PageInfo(cid: 2, page: 1, hasAlias: false, tid: 0),
      );
      final restored = BiliDownloadEntryInfo.fromJson(
        jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
      );
      expect(restored.requiredVideoQuality, 32);
      expect(restored.preferedVideoQuality, 64);
      expect(
        select480(dashResponse([video(VideoQuality.clear480)])),
        restored.requiredVideoQuality,
      );
      expect(Pref.defaultDownloadVideoQa, VideoQuality.high108060.code);

      final legacy = entry.toJson()..remove('required_video_quality');
      expect(
        BiliDownloadEntryInfo.fromJson(legacy).requiredVideoQuality,
        isNull,
      );
    },
  );
}
