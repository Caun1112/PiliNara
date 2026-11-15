import 'dart:io';
import 'dart:typed_data';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.response);
  final ResponseBody response;
  String? range;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    range = options.headers['range'] as String?;
    return response;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pilinara_resume_test_');
    file = File('${dir.path}/video');
    await file.writeAsBytes([1, 2, 3]);
  });
  tearDown(() async => dir.delete(recursive: true));

  Future<(DownloadStatus, Object?, String?)> download(
    int status,
    List<int> bytes,
    Map<String, List<String>> headers,
  ) async {
    final adapter = _ResponseAdapter(
      ResponseBody.fromBytes(bytes, status, headers: headers),
    );
    final client = Dio()..httpClientAdapter = adapter;
    Object? error;
    final manager = DownloadManager(
      url: 'https://example.com/video',
      path: file.path,
      client: client,
      onReceiveProgress: null,
      onDone: ([e]) => error = e,
    );
    await manager.task;
    client.close();
    return (manager.status, error, adapter.range);
  }

  test('206 appends only the exact remaining range', () async {
    final result = await download(
      206,
      [4, 5],
      {
        'content-range': ['bytes 3-4/5'],
      },
    );
    expect(result.$1, DownloadStatus.completed);
    expect(result.$3, 'bytes=3-');
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
  });

  test('ignored range replaces rather than appending existing data', () async {
    final result = await download(
      200,
      [8, 9],
      {
        'content-length': ['2'],
      },
    );
    expect(result.$1, DownloadStatus.completed);
    expect(await file.readAsBytes(), [8, 9]);
  });

  test('failed restart preserves previous partial data', () async {
    final result = await download(
      200,
      [8, 9],
      {
        'content-length': ['4'],
      },
    );
    expect(result.$1, DownloadStatus.failDownload);
    expect(result.$2, isNotNull);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('416 succeeds only with matching known total', () async {
    var result = await download(416, [], {
      'content-range': ['bytes */3'],
    });
    expect(result.$1, DownloadStatus.completed);
    result = await download(416, [], {
      'content-range': ['bytes */4'],
    });
    expect(result.$1, DownloadStatus.failDownload);
    result = await download(416, [], {});
    expect(result.$1, DownloadStatus.failDownload);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test('unknown length and wrong offsets cannot be completed', () async {
    var result = await download(200, [4, 5], {});
    expect(result.$1, DownloadStatus.failDownload);
    result = await download(
      206,
      [4, 5],
      {
        'content-range': ['bytes 1-2/3'],
      },
    );
    expect(result.$1, DownloadStatus.failDownload);
    result = await download(
      206,
      [4, 5],
      {
        'content-range': ['bytes 3-4/*'],
      },
    );
    expect(result.$1, DownloadStatus.failDownload);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
}
