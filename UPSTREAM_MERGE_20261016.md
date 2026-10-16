# 上游合并记录：2026-10-16

## 1. 合并前状态

| 项目 | 值 |
| --- | --- |
| fork | `Caun1112/PiliNara`，默认分支 `main` |
| upstream | `Starfallan/PiliNara`，默认分支 `main` |
| 当前功能分支 | `codex/ios-open-in-bilibili` |
| 合并前功能提交 | `22587a6bf161403b3ff41c8dccc66da052d9ffd6` |
| 合并前 fork main | `9825548386fc82b6fa79db7e18716699a95a02e6` |
| 上游目标 | `8d755f16b3f0929084f94b121e1ee38bb7af1686`，2026-10-15，2.1.6 |
| 共同基点 | `1807e22ed567293d7ef5fceb58dc4513d46f9cc5` |
| 分叉后的提交数 | fork 一侧 57，上游一侧 92；fork 数量包含既有定制和上次合并提交 |
| 工作区 | 仅有未跟踪的 `patch-retry.py`，保留在原工作树，不纳入提交 |

已重新 fetch 两个远端及 tags。当前功能分支比 main 多一个提交 `22587a6bf`，9 文件 +281/-47 行，实现 iOS 从官方 B 站打开当前视频/分 P/番剧集数。

## 2. 修改来源与重叠

相对共同基点，上游改动 231 文件，+7361/-3048 行；fork 改动 226 文件，+15238/-1361 行。29 文件两边都有修改，Git 合并预演发现 7 个文本冲突。

上游主要更新：

- 2.1.6、Flutter 3.47.7 及依赖更新；窗口、托盘和桌面缓存目录迁移。
- 同视频复用的 `pageOwner`/GlobalKey 所有权保护、控制栏布局、避免简介控制器重复初始化。
- iOS 原生系统画中画、桌面小窗边界与比例缓存、后台媒体上一集/下一集。
- OGV/番剧接口迁移、切季与侧栏播放列表、离线合集/番剧缓存和合集原顺序。
- 未开播直播聊天室、直播 SC 时间修复、“我的”新增分页、综合搜索过滤等。
- 修复上次报告中指出的弹幕数量与本地高能趋势并发互相取消问题（`57567d330`）。

fork 必须保留：

- 虎牙直播、本地关注、请求头、签名刷新、错误恢复、原播放器重开、横竖屏纹理连续性。
- B 站本地直播关注与短房间号归一化。
- 右侧半宽单手导航、悬浮返回、搜索聚焦、消息入口始终可见；macOS 隐藏相关浮钮。
- 评论全选、智能选评、排序、保存/复制、超长成图保护、空白退出和滚动暂停交互。
- 下载画质记忆、单视频紧凑弹窗、下载大小、换画质重下、缓存自动分享/取消与 FFmpeg。
- 自定义图标/启动页，以及 `path_provider_foundation: 2.5.1` 的 TrollStore 启动修复。
- iOS 官方 B 站打开：当前 cid 对应原始分 P 编号、当前 epId、重复点击锁、成功打开后才暂停；通用链接失败再尝试官方 scheme，不回退浏览器。PiliNara 入站 scheme 保持 `pilinara`，避免抢占官方 `bilibili`。

29 个重叠文件：

```text
.fvmrc
README.md
ios/Runner.xcodeproj/project.pbxproj
lib/common/widgets/image/image_save.dart
lib/main.dart
lib/pages/danmaku/view.dart
lib/pages/download/detail/widgets/item.dart
lib/pages/dynamics_detail/view.dart
lib/pages/live_room/controller.dart
lib/pages/live_room/view.dart
lib/pages/main/controller.dart
lib/pages/main/view.dart
lib/pages/mine/view.dart
lib/pages/video/controller.dart
lib/pages/video/download_panel/view.dart
lib/pages/video/introduction/pgc/controller.dart
lib/pages/video/introduction/pgc/view.dart
lib/pages/video/introduction/ugc/view.dart
lib/pages/video/reply/widgets/reply_item_grpc.dart
lib/pages/video/view.dart
lib/pages/video/widgets/header_control.dart
lib/plugin/pl_player/controller.dart
lib/plugin/pl_player/view/view.dart
lib/services/download/download_service.dart
lib/utils/app_scheme.dart
lib/utils/storage_key.dart
lib/utils/storage_pref.dart
pubspec.lock
pubspec.yaml
```

自动合并也已审阅：iOS 项目添加上游 `PipPlugin.swift` 编译项，同时保留 fork 的入站 scheme；iOS 的 UGC/PGC/横屏“B站打开”按钮保留，其他平台仍分享；旧页 owner 限制、虎牙恢复钩子、绿色启动页及依赖固定保留。

## 3. 安全操作与回滚

先将合并前 `22587a6bf` 推送到 `codex/backup-before-upstream-20261016`。在独立工作树 `/Users/caun/.codex/worktrees/merge-upstream-20261016/PiliNara` 的 `codex/merge-upstream-20261016` 分支合并，原工作树和未跟踪文件不参与冲突处理。

```sh
git fetch origin --prune --tags
git fetch upstream --prune --tags
git branch codex/backup-before-upstream-20261016 22587a6bf
git push origin codex/backup-before-upstream-20261016
# 在从 22587a6bf 建立的独立工作树：
git switch -c codex/merge-upstream-20261016
git merge --no-ff --no-commit upstream/main
# 审阅并解决冲突、完成依赖和测试后：
git add <已审查文件>
git commit
git push -u origin codex/merge-upstream-20261016
# 创建审查 PR；从同一提交运行 iOS/macOS GitHub Actions。
# 所有构建和产物验证成功后，以非 force push 快进 main：
git push origin codex/merge-upstream-20261016:main
```

未提交时可 `git merge --abort`。合并已推送时，使用 `git revert -m 1 <本次合并提交>` 创建反向提交，不改写共享历史。第一父提交是 `22587a6bf`，因此回滚上游仍保留 iOS 官方 B 站打开及全部此前定制；若要查看原 main，则使用 `982554838` 的独立工作树。后续若有 CI 修复提交，先按逆序 revert 修复提交，再 revert merge。

## 4. 七个冲突的原因及合并代码

### `.fvmrc`

双方版本有差异，采用上游 3.47.7，与 `pubspec.yaml` 对齐：

```json
{
  "flutter": "3.47.7"
}
```

### `lib/pages/mine/view.dart`

上游把 `PlayerBar(children:)` 改为 `left/right`；fork 将消息入口移出搜索条件。采用上游新布局及新增分页，保留消息入口始终显示，避免重复按钮。

```dart
return PlayerBar(
  left: widget.showBackBtn
      ? const Padding(
          padding: EdgeInsets.only(left: 8),
          child: BackButton(),
        )
      : const SizedBox.shrink(),
  right: Row(
    spacing: 5,
    mainAxisSize: .min,
    children: [
      if (!_mainController.hasHome) ...[
        IconButton(
          iconSize: iconSize,
          padding: padding,
          style: style,
          tooltip: '搜索',
          onPressed: () => Get.toNamed('/search'),
          icon: const Icon(Icons.search),
        ),
      ],
      if (GStorage.reply != null)
        IconButton(
          iconSize: iconSize,
          padding: padding,
          style: style,
          tooltip: '评论记录',
          onPressed: () => Get.toNamed('/myReply'),
          icon: const Icon(Icons.message_outlined),
        ),
      msgBadge(_mainController),
      // 无痕、切换账号、主题和设置各一份。
    ],
  ),
);
```

### `lib/pages/video/download_panel/view.dart`

base 的画质菜单位于 header，fork 已移到底部并增加持久化；上游修改相邻网络条件，导致旧菜单进入冲突。删除 header 旧菜单，保留底部唯一选择器，接入上游合集元数据、顺序和新下载接口。网络提示采用上游的仅移动端显示条件。

```dart
VideoQuality _quality =
    VideoQuality.fromCode(Pref.defaultDownloadVideoQa);
```

```dart
onSelected: (value) async {
  await Pref.setDefaultDownloadVideoQa(value.code);
  if (mounted) {
    setState(() => _quality = value);
  }
},
```

```dart
final autoFolderIndex = _seasonIndex(episode, parent);
_downloadService.downloadVideo(
  index: index,
  page: part,
  videoDetail: parent == null ? widget.videoDetail : null,
  videoArc: parent,
  videoQuality: _quality,
  autoFolderTitle: autoFolderInfo?.title,
  autoFolderSourceKey: autoFolderInfo?.sourceKey,
  autoFolderIndex: autoFolderIndex,
  seasonInfo: widget.videoDetail?.seasonInfo(index),
);
```

### `lib/pages/video/introduction/pgc/controller.dart`

fork 和上游在相同导入位置分别添加链接工具与 PGC 类型工具，两者均有调用，取并集；保留上游 OGV/换季逻辑和 fork 当前集跳转。

```dart
import 'package:PiliPlus/utils/bili_utils.dart';
import 'package:PiliPlus/utils/bilibili_video_link.dart';
```

```dart
@override
BilibiliVideoLink? get bilibiliVideoLink {
  final currentEpId = videoDetailCtr.epId;
  return currentEpId != null && currentEpId > 0
      ? BilibiliVideoLink.episode(epId: currentEpId)
      : super.bilibiliVideoLink;
}
```

同时删除重复的 foundation 导入，保留完整导入供 `kDebugMode`/`debugPrint` 使用。

### `lib/pages/video/view.dart`

fork 调整播放器布局和悬浮返回，上游为共享 controller 的列表 key 加所有权保护。预合并产生重复的局部 `AnimatedList`；不能直接选某一侧。保留 fork 完整 Stack 和互动视频选项层，仅保留一份列表，并将列表 key 接入上游保护：

```dart
child: AnimatedList(
  padding: EdgeInsets.zero,
  key: _ownedKey(videoDetailController.listKey),
  reverse: true,
  shrinkWrap: true,
  initialItemCount: videoDetailController.listData.length,
  itemBuilder: (context, index, animation) {
    return videoDetailController.buildItem(
      videoDetailController.listData[index],
      animation,
    );
  },
),
```

同时检查 pageOwner 在 initState/didPopNext 认领、dispose 条件释放、非 owner 不创建播放器、不挂共享 GlobalKey/scrollCtr。fork 的 Obx 先读 `isFullScreen` 和 macOS 按钮隐藏仍保留。

### `lib/plugin/pl_player/view/view.dart`

fork 使用统一生命周期判定，上游添加 iOS PiP 播放保护。保留 fork 暂停/恢复与自动只听生命周期转发，在入口融合上游保护：

```dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  // Keep playing in the PiP window.
  if (Platform.isIOS && IOSPipHelper.isActive) return;
  late final player = plPlayerController.videoPlayerController;
  if (plPlayerController.shouldAutoPauseForLifecycle(state)) {
    if (player != null && player.state.playing) {
      _pauseDueToPauseUponEnteringBackgroundMode = true;
      player.pause();
    }
  } else {
    if (_pauseDueToPauseUponEnteringBackgroundMode) {
      _pauseDueToPauseUponEnteringBackgroundMode = false;
      player?.play();
    }
    plPlayerController.handleAutoAudioOnlyLifecycle(state);
    return;
  }
  plPlayerController.handleAutoAudioOnlyLifecycle(state);
}
```

### `pubspec.lock`

上游依赖升级与 fork 本地直播/导出依赖重叠。融合上游版本和 fork 包后，用 Flutter 3.47.7 重新解析并强制验证；不整份覆盖为 ours/theirs。

```yaml
dependencies:
  ffmpeg_kit_flutter_new: ^4.3.2
  simple_live_core:
    path: packages/simple_live_core
dependency_overrides:
  path_provider_foundation: 2.5.1
```

上游 cached_network_image_ce 来源迁移、nativeapi、window_manager、tray_manager、OGV 所需依赖按新清单解析；TrollStore 的版本固定和本地 tars_dart 保留。

### 自动合并后的接口兼容修复

静态分析还发现一处 Git 没标记为文本冲突的旧变量引用：上游移除了 `onDownload()` 的局部 `ugcIntroController`，fork 的单视频弹窗分支已自动更新，但底部批量面板仍引用该旧变量。两处统一采用上游按视频类型取得 controller 的方式：

```dart
ugcIntroController: isUgc ? ugcIntroCtr : null,
```

该修改保证普通视频和番剧两种下载入口均可编译，继续保留 fork 的单视频紧凑弹窗与分享选项。

## 5. 验证与交付步骤

本地使用独立的 Flutter 3.47.7 SDK，并对本地验证专用的 material_ui 副本应用项目补丁，避免修改原工作树使用的 SDK/依赖。执行：

```sh
actionlint .github/workflows/ios.yml .github/workflows/mac.yml
plutil -lint ios/Runner/Info.plist ios/Runner.xcodeproj/project.pbxproj
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
git diff --cached --check -- . ':!*.patch'
```

嵌入式 `.patch` 文本中的空格前缀/上下文空行保留，避免改变补丁语法；源码与配置另做 whitespace 和冲突标记检查。

iOS/macOS 均通过 GitHub Actions 在 macOS 26 runner 使用同一最终提交编译。分别保存实际 pubspec.lock、分析与测试日志、源码 SHA 和安装包 SHA-256。

- iOS：`flutter build ios --release --no-codesign --dart-define-from-file=pili_release.json --no-pub`，采用 `Payload/Runner.app` 结构生成未签名 IPA，检查 ZIP 完整性、无 provisioning profile、版本与源码一致；现有工作流另提供同内容 TIPA。
- macOS：`flutter build macos --release --dart-define-from-file=pili_release.json --no-pub`，检查可执行文件、Info.plist 与架构，使用 `ditto --keepParent` 生成 `.app.zip`，DMG 为可选附加格式。
- 下载产物后核对本地及 GitHub 资产 SHA-256；macOS 在不覆盖已安装应用的目录尝试启动，记录启动检查结果。
- CI 和产物检查成功后快进更新 fork main，创建/更新本轮 GitHub Release；保持备份分支及审查 PR。

设备与功能回归清单：

1. TrollStore/iPhone 冷启动；后台播放、iOS 系统 PiP、关闭小窗与返回页面。
2. 同视频复用、PiP 展开后返回旧页、侧栏、SponsorBlock 提示和互动视频选项，检查 GlobalKey/灰屏问题。
3. iOS 官方 B 站打开：单 P、多 P 非首 P、倒序、番剧切集/换季、未加载元数据、未安装官方 App、连续点击和返回恢复；同时开启自动 PiP 时检查是否残留暂停小窗。
4. 虎牙横竖屏、Texture 连续性、前后台、断网恢复与切线；B 站本地关注刷新、持久化与取消。
5. 下载画质记忆、相同画质复用/不同画质重下、合集顺序与离线元数据、番剧缓存、导出分享及取消。
6. 评论全选/智能选评/排序、保存/复制、超长成图保护、空白退出及滚动停止。
7. macOS 播放、窗口/托盘迁移、原桌面缓存目录、隐藏浮钮、单手底栏、搜索和“我的”消息入口。

编译、单元/组件测试和启动检查不能替代真机安装、登录、直播网络及完整播放回归。最终实际执行结果、CI 链接和产物哈希以本轮 Release 的验证记录为准。


### 已完成的本地验证

- Flutter 3.47.7 `pub get --enforce-lockfile` 成功。
- 全量 128 项测试通过，包含官方 B 站链接、搜索过滤、评论成图、虎牙布局/生命周期、本地关注、缓存画质/大小、导航及人像蒙版几何。
- 全项目静态分析 0 error、5 warning、71 info；沿用 CI 非致命 warning/info 设置，日志保留实际结果。
- iOS plist 与 Xcode 工程结构检查、iOS/macOS 工作流 actionlint、源码 whitespace 与冲突标记检查通过。
- 修复自动合并残留的下载 controller 旧变量后，已重新执行完整分析和全量测试。

正式双平台编译、安装包校验与启动检查由最终 Release 的构建及验证记录说明；此处本地测试结果不代表真机回归完成。
