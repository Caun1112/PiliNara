# PiliNara 上游合并审查记录（2026-09-10）

## 1. 初始状态

- fork：`https://github.com/Caun1112/PiliNara.git`；上游：`https://github.com/Starfallan/PiliNara.git`。
- 本地分支 `main`：`cccb47d43`；fork 远端 `main`：`80558c40e`。本地比远端超前 129 个提交，远端没有本地缺少的提交。
- 本次固定合并上游 `main`：`bcf0939cc`（2.1.3），共同基点：`5405e863f`。
- 基点之后 fork 独有 46 个提交，上游独有 68 个提交。129 是相对 fork 远端的计数，46 是相对上游的计数，不能混用。
- 工作区有 71 个已跟踪文件改动、14 个未跟踪文件。84 个应用相关文件已保存到 `0c7102e23`；无关工具 `patch-retry.py` 保留本地并备份，未上传。
- 未执行 reset --hard、强制推送或 rebase。

## 2. 来源与重叠

上游修改 137 个文件，主要涉及后台自动只听音频及恢复、直播弹幕屏蔽、画面参数、画质可用性、账号隔离、动态/评论 API、首页预览、Linux 及依赖更新。

fork 已提交定制涉及 126 个文件，主要为虎牙直播及关注、重连、右侧单手导航和搜索、悬浮返回、智能选评与评论图片分享、下载画质记忆/大小/替换/导出，以及 TrollStore 兼容处理。未提交定制另包括跨平台图标、绿色启动页及横竖屏连续播放修复。

双方已提交修改重叠 13 个文件：

- `README.md`
- `lib/pages/home/view.dart`
- `lib/pages/main/controller.dart`
- `lib/pages/save_panel/view.dart`
- `lib/pages/video/controller.dart`
- `lib/pages/video/widgets/header_control.dart`
- `lib/plugin/pl_player/controller.dart`
- `lib/plugin/pl_player/view/view.dart`
- `lib/services/download/download_service.dart`
- `lib/utils/storage_key.dart`
- `lib/utils/storage_pref.dart`
- `pubspec.lock`
- `pubspec.yaml`

未提交修改与上游的交集只有 `pubspec.yaml`，图标配置与版本/依赖更新位于不同区段，自动合并成功。

## 3. 安全方案与实际操作

先将完整工作区二进制 diff 与所有未跟踪文件保存到本目录，再创建独立 worktree，原工作区在合并与构建期间保持不变。随后提交应用相关未提交修改，使用三方合并，不使用整批 ours/theirs 覆盖。

```sh
git fetch origin --prune
git fetch upstream --prune
git branch codex/backup-before-upstream-20260910 cccb47d43
git worktree add -b codex/merge-upstream-20260910 /Users/caun/code/PiliNara-merge-20260910 cccb47d43
# 在独立 worktree 应用备份的 tracked-worktree.patch，并复制应用相关未跟踪文件
# 提交这些内容后建立工作区快照备份：
git branch codex/backup-workspace-20260910 0c7102e23
git merge --no-ff --no-commit bcf0939cc
# 逐文件解决冲突、分析和测试后提交：912e889e4
# 构建工作流与测试环境修复另存为提交：8e503f236
```

两条备份分支与合并分支均已推送到 fork。`merge-resolution.diff` 是 `git show --remerge-diff 912e889e4` 的完整结果，可直接审查人工冲突解决。`merged-vs-upstream.diff` 展示合并后保留的 fork 定制。

验证成功后已使用普通快进更新本地与远端 `main` 到 `542a9800a52690dc988eb56801172c80434d6729`，没有强制推送。更新前再次核对原工作区二进制 diff、未跟踪文件内容和远端 main，确认没有并发改动。

### 回滚方式

合并尚未提交时可以 `git merge --abort`；本次已经提交，应使用备份分支或新增 revert 提交。

```sh
# 查看合并前的已提交状态（不会修改 main）
git worktree add /tmp/PiliNara-before-merge codex/backup-before-upstream-20260910
# 查看包含所有应用工作区改动的合并前快照
git worktree add /tmp/PiliNara-workspace-before-merge codex/backup-workspace-20260910
# main 上撤回本次更新：新建回滚分支，按倒序撤回 CI 提交和合并提交
# 此处保留 0c7102e23 中原有的图标及横竖屏修改。
git switch -c codex/revert-upstream-20260910 origin/main
git revert 542a9800a
git revert fe88782d1
git revert 8e503f236
git revert -m 1 912e889e4
# 审查、验证后普通推送，不强制回退远端分支。
```

## 4. 逐文件冲突解决与最终片段

### lib/pages/home/view.dart

fork 将搜索入口移到底部，上游为首页预览加入 `HomePreviewScope`。保留底部搜索，不恢复旧顶部搜索栏，同时包裹预览作用域，防止设置页预览与实际首页重复使用刷新 Key。

```dart
    return HomePreviewScope(
      enabled: widget.preview,
      child: Column(
        children: [
          tabBar,
          Expanded(
            child: onBuild(
              tabBarView(
                controller: _homeController.tabController,
                children: _homeController.tabs.map((e) => e.page).toList(),
              ),
            ),
          ),
        ],
      ),
    );
```

### lib/pages/main/controller.dart

冲突位于导航配置：fork 强制固定四个单手入口，上游在原有可配置导航逻辑中简化了映射表达式。保留 fork 固定顺序；上游未读消息改为可空值、清空通知与切换账号刷新等修改仍完整保留。

```dart
  void setNavBarConfig() {
    navigationBars = _fixedNavigationBars;
    final defPage = Pref.defaultHomePage;
    selectedIndex.value = math.max(0, navigationBars.indexOf(defPage));
  }
```

### lib/pages/save_panel/view.dart

fork 重写了初始化和完整评论加载；上游仅将动态链接解析结果赋给 `uri`。fork 已有等价的 `uri = parseDyn(i)`，因此该文件最终与 fork 工作区快照完全一致。保留滚动保护、选评理由、排序、故事卡、完整跟评加载。

```dart
_scrollController = ScrollController(
  onAttach: (position) {
    position.isScrollingNotifier.addListener(_handleScrollActivity);
  },
  onDetach: (position) {
    position.isScrollingNotifier.removeListener(_handleScrollActivity);
  },
);
_item = widget.item;
// 评论分支保留完整加载与智能选评逻辑；动态分支保留链接赋值：
if (_item case final DynamicItemModel i) {
  uri = parseDyn(i);
  if (kDebugMode) debugPrint(uri);
}
```

### lib/plugin/pl_player/controller.dart

同一播放源打开位置，fork 新增虎牙 HTTP headers，上游新增直播不可 seek 的断言。两者都保留，不互相覆盖；上游后台音频状态机、音量标准化和画面参数均保留。

```dart
    if (dataSource case NetworkSource(:final httpHeaders)) {
      _setNetworkSourceHeaders(player, httpHeaders);
    }

    assert(!isLive || seekTo == null);
    await player.open(
      Media(
        video,
        start: seekTo,
        extras: extras.isEmpty ? null : extras,
      ),
      play: false,
    );
    applyVideoPictureParameters(player);
```

此外，虎牙没有接入纯音频源切换回调，不能进入上游需要此回调的自动只听状态；继续使用原有后台播放行为。虎牙重新拉流后重新应用画面参数。

```dart
if (isLive && onNeedsPlayerInit == null) return false;
// reopenLiveSource 中 player.open 完成后：
applyVideoPictureParameters(player);
```

### pubspec.lock（及自动合并的 pubspec.yaml）

上游将 media-kit 切到 native 分支并更新 jnigen，fork 增加 FFmpeg、虎牙本地包并固定 path_provider_foundation 2.5.1。先保留两侧意图，再使用 Flutter 3.47.2 重新解析锁文件；解析器移除旧 FFI 原生资产依赖，而非手工选择旧版全量锁文件。保留锁文件中的实际 Git resolved-ref。

```yaml
version: 2.1.3+1
environment:
  sdk: ">=3.13.0"
  flutter: 3.47.2
# 以下分别保留在对应的 dependencies / dependency_overrides 中：
dependencies:
  ffmpeg_kit_flutter_new: ^4.3.2
  simple_live_core:
    path: packages/simple_live_core
dependency_overrides:
  path_provider_foundation: 2.5.1
  media_kit:
    git:
      url: https://github.com/Starfallan/media-kit.git
      path: media_kit
      ref: native
```

同时保留 `#65A981` 启动页、全部平台图标，以及 fork 的所有其他依赖和功能。

## 5. 验证步骤与已执行结果

- 祖先关系：上游 `bcf0939cc` 和原 fork `cccb47d43` 均为合并后 HEAD 的祖先；全部提交历史保留。
- 工作区保留检查：84 个应用相关变更中，只有 `pubspec.yaml` 因上游版本/依赖发生进一步变化，其余文件逐字节保留。
- 对未被上游修改的文件，额外变更仅为 iOS 工作流、评论测试初始化，以及下载音轨 ID 适配上游非空类型。
- 本地环境：Flutter 3.47.2 / Dart 3.13.2，使用仓库要求的 Flutter 补丁，UI 包在本审计目录内建立隔离副本并应用上游补丁，不覆盖用户现有依赖副本。
- 本地静态分析：0 错误，78 项 warning/info；使用 `--no-fatal-infos --no-fatal-warnings`，不屏蔽 error。两处因上游 ID 非空化导致的多余 `!` 已处理。
- 本地全量测试：52 项全部通过。首次遇到的评论测试失败是测试壳没有初始化 SmartDialog；已与主应用一致初始化，并等待 Toast 定时器完成。
- Git 空白检查：本次人工解决与后续提交没有新增空白错误；对完整上游增量运行检查会报告上游已有的补丁上下文空格及 chat_panel 文件尾空行，未改写上游 patch 内容。

```sh
# 干净环境：使用 pubspec 指定的 Flutter，先按 lib/scripts/patch.ps1 iOS 应用补丁
flutter pub get --enforce-lockfile
git diff --exit-code -- pubspec.lock
flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
# 以下仅在 GitHub Actions 执行：
flutter build ios --release --no-codesign --dart-define-from-file=pili_release.json --no-pub
```

远端构建：[GitHub Actions 34437612255](https://github.com/Caun1112/PiliNara/actions/runs/34437612255)，构建源码 `542a9800a52690dc988eb56801172c80434d6729`。工作流打包标准 `Payload/Runner.app`，输出源码 SHA 和 IPA SHA-256。

“未签名”指不使用 Apple 开发者证书及 provisioning profile；按仓库原流程对嵌入 frameworks 保留 ad-hoc 签名以兼容 AltSign。

### CI 检查顺序修正

第一轮 `34436714360` 在锁文件 diff 检查处失败：原有 `geetest_ios.patch` 会新增 `gt3_flutter_plugin 0.1.1`，因此平台补丁后的锁文件与仓库初始锁文件不同是预期行为。已在 `fe88782d1` 中将仓库锁文件校验移到平台补丁前；补丁后再次 `--enforce-lockfile` 并保存 `BUILD-pubspec.lock` 到产物。没有跳过依赖检查或删除验证码功能。

### CI 上传配置修正

第二轮 `34436931822` 已通过依赖、静态分析、全部测试、iOS Release 编译及 IPA ZIP 完整性检查，生成 104.8 MB 的 Runner.app；但原工作流 `archive: false` 不支持一次上传多个文件，新增的三份构建记录触发上传失败。已在 `542a9800a` 删除此单文件模式，使用标准 artifact 归档上传；应用代码没有变化。

第二轮 CI 静态分析是 79 项 warning/info，0 error（比本地多出的 1 项来自仅在 iOS 应用的代码补丁）。

### 安装运行与人工回归（待真机执行）

1. 用你现有的 TrollStore / 签名安装方式安装 IPA；检查新图标与绿色启动页、启动不滞留。
2. 检查右侧固定四入口、搜索自动弹出键盘、竖屏返回按钮；视频/B 站直播/虎牙横屏隐藏按钮，返回竖屏后恢复。
3. 虎牙进入直播、切画质/线路、关注与取消、横竖屏反复切换；连续播放并经历网络短断，确认恢复策略和画面没有回退。
4. B 站点播及直播：后台超过 10 秒再回前台、系统与应用内小窗、手动听视频、关闭后台播放，检查声音/画面/暂停状态；检查画面参数在切源后保留。
5. 下载：画质选择与记忆、大小显示、同视频换画质替换、取消任务、离线播放、导出分享与批量弹幕下载。
6. 评论图片：惯性滚动时点击只停滚、选评理由和故事卡、调整顺序、长截图、小屏大字体、不误退出；动态内容复制/分享链接正确。
7. 切换/删除账号、未读数清空、设置页首页预览和页面排序，确认预览没有重复 Key 异常。

没有已授权可用的 iPhone 实机运行环境，以上手工项目不会记为已通过。


## 6. 最终交付

- 本地 main / fork 远端 main / IPA 构建源码一致：`542a9800a52690dc988eb56801172c80434d6729`。
- 上游 main 的本次固定提交 `bcf0939cc` 已合入；合并提交为 `912e889e4`。
- [最终成功的 GitHub Actions](https://github.com/Caun1112/PiliNara/actions/runs/34437612255)。依赖检查、分析、52 项回归测试、iOS Release 编译、打包与 artifact 上传全部成功。
- [GitHub artifact](https://github.com/Caun1112/PiliNara/actions/runs/34437612255/artifacts/10136944298)。
- [未签名 IPA](/Users/caun/code/PiliNara/dist/upstream-merge-20260910/PiliNara_ios_2.1.3+5911_unsigned.ipa)：`2.1.3+5911`，45,792,803 字节（约 43.7 MiB），ARM64。
- SHA-256：`f2fb7e1ad3950ad45bdc8023df2f0146716a39e7154c14ec353d90100acd7eb9`，与 Actions 输出完全一致；ZIP 完整性检查通过。
- 主程序 codesign 检查：`code object is not signed at all`；包内无 provisioning profile。嵌入 frameworks 仍沿用仓库的 ad-hoc 处理。
- 安装包旁的 `SOURCE-COMMIT.txt`、`IPA-SHA256.txt`、`BUILD-pubspec.lock` 记录源码、校验值与实际 iOS 依赖。
- 原工作区应用修改已提交并包含在 main；另外保留原工作区 stash：`cdeb036a12ab636bfd7a58b90214e437552157f7`，说明为“合并上游前原工作区快照 20260910（应用改动已合入 main）”。不要直接 pop 到已包含这些改动的 main；需要恢复原编辑状态时，在 `cccb47d43` 对应的独立工作区 apply 此 stash。
- 原工作区最终仅剩无关的未跟踪 `patch-retry.py`，内容未改动。完整备份文件的校验值见 `BACKUP-SHA256.txt`。
- 真机安装/运行与人工回归仍待实际设备验证，未将编译或 widget 测试冒充真机通过。
