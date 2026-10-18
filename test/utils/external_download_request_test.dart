import 'package:PiliPlus/utils/external_download_request.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'B81A9671-EF8B-409D-9740-5A74019B2AA3';
  const url = 'pilinara://video/170001?cid=279786&action=download&quality=32';

  ExternalDownloadRequest request({String? requestId, int cid = 279786}) =>
      ExternalDownloadRequest.tryParse(
        Uri.parse(
          'pilinara://video/170001?cid=$cid&action=download&quality=32'
          '${requestId == null ? '' : '&request_id=$requestId'}',
        ),
      )!;

  test(
    'explicit download preserves the exact video, part and share default',
    () {
      final parsed = ExternalDownloadRequest.tryParse(Uri.parse(url))!;
      expect(parsed.aid, 170001);
      expect(parsed.bvid, IdUtils.av2bv(170001));
      expect(parsed.cid, 279786);
      expect(parsed.share, isTrue);
      expect(parsed.requestId, isNull);
      expect(ExternalDownloadRequest.quality, 32);
    },
  );

  test('canonical BV links and explicit share options are accepted', () {
    final bvid = IdUtils.av2bv(170001);
    final parsed = ExternalDownloadRequest.tryParse(
      Uri.parse(
        'pilinara://video/$bvid?cid=279786&action=download&quality=32&share=0&request_id=$id',
      ),
    )!;
    expect(parsed.aid, 170001);
    expect(parsed.bvid, bvid);
    expect(parsed.share, isFalse);
    expect(parsed.requestId, id.toLowerCase());
    expect(
      ExternalDownloadRequest.tryParse(Uri.parse('$url&share=1'))!.share,
      isTrue,
    );
  });

  test('ordinary links and malformed actions never become downloads', () {
    final invalid = [
      'pilinara://video/170001?cid=279786',
      url.replaceFirst('pilinara:', 'bilibili:'),
      url.replaceFirst('video/', 'pgc/'),
      url.replaceFirst('170001', '170001/extra'),
      url.replaceFirst('170001', '0'),
      url.replaceFirst('170001', '-1'),
      url.replaceFirst('170001', '${IdUtils.MAX_AID}'),
      url.replaceFirst('170001', 'BV1000000000'),
      url.replaceFirst('cid=279786', 'cid=0'),
      url.replaceFirst('cid=279786', 'cid=-1'),
      url.replaceFirst('cid=279786', 'cid=9223372036854775808'),
      url.replaceFirst('cid=279786', 'cid=1.5'),
      url.replaceFirst('action=download', 'action=play'),
      url.replaceFirst('quality=32', 'quality=64'),
      '$url&share=true',
      '$url&request_id=',
      '$url&request_id=not-a-uuid',
      '$url&request_id=${'a' * 200}',
      '$url&cid=1',
      '$url&quality=16',
      '$url&share=0&share=1',
      '$url#download',
      url.replaceFirst('video/', 'video:80/'),
      url.replaceFirst('video/', 'user@video/'),
    ];
    for (final value in invalid) {
      expect(
        ExternalDownloadRequest.tryParse(Uri.parse(value)),
        isNull,
        reason: value,
      );
    }
  });

  test(
    'request is claimed before async work and stays consumed after failure',
    () {
      final gate = ExternalDownloadRequestGate();
      final first = request(requestId: id);
      expect(gate.begin(first), isTrue);
      expect(gate.begin(request(requestId: id.toLowerCase())), isFalse);
      gate.finish(first);
      expect(gate.begin(first), isFalse);
    },
  );

  test(
    'different requests for an in-flight CID cannot enqueue concurrently',
    () {
      final gate = ExternalDownloadRequestGate();
      final first = request();
      expect(gate.begin(first), isTrue);
      expect(gate.begin(request(requestId: id)), isFalse);
      expect(gate.begin(request(cid: 279787)), isTrue);
      gate.finish(first);
      expect(gate.begin(request()), isTrue);
      // A suppressed external event must not replay later with its old ID.
      expect(gate.begin(request(requestId: id)), isFalse);
    },
  );

  test('request ID memory stays bounded and evicts the oldest claim', () {
    final gate = ExternalDownloadRequestGate(capacity: 2);
    final ids = [
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000002',
      '00000000-0000-0000-0000-000000000003',
    ];
    for (final id in ids) {
      final item = request(requestId: id);
      expect(gate.begin(item), isTrue);
      gate.finish(item);
    }
    expect(gate.begin(request(requestId: ids[1])), isFalse);
    expect(gate.begin(request(requestId: ids.first)), isTrue);
  });
}
