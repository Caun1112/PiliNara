import 'package:PiliPlus/models/common/pgc_episode_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/section.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/video/download_panel/episode_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary P2 wins over the video metadata P1 cid', () {
    final pages = [Part(cid: 101), Part(cid: 102)];
    expect(findDownloadEpisodeIndex(pages, 102, seasonCid: 101), 1);
  });

  test('a collection part resolves to its original parent index', () {
    final entries = [
      ugc.EpisodeItem(cid: 11, pages: [Part(cid: 11)]),
      ugc.EpisodeItem(cid: 21, pages: [Part(cid: 21), Part(cid: 22)]),
    ];
    expect(findDownloadEpisodeIndex(entries, 22, seasonCid: 21), 1);
    expect(findDownloadEpisodeIndex(entries, 99, seasonCid: 21), 1);
    expect(findDownloadEpisodeIndex(entries, 99), -1);
  });

  test(
    'collection downloads resolve the actual part from current metadata',
    () {
      final parent = ugc.EpisodeItem(cid: 21, pages: [Part(cid: 21)]);
      final first = Part(cid: 21, page: 1);
      final second = Part(cid: 22, page: 2);
      final current = VideoDetailData(cid: 21, pages: [first, second]);

      expect(
        findCurrentCollectionPart(parent, 22, videoDetail: current),
        same(second),
      );
      expect(
        findCurrentCollectionPart(parent, 23, videoDetail: current),
        isNull,
      );
      expect(
        findCurrentCollectionPart(
          parent,
          22,
          videoDetail: VideoDetailData(cid: 31, pages: [second]),
        ),
        isNull,
      );
      expect(
        findCurrentCollectionPart(
          ugc.EpisodeItem(cid: 21),
          22,
          videoDetail: current,
        ),
        same(second),
      );
    },
  );

  test('PGC downloads use the active extras section', () {
    final main = pgc.EpisodeItem(cid: 101);
    final extra = pgc.EpisodeItem(cid: 202);
    final item = PgcInfoModel(
      episodes: [main],
      sections: [
        Section(episodes: [extra]),
      ],
    );
    final section = pgcDownloadEpisodes(item, PgcEpisodeType.section, 0);
    expect(section, [extra]);
    expect(findDownloadEpisodeIndex(section, 202), 0);
    expect(pgcDownloadEpisodes(item, PgcEpisodeType.episode, 0), [main]);
    expect(pgcDownloadEpisodes(item, PgcEpisodeType.section, 1), isEmpty);
  });
}
