import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:flutter_test/flutter_test.dart';

BiliDownloadEntryInfo _entry(int cid) => BiliDownloadEntryInfo(
  isCompleted: false,
  totalBytes: 10,
  downloadedBytes: 0,
  title: '测试视频',
  cover: '',
  videoQuality: VideoQuality.clear480.code,
  preferedVideoQuality: VideoQuality.clear480.code,
  guessedTotalBytes: 10,
  totalTimeMilli: 1000,
  danmakuCount: 0,
  avid: 1,
  bvid: 'BV1test',
  pageData: PageInfo(cid: cid, page: 1, hasAlias: false, tid: 0),
);

void main() {
  for (final failed in [false, true]) {
    final event = failed ? 'failed' : 'completed';

    test('$event listeners can remove themselves during notification', () {
      final service = DownloadService();
      final listeners = failed
          ? service.failedEntryNotifier
          : service.completedEntryNotifier;
      final firstEntry = _entry(2);
      final nextEntry = _entry(3);
      final calls = <String>[];
      final received = <BiliDownloadEntryInfo>[];
      late ValueChanged<BiliDownloadEntryInfo> once;
      once = (entry) {
        calls.add('once');
        received.add(entry);
        listeners.remove(once);
      };
      void persistent(BiliDownloadEntryInfo entry) {
        calls.add('persistent');
        received.add(entry);
      }

      listeners
        ..add(once)
        ..add(persistent);

      expect(() => listeners.notify(firstEntry), returnsNormally);
      expect(calls, ['once', 'persistent']);
      expect(received, everyElement(same(firstEntry)));
      expect(listeners, orderedEquals([persistent]));

      expect(() => listeners.notify(nextEntry), returnsNormally);
      expect(calls, ['once', 'persistent', 'persistent']);
      expect(received.last, same(nextEntry));
      expect(listeners, orderedEquals([persistent]));
    });

    test(
      '$event notification keeps its snapshot when a listener removes another',
      () {
        final service = DownloadService();
        final listeners = failed
            ? service.failedEntryNotifier
            : service.completedEntryNotifier;
        final entry = _entry(2);
        final calls = <String>[];
        final received = <BiliDownloadEntryInfo>[];
        void removed(BiliDownloadEntryInfo value) {
          calls.add('removed');
          received.add(value);
        }

        void remover(BiliDownloadEntryInfo value) {
          calls.add('remover');
          received.add(value);
          listeners.remove(removed);
        }

        void persistent(BiliDownloadEntryInfo value) {
          calls.add('persistent');
          received.add(value);
        }

        listeners
          ..add(remover)
          ..add(removed)
          ..add(persistent);

        expect(() => listeners.notify(entry), returnsNormally);
        expect(calls, ['remover', 'removed', 'persistent']);
        expect(received, everyElement(same(entry)));
        expect(listeners, orderedEquals([remover, persistent]));

        expect(() => listeners.notify(entry), returnsNormally);
        expect(calls, [
          'remover',
          'removed',
          'persistent',
          'remover',
          'persistent',
        ]);
        expect(listeners, orderedEquals([remover, persistent]));
      },
    );
  }

  test('only terminal download failures are classified as failures', () {
    const failures = {
      DownloadStatus.failDownload,
      DownloadStatus.failDownloadAudio,
      DownloadStatus.failDanmaku,
      DownloadStatus.failPlayUrl,
    };

    for (final status in DownloadStatus.values) {
      expect(status.isFailure, failures.contains(status), reason: status.name);
    }
  });
}
