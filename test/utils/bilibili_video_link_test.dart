import 'package:PiliPlus/utils/bilibili_video_link.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <Map<dynamic, dynamic>>[];
  late Future<bool> Function(int attempt) launchResult;

  setUp(() {
    launches.clear();
    launchResult = (_) => Future.value(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          expect(call.method, 'launch');
          launches.add(call.arguments as Map<dynamic, dynamic>);
          return launchResult(launches.length);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('ordinary video uses a numeric aid and zero-based part', () {
    final link = BilibiliVideoLink.video(aid: 115012345678901, page: 3);

    expect(link.appUri.toString(), 'bilibili://video/115012345678901?page=2');
    expect(
      link.universalUri.toString(),
      'https://m.bilibili.com/video/av115012345678901?page=2',
    );
  });

  test('ordinary video defaults to its first part', () {
    final link = BilibiliVideoLink.video(aid: 170001);

    expect(link.appUri.toString(), 'bilibili://video/170001?page=0');
    expect(
      link.universalUri.toString(),
      'https://m.bilibili.com/video/av170001?page=0',
    );
  });

  test('episode routes preserve the episode instead of its season', () {
    final link = BilibiliVideoLink.episode(epId: 876543);

    expect(link.appUri.toString(), 'bilibili://pgc/season/ep/876543');
    expect(
      link.universalUri.toString(),
      'https://m.bilibili.com/bangumi/play/ep876543',
    );
  });

  test('invalid identifiers and parts are rejected before launch', () {
    for (final invalid in [0, -1]) {
      expect(
        () => BilibiliVideoLink.video(aid: invalid),
        throwsArgumentError,
      );
      expect(
        () => BilibiliVideoLink.video(aid: 170001, page: invalid),
        throwsArgumentError,
      );
      expect(
        () => BilibiliVideoLink.episode(epId: invalid),
        throwsArgumentError,
      );
    }
    expect(launches, isEmpty);
  });

  test('successful universal link opens only the associated app', () async {
    expect(await BilibiliVideoLink.video(aid: 170001, page: 2).open(), isTrue);

    expect(launches, hasLength(1));
    expect(
      launches.single['url'],
      'https://m.bilibili.com/video/av170001?page=1',
    );
    expect(launches.single['universalLinksOnly'], isTrue);
    expect(launches.single['useSafariVC'], isFalse);
    expect(launches.single['useWebView'], isFalse);
  });

  for (final universalThrows in [false, true]) {
    test(
      '${universalThrows ? 'throwing' : 'rejected'} universal link tries the app scheme',
      () async {
        launchResult = (attempt) async {
          if (attempt == 1) {
            if (universalThrows) {
              throw PlatformException(code: 'universal_link_unavailable');
            }
            return false;
          }
          return true;
        };

        expect(await BilibiliVideoLink.episode(epId: 876543).open(), isTrue);

        expect(launches.map((call) => call['url']), [
          'https://m.bilibili.com/bangumi/play/ep876543',
          'bilibili://pgc/season/ep/876543',
        ]);
        expect(launches.first['universalLinksOnly'], isTrue);
        expect(launches.last['universalLinksOnly'], isFalse);
        for (final launch in launches) {
          expect(launch['useSafariVC'], isFalse);
          expect(launch['useWebView'], isFalse);
        }
      },
    );

    for (final schemeThrows in [false, true]) {
      test(
        'unavailable app returns false without a browser '
        '(universal throws: $universalThrows, scheme throws: $schemeThrows)',
        () async {
          launchResult = (attempt) async {
            if (attempt == 1 ? universalThrows : schemeThrows) {
              throw PlatformException(code: 'app_unavailable');
            }
            return false;
          };

          expect(
            await BilibiliVideoLink.video(aid: 170001, page: 2).open(),
            isFalse,
          );

          expect(launches.map((call) => call['url']), [
            'https://m.bilibili.com/video/av170001?page=1',
            'bilibili://video/170001?page=1',
          ]);
          expect(launches.first['universalLinksOnly'], isTrue);
          for (final launch in launches) {
            expect(launch['useSafariVC'], isFalse);
            expect(launch['useWebView'], isFalse);
          }
        },
      );
    }
  }
}
