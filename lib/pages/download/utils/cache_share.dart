import 'dart:io';

import 'package:PiliPlus/common/widgets/custom_toast.dart';
import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

abstract final class CacheShare {
  static const _progressTagPrefix = 'cache-share-progress-';
  static final Map<int, ValueChanged<BiliDownloadEntryInfo>>
  _pendingShareCallbacks = {};
  static final Set<int> _cancellingCids = {};

  static Future<void> shareAfterDownload(
    DownloadService downloadService,
    int cid,
  ) async {
    await downloadService.waitForInitialization;
    for (final entry in downloadService.downloadList) {
      if (entry.cid == cid) {
        await shareEntry(entry);
        return;
      }
    }

    _showDownloadProgress(downloadService, cid);
    if (_pendingShareCallbacks.containsKey(cid)) {
      return;
    }

    late final ValueChanged<BiliDownloadEntryInfo> callback;
    callback = (entry) {
      if (entry.cid != cid) {
        return;
      }
      downloadService.completedEntryNotifier.remove(callback);
      _pendingShareCallbacks.remove(cid);
      _shareCompletedEntry(entry);
    };
    _pendingShareCallbacks[cid] = callback;
    downloadService.completedEntryNotifier.add(callback);
  }

  static String _progressTag(int cid) => '$_progressTagPrefix$cid';

  static void _showDownloadProgress(
    DownloadService downloadService,
    int cid,
  ) {
    final tag = _progressTag(cid);
    if (SmartDialog.checkExist(tag: tag)) {
      return;
    }
    SmartDialog.show(
      tag: tag,
      alignment: Alignment.bottomCenter,
      usePenetrate: true,
      clickMaskDismiss: false,
      bindPage: false,
      builder: (_) => _DownloadProgressPill(
        downloadService: downloadService,
        cid: cid,
      ),
    );
  }

  static Future<void> _shareCompletedEntry(
    BiliDownloadEntryInfo entry,
  ) async {
    await SmartDialog.dismiss(tag: _progressTag(entry.cid));
    await shareEntry(entry);
  }

  static Future<void> _cancelDownloadAndShare(
    DownloadService downloadService,
    int cid,
  ) async {
    if (!_cancellingCids.add(cid)) {
      return;
    }
    try {
      final callback = _pendingShareCallbacks.remove(cid);
      if (callback != null) {
        downloadService.completedEntryNotifier.remove(callback);
      }

      BiliDownloadEntryInfo? entry;
      final current = downloadService.curDownload.value;
      if (current?.cid == cid) {
        entry = current;
      } else {
        for (final item in downloadService.waitDownloadQueue) {
          if (item.cid == cid) {
            entry = item;
            break;
          }
        }
      }
      if (entry != null) {
        await downloadService.deleteDownload(
          entry: entry,
          removeQueue: true,
        );
      }

      await SmartDialog.dismiss(tag: _progressTag(cid));
      SmartDialog.showToast('已取消缓存和自动分享');
    } finally {
      _cancellingCids.remove(cid);
    }
  }

  /// 用 FFmpeg 合并缓存的音视频流后调起系统分享面板
  static Future<void> shareEntry(BiliDownloadEntryInfo entry) async {
    try {
      SmartDialog.showLoading(msg: '正在导出视频');

      final typeTag = entry.typeTag;
      if (typeTag == null) throw '缓存信息不完整';
      final videoDir = path.join(entry.entryDirPath, typeTag);
      final isMp4 = entry.mediaType == 1;
      final videoFile = File(
        path.join(
          videoDir,
          isMp4 ? PathUtils.videoNameType1 : PathUtils.videoNameType2,
        ),
      );
      if (!videoFile.existsSync()) throw '视频文件不存在';
      final audioFile = File(path.join(videoDir, PathUtils.audioNameType2));
      final hasAudio = !isMp4 && entry.hasDashAudio && audioFile.existsSync();

      final workDir = Directory(path.join(tmpDirPath, 'cache_share'));
      if (!workDir.existsSync()) workDir.createSync(recursive: true);
      final mergedPath = path.join(workDir.path, 'merged_output.mp4');
      final fixedPath = path.join(workDir.path, 'fixed.mp4');

      // 合并视频流与音频流(流复制,不转码)
      await _run([
        '-y',
        '-i',
        videoFile.path,
        if (hasAudio) ...['-i', audioFile.path],
        '-c',
        'copy',
        mergedPath,
      ]);

      // HEVC tag 为 hev1 时修正为 hvc1,否则系统相册/分享目标可能无法识别
      String sharePath = mergedPath;
      if (await _isHev1(mergedPath)) {
        await _run([
          '-y',
          '-i',
          mergedPath,
          '-c',
          'copy',
          '-tag:v',
          'hvc1',
          fixedPath,
        ]);
        sharePath = fixedPath;
      }

      SmartDialog.dismiss();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(sharePath, mimeType: 'video/mp4')],
          sharePositionOrigin: await ShareUtils.sharePositionOrigin,
        ),
      );
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast('分享导出失败: $e');
    }
  }

  static Future<void> _run(List<String> args) async {
    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      throw 'FFmpeg 执行失败(code: ${returnCode?.getValue()})';
    }
  }

  static Future<bool> _isHev1(String filePath) async {
    final session = await FFprobeKit.getMediaInformation(filePath);
    final streams = session.getMediaInformation()?.getStreams();
    if (streams == null) return false;
    for (final stream in streams) {
      if (stream.getType() == 'video') {
        return stream.getStringProperty('codec_tag_string') == 'hev1';
      }
    }
    return false;
  }
}

class _DownloadProgressPill extends StatelessWidget {
  const _DownloadProgressPill({
    required this.downloadService,
    required this.cid,
  });

  final DownloadService downloadService;
  final int cid;

  static String _formatMb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Obx(() {
      final current = downloadService.curDownload.value;
      BiliDownloadEntryInfo? entry = current?.cid == cid ? current : null;
      if (entry == null) {
        for (final item in downloadService.waitDownloadQueue) {
          if (item.cid == cid) {
            entry = item;
            break;
          }
        }
      }
      final downloadedBytes = entry?.downloadedBytes ?? 0;
      final totalBytes = entry?.totalBytes ?? 0;
      final progress = totalBytes == 0
          ? null
          : (downloadedBytes / totalBytes).clamp(0.0, 1.0);
      final status = entry?.status.message ?? '准备缓存';

      return Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 30,
        ),
        child: Material(
          color: colorScheme.primaryContainer.withValues(
            alpha: CustomToast.toastOpacity,
          ),
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => CacheShare._cancelDownloadAndShare(
              downloadService,
              cid,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '完成后将自动打开分享',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$status · ${_formatMb(downloadedBytes)} / '
                    '${totalBytes == 0 ? '-- MB' : _formatMb(totalBytes)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: colorScheme.primary,
                      backgroundColor: colorScheme.onPrimaryContainer
                          .withValues(alpha: 0.16),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '点击取消下载与分享',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
