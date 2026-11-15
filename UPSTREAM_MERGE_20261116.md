# 上游合并审查记录（2026-11-16）

## 基线与范围

- 上游：`Starfallan/PiliNara` 的 `main`，`eca9c04eb59e596928b75213ea06c825d7e7fb25`，包含 2.6.2 更新。
- fork 合并起点：`Caun1112/PiliNara` 的 `codex/external-480p-download`，`309cee7a94668746465a11d2add848bc6574a30c`。fork 的默认分支 `main` 位于 `75f77bbfa7a3421e74a564c2154eb40a77609800`，不是此次功能最完整的起点。
- 共同祖先：`8d755f16b3f0929084f94b121e1ee38bb7af1686`；从共同祖先计算，fork 独有 59 个提交，上游独有 174 个提交。fork 有 236 个路径变更，上游有 352 个路径变更，交集为 34 个路径。
- fork 的重要定制包括虎牙直播、B 站本地关注与快捷入口、评论选择与截图、下载画质与大小、精确 480P 下载及自动分享、iOS 官方客户端跳转和自定义图标。上游更新包含缓存三层结构、音频画质、树状评论、视频播放及直播改进。
- 原工作区存在未跟踪的 `patch-retry.py`；该文件不属于提交，合并工作在单独 worktree 中进行，未覆盖原文件。

## 重叠文件

下列路径从共同祖先起在双方均有变化。重叠不必然意味着 Git 冲突；自动合并的部分仍须回归：

```text
.fvmrc
.gitignore
README.md
android/app/src/main/res/values/styles.xml
lib/http/download.dart
lib/main.dart
lib/models_new/download/bili_download_entry_info.dart
lib/pages/common/common_intro_controller.dart
lib/pages/danmaku/view.dart
lib/pages/download/detail/widgets/item.dart
lib/pages/dynamics/controller.dart
lib/pages/dynamics_detail/view.dart
lib/pages/live/view.dart
lib/pages/live_room/controller.dart
lib/pages/live_room/view.dart
lib/pages/main/controller.dart
lib/pages/main/view.dart
lib/pages/save_panel/view.dart
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

## 冲突分析与合并意图

`git merge-tree --write-tree 309cee7a9 eca9c04eb` 预演报告以下 21 个内容冲突。以下描述记录冲突原因及应保留的行为；最终行为须通过下文验证。

| 文件 | 冲突原因与合并保留内容 |
| --- | --- |
| `.fvmrc` | 双方升级 Flutter 版本；采用与上游和 `pubspec.yaml` 一致的 3.47.9。 |
| `.gitignore` | 双方修改忽略规则；保留两侧仍适用的规则。 |
| `README.md` | 上游重写说明，fork 保留自用项目说明与致谢；以 fork 说明为基础补充相关信息。 |
| `lib/http/download.dart` | 上游重构质量模型及音频选择，fork 要求精确画质；保留新质量 API，兼顾 480P 实际流校验、拒绝不匹配和多分段情况。 |
| `lib/models_new/download/bili_download_entry_info.dart` | 上游改造缓存元数据，fork 增加精确画质字段；保留新结构和可持久化的画质要求。 |
| `lib/pages/common/common_intro_controller.dart` | 上游更新分集切换接口，fork 添加跳转官方 B 站；同时保留 `onChangeEpisode` 与基于当前分 P 的官方客户端跳转。 |
| `lib/pages/download/detail/widgets/item.dart` | 上游调整缓存删除与导出，fork 增加缓存分享；在新版详情结构中同时保留分享、删除和导出。 |
| `lib/pages/live/view.dart` | 上游重构直播分区固定头和列表，fork 添加本地关注快捷操作；采用新版滚动结构并叠加快捷按钮。 |
| `lib/pages/save_panel/view.dart` | 上游支持评论链并更新番剧查找，fork 大幅扩展评论加载、选择、排序及截图；保留 fork 交互，接入评论链与 `findEpisode`。 |
| `lib/pages/video/controller.dart` | 上游调整播放、缓存和质量 API，fork 支持仅下载当前视频与分享；使用新版模型并保留当前项下载和分享参数。 |
| `lib/pages/video/download_panel/view.dart` | 上游加入音频画质并修改下载结构，fork 自定义画质选择、大小及自动分享；合并音视频质量和 fork 的下载交互。 |
| `lib/pages/video/introduction/pgc/controller.dart` | 上游调整导入及番剧分集逻辑，fork 增加跳转官方 B 站；保留上游处理和 fork 的链接生成。 |
| `lib/pages/video/introduction/pgc/view.dart` | 两侧调整番剧介绍/下载按钮布局；适配上游组件并保留 fork 入口。 |
| `lib/pages/video/introduction/ugc/view.dart` | 两侧调整视频介绍及下载动作；适配上游布局并保留 fork 下载与分享入口。 |
| `lib/pages/video/reply/widgets/reply_item_grpc.dart` | 上游重构为树状评论和新版时间跳转，fork 扩展截图选取与图片展示；采用上游常规评论布局，移植截图专用回复列表、选择状态和图片模式。 |
| `lib/pages/video/widgets/header_control.dart` | 上游增加全屏缓存入口，fork 增加官方 B 站跳转按钮；同时保留两种操作。 |
| `lib/plugin/pl_player/controller.dart` | 上游引入音量限幅，fork 管理应用内音量；以 fork 设置计算音量并使用上游限幅。 |
| `lib/plugin/pl_player/view/view.dart` | 两侧修改生命周期和后台播放；保留 fork 生命周期判断并通过上游播放/暂停接口维护音频焦点。 |
| `lib/services/download/download_service.dart` | 上游将缓存重构为三层并扩展音频质量，fork 增加精确 480P 和下载后分享；保留上游目录/任务模型，同时保留严格画质约束和分享。 |
| `lib/utils/app_scheme.dart` | 上游改进评论、定位和跳转处理，fork 增加外部下载深链；先处理 `pilinara` 下载请求，再使用上游评论 ID 和跳转逻辑。 |
| `pubspec.lock` | 两侧依赖版本不同；根据合并后的依赖和 Flutter 版本生成一致的锁文件，并用 `--enforce-lockfile` 校验。 |

## 每个冲突文件的最终代码位置

下表链接到已合并工作树中具体实现，供逐文件审查。行号对应本次合并内容；文件后续修改时以代码内容为准。

| 冲突文件 | 合并后代码位置 |
| --- | --- |
| `.fvmrc` | [Flutter 3.47.9](.fvmrc#L2) |
| `.gitignore` | [构建产物忽略规则](.gitignore#L150) |
| `README.md` | [虎牙数据源说明](README.md#L362) |
| `lib/http/download.dart` | [精确画质校验和上游质量模型](lib/http/download.dart#L22) |
| `lib/models_new/download/bili_download_entry_info.dart` | [精确视频画质和音频偏好字段](lib/models_new/download/bili_download_entry_info.dart#L35)，[JSON 读写](lib/models_new/download/bili_download_entry_info.dart#L229) |
| `lib/pages/common/common_intro_controller.dart` | [确定当前视频及分 P 的链接](lib/pages/common/common_intro_controller.dart#L71)，[打开官方客户端](lib/pages/common/common_intro_controller.dart#L87) |
| `lib/pages/download/detail/widgets/item.dart` | [缓存分享导出菜单](lib/pages/download/detail/widgets/item.dart#L525) |
| `lib/pages/live/view.dart` | [上游直播列表](lib/pages/live/view.dart#L71)，[fork 快捷入口](lib/pages/live/view.dart#L81) |
| `lib/pages/save_panel/view.dart` | [评论链及番剧定位](lib/pages/save_panel/view.dart#L167)，[选择和截图控制](lib/pages/save_panel/view.dart#L820) |
| `lib/pages/video/controller.dart` | [当前视频下载及分享选项](lib/pages/video/controller.dart#L2116) |
| `lib/pages/video/download_panel/view.dart` | [视频和音频画质状态](lib/pages/video/download_panel/view.dart#L106)，[分享模式](lib/pages/video/download_panel/view.dart#L140) |
| `lib/pages/video/introduction/pgc/controller.dart` | [当前番剧分集链接](lib/pages/video/introduction/pgc/controller.dart#L50)，[新版分集查找](lib/pages/video/introduction/pgc/controller.dart#L523) |
| `lib/pages/video/introduction/pgc/view.dart` | [番剧当前项下载分享](lib/pages/video/introduction/pgc/view.dart#L454) |
| `lib/pages/video/introduction/ugc/view.dart` | [视频当前项下载分享](lib/pages/video/introduction/ugc/view.dart#L526) |
| `lib/pages/video/reply/widgets/reply_item_grpc.dart` | [树状回复和截图回复选择分支](lib/pages/video/reply/widgets/reply_item_grpc.dart#L564)，[截图回复列表](lib/pages/video/reply/widgets/reply_item_grpc.dart#L1107) |
| `lib/pages/video/widgets/header_control.dart` | [iOS 打开官方客户端控制](lib/pages/video/widgets/header_control.dart#L2193)，[质量选择](lib/pages/video/widgets/header_control.dart#L1046) |
| `lib/plugin/pl_player/controller.dart` | [按 fork 设置应用上游音量限幅](lib/plugin/pl_player/controller.dart#L1225) |
| `lib/plugin/pl_player/view/view.dart` | [后台暂停及恢复](lib/plugin/pl_player/view/view.dart#L390) |
| `lib/services/download/download_service.dart` | [音视频质量及严格要求](lib/services/download/download_service.dart#L191)，[已有任务画质校验](lib/services/download/download_service.dart#L260) |
| `lib/utils/app_scheme.dart` | [外部下载深链及上游评论 ID 解析](lib/utils/app_scheme.dart#L160) |
| `pubspec.lock` | [锁定的 Flutter SDK 版本](pubspec.lock#L2154)，[material_ui 依赖版本](pubspec.lock#L1242) |

关键合并代码可在相应文件中审查。例如外部下载深链先于通用视频路由处理：

```dart
if (scheme == 'pilinara' && queryParameters['action'] == 'download') {
  final request = ExternalDownloadRequest.tryParse(uri);
  if (request == null) {
    SmartDialog.showToast('下载链接无效，未开始下载');
  } else {
    unawaited(externalVideoDownload.open(request));
  }
  return true;
}
final (rootRpId, secondRpId) = parseCommentId(queryParameters);
```

直播页保留上游分区与 fork 快捷入口：

```dart
slivers: [
  Obx(() => _buildTop(controller.topState.value)),
  Obx(() => _buildBody(controller.loadingState.value)),
  const SliverPadding(padding: .only(bottom: 100)),
],
// 同一 Stack 中：
child: const BiliLiveQuickActions(),
```

评论截图保留 fork 的选择状态，同时保留上游的常规树状评论：

```dart
subReplies: showReplies && replyItem.count > Int64.ZERO
    ? _buildCaptureReplyRow(/* 已选回复、选择回调及显示模式 */)
    : replyLevel == 1 && replyItem.count > Int64.ZERO
        ? _replyItemRow(context, colorScheme, replyItem.replies)
        : null,
```

## 可审查和可回滚的操作

从精确基线创建隔离 worktree 和备份引用，以普通 merge 保留双方历史；完成冲突处理后检查 `git diff --cached`，确认无冲突标记、未意外删除定制，再提交 merge commit。推送专用分支供审查，不覆盖默认分支。完成提交后，若需撤销合并而不改写已发布历史，执行 `git revert -m 1 <merge-commit>`；若尚未提交且要放弃工作，可在隔离 worktree 执行 `git merge --abort`。原分支和未跟踪文件继续保留。

## 验证清单

1. 使用项目指定 Flutter 3.47.9，运行 `flutter pub get --enforce-lockfile`，确认 `pubspec.lock` 无变化；运行 `flutter analyze --no-pub` 与 `flutter test --no-pub`。
2. 用 GitHub Actions 的 `Build for iOS` workflow 构建未签名 IPA；核对 workflow 的分析与测试结果、IPA ZIP 完整性、无 embedded.mobileprovision、来源提交和 SHA-256，再更新 fork 的 GitHub Release。
3. 真机检查启动、登录、普通视频和番剧播放、切换画质、横竖屏与后台恢复、直播和虎牙播放、本地关注与快捷入口。
4. 检查缓存三层目录、旧缓存迁移、视频及音频质量选择、文件大小、精确 480P 的可用与不可用情况、完成后分享和外部深链。
5. 检查普通评论、树状回复、评论链分享、截图中选择与排序跟评、长图与图片显示，以及动态截图；检查视频、评论、番剧深链及 iOS 打开官方客户端。

本地验证：Flutter 3.47.9 下严格锁文件校验通过；按 iOS 工作流应用补丁后静态分析无错误，全量 226 项测试通过。测试期间修复了测试设置库初始化及上游窗口恢复时的越界位置。iOS 构建和真机检查仍以 Actions 日志及实际设备结果为准。
