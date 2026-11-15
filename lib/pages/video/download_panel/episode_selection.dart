import 'package:PiliPlus/models/common/pgc_episode_type.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';

/// Match the actual playing part before falling back to the collection entry.
int findDownloadEpisodeIndex(
  List<ugc.BaseEpisodeItem> episodes,
  int currentCid, {
  int? seasonCid,
}) {
  final index = episodes.indexWhere(
    (episode) =>
        episode.cid == currentCid ||
        (episode is ugc.EpisodeItem &&
            episode.pages?.any((part) => part.cid == currentCid) == true),
  );
  if (index >= 0 || seasonCid == null) return index;
  return episodes.indexWhere((episode) => episode.cid == seasonCid);
}

/// Resolve only the exact playing part, including when a collection entry has
/// an incomplete page list. Never silently substitute the entry's first part.
Part? findCurrentCollectionPart(
  ugc.EpisodeItem episode,
  int currentCid, {
  VideoDetailData? videoDetail,
}) {
  for (final part in episode.pages ?? const <Part>[]) {
    if (part.cid == currentCid) return part;
  }
  if (episode.cid != null && episode.cid == videoDetail?.cid) {
    for (final part in videoDetail?.pages ?? const <Part>[]) {
      if (part.cid == currentCid) return part;
    }
  }
  return null;
}

/// PGC extras live in sections instead of the main episode list.
List<pgc.EpisodeItem> pgcDownloadEpisodes(
  PgcInfoModel item,
  PgcEpisodeType episodeType,
  int sectionIndex,
) {
  if (episodeType == PgcEpisodeType.section) {
    final sections = item.sections;
    if (sections == null ||
        sectionIndex < 0 ||
        sectionIndex >= sections.length) {
      return const [];
    }
    return sections[sectionIndex].episodes ?? const [];
  }
  return item.episodes ?? const [];
}
