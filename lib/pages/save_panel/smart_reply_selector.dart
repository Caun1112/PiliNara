import 'dart:math' show log, max, min;

import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;

const double _defaultMaxEstimatedReplyHeight = 480;
const double _defaultEstimatedContentWidth = 360;

enum SmartReplyMode {
  highlight('精彩观点', '优先选择观点完整、互动较高且适合分享的评论'),
  debate('正反讨论', '只从真实回复关系中选择相互回应的不同观点'),
  knowledge('科普补充', '寻找包含原因、数据、定义或解释结构的评论'),
  humor('搞笑瞬间', '寻找有完整笑点或包袱的评论，过滤纯刷屏内容');

  const SmartReplyMode(this.label, this.description);

  final String label;
  final String description;
}

class SmartReplyRecommendation {
  const SmartReplyRecommendation({
    required this.replyId,
    required this.reason,
    required this.score,
  });

  final int replyId;
  final String reason;
  final double score;
}

class SmartReplySelection {
  const SmartReplySelection(this.recommendations);

  final List<SmartReplyRecommendation> recommendations;
}

SmartReplySelection selectSmartReplies({
  required ReplyInfo root,
  required SmartReplyMode mode,
  int? upMid,
  double maxEstimatedReplyHeight = _defaultMaxEstimatedReplyHeight,
  bool showFullImages = false,
  double contentWidth = _defaultEstimatedContentWidth,
}) {
  final candidates = _buildCandidates(root, upMid: upMid);
  if (candidates.isEmpty) return const SmartReplySelection([]);

  if (mode == SmartReplyMode.debate) {
    return SmartReplySelection(
      _selectDebate(
        root,
        candidates,
        maxEstimatedReplyHeight: maxEstimatedReplyHeight,
        showFullImages: showFullImages,
        contentWidth: contentWidth,
      ),
    );
  }

  for (final candidate in candidates) {
    candidate
      ..score = _scoreCandidate(candidate, mode)
      ..reason = _reasonFor(candidate, mode);
  }

  final threshold = switch (mode) {
    SmartReplyMode.highlight => 34.0,
    SmartReplyMode.knowledge => 34.0,
    SmartReplyMode.humor => 30.0,
    SmartReplyMode.debate => double.infinity,
  };
  final targetCount = switch (mode) {
    SmartReplyMode.highlight => 4,
    SmartReplyMode.knowledge => 4,
    SmartReplyMode.humor => 4,
    SmartReplyMode.debate => 3,
  };
  final ranked = candidates.where((item) => item.score >= threshold).toList()
    ..sort(_rankCandidates);
  final selected = _selectIndependentReplies(
    root,
    ranked,
    targetCount: targetCount,
    maxEstimatedReplyHeight: maxEstimatedReplyHeight,
    showFullImages: showFullImages,
    contentWidth: contentWidth,
  );
  return SmartReplySelection(_toRecommendations(selected));
}

double estimateReplyCaptureHeight(
  ReplyInfo reply, {
  bool showFullImages = false,
  double contentWidth = _defaultEstimatedContentWidth,
}) {
  final safeWidth = max(1.0, contentWidth);
  final charsPerLine = max(8, (safeWidth / 18).floor());
  final textLength = reply.content.message.trim().runes.length;
  final textLines = max(1, (textLength / charsPerLine).ceil());
  var height = 44 + textLines * 24.0;
  final pictures = reply.content.pictures;
  if (pictures.isEmpty) return height;

  if (showFullImages) {
    for (final picture in pictures) {
      final sourceWidth = picture.imgWidth > 0 ? picture.imgWidth : 1;
      final sourceHeight = picture.imgHeight > 0 ? picture.imgHeight : 1;
      height += min(safeWidth * sourceHeight / sourceWidth, safeWidth * 2);
    }
    height += 6 + max(0, pictures.length - 1) * 8;
  } else {
    final cellWidth = max(1.0, (safeWidth - 10) / 3);
    final rows = (pictures.length / 3).ceil();
    height += 6 + rows * cellWidth + max(0, rows - 1) * 5;
  }
  return height;
}

List<_Candidate> _buildCandidates(ReplyInfo root, {required int? upMid}) {
  final localReplyCount = <int, int>{};
  for (final reply in root.replies) {
    final parent = reply.parent.toInt();
    localReplyCount[parent] = (localReplyCount[parent] ?? 0) + 1;
  }

  final raw = <_Candidate>[];
  for (var index = 0; index < root.replies.length; index++) {
    final reply = root.replies[index];
    if (!_isEligible(reply)) continue;
    final message = reply.content.message.trim();
    final normalized = _normalizeMessage(message);
    final canonical = _canonicalMessage(normalized);
    if (canonical.isEmpty && reply.content.pictures.isEmpty) continue;
    if (_isLowInformation(canonical)) continue;

    raw.add(
      _Candidate(
        reply: reply,
        originalIndex: index,
        normalized: normalized,
        canonical: canonical,
        localChildren: localReplyCount[reply.id.toInt()] ?? 0,
        isUp: upMid != null && reply.mid.toInt() == upMid,
      ),
    );
  }
  if (raw.isEmpty) return raw;

  final maxLikes = raw.fold<int>(
    0,
    (value, item) => max(value, item.reply.like.toInt()),
  );
  final maxInteractions = raw.fold<int>(
    0,
    (value, item) => max(
      value,
      max(item.reply.count.toInt(), item.localChildren),
    ),
  );
  for (final candidate in raw) {
    candidate
      ..likeScore = _logNormalized(candidate.reply.like.toInt(), maxLikes)
      ..interactionScore = _logNormalized(
        max(candidate.reply.count.toInt(), candidate.localChildren),
        maxInteractions,
      )
      ..upScore = candidate.reply.replyControl.upLike
          ? 1
          : candidate.isUp
          ? 0.85
          : candidate.reply.replyControl.upReply
          ? 0.7
          : 0
      ..argumentHits = _keywordHits(candidate.normalized, _argumentGroups)
      ..knowledgeHits = _keywordHits(candidate.normalized, _knowledgeGroups)
      ..humorHits = _keywordHits(candidate.normalized, _humorGroups)
      ..opposeHits = _keywordHits(candidate.normalized, _oppositionGroups)
      ..supportHits = _keywordHits(candidate.normalized, _supportGroups)
      ..factDensity = _factDensity(candidate)
      ..contentQuality = _contentQuality(candidate);
  }
  return raw;
}

bool _isEligible(ReplyInfo reply) {
  if (reply.id.toInt() <= 0) return false;
  final control = reply.replyControl;
  return !control.blocked &&
      !control.invisible &&
      !control.isFoldedReply &&
      !reply.member.name.trim().startsWith('账号已注销');
}

double _scoreCandidate(_Candidate item, SmartReplyMode mode) {
  final length = item.normalized.runes.length;
  final hasInsult = _containsAggressiveLanguage(item.normalized);
  final isQuestionOnly =
      RegExp(r'[?？]\s*$').hasMatch(item.normalized) && item.argumentHits == 0;
  switch (mode) {
    case SmartReplyMode.highlight:
      var score =
          30 * _lengthFit(length, minLength: 12, peak: 70, maxLength: 260) +
          24 * min(1, item.argumentHits / 3) +
          20 * item.likeScore +
          10 * item.interactionScore +
          8 * item.upScore +
          8 * item.contentQuality;
      if (isQuestionOnly) score -= 12;
      if (length > 420) score -= 18;
      if (hasInsult) score -= 20;
      return score;
    case SmartReplyMode.knowledge:
      var score =
          26 * min(1, item.knowledgeHits / 3) +
          20 * min(1, item.argumentHits / 3) +
          20 * item.factDensity +
          14 * _lengthFit(length, minLength: 20, peak: 90, maxLength: 300) +
          10 * item.likeScore +
          5 * item.upScore +
          5 * item.contentQuality;
      if (_containsAny(item.normalized, _uncertainWords)) score -= 18;
      if (_containsAny(item.normalized, _absoluteWords) &&
          item.factDensity < 0.35) {
        score -= 15;
      }
      if (hasInsult) score -= 20;
      return score;
    case SmartReplyMode.humor:
      var score =
          34 * min(1, item.humorHits / 2) +
          17 * _humorStructure(item.normalized) +
          20 * item.likeScore +
          8 * item.upScore +
          6 * item.interactionScore +
          10 * _lengthFit(length, minLength: 4, peak: 26, maxLength: 110) +
          5 * _mediaSignal(item);
      if (_isPureLaugh(item.canonical)) score -= 35;
      if (hasInsult) score -= 35;
      return score;
    case SmartReplyMode.debate:
      return 0;
  }
}

String _reasonFor(_Candidate item, SmartReplyMode mode) {
  final likes = item.reply.like.toInt();
  switch (mode) {
    case SmartReplyMode.highlight:
      if (item.reply.replyControl.upLike) return '获得 UP 主认可，观点较完整';
      if (likes >= 10) return '互动较高 · $likes 赞';
      if (item.argumentHits >= 2) return '因果和观点表达较完整';
      if (item.reply.parent != item.reply.root) return '承接前文的关键回应';
      if (item.reply.content.pictures.isNotEmpty) return '包含图片信息，内容较完整';
      return '内容完整，适合分享';
    case SmartReplyMode.knowledge:
      if (item.factDensity >= 0.55) return '包含数据或来源线索';
      if (item.knowledgeHits >= 2 || item.argumentHits >= 2) {
        return '包含原因和解释结构';
      }
      if (item.reply.content.pictures.isNotEmpty) return '包含图示补充';
      return '补充背景信息；请自行核验事实';
    case SmartReplyMode.humor:
      if (likes >= 10) return '高赞趣味回复 · $likes 赞';
      if (_humorStructure(item.normalized) > 0.5) return '有完整反转或包袱';
      if (item.reply.content.emotes.isNotEmpty) return '情绪表达鲜明，笑点集中';
      return '表达短而有梗';
    case SmartReplyMode.debate:
      return '来自同一条真实讨论链';
  }
}

List<_Candidate> _selectIndependentReplies(
  ReplyInfo root,
  List<_Candidate> ranked, {
  required int targetCount,
  required double maxEstimatedReplyHeight,
  required bool showFullImages,
  required double contentWidth,
}) {
  final allById = <int, _Candidate>{};
  for (final item in _buildCandidates(root, upMid: null)) {
    allById[item.reply.id.toInt()] = item;
  }
  final selected = <_Candidate>[];
  final selectedIds = <int>{};
  final authorCount = <int, int>{};
  var estimatedHeight = 0.0;

  bool tryAddAll(
    List<_Candidate> items, {
    int? contextId,
    bool relaxAuthor = false,
  }) {
    final additions = <_Candidate>[];
    final additionIds = <int>{};
    final additionAuthorCount = <int, int>{};
    var additionalHeight = 0.0;

    for (final item in items) {
      final id = item.reply.id.toInt();
      if (selectedIds.contains(id) || !additionIds.add(id)) continue;
      if (_isNearDuplicateOfSelected(item, [...selected, ...additions])) {
        return false;
      }
      final mid = item.reply.mid.toInt();
      if (!relaxAuthor && mid != 0) {
        final count = (authorCount[mid] ?? 0) + (additionAuthorCount[mid] ?? 0);
        if (count >= 1) return false;
        additionAuthorCount[mid] = count + 1;
      }
      additionalHeight += estimateReplyCaptureHeight(
        item.reply,
        showFullImages: showFullImages,
        contentWidth: contentWidth,
      );
      additions.add(item);
    }

    if (additions.isEmpty) return true;
    if (selected.length + additions.length > targetCount ||
        estimatedHeight + additionalHeight > maxEstimatedReplyHeight) {
      return false;
    }

    for (final item in additions) {
      final id = item.reply.id.toInt();
      if (id == contextId) {
        item
          ..score = max(item.score, 100)
          ..reason = '为保留回复上下文一并选中';
      }
      selected.add(item);
      selectedIds.add(id);
      final mid = item.reply.mid.toInt();
      if (mid != 0) authorCount[mid] = (authorCount[mid] ?? 0) + 1;
    }
    estimatedHeight += additionalHeight;
    return true;
  }

  bool tryAddRanked(_Candidate item, {bool relaxAuthor = false}) {
    final context = _requiredContext(item, root, allById);
    if (context == null || selectedIds.contains(context.reply.id.toInt())) {
      return tryAddAll([item], relaxAuthor: relaxAuthor);
    }
    return tryAddAll(
      [context, item],
      contextId: context.reply.id.toInt(),
      relaxAuthor: relaxAuthor,
    );
  }

  for (final item in ranked) {
    if (selected.length >= targetCount) break;
    tryAddRanked(item);
  }
  if (selected.length < min(3, ranked.length)) {
    for (final item in ranked) {
      if (selected.length >= min(3, targetCount)) break;
      tryAddRanked(item, relaxAuthor: true);
    }
  }

  selected.sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
  return selected;
}

_Candidate? _requiredContext(
  _Candidate item,
  ReplyInfo root,
  Map<int, _Candidate> byId,
) {
  final parentId = item.reply.parent.toInt();
  if (parentId == 0 || parentId == root.id.toInt()) return null;
  if (!_dependsOnPrevious(
    item.normalized,
    item.reply.content.atNameToMid.isNotEmpty,
  )) {
    return null;
  }
  return byId[parentId];
}

List<SmartReplyRecommendation> _selectDebate(
  ReplyInfo root,
  List<_Candidate> candidates, {
  required double maxEstimatedReplyHeight,
  required bool showFullImages,
  required double contentWidth,
}) {
  final rootId = root.id.toInt();
  final edges = <_DebateEdge>[];
  for (final response in candidates) {
    response.score = _scoreCandidate(response, SmartReplyMode.highlight);
    final opposition = min(1.0, response.opposeHits / 2);
    if (opposition <= 0 || _containsAggressiveLanguage(response.normalized)) {
      continue;
    }

    final parentId = response.reply.parent.toInt();
    if (parentId == rootId) {
      final score =
          35 +
          25 * opposition +
          15 * response.contentQuality +
          10 * response.likeScore +
          5 * response.interactionScore;
      edges.add(_DebateEdge(response: response, score: score));
      continue;
    }

    for (final statement in candidates) {
      if (statement.reply.id == response.reply.id ||
          statement.reply.mid == response.reply.mid) {
        continue;
      }
      final relation = _relationStrength(statement, response);
      if (relation <= 0) continue;
      final score =
          35 * relation +
          25 * opposition +
          15 * ((statement.contentQuality + response.contentQuality) / 2) +
          10 * ((statement.likeScore + response.likeScore) / 2) +
          5 +
          5 * max(statement.interactionScore, response.interactionScore);
      edges.add(
        _DebateEdge(statement: statement, response: response, score: score),
      );
    }
  }
  if (edges.isEmpty) return const [];
  edges.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    return _rankCandidates(a.response, b.response);
  });
  final best = edges.first;
  if (best.score < 58) return const [];

  final selected = <_Candidate>[];
  final selectedIds = <int>{};
  var estimatedHeight = 0.0;

  bool tryAddAll(List<_Candidate> items) {
    final additions = <_Candidate>[];
    var additionalHeight = 0.0;
    for (final item in items) {
      final id = item.reply.id.toInt();
      if (selectedIds.contains(id) ||
          additions.any((addition) => addition.reply.id.toInt() == id)) {
        continue;
      }
      additionalHeight += estimateReplyCaptureHeight(
        item.reply,
        showFullImages: showFullImages,
        contentWidth: contentWidth,
      );
      additions.add(item);
    }
    if (additions.isEmpty) return true;
    if (estimatedHeight + additionalHeight > maxEstimatedReplyHeight) {
      return false;
    }
    selected.addAll(additions);
    selectedIds.addAll(additions.map((item) => item.reply.id.toInt()));
    estimatedHeight += additionalHeight;
    return true;
  }

  if (best.statement case final statement?) {
    if (!tryAddAll([statement, best.response])) return const [];
    statement
      ..reason = '对话起点，保留观点上下文'
      ..score = best.score;
  } else if (!tryAddAll([best.response])) {
    return const [];
  }
  best.response
    ..reason = best.statement == null ? '直接回应主评论，提供不同立场' : '直接回应前文，提供不同立场'
    ..score = best.score;

  final followUp =
      candidates
          .where(
            (item) =>
                !selectedIds.contains(item.reply.id.toInt()) &&
                item.reply.mid != best.response.reply.mid &&
                (item.reply.parent == best.response.reply.id ||
                    _sameDialogue(item, best.response)) &&
                (item.opposeHits > 0 || item.supportHits > 0),
          )
          .toList()
        ..sort(_rankCandidates);
  if (followUp.isNotEmpty) {
    for (final item in followUp) {
      if (tryAddAll([item])) {
        item
          ..reason = '延续同一条讨论链'
          ..score = best.score - 1;
        break;
      }
    }
  }

  selected.sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
  return _toRecommendations(selected.take(3).toList());
}

double _relationStrength(_Candidate statement, _Candidate response) {
  if (response.reply.parent == statement.reply.id) return 1;
  if (_sameDialogue(statement, response) &&
      (_mentions(response, statement) ||
          response.normalized.startsWith('回复') ||
          response.normalized.contains('@'))) {
    return 0.8;
  }
  if (_mentions(response, statement)) return 0.7;
  return 0;
}

bool _sameDialogue(_Candidate a, _Candidate b) {
  final dialog = a.reply.dialog.toInt();
  return dialog != 0 && dialog == b.reply.dialog.toInt();
}

bool _mentions(_Candidate response, _Candidate statement) {
  final mid = statement.reply.mid;
  return mid.toInt() != 0 &&
      response.reply.content.atNameToMid.values.any((value) => value == mid);
}

List<SmartReplyRecommendation> _toRecommendations(List<_Candidate> selected) {
  return [
    for (final item in selected)
      SmartReplyRecommendation(
        replyId: item.reply.id.toInt(),
        reason: item.reason,
        score: item.score,
      ),
  ];
}

int _rankCandidates(_Candidate a, _Candidate b) {
  final score = b.score.compareTo(a.score);
  if (score != 0) return score;
  final likes = b.reply.like.compareTo(a.reply.like);
  if (likes != 0) return likes;
  final ctime = a.reply.ctime.compareTo(b.reply.ctime);
  if (ctime != 0) return ctime;
  return a.reply.id.compareTo(b.reply.id);
}

double _contentQuality(_Candidate item) {
  final length = item.canonical.runes.length;
  if (length == 0) return item.reply.content.pictures.isNotEmpty ? 0.35 : 0;
  final uniqueRatio = item.canonical.runes.toSet().length / min(24, length);
  final sentenceSignal = RegExp(
    r'[，。！？；,.!?;]',
  ).allMatches(item.normalized).length;
  return min(
    1,
    0.55 * min(1, uniqueRatio) +
        0.25 * min(1, sentenceSignal / 3) +
        0.2 * _lengthFit(length, minLength: 8, peak: 65, maxLength: 260),
  );
}

double _factDensity(_Candidate item) {
  var signals = 0.0;
  if (RegExp(r'\d').hasMatch(item.normalized)) signals += 0.25;
  if (RegExp(
    r'\d+(?:\.\d+)?\s*(?:%|年|月|日|秒|分钟|小时|MB|GB|Hz|km|kg|元|倍)',
    caseSensitive: false,
  ).hasMatch(item.normalized)) {
    signals += 0.3;
  }
  if (item.reply.content.urls.isNotEmpty) signals += 0.3;
  if (item.reply.content.topics.isNotEmpty) signals += 0.15;
  if (item.reply.content.pictures.isNotEmpty) signals += 0.1;
  return min(1, signals);
}

double _mediaSignal(_Candidate item) {
  if (item.reply.content.emotes.isNotEmpty) return 1;
  if (item.reply.content.pictures.isNotEmpty) return 0.45;
  return 0;
}

double _humorStructure(String text) {
  if (_containsAny(text, const ['当', '属于是', '建议', '结果', '本以为', '没想到', '原来'])) {
    return 1;
  }
  if (text.contains('：') || text.contains(':') || text.contains('——')) {
    return 0.55;
  }
  return 0;
}

double _lengthFit(
  int length, {
  required int minLength,
  required int peak,
  required int maxLength,
}) {
  if (length <= 0 || length >= maxLength * 2) return 0;
  if (length < minLength) return length / minLength;
  if (length <= peak) return 1;
  return max(0, 1 - (length - peak) / (maxLength - peak));
}

double _logNormalized(int value, int maximum) {
  if (value <= 0 || maximum <= 0) return 0;
  return log(value + 1) / log(maximum + 1);
}

bool _isNearDuplicateOfSelected(_Candidate item, List<_Candidate> selected) {
  for (final other in selected) {
    if (item.canonical == other.canonical) return true;
    final shorter = min(item.canonical.length, other.canonical.length);
    final longer = max(item.canonical.length, other.canonical.length);
    if (shorter >= 10 &&
        (item.canonical.contains(other.canonical) ||
            other.canonical.contains(item.canonical)) &&
        shorter / longer >= 0.85) {
      return true;
    }
    if (shorter >= 10 &&
        _bigramJaccard(item.canonical, other.canonical) >= 0.82) {
      return true;
    }
  }
  return false;
}

double _bigramJaccard(String a, String b) {
  final aRunes = a.runes.toList();
  final bRunes = b.runes.toList();
  if (aRunes.length < 2 || bRunes.length < 2) return 0;
  final aPairs = <String>{
    for (var i = 0; i < aRunes.length - 1; i++) '${aRunes[i]}:${aRunes[i + 1]}',
  };
  final bPairs = <String>{
    for (var i = 0; i < bRunes.length - 1; i++) '${bRunes[i]}:${bRunes[i + 1]}',
  };
  final intersection = aPairs.intersection(bPairs).length;
  final union = aPairs.union(bPairs).length;
  return union == 0 ? 0 : intersection / union;
}

bool _dependsOnPrevious(String text, bool hasMention) {
  if (hasMention) return true;
  return RegExp(r'^(这|那|你说|上面|不是|同意|不同意|回复|但是|不过)').hasMatch(text);
}

bool _isLowInformation(String canonical) {
  if (canonical.isEmpty) return false;
  final runes = canonical.runes.toList();
  if (runes.length <= 6) return false;
  return runes.toSet().length <= 2;
}

bool _isPureLaugh(String canonical) {
  if (canonical.isEmpty) return false;
  final stripped = canonical.replaceAll(RegExp(r'(?:笑死|哈|草|h)+'), '');
  return stripped.isEmpty;
}

String _normalizeMessage(String message) {
  var value = message.toLowerCase();
  value = value.replaceFirst(RegExp(r'^\s*回复\s*@[^:：\s]+\s*[:：]\s*'), '');
  value = value.replaceAll(RegExp(r'https?://\S+'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return value;
}

String _canonicalMessage(String message) {
  return message.replaceAll(
    RegExp(r'''[\s，。！？、；：,.!?;:~～…—\-_=+`"“”‘’'（）()\[\]{}<>《》/@#￥%&*|\\]+'''),
    '',
  );
}

int _keywordHits(String text, List<List<String>> groups) {
  var hits = 0;
  for (final group in groups) {
    if (_containsAny(text, group)) hits++;
  }
  return hits;
}

bool _containsAny(String text, List<String> words) {
  return words.any(text.contains);
}

bool _containsAggressiveLanguage(String text) {
  if (_aggressiveWords.any(text.contains)) return true;
  final withoutNeutralRolling = text.replaceAll(
    RegExp(r'(?:滚动|滚轮|滚轴|滚屏|翻滚)'),
    '',
  );
  return withoutNeutralRolling.contains('滚');
}

class _Candidate {
  _Candidate({
    required this.reply,
    required this.originalIndex,
    required this.normalized,
    required this.canonical,
    required this.localChildren,
    required this.isUp,
  });

  final ReplyInfo reply;
  final int originalIndex;
  final String normalized;
  final String canonical;
  final int localChildren;
  final bool isUp;

  double likeScore = 0;
  double interactionScore = 0;
  double upScore = 0;
  double contentQuality = 0;
  double factDensity = 0;
  int argumentHits = 0;
  int knowledgeHits = 0;
  int humorHits = 0;
  int opposeHits = 0;
  int supportHits = 0;
  double score = 0;
  String reason = '';
}

class _DebateEdge {
  const _DebateEdge({
    this.statement,
    required this.response,
    required this.score,
  });

  final _Candidate? statement;
  final _Candidate response;
  final double score;
}

const _argumentGroups = <List<String>>[
  ['因为', '所以', '因此', '导致', '原因'],
  ['但是', '不过', '然而', '相反', '反而'],
  ['本质', '关键', '意味着', '区别', '相比', '应该', '我认为', '结论'],
  ['例如', '比如', '举例', '例子'],
];

const _knowledgeGroups = <List<String>>[
  ['根据', '数据显示', '研究', '资料', '来源', '参考'],
  ['定义', '原理', '机制', '本质', '准确地说'],
  ['补充', '解释', '原因', '区别', '总结'],
  ['首先', '其次', '最后', '例如', '比如', '例子'],
];

const _humorGroups = <List<String>>[
  ['笑死', '绷不住', '蚌埠住', '好家伙', '救命'],
  ['哈哈', 'hhh', '草', '乐', '典'],
  ['属于是', '节目效果', '抽象', '神评', '逆天'],
  ['😂', '🤣', '😅', '💀'],
];

const _oppositionGroups = <List<String>>[
  ['不对', '不是', '并非', '错了', '错误'],
  ['但是', '不过', '然而', '相反', '反而'],
  ['不同意', '未必', '不一定', '你忽略', '问题是'],
];

const _supportGroups = <List<String>>[
  ['同意', '赞同', '支持', '+1'],
  ['确实', '没错', '是的', '有道理', '说得好'],
];

const _aggressiveWords = <String>[
  '傻逼',
  '智障',
  '脑残',
  '弱智',
  '废物',
  '去死',
  '妈的',
];

const _uncertainWords = <String>['听说', '据说', '好像', '我记得', '大概', '可能吧'];

const _absoluteWords = <String>['百分之百', '绝对', '肯定就是', '毫无疑问'];
