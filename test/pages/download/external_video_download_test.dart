import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/services/download/external_video_download.dart';
import 'package:PiliPlus/utils/external_download_request.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';

const _cid = 279786;
const _requestId = 'B81A9671-EF8B-409D-9740-5A74019B2AA3';

ExternalDownloadRequest _request() => ExternalDownloadRequest.tryParse(
  Uri.parse(
    'pilinara://video/170001?cid=$_cid&action=download&quality=32'
    '&request_id=$_requestId',
  ),
)!;

BiliDownloadEntryInfo _entry({
  int cid = _cid,
  int quality = 32,
  bool completed = false,
  DownloadStatus status = DownloadStatus.wait,
}) => BiliDownloadEntryInfo(
  isCompleted: completed,
  totalBytes: 0,
  downloadedBytes: 0,
  title: 'Video',
  cover: 'https://example.com/cover.jpg',
  videoQuality: completed ? quality : null,
  preferedVideoQuality: quality,
  guessedTotalBytes: 0,
  totalTimeMilli: 1000,
  danmakuCount: 0,
  avid: 170001,
  bvid: IdUtils.av2bv(170001),
  pageData: PageInfo(cid: cid, page: 2, hasAlias: false, tid: 0),
)..status = status;

class FakeDownloadService extends DownloadService {
  FakeDownloadService(this.events) {
    waitForInitialization = Future.value();
  }

  final List<String> events;
  Completer<void>? enqueueGate;
  int enqueueCount = 0;
  int resumeCount = 0;
  int? enqueuedCid;
  int? enqueuedIndex;
  VideoQuality? enqueuedQuality;
  int? enqueuedRequiredQuality;

  @override
  Future<BiliDownloadEntryInfo?> downloadVideo({
    required int index,
    required Part page,
    VideoDetailData? videoDetail,
    ugc.EpisodeItem? videoArc,
    required VideoQuality videoQuality,
    int? requiredVideoQuality,
    String? autoFolderTitle,
    String? autoFolderSourceKey,
    int? autoFolderIndex,
    SeasonInfo? seasonInfo,
  }) async {
    events.add('enqueue');
    enqueueCount++;
    enqueuedCid = page.cid;
    enqueuedIndex = index;
    enqueuedQuality = videoQuality;
    enqueuedRequiredQuality = requiredVideoQuality;
    await enqueueGate?.future;
    final entry = _entry()..requiredVideoQuality = requiredVideoQuality;
    waitDownloadQueue.add(entry);
    events.add('enqueued');
    return entry;
  }

  @override
  Future<void> requireVideoQuality(
    BiliDownloadEntryInfo entry,
    int quality,
  ) async {
    events.add('persist-strict');
    entry.requiredVideoQuality = quality;
  }

  @override
  Future<void> startDownload(BiliDownloadEntryInfo entry) async {
    events.add('resume');
    resumeCount++;
    curDownload.value = entry;
    entry.status = DownloadStatus.downloading;
  }
}

void main() {
  late Directory storageDir;
  late List<String> events;
  late List<String> messages;
  late FakeDownloadService service;
  late VideoDetailData detail;
  late PlayUrlModel playUrl;

  setUpAll(() async {
    storageDir = await Directory.systemTemp.createTemp('external_download_');
    appSupportDirPath = storageDir.path;
    await GStorage.init();
  });
  tearDownAll(() async {
    await GStorage.close();
    await storageDir.delete(recursive: true);
  });
  setUp(() {
    events = [];
    messages = [];
    service = FakeDownloadService(events);
    detail = VideoDetailData(
      aid: 170001,
      bvid: IdUtils.av2bv(170001),
      title: 'Video',
      pic: 'https://example.com/cover.jpg',
      pages: [
        Part(cid: 1, page: 1),
        Part(cid: _cid, page: 2),
      ],
    );
    playUrl = PlayUrlModel(
      dash: Dash(
        video: [
          VideoItem(id: 32, quality: VideoQuality.clear480),
          VideoItem(id: 64, quality: VideoQuality.high720),
        ],
      ),
    );
  });

  ExternalVideoDownload coordinator() => ExternalVideoDownload(
    findService: () => service,
    navigate: () async => events.add('navigate'),
    fetchDetail: (request) async {
      expect(request.bvid, detail.bvid);
      events.add('metadata');
      return Success(detail);
    },
    fetchPlayUrl: (request) async {
      expect(request.cid, _cid);
      events.add('preflight');
      return Success(playUrl);
    },
    share: (_, cid) async {
      expect(cid, _cid);
      events.add('share');
    },
    toast: (message) async => messages.add(message),
  );

  test(
    'fresh P2 navigates, validates 480P, awaits enqueue, then shares',
    () async {
      await Pref.setDefaultDownloadVideoQa(VideoQuality.high108060.code);
      service.enqueueGate = Completer<void>();
      final operation = coordinator().open(_request());
      await Future<void>.delayed(Duration.zero);
      expect(events, ['navigate', 'metadata', 'preflight', 'enqueue']);
      service.enqueueGate!.complete();
      await operation;

      expect(events, [
        'navigate',
        'metadata',
        'preflight',
        'enqueue',
        'enqueued',
        'share',
      ]);
      expect(service.enqueuedCid, _cid);
      expect(service.enqueuedIndex, 1);
      expect(service.enqueuedQuality, VideoQuality.clear480);
      expect(service.enqueuedRequiredQuality, 32);
      expect(Pref.defaultDownloadVideoQa, VideoQuality.high108060.code);
      expect(messages, isEmpty);
    },
  );

  test(
    'cold-start waiting 480P registers sharing before starting the task',
    () async {
      final pending = _entry();
      service.waitDownloadQueue.add(pending);
      await coordinator().open(_request());
      expect(events, ['navigate', 'persist-strict', 'share', 'resume']);
      expect(pending.requiredVideoQuality, 32);
      expect(service.curDownload.value, same(pending));
      expect(service.enqueueCount, 0);
      expect(service.resumeCount, 1);
      expect(service.waitDownloadQueue, hasLength(1));
    },
  );

  for (final status in [DownloadStatus.pause, DownloadStatus.failPlayUrl]) {
    test(
      'existing ${status.name} task resumes after the share listener is ready',
      () async {
        final pending = _entry(status: status);
        service.waitDownloadQueue.add(pending);
        service.curDownload.value = pending;
        await coordinator().open(_request());
        expect(events, ['navigate', 'persist-strict', 'share', 'resume']);
        expect(service.resumeCount, 1);
        expect(service.enqueueCount, 0);
      },
    );
  }

  test(
    'waiting target never interrupts an unrelated active download',
    () async {
      final active = _entry(cid: _cid + 1, status: DownloadStatus.downloading);
      final pending = _entry();
      service.curDownload.value = active;
      service.waitDownloadQueue.add(pending);
      await coordinator().open(_request());
      expect(events, ['navigate', 'persist-strict', 'share']);
      expect(service.resumeCount, 0);
      expect(service.curDownload.value, same(active));
      expect(active.status, DownloadStatus.downloading);
      expect(pending.status, DownloadStatus.wait);
    },
  );

  test(
    'completed exact 480P is shared without HTTP or another queue entry',
    () async {
      final completed = _entry(completed: true);
      service.downloadList.add(completed);
      await coordinator().open(_request());
      expect(events, ['navigate', 'share']);
      expect(service.downloadList.single, same(completed));
      expect(service.waitDownloadQueue, isEmpty);
      expect(service.enqueueCount, 0);
    },
  );

  test(
    'another quality remains untouched and reports a visible conflict',
    () async {
      final original = _entry(completed: true, quality: 64);
      service.downloadList.add(original);
      await coordinator().open(_request());
      expect(events, ['navigate']);
      expect(messages.single, contains('已有其他画质缓存'));
      expect(service.downloadList.single, same(original));
      expect(original.videoQuality, 64);
      expect(original.requiredVideoQuality, isNull);
      expect(service.enqueueCount, 0);
    },
  );

  test(
    'metadata missing the requested CID cannot download another part',
    () async {
      detail.pages = [Part(cid: 1, page: 1)];
      await coordinator().open(_request());
      expect(events, ['navigate', 'metadata']);
      expect(messages.single, contains('未找到当前分P'));
      expect(service.enqueueCount, 0);
    },
  );

  test(
    'advertised 480P without an actual 480P track fails before enqueue',
    () async {
      playUrl = PlayUrlModel(
        acceptQuality: [64, 32],
        dash: Dash(video: [VideoItem(id: 64, quality: VideoQuality.high720)]),
      );
      await coordinator().open(_request());
      expect(events, ['navigate', 'metadata', 'preflight']);
      expect(messages.single, contains('未提供 480P'));
      expect(service.enqueueCount, 0);
    },
  );

  test(
    'a duplicate external UUID performs navigation and enqueue only once',
    () async {
      final importer = coordinator();
      await Future.wait([importer.open(_request()), importer.open(_request())]);
      await importer.open(_request());
      expect(events.where((event) => event == 'navigate'), hasLength(1));
      expect(events.where((event) => event == 'share'), hasLength(1));
      expect(service.enqueueCount, 1);
      expect(service.waitDownloadQueue, hasLength(1));
    },
  );
}
