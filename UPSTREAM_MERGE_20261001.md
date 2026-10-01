# 上游合并记录：2026-10-01

## 1. 合并前状态

| 项目 | 状态 |
| --- | --- |
| fork | `https://github.com/Caun1112/PiliNara.git`，默认分支 `main` |
| 上游 | `https://github.com/Starfallan/PiliNara.git`，默认分支 `main` |
| 当前功能分支 | `codex/comment-select-all-bili-local-follow` |
| fork 当前提交 | `8f4375c7bf449388b604e233b5bff72281a2750c` |
| fork main | `542a9800a52690dc988eb56801172c80434d6729` |
| 本次上游目标 | `1807e22ed`，2026-09-26，2.1.5.1 - Pearl 更新日志 |
| 共同基点 | `bcf0939cc0550446b246ee09abe15d7f4d3dd88d` |
| 分叉后的提交数 | 当前 fork 55，上游 106；其中 fork 当前分支比 main 多 4 个提交 |
| 本地未提交文件 | 只有未跟踪的 `patch-retry.py`，留在原工作树，不纳入合并 |

已先 fetch 两个远端及 tags。上游更新涉及 224 文件，+27399/-16481 行；fork 相对共同基点涉及 216 文件，+14559/-1303 行。大量上游行数来自生成的 protobuf 文件。

上游更新日志为 2.1.5.1，但 `pubspec.yaml` 保持上游的 `version: 2.1.5+1`。构建脚本将 build number 替换为最终提交计数，产物文件名因此使用 2.1.5。

## 2. 修改来源与重叠

上游主要新增/修复：弹幕人像防挡、分 P 弹幕数、系统与应用内 PiP、音频中断和音频延迟、媒体控制状态、搜索综合结果、电竞信息、AI 推理内容/思考强度/滚动、渐变背景、自定义主题种子、动态视频过滤、桌面 WebView，以及 Flutter 3.47.5 和依赖更新。

fork 保留的定制：

- 虎牙直播与本地关注、请求头、重新获取签名地址、原播放器恢复、横竖屏纹理连续性；本地 `simple_live_core`/`tars_dart`。
- 固定导航顺序、右侧半宽底栏、搜索自动聚焦、搜索框位置与单手悬浮返回按钮。
- 下载画质记忆、大小显示、不同画质重下、缓存自动分享/取消与 FFmpeg 导出。
- 评论智能选评、全选、手动排序、复制、图片内存保护、滚动停止和空白退出。
- 自定义图标、启动页与 `path_provider_foundation: 2.5.1` 的 TrollStore 启动修复。
- macOS 隐藏返回/动态回复浮钮，以及横屏/PiP `Obx` 订阅修复。
- 无需登录的 B 站本地直播关注、短房间号归一化、刷新与持久化。

当前功能分支额外 4 个提交均保留：

| 提交 | 内容 |
| --- | --- |
| `2a20f1813` | 横屏/PiP 在条件短路前读取 `isFullScreen`，避免无 GetX 订阅导致灰屏 |
| `d183f6359` | macOS 隐藏全局/视频返回与动态回复浮钮 |
| `82217c324` | 评论全选、移除故事卡标题、B 站本地直播关注、macOS app 压缩包 |
| `8f4375c7b` | 评论成图页点图片外空白退出，内容区/选评/惯性滚动点击不误退出 |

25 个重叠文件如下，其中 9 个出现 Git 文本冲突：

```text
.fvmrc
.gitignore
lib/common/widgets/image/image_save.dart
lib/main.dart
lib/pages/download/detail/widgets/item.dart
lib/pages/dynamics_detail/view.dart
lib/pages/live_room/controller.dart
lib/pages/live_room/view.dart
lib/pages/main/controller.dart
lib/pages/main/view.dart
lib/pages/mine/view.dart
lib/pages/save_panel/view.dart
lib/pages/search/view.dart
lib/pages/video/controller.dart
lib/pages/video/reply/widgets/reply_item_grpc.dart
lib/pages/video/view.dart
lib/pages/video/widgets/header_control.dart
lib/plugin/pl_player/controller.dart
lib/plugin/pl_player/view/view.dart
lib/utils/app_scheme.dart
lib/utils/storage.dart
lib/utils/storage_key.dart
lib/utils/storage_pref.dart
pubspec.lock
pubspec.yaml
```

自动合并的播放器/直播文件已另行检查：保留 fork 生命周期、虎牙错误/结束回调、网络请求头、`reopenLiveSource()`、横屏布局与 macOS 按钮控制，同时接入上游 `PlayerStatus` API、手动 PiP 和人像蒙版。

## 3. 可审查、可回滚的操作

在原功能分支上创建并推送 `codex/backup-before-upstream-20261001`，保存合并前完整历史。独立工作树位于 `/Users/caun/.codex/worktrees/merge-upstream-20261001/PiliNara`，分支为 `codex/merge-upstream-20261001`。原工作树和未跟踪文件不参与冲突处理。

操作顺序：

```sh
git fetch origin --prune --tags
git fetch upstream --prune --tags
git branch codex/backup-before-upstream-20261001 8f4375c7b
git push origin codex/backup-before-upstream-20261001
# 在独立工作树内：
git switch -c codex/merge-upstream-20261001
git merge --no-ff --no-commit upstream/main
# 逐文件融合、依赖验证、静态分析、回归测试后：
git add <已审查文件>
git commit
git push -u origin codex/merge-upstream-20261001
# 创建 PR，使用同一提交在 GitHub Actions 构建 iOS/macOS。
# CI 成功后，以普通、非 force push 快进更新 main。
git push origin codex/merge-upstream-20261001:main
```

合并尚未提交时可 `git merge --abort`。提交已共享后，使用 `git revert -m 1 <本次 merge 提交>` 生成反向提交；合并提交的第一父提交是 `8f4375c7b`，因此仍保留合并前全部 fork 定制。后续构建修复若有独立提交，需要按逆序先 revert。需要审查旧版时可从备份分支创建新工作树，不重写远端历史。

## 4. 九个冲突的原因与结果

### `.fvmrc`

双方升级到不同 Flutter 版本。采用上游 3.47.5，并与 `pubspec.yaml` 对齐，保留 Dart SDK `>=3.13.0`。

```json
{
  "flutter": "3.47.5"
}
```

### `.gitignore`

双方在文件尾添加不同规则。合并 fork 的本地 IPA 忽略与上游 `.agents` 忽略，并增加 TIPA 忽略。

```gitignore
# 本地生成的未签名 iOS 安装包
/*.ipa
/*.tipa
.agents
```

### `lib/common/widgets/image/image_save.dart`

fork 将“保存封面”改为“复制封面”；上游将 SmartDialog 改为 Navigator 的 `PublishRoute`，并修复关闭弹窗。保留复制动作，使用对应路由关闭调用。

```dart
tooltip: '复制封面图',
onPressed: () {
  Get.back();
  ImageUtils.copyImg(cover);
},
icon: const Icon(Icons.copy_outlined),
```

### `lib/pages/dynamics_detail/view.dart`

fork 增加 `Platform` 导入控制 macOS 浮钮；上游增加 `Timer` 和刷新组件。两者并存。

```dart
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
```

```dart
if (!controller.showDynActionBar) {
  return Platform.isMacOS ? const SizedBox.shrink() : fabButton;
}
```

另一个回复按钮也继续受 `if (!Platform.isMacOS)` 控制。

### `lib/pages/main/view.dart`

fork 修改底栏右侧对齐；上游提取 `MainLayout` 以叠加渐变背景。将对齐属性移入上游结构，保留两种能力。

```dart
final mainLayout = MainLayout(
  sideBar: sideBar,
  bottomNav: bottomNav,
  bottomNavAlignment: _mainController.floatingNavBar
      ? Alignment.bottomRight
      : Alignment.bottomCenter,
  body: Padding(padding: padding, child: child),
);
child = Material(
  child: Pref.enableGradientBg
      ? Stack(
          children: [Positioned.fill(child: _gradientBg()), mainLayout],
        )
      : mainLayout,
);
```

右对齐、屏幕 50% 宽的 `FloatingNavigationBar` 也保留。

### `lib/pages/mine/view.dart`

fork 将消息入口移出 `!hasHome` 条件；上游重构为 `PlayerBar` 中左右两组操作，自动合并重复了按钮。采用上游布局，消息入口始终保留，各按钮仅一份。

```dart
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
```

### `lib/pages/save_panel/view.dart`

fork 已重构成图动作；上游仅将文件名日期格式统一为缓存格式。保留完整 fork 流程，仅替换命名。当前 fork 动作是保存/复制，未重新引入已删除的系统分享动作。

```dart
final picName =
    "${Constants.appName}_${itemType}_${DateFormatUtils.only0_9.format(DateTime.now())}";
switch (action) {
  case _PicAction.copy:
    await FlutterClipboard.copyImage(pngBytes);
    SmartDialog.dismiss();
    SmartDialog.showToast('已复制图片');
  case _PicAction.save:
    final result = await ImageUtils.saveByteImg(
      bytes: pngBytes,
      fileName: picName,
    );
    if (result?.isSuccess == true) {
      Get.back();
    }
}
```

### `lib/plugin/pl_player/controller.dart`

fork 改动截图编码格式表达；上游修复关闭截图弹窗及释放 `ui.Image`。采用上游生命周期处理，虎牙相关代码继续保留。

```dart
final dispose = await showDialog<bool>(
  context: Get.context!,
  builder: (context) => GestureDetector(
    onTap: () async {
      Get.back(result: false);
      final bytes = await image.toByteData(format: .png);
      image.dispose();
      // 继续保存 bytes；false 避免外层重复释放。
    },
    // 其余截图预览布局保留。
  ),
);
if (dispose ?? true) image.dispose();
```

### `pubspec.lock`

上游依赖升级与 fork 的本地直播包/原生资产兼容修复重叠。先融合上游依赖版本与 fork 包，再用 Flutter 3.47.5 解析并校验锁文件。避免仅对整个 lock 使用 ours/theirs。

```yaml
dependencies:
  ffmpeg_kit_flutter_new: ^4.3.2
  simple_live_core:
    path: packages/simple_live_core

dependency_overrides:
  path_provider_foundation: 2.5.1
```

最终 lock 保留 `ffmpeg_kit_flutter_new: 4.6.2`、`simple_live_core: 1.0.3-pilinara.1`、本地 `tars_dart: 0.1.0` 和 `path_provider_foundation: 2.5.1`。不再需要的原生资产相关传递依赖由依赖解析器移除。

## 5. 验证与构建

本地先核对冲突标记、`git diff --check`、修改的 iOS/macOS workflow 的 `actionlint`、Flutter 3.47.5 的依赖锁文件一致性；在单独 SDK 和单独的 material_ui 副本中应用项目补丁，避免改动原工作树使用的 SDK/界面依赖。然后运行：

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
```

GitHub Actions 在 macOS 26 runner 分别构建 iOS 和 macOS，使用同一最终源码提交，记录实际依赖锁文件、分析/测试日志、`SOURCE-COMMIT.txt` 和 SHA-256。

iOS：`flutter build ios --release --no-codesign --dart-define-from-file=pili_release.json --no-pub`；使用 `Payload/Runner.app` 结构生成 IPA/TIPA，检查 ZIP 完整性、无 embedded provisioning profile，以及 IPA/TIPA 字节一致性。Framework 继续采用现有 ad-hoc 签名步骤。

macOS：`flutter build macos --release --dart-define-from-file=pili_release.json --no-pub`；检查 `Contents/MacOS/PiliNara` 可执行文件、Info.plist 和二进制架构，使用 `ditto --keepParent` 生成 `.app.zip`。DMG 继续作为可选附加格式，制作失败不阻断 `.app` 交付。

运行/设备回归清单：

1. iPhone/TrollStore 冷启动、后台音频中断、恢复播放；确认不再卡启动页。
2. 视频横竖屏/PiP/分 P 切换、全屏手动小窗、蒙版缩放/镜像；macOS 播放正常且返回/动态回复浮钮隐藏。
3. 虎牙横竖屏、前后台、断网恢复、手动切线；播放器 Texture 身份与播放连续性。
4. B 站短房间号关注、重启持久化、刷新与取消关注；取消后的异步结果不能重新加入。
5. 评论全选/取消/再次全选、智能推荐与排序、超长图片保护、图片内部不退出、空白退出、惯性滚动第一次点击仅停止。
6. 下载画质记忆、相同画质复用/不同画质重下、自动分享取消与完成导出。
7. 渐变背景开/关、右侧半宽导航、搜索键盘自动弹出、小屏/大字体的“我的”操作栏与消息入口。

构建和自动化测试不能替代真机登录、TrollStore 安装、直播网络和音频设备回归；这些检查必须区分“已执行”与“待设备验证”。

## 6. 已知范围与风险

- `COMMENT_SAVE_INTERACTION_PROGRESS.md` 是历史记录，关于仅明确关闭退出、故事卡标题的描述已被最新 fork 提交替代；当前代码及测试为准。
- README 的许多“Fork 特性”描述的是 Starfallan 相对 PiliPlus 的功能，并不全部是 Caun1112 独有修改。
- 上游新 `_fetchAllDanmaku()` 没有给 `_dmElemsCid` 赋值：同时启用弹幕数和本地高能趋势时，可能重复请求或相互取消。该代码在上游已存在，本次保持非冲突实现；需要后续单独修复并验证切 P 异步回写。
- 旧 FFmpeg 重连参数在 fork 的 `7db7054da` 已主动撤销，本次没有恢复，继续采用当前 fork 最新的虎牙恢复策略。

最终执行结果、Actions 链接、产物哈希和下载地址随 Release 记录一起保存。


### 已完成的本地检查

- Flutter 3.47.5 `pub get --enforce-lockfile` 通过；依赖锁文件已稳定。
- 全部 93 项测试通过，包括评论成图、B 站本地关注、虎牙生命周期/布局/返回按钮、下载画质/大小、导航、搜索、已删除账号与上游人像蒙版几何测试。
- 全项目静态分析无 error；78 项 warning/info 以日志为准，使用与现有 CI 相同的非致命 warning/info 设置。
- 修改的 `ios.yml`、`mac.yml` 的 actionlint 通过；`git diff --check` 通过，9 文件冲突标记均已清理。
- 聚合 `build.yml` 的 actionlint 另有既有 ShellCheck SC2129 风格提示（Android 写 key 步骤），本次未修改该流程。

CI 编译、产物校验和设备回归的执行状态由最终 Release 附带的记录说明，不由本地测试结果推定。
