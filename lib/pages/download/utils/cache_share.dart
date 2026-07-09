import 'dart:io';

import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

abstract final class CacheShare {
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
