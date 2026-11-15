import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:dio/dio.dart';

class DownloadManager {
  final String url;
  final String path;
  final void Function(int, int)? onReceiveProgress;
  final void Function([Object? error]) onDone;
  final Dio? client;

  DownloadStatus _status = DownloadStatus.downloading;

  DownloadStatus get status => _status;
  final _cancelToken = CancelToken();
  late Future<void> task;

  DownloadManager({
    required this.url,
    required this.path,
    required this.onReceiveProgress,
    required this.onDone,
    this.client,
  }) {
    task = _start();
  }

  Future<void> _start() async {
    final file = File(path);
    IOSink? sink;
    File? replacement;
    try {
      final originalLength = file.existsSync() ? await file.length() : 0;
      final response = await (client ?? Request.http11Dio).get<ResponseBody>(
        url.http2https,
        options: Options(
          headers: {
            'range': 'bytes=$originalLength-',
            'accept-encoding': 'identity',
          },
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status == 200 || status == 206 || status == 416,
        ),
        cancelToken: _cancelToken,
      );
      final contentRange = response.headers.value('content-range');
      if (response.statusCode == 416) {
        final match = RegExp(
          r'^bytes \*/(\d+)$',
          caseSensitive: false,
        ).firstMatch(contentRange ?? '');
        final total = match == null ? null : int.tryParse(match.group(1)!);
        if (total == null || total <= 0 || total != originalLength) {
          throw const FormatException('无法验证已下载文件的完整长度');
        }
        await response.data?.stream.drain<void>();
        onReceiveProgress?.call(total, total);
        _status = DownloadStatus.completed;
        onDone();
        return;
      }

      final body = response.data;
      if (body == null) throw const FormatException('下载响应没有内容');
      var received = originalLength;
      late final int total;
      if (response.statusCode == 206) {
        final match = RegExp(
          r'^bytes (\d+)-(\d+)/(\d+)$',
          caseSensitive: false,
        ).firstMatch(contentRange ?? '');
        if (match == null)
          throw const FormatException('下载响应缺少有效的 Content-Range');
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        total = int.parse(match.group(3)!);
        if (start != originalLength ||
            total <= 0 ||
            end != total - 1 ||
            end < start) {
          throw const FormatException('下载响应的范围与本地文件不匹配');
        }
      } else {
        // A 200 response ignored Range. Start over rather than append the full
        // response to the existing partial file.
        total = body.contentLength;
        if (total <= 0) throw const FormatException('下载响应缺少完整长度');
        received = 0;
      }
      await file.parent.create(recursive: true);
      if (response.statusCode == 200 && originalLength > 0) {
        replacement = File(
          '${file.path}.${DateTime.now().microsecondsSinceEpoch}.restart',
        );
      }
      sink = (replacement ?? file).openWrite(
        mode: received == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend,
      );
      onReceiveProgress?.call(received, total);
      int? last;
      await for (final chunk in body.stream) {
        if (received + chunk.length > total) {
          throw const FormatException('下载内容超过声明长度');
        }
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (last != now) {
          last = now;
          onReceiveProgress?.call(received, total);
        }
      }
      await sink.close();
      sink = null;
      if (received != total) throw const FormatException('下载内容不完整');
      if (replacement != null) {
        await replacement.rename(file.path);
        replacement = null;
      }
      _status = DownloadStatus.completed;
      onDone();
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (replacement != null && await replacement.exists()) {
        await replacement.delete();
      }
      if (_status == DownloadStatus.downloading) {
        _status = DownloadStatus.failDownload;
      }
      onDone(e);
    }
  }

  Future<void> cancel({required bool isDelete}) {
    if (!isDelete && _status == DownloadStatus.downloading) {
      _status = DownloadStatus.pause;
    }
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    return task;
  }
}
