import 'package:PiliPlus/utils/id_utils.dart';

/// An explicit download action from the companion Bilibili tweak.
class ExternalDownloadRequest {
  const ExternalDownloadRequest._({
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.requestId,
    required this.share,
  });

  static const quality = 32;
  static final _digits = RegExp(r'^[0-9]+$');
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final int aid;
  final String bvid;
  final int cid;
  final String? requestId;
  final bool share;

  static int? _positiveInteger(String? value) {
    if (value == null || value.length > 19 || !_digits.hasMatch(value)) {
      return null;
    }
    final number = int.tryParse(value);
    return number != null && number > 0 ? number : null;
  }

  static ExternalDownloadRequest? tryParse(Uri uri) {
    if (uri.scheme != 'pilinara' ||
        uri.host != 'video' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty ||
        uri.pathSegments.length != 1) {
      return null;
    }
    final query = uri.queryParameters;
    if (query['action'] != 'download' || query['quality'] != '$quality') {
      return null;
    }
    for (final key in ['action', 'quality', 'cid', 'share', 'request_id']) {
      if ((uri.queryParametersAll[key]?.length ?? 0) > 1) return null;
    }
    final cid = _positiveInteger(query['cid']);
    if (cid == null) return null;
    final share = query['share'];
    if (share != null && share != '0' && share != '1') return null;
    final requestId = query['request_id'];
    if (requestId != null && !_uuid.hasMatch(requestId)) return null;

    final id = uri.pathSegments.single;
    try {
      final numericId = _positiveInteger(id);
      final int aid;
      final String bvid;
      if (numericId != null) {
        // The AV/BV conversion represents 51-bit AV identifiers.
        if (numericId >= IdUtils.MAX_AID) return null;
        aid = numericId;
        bvid = IdUtils.av2bv(aid);
      } else {
        if (!RegExp(r'^BV1[0-9A-Za-z]{9}$').hasMatch(id)) return null;
        aid = IdUtils.bv2av(id);
        bvid = IdUtils.av2bv(aid);
        if (aid <= 0 || bvid != id) return null;
      }
      return ExternalDownloadRequest._(
        aid: aid,
        bvid: bvid,
        cid: cid,
        requestId: requestId?.toLowerCase(),
        share: share != '0',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Claims an external action synchronously, before any initialization or I/O.
class ExternalDownloadRequestGate {
  ExternalDownloadRequestGate({this.capacity = 64}) : assert(capacity > 0);

  final int capacity;
  final _seenIds = <String>{};
  final _inFlightCids = <int>{};

  bool begin(ExternalDownloadRequest request) {
    final id = request.requestId;
    if (id != null) {
      if (!_seenIds.add(id)) return false;
      while (_seenIds.length > capacity) {
        _seenIds.remove(_seenIds.first);
      }
    }
    return _inFlightCids.add(request.cid);
  }

  void finish(ExternalDownloadRequest request) {
    _inFlightCids.remove(request.cid);
  }
}
