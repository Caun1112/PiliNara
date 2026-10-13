import 'package:url_launcher/url_launcher.dart';

/// Routes used by Bilibili's H5 app-opening buttons. App pages are zero-based.
class BilibiliVideoLink {
  BilibiliVideoLink.video({required int aid, int page = 1}) {
    if (aid <= 0 || page <= 0) {
      throw ArgumentError('A video requires a positive aid and page.');
    }
    final query = {'page': '${page - 1}'};
    appUri = Uri(
      scheme: 'bilibili',
      host: 'video',
      path: '/$aid',
      queryParameters: query,
    );
    universalUri = Uri.https('m.bilibili.com', '/video/av$aid', query);
  }

  BilibiliVideoLink.episode({required int epId}) {
    if (epId <= 0) {
      throw ArgumentError('An episode requires a positive epId.');
    }
    appUri = Uri(scheme: 'bilibili', host: 'pgc', path: '/season/ep/$epId');
    universalUri = Uri.https('m.bilibili.com', '/bangumi/play/ep$epId');
  }

  late final Uri appUri;
  late final Uri universalUri;

  /// A universal link selects the app associated with Bilibili's own domain.
  /// Do not fall back to a browser: this action explicitly opens the Bilibili app.
  Future<bool> open() async {
    try {
      if (await launchUrl(
        universalUri,
        mode: LaunchMode.externalNonBrowserApplication,
      )) {
        return true;
      }
    } on Exception {
      // The scheme remains usable if universal links are disabled/unavailable.
    }
    try {
      return await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}
