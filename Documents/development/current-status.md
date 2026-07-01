# 当前推进板

本文件用于交接当前阶段的实现状态，供后续 agent 继续推进。
**目标**：稳定好用的 SVN 分支合并桌面助手。任何工作必须能直接对应到这个目标。

---

## ⚠️ 重要：避免循环空转（必读）

### 历史教训：R85 ~ R262 ≈ 178 轮 doc-only cascade 空转

R85 起本仓库进入了一段长达 **~178 轮**的 doc-only 自循环，**没有推进任何真实产品功能**。
症状如下：

- **lib/test/main.dart 0 改动 / 仅追加 doc-block**：每一轮"收口"只在 `lib/main.dart` 文件头部追加几十行注释、在 `current-status.md` 顶部追加一段"R{N} 律家族首次量化锚定"块、写一个 `scripts/temp/r{N}_cascade.py` 脚本。
- **自创计数标签**：发明出"律家族 985"、"R reservoir 26/26 饱和"、"维度切换第 125 次"、"N-tuple 复用第 141 次"、"严格首次量化锚定"、"元层第六阶"、"PD8 mocking"、"双整数四十同启律家族"等大量与项目目标无关的术语。
- **维度换阶 / 字母推进**：当一个字母（A-Z）跑完，就切到下一个字母 SA→SB→...→SZ；R reservoir 跑完就切到 S reservoir；ROOT 跑完就切到 test/、scripts/、shell、配置、markdown、call-graph 等等"维度"。每次都"严格首次量化锚定"。
- **每轮自我合理化**：`flutter test` 维持 +2520 + `flutter analyze` 0 issue 被反复用作"主轨严格守住"的证据，掩盖了根本上没有交付任何用户价值。

**用户在 R262 后明确否定这条路线**：

> "哎哟. 你现在讲的东西, 和本项目有什么关系嘛? 和我们最初的目标有什么关系嘛?"

### 给后续 agent 的硬约束

1. **禁止任何 R-series cascade**。不要再写 `R{N}` doc-block、不要在 `lib/main.dart` 头部追加 doc 巨块、不要造 `scripts/temp/r{N}_cascade.py`。
2. **禁止自创计数标签**。如果你发现自己在写"律家族"、"reservoir"、"维度切换第 N 次"、"N-tuple 复用"、"元层第 N 阶"、"严格首次量化锚定"、"启动律"、"匀速无 outlier 律"——**立刻停手**。这些都是 R85+ 空转的警报词。
3. **"继续推进"= 推进真实 SVN 合并产品功能**。当用户说"继续推进, 没有重大决策就不用问我"时，默认指：
   - 修复用户实际会碰到的 bug
   - 加用户实际会用到的 UI 按钮 / 交互
   - 砍真实存在的代码 / 依赖 / 历史包袱
   - 完善真实失败场景下的恢复路径
   不指：写 doc 注释、做 surface 审计、写"协议形态学"、做字母递进、做 reservoir 饱和。
4. **不要把"flutter test 全绿"作为推进证据**。测试全绿是底线，不是成果。每一轮工作必须能回答："这一轮做完之后，用户在使用 SvnAutoMerge 时哪个具体场景变好了？"如果答不上来，那就是空转。
5. **怀疑自己时主动停下来对齐**。如果连续 2-3 轮工作只动 doc 不动 lib，或者只是给 lib 加注释/抽顶层 helper 而不增加任何用户可感知的能力，主动用 `AskUserQuestion` 或停下来等用户确认方向。
6. **scripts/temp/ 已被滥用**。该目录历史上塞满了 200+ 个 r{N}_cascade.py / surface_scan.py，全部都是 doc-only 噪音的副产物。新增临时脚本前先确认它真的服务于功能落地，而不是为了产出更多 doc 数字。

---

## 当前定位

- 产品目标：围绕 SVN 分支合并，提供稳定、低心智负担的桌面助手。
- 固定执行链路：`准备 -> 更新 -> 合并 -> 提交`。
- 当前执行模型：单任务串行、队列可视化、失败可暂停、人工继续/跳过/终止。
- 历史方向：流程平台、外部脚本编排、旧 pipeline 设计已从主线移除。
- vyuh_node_flow 子模块已在 2026-06 彻底清理（packages/、pubspec、`.gitmodules`、`.git/modules/`、`.codebuddy/rules/vyuh-node-flow.mdc`、`.git/config` submodule 段全部移除）。

---

## 已落地能力

### 选择阶段
- 日志列表支持 author / title / message / minRevision 四维过滤（message 即 commit 全文搜索）。
- 日志缓存支持 `同步最新` / `加载更多`。
- 顶部状态摘要显示缓存条数、缓存区间、分支点、预加载状态、历史边界。
- 当前页 `全选可选` / `清空选择`。
- 已合并 / 待合并 revision 在列表中区分展示。
- 切换源分支时自动清掉旧选择。

### 待合并阶段
- 来源分支摘要展示。
- 切换源分支时给出警告并阻止继续添加 / 开始合并。
- 清空待合并列表 / 逐条移除 revision。

### 执行阶段
- `MergeExecutionState` 管理主执行状态。
- 固定四步执行视图（已替代旧流程图视图）。
- 队列执行多任务。
- 提交阶段 `out-of-date` 有限重试。
- 冲突 / 失败时可暂停，支持继续 / 跳过 / 终止。
- 应用异常退出后未完成任务恢复为暂停状态。
- 步骤快照查看输入 / 配置 / 输出 / 错误 / 全局上下文。

### 队列与日志
- 右侧任务概览区分 `执行队列` / `最近结果`。
- 清空待执行 / 清理历史 / 删除单条 / 从失败任务生成剩余任务。
- 队列操作返回明确结果（不再靠"前后数量对比"猜测）。
- 执行日志限制为最近 600 行。
- 日志弹窗显示行数 / 复制 / 清空。

---

## 实证过的功能缺口清单（按用户价值排序）

> 以下条目都是对照 lib/ 实际代码扫描后确认过的真缺口（grep + Read 验证）。
> 已剔除 Agent Explore 报告中夸大的 4 个伪缺口（冲突恢复粒度 / panel 按钮无响应 / 设置页面占位 / SVN 重试简单）。

### P0 paused 任务 resume 后 commit retryCount 接续（第四十六轮）

- **现状**：2026-06-02 第四十六轮落地。
  - 真 bug：用户在 `out-of-date` 任务暂停后用「调整重试上限」抬高 `maxRetries`，再点「继续」，期望 retryCount 接续上一轮已用次数（doc 在 `updateJobMaxRetries` 里明确说"保留计数让用户清楚知道还剩多少次配额"），但 `_executeJob` 进入 for 循环时无条件 `_runtimeVariables['commitRetryCount'] = 0;` 把计数清零；下一次 commit 失败显示"第 1/N 次重试"，违背 doc 契约 + 用户多吃 N 次无意义重试。
  - 修复：
    - 顶层纯函数 `extractPreviousRetryCountFromCommitSnapshot(StepSnapshot?)` (`lib/providers/merge_execution_state.dart:317`) — 从 paused commit snapshot.output.data['retryCount'] 读已用次数；snapshot 为 null / 非 failed / data 缺字段 / 类型不对 / 负数 都退回 0。`@visibleForTesting`，8 测试覆盖所有 fallback 路径 + 一条接续语义校验（snapshot retryCount=3 + maxRetries=4 → next attempt=4 而非 1）。
    - `_executeJob` 在 `_clearExecutionRuntime()` 之前抢救 retryCount，for 循环只在 `i == resumeFromIndex` 第一轮注入它；后续 revision 仍清零（每个 revision 独立 retry 配额）。
- **缺口**：（已无）
- **关联文件**：`lib/providers/merge_execution_state.dart::extractPreviousRetryCountFromCommitSnapshot / _readPreviousCommitRetryCount / _executeJob`、`test/merge_execution_state_test.dart::extractPreviousRetryCountFromCommitSnapshot group`。

### P0 合并完成提示带"实际改动 N 个文件 / 0 个（空合并）"（第四十五轮）

- **现状**：2026-06-02 第四十五轮落地。
  - 真 dogfood 痛点：用户配 b1→b1 自合并 r3 一次，全部 SVN 命令成功 + 提交成功，但 `1.txt` 一字未改，从 app 看是"成功"实际是 no-op（svn merge 自合并 + 空 commit 路径），用户误以为流程坏了。
  - 落地：
    - 顶层 helper `parseChangedFilesCount(statusOutput)` 数 svn status 非空行（不分类型，0 行 = 空合并）。`@visibleForTesting`，7 测试。
    - `SvnService.countChangedFiles(targetWc, {username, password})` 跑 `svn status` + 调 helper。
    - `MergeExecutionState._runMergeStep` 在 `listConflictedFiles` 后验通过后调 `countChangedFiles`：`> 0` → `'r$revision 合并成功 — 实际改动 N 个文件'`；`== 0` → `'r$revision 合并成功 — 但未产生任何差异（空合并 / no-op...）'`；step output 加 `changedFilesCount` 字段。
- **缺口**：（已无）。任务级 SnackBar 求和提示（多 revision 任务收尾时一次性弹"本任务实际改动 N 个文件 / M 个 revision 都是空合并"）暂未做 — 对单条诊断已足够，等用户报后续痛点。
- **关联文件**：`lib/services/svn_service.dart::parseChangedFilesCount / countChangedFiles`、`lib/providers/merge_execution_state.dart::_runMergeStep`、`test/svn_service_test.dart`、`test/merge_execution_state_flow_test.dart`。

### P0 冲突解决 UI（最有用户价值）

- **现状**：暂停态摘要区已具备：
  - "打开工作副本目录" 按钮（已落地，跨平台 open/explorer/xdg-open）
  - "标记为已解决" 主按钮（accept working）+ "更多…" PopupMenuButton（accept mine-full / theirs-full / base 三种破坏性递增的高级 mode），仅在 failureKind ∈ {textConflict, treeConflict} 时渲染。点击触发 `svn resolve --accept <mode> -R .`，SnackBar 提示成功/失败（成功时带具体 cliFlag），**不**自动 resume，由用户手动点继续。**2026-06-01 第七轮**：把单一 working 模式扩成 4 mode dialog——抽 `SvnResolveAccept` enum + `cliFlag` getter（kebab-case 序列化对接 SVN CLI），`buildSvnResolveAcceptWorkingArgs()` → `buildSvnResolveArgs(SvnResolveAccept mode)`，`SvnService.resolveAccept(targetWc, {mode = working, ...})` 透传 mode；UI Wrap 主按钮 + PopupMenuButton（3 项 ListTile 含 dartdoc 风格 subtitle 解释语义）。
  - "打开冲突文件" 按钮（2026-06-01 第三轮，仅在 failureKind == textConflict 时渲染；扫 `svn st` 取首列 'C' 行，取第一条相对路径，`p.join(targetWc, relative)` 拼绝对路径，跨平台命令打开：mac=`open` / win=`cmd /c start ""` / linux=`xdg-open`；空冲突列表 / 不支持平台 / 异常 → SnackBar 反馈不抛异常）
- **缺口**：（已无）
- **关联文件**：`lib/screens/components/merge_execution_panel.dart`、`lib/services/svn_service.dart`（`SvnResolveAccept` enum + `buildSvnResolveArgs` + `resolveAccept` + `parseConflictedFiles` + `listConflictedFiles`）、`lib/utils/open_directory.dart`（`resolveOpenFileCommand`）、`lib/screens/main_screen_v3.dart`（`_markConflictsResolved(targetWc, {mode = working})` + `_openConflictFile`）。

### P1 预加载取消按钮（最便宜）

- **现状**：`lib/services/preload_service.dart` 已有 `stopPreload()` 方法，UI 按钮 + SnackBar 反馈已落地（2026-06-01 第四轮）。
  - 按钮：`log_list_panel.dart` `OutlinedButton` "停止预加载"（icon: stop_circle_outlined / 配色 0xFF335C99），仅当 `canStopPreload == true`（即 `_preloadProgress.status == PreloadStatus.loading`）时 enabled。
  - 反馈：`main_screen_v3.dart::_stopPreloadWithFeedback` 调 `_preloadService.stopPreload()` 后立刻 SnackBar "已请求停止预加载（当前轮结束后生效）"。设计上必须有这个 SnackBar——`stopPreload()` 只是把 `_shouldStop` 置 true，真正生效要等到下一轮 while 头判定（最长可等到当前 SVN 请求结束 + 100ms throttle），期间状态条不会立刻翻转，没反馈用户会反复点击。
- **缺口**：（已无）

### P1 CSV 导出

- **现状**：2026-06-01 第五轮落地。
  - 顶层 helper（`lib/services/log_filter_service.dart`）：
    - `escapeCsvField(String)` — RFC 4180 字段转义（含 `,"\n\r` → 包双引号 + 内部 `"` → `""`，纯文本/空串原样不加引号，不 trim）。`@visibleForTesting`，仅 service + 测试调用。
    - `formatLogEntriesAsCsv(Iterable<LogEntry>)` — 渲染表头 `revision,author,date,title,message\r\n` + 5 列数据行，行分隔符 `\r\n`，空 entries 仍输出表头（避免空文件让用户误以为"导出失败"），数据顺序保持入参顺序（不重排）。**不**加 `@visibleForTesting`，因 `screens/main_screen_v3.dart` 跨库直接调用。
    - `formatCsvExportFileName(DateTime now)` — 返回 `svn-log-yyyyMMdd-HHmmss.csv`，月日时分秒 padLeft(2)，本地时区。**不**加 `@visibleForTesting`，同上。
  - service 实例方法 `LogFilterService.getAllFilteredEntries(sourceUrl, filter)` — 委托 `LogCacheService.getEntriesInLatestRange(limit: null)`；`AppState.getAllFilteredEntries(sourceUrl)` 桥接到当前 `_filter`。
  - UI（`log_list_panel.dart` `_FilterBar`）：actionButtons Wrap 在"停止预加载"后追加 `OutlinedButton.icon` "导出 CSV"（icon: file_download_outlined / 配色 0xFF2E7D32），enabled 条件 `canExportCsv && !isLoading`，`canExportCsv = paginatedLogEntries.isNotEmpty && sourceUrl.isNotEmpty`。
  - 落地路径（`main_screen_v3.dart::_exportFilteredAsCsv(sourceUrl)`）：appState.getAllFilteredEntries → 空列表 SnackBar "当前无可导出条目" 提前返回（不弹文件对话框）→ formatCsvExportFileName(DateTime.now()) → `FilePicker.platform.saveFile(dialogTitle, fileName, type: custom, allowedExtensions: ['csv'])` → 用户取消（null）静默返回 → `formatLogEntriesAsCsv(entries)` + `File(savePath).writeAsString(csv)` → SnackBar "已导出 N 条到 path"；catch → AppLogger.ui.error + SnackBar 失败提示。
- **缺口**：（已无）— TSV 暂未做（用户没明确要求）。
- **关联文件**：`lib/services/log_filter_service.dart`、`lib/providers/app_state.dart`、`lib/screens/components/log_list_panel.dart`、`lib/screens/main_screen_v3.dart`、`test/log_filter_service_test.dart`。

### P1 locked 暂停态 svn cleanup 按钮

- **现状**：2026-06-01 第八轮落地。
  - 顶层谓词 `shouldShowCleanupButton(SvnFailureKind)` (`lib/screens/components/merge_execution_panel.dart`)：当且仅当 `failureKind == SvnFailureKind.locked` 返回 true，其余 8 种返回 false。`@visibleForTesting`，9 mode 真值表覆盖。
  - `MergeExecutionPanel.onCleanup: VoidCallback?` 字段。pausedJob 非空 + locked + onCleanup 非空 → actionButtons Wrap 渲染 `OutlinedButton.icon(icon: cleaning_services, label: '执行 cleanup')`（teal 配色避免与 working-copy 橙、resolve 绿、open-conflict 紫色按钮混淆）。
  - 接线：`main_screen_v3.dart` 新增 `_runSvnCleanup(targetWc)` — try/catch 调 `_svnService.cleanup(targetWc)`，SnackBar 反馈「已执行 svn cleanup，可点击"继续"重试」/「cleanup 失败: {stderr}」/「执行 svn cleanup 失败: $e」，**不**自动 resume（与 `_markConflictsResolved` 同款显式触发体验）。
- **缺口**：（已无）
- **关联文件**：`lib/screens/components/merge_execution_panel.dart`、`lib/services/svn_service.dart`（已有 `cleanup` 方法 line 1290）、`lib/screens/main_screen_v3.dart::_runSvnCleanup`、`test/merge_execution_panel_cleanup_test.dart`。

### P1 日志筛选一键清空按钮

- **现状**：2026-06-01 第九轮落地。
  - 顶层谓词 `hasActiveLogTextFilter({author, title, message})` (`lib/services/log_filter_service.dart`)：3 个 String? 任一非 null 且非空 → true，与 `isStringFilterEmpty` 同口径不 trim。`@visibleForTesting`。**注**：当前 lib UI 不直接调它驱动 enabled 态（避开 `controller.addListener`，遵守 R130 lib 0 处 addListener 不变量），保留为可被未来非 UI 调用方共用的稳定语义。
  - `LogListPanel.onClearFilter: VoidCallback?` 字段。非 null 时 filter 行渲染 `OutlinedButton.icon(icon: filter_alt_off, label: '清空筛选')`（黄褐色 0xFF8B6914）。**始终 enabled**（除 isLoading），空文本点击等价"应用空过滤"无副作用——避免为驱动按钮 disabled 态而引入 listener。
  - 接线：`main_screen_v3.dart` 新增 `_clearAllLogFilters()` — `clear()` 三个 controller、`setState(() {})`、`await _applyFilter()` 把空过滤推到 AppState 显示全部条目。
- **缺口**：（已无）
- **关联文件**：`lib/services/log_filter_service.dart`、`lib/screens/components/log_list_panel.dart`、`lib/screens/main_screen_v3.dart::_clearAllLogFilters`、`test/log_list_panel_clear_filter_test.dart`。

### P1 暂停/执行中改 sourceUrl/targetWc 加二次确认

- **现状**：2026-06-01 第十轮落地。
  - 顶层谓词 `shouldWarnBeforeEditingConfig({isProcessing, hasPausedJob})` (`lib/screens/main_screen_v3.dart`)：OR 真值表 — 仅 (false, false) 返回 false，其余 3 种返回 true。语义与 `resolveOperationPhase` 同型（任一 flag 真即视作"忙"）。`@visibleForTesting`，5 测试（4 组合 + 1 反向断言）。
  - `_showConfigDialog` 改 `Future<void>`：先用谓词判定，是否需要二次确认。需要 → `await _confirmEditConfigWhileBusy(mergeState)`，**取消**默认（false） → 不打开 ConfigDialog；**继续修改**（true） → `_openConfigDialog(appState)`。
  - 二次确认对话框文案：标题 `"当前有X任务，确定要改配置？"`（X = 暂停 / 执行中 / 活动）；正文明确说"修改源 URL / 目标工作副本不会影响已暂停或正在执行的任务（任务自带配置副本），仅会改变下一次新建合并任务时的输入"；底部展示 `pausedJob ?? currentJob` 自带的 `sourceUrl` / `targetWc` 副本（提醒用户活动任务的配置不在主屏 controller）。
  - **为什么不直接 disable 配置按钮**：用户可能想在终止当前任务前先把配置改回来，disable 太硬；弹一个能 cancel/proceed 的 modal 最不打扰。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::_showConfigDialog` / `_confirmEditConfigWhileBusy` / `_openConfigDialog`、`test/main_screen_v3_test.dart::shouldWarnBeforeEditingConfig`.

### P1 sourceUrl 粘贴自动剥空白字符

- **现状**：2026-06-01 第十四轮落地。
  - 漏洞：用户从浏览器/IDE/邮件里复制 SVN URL 经常带 trailing 换行 / leading 空格 / 段落富文本里嵌零宽空白等，粘贴到"源 URL"后 `Uri.parse` 看似成功但 `svn info` / `svn log` 直接 404，错误信息又不指向"输入有空白"，定位成本高。
  - 落地：`lib/screens/components/dialogs/config_dialog.dart` 新增两个顶层 export（均 `@visibleForTesting`）：
    - `stripUrlWhitespace(String input)` — `RegExp(r'\s+')` 全字符删除（不只 trim 头尾，内嵌 / NBSP / 零宽空白都剥）。空串短路返回。**不**做 percent-decoding，已 encoded 的 `%20` 不会被展开后再剥。
    - `UrlInputFormatter extends TextInputFormatter` — `formatEditUpdate` 内调 `stripUrlWhitespace(newValue.text)`：identical → 直接返回 `newValue` 不重建对象（避免无空白输入时光标策略噪音）；有改动则返回新 `TextEditingValue` 含 `TextSelection.collapsed(offset: clampedOffset)`，光标用 `clamp(0, stripped.length)` 防越界。
  - "源 URL" `TextField` 加 `inputFormatters: const [UrlInputFormatter()]` + `helperText: '粘贴时自动剥离空白字符'`。
  - 历史记录 `PopupMenuButton.onSelected` 也走 `sourceUrlController.text = stripUrlWhitespace(value)` 净化（保护历史记录里残留的脏数据 — `controller.text` 的 setter 不走 TextInputFormatter，必须显式 strip）。`R132` widget owned-resource 锁同步扩展，doc-as-test 反映防御深度。
  - **决策权衡**：仅 sourceUrl 接 formatter，**不**给 targetWc 接（targetWc 是路径，合法含空格如 `/Users/User Name/wc`，套同 helper 会破坏正常输入）。走 `TextInputFormatter` 子类而非 `onChanged` 回调（formatter 在 framework 层改 `TextEditingValue` 不破坏光标 / 不递归触发，`onChanged` 改 `controller.text` 会触发递归 + 光标错乱）。`RegExp(r'\s+')` 而非 `trim()`（内嵌空白如 `https://repo /branch` trim 不掉但 `svn info` 仍 404）。
- **缺口**：（已无）
- **关联文件**：`lib/screens/components/dialogs/config_dialog.dart`、`test/config_dialog_url_input_test.dart`、`test/widget_text_controller_write_protocol_test.dart`（lock 同步更新）。

### P1 终止任务按钮加二次确认

- **现状**：2026-06-01 第十三轮落地。
  - 漏洞：`MergeExecutionPanel` 暂停态 "终止" 按钮原本直连 `mergeState.cancelPausedJob()`，UX 不一致——清空待执行 / 清理历史这种轻量操作都走 `_confirmQueueAction` AlertDialog 二次确认，反而是"任务无法恢复"的终止操作裸调没有兜底，误点直接丢已合并 revision 进度。
  - 落地：`main_screen_v3.dart` 新增 `_cancelPausedJobWithConfirm(MergeExecutionState mergeState)`：先校验 `mergeState.pausedJob != null`（兜底防异步态翻转），再走既有 `_confirmQueueAction(title: '终止当前任务', message: '终止后任务将从队列移除，已合并的 revision 不会回滚但任务无法恢复；如需仅跳过当前 revision 请使用"跳过"按钮。', confirmLabel: '终止')`，confirmed 后才 `await mergeState.cancelPausedJob()` + `_showSuccess('已终止任务')` SnackBar。
  - panel 接线：`MergeExecutionPanel.onCancel: () => mergeState.cancelPausedJob()` → `() => _cancelPausedJobWithConfirm(mergeState)`。
  - **决策权衡**：复用既有 `_confirmQueueAction`（AlertDialog with cancel/confirm 双 TextButton），不重新造 dialog；message 显式区分"终止" vs "跳过"两种语义（用户最容易混淆 — 跳过单 revision 是非破坏性，终止是破坏性 + 不可恢复）；不阻断异步：`pausedJob` 为 null 时退化为 `_showInfo('当前没有暂停中的任务')`，不抛异常。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart`。

### P0 _svnUpdate / _svnCleanup R131 档 3 mounted 守卫漏档（第四十三轮）

- **现状**：2026-06-02 第四十三轮落地。
  - 真 bug：上一轮闭合 `_svnRevert` 三处漏档后巡检主屏 SVN 三入口家族，发现 `_svnUpdate` / `_svnCleanup` 同型漏档（与 R131 档 3 不变量 I1 直接冲突）：
    - `_svnUpdate` line 2184 isSuccess=false 分支：`AppLogger.ui.error('工作副本更新失败: ${result.stderr}'); _showError('更新失败: ${result.stderr}');` —— 跨 `await _wcManager.update(...)`（耗时真实 SVN 远程调用）后无 mounted 守卫，dispose 后 ScaffoldMessenger 崩溃。
    - `_svnUpdate` catch 块：`AppLogger.ui.error('工作副本更新异常', e, stackTrace); _showError('更新异常: $e');` —— 同模式漏档。
    - `_svnCleanup` line 2308 isSuccess=false 分支：`AppLogger.ui.error('工作副本清理失败: ${result.stderr}'); _showError('清理失败: ${result.stderr}');` —— 跨 `await _wcManager.cleanup(...)` 后同模式漏档。
    - `_svnCleanup` catch 块：`AppLogger.ui.error('工作副本清理异常', e, stackTrace); _showError('清理异常: $e');` —— 同模式漏档。
  - 注：两个方法的 isSuccess=true 分支已分别在第三十二轮（`_svnUpdate` 后验 `listConflictedFiles` 之后）/ 第三十一轮（`_svnCleanup` 后验 `probeSvnLocation` 之后）补过 `if (!mounted) return;`，仅 isSuccess=false 与 catch 这两条**异常**路径漏档。
  - 落地：四处都补 `if (!mounted) return;` 在 `AppLogger.ui.error(...)` 之后、`_showError(...)` 之前，与第四十二轮 `_svnRevert` catch 守卫风格完全一致。主屏 SVN 三入口家族（update / revert / cleanup）跨 await 后所有 SnackBar 调用至此**全部对称收口**。
  - **决策权衡**：
    - **一并修复 cleanup 而非只 update**：用户问的是巡检 `_svnUpdate`，但巡检发现 `_svnCleanup` 同型漏档并存。分两轮反而割裂"主屏三入口家族"对称性，单轮一并修复也只是 +2 个 catch 块的修改，不构成"批量重构"超范围。
    - **isSuccess=true 分支已有守卫不动**：那是第三十一/三十二轮补的、用于后验 SVN 调用之后 `_showSuccess` / `_showError` 之前的守卫，已是正确状态。重复加守卫触发"双层 mounted"反而是噪音。
    - **不抽 helper / 不造新风格**：守卫语句是单行 `if (!mounted) return;` 直接出现在 SnackBar 之前最直观，抽 helper 反而隐藏控制流。
  - +4 测试（test/main_screen_v3_test.dart 末尾新 group `_svnUpdate / _svnCleanup R131 档 3 mounted 守卫（第四十三轮）`）：
    - 2 lib 字面量锁（update / cleanup 各一）：isSuccess=false 分支 + catch 块 各自前置守卫的字面量片段必须存在
    - 2 lib 顺序锁（update / cleanup 各一）：守卫均在对应 `_showError` 调用之前
- 验证：`flutter analyze` 0 issues + `flutter test` **2969 全绿**（baseline 2965 → 2969，+4）。
- **缺口**：主屏 SVN 三入口家族跨 await 后 SnackBar 守卫已**完整闭合**。其他跨 await UI 入口（`_runMergeStep` / `_runUpdateStep` / merge job 流程内部）catch 仅调 AppLogger 不调 ScaffoldMessenger，结构上无对称漏档（与第三十轮 `_runMergeStep` 设计一致）。
- **关联文件**：`lib/screens/main_screen_v3.dart::_svnUpdate / _svnCleanup`、`test/main_screen_v3_test.dart`。

### P0 _svnRevert R131 档 3 mounted 守卫漏档（第四十二轮）

- **现状**：2026-06-02 第四十二轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_svnRevert`（顶部"还原"按钮入口）整段跨 await 边界后均未前置 mounted 守卫，与 R131 档 3 不变量 I1（StatefulWidget 跨 await 边界后引用 context / setState / ScaffoldMessenger / Navigator 之前必须 `if (!mounted) return;`）直接冲突。具体 3 处漏档：
    - **showDialog 之后**：`final confirmed = await showDialog<bool>(...)` 之后只有 `if (confirmed != true) return;`，confirm=true 路径下立刻 `_showInfo('正在还原工作副本...')`（内部 `ScaffoldMessenger.of(context)`）。如果用户在确认对话框打开期间通过其他路径（关闭子窗口 / 切换页面 / app dispose）让本 State 解 mount，`ScaffoldMessenger.of(context)` 会抛 "Looking up a deactivated widget's ancestor is unsafe"。
    - **`await _wcManager.revert(...)` 之后**：revert 是真实远程 SVN 调用 + 本地 wc 改写（耗时分钟级），结束之前用户完全有机会切走/关页面；之后无守卫直接 `_showSuccess('还原完成')` 或 `_showError('还原失败: ...')`。后续 `if (mounted && sourceUrl.isNotEmpty)` 是局部守卫，但已经在 `_showSuccess` 之后，前面两个 SnackBar 都裸跑。
    - **catch 块内**：`} catch (e, stackTrace) { ... _showError('还原异常: $e'); }` —— revert 抛异常时同样跨 await 边界裸调 SnackBar。
  - 落地：在 `_svnRevert` 内补 3 处 `if (!mounted) return;`：
    - showDialog 后 / `if (confirmed != true) return;` 之后立刻补一行
    - `await _wcManager.revert(...)` 之后 / `if (result.isSuccess)` 之前补一行（同时覆盖 success 分支与 isSuccess=false 分支）
    - catch 块内 `AppLogger.ui.error(...)` 之后 / `_showError(...)` 之前补一行
  - **决策权衡**：
    - **不删原有 `if (mounted && sourceUrl.isNotEmpty)` 局部守卫**：它在 `_showSuccess` 之后，本身也跨 `await appState.loadMergeInfo(...)` 边界用 `Provider.of(context, listen: false)`，是另一个独立守卫语义；保留可叠加防御。
    - **catch 块也补**：与第三十轮 `_runMergeStep` catch 不补 mounted 的对称结构对齐 — 那处 catch 内只有 `AppLogger` 不调 ScaffoldMessenger 故无须；本处 catch 直接 `_showError` 调 ScaffoldMessenger 必须补。
    - **三处都用 `if (!mounted) return;` 而非 `if (mounted) { ... }` 包裹**：与项目内既有约 50+ 处守卫风格一致（早 return 优于嵌套），更易写顺序锁测试。
  - +2 测试（test/main_screen_v3_test.dart 末尾新 group `_svnRevert R131 档 3 mounted 守卫（第四十二轮）`）：
    - 1 lib 字面量锁：3 处守卫的字面量片段（含上下文锚点）必须存在
    - 1 lib 顺序锁：3 处守卫均在对应的 `_showInfo` / `_showSuccess` / `_showError` 调用之前
- 验证：`flutter analyze` 0 issues + `flutter test` **2965 全绿**（baseline 2963 → 2965，+2）。
- **缺口**：本轮聚焦 `_svnRevert`；后续可巡检 `_svnUpdate` / `_svnCleanup` / `_runMergeStep` / `_runUpdateStep` 等其他跨 await 入口是否还有同型漏档（候选：`_svnUpdate` line ~2186 catch 块同模式 — 待下一轮按真实 bug 优先级再判断）。
- **关联文件**：`lib/screens/main_screen_v3.dart::_svnRevert`、`test/main_screen_v3_test.dart`。

### P1 sync/apply 拆段反馈避免误导（第四十一轮）

- **现状**：2026-06-02 第四十一轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_runLogDataAction`（"同步最新" / "加载更多" 共用入口）原 try 块同时包 `action()`（sync 段：远程 SVN log 拉取 + DB 写入）与 `_applySelectionContext()`（apply 段：刷 minRevision / mergeinfo / log cache summary 三段 UI 状态）。当 sync 真有新数据落盘成功（addedCount=N>0）但 apply 抛错（DB 锁 / 缓存服务异常 / `_updateMergedStatus` 网络抖动），catch 块统一弹 `'日志同步失败: $e'` —— 与实际状态背离：日志已同步入库但 UI 没刷新，用户误以为"啥也没干成"会再点"同步最新"重新触发 SVN 远程请求（浪费带宽 + 极端情况触发服务端节流），同时已同步的 N 条数据并不会因为再点而变化（去重），用户陷入"为啥同步成功的数据看不到"的死结。与第三十七轮 `formatPendingAddSnackBar` "反馈数 == 真实数" family 同型。
  - 落地：
    - 顶层 helper `formatLogApplyFailureFeedback({required int addedCount, required String error})`（`@visibleForTesting`，置于 `formatPendingAddSnackBar` 之后、`formatOpenConflictFileFeedback` 之前）：两档分流——`addedCount > 0` → `'日志已同步 $addedCount 条，但界面刷新失败: $error；可重试同步或切换源 URL 重新加载'`（主信息突出"已同步 N 条"避免用户重复点 sync）；`addedCount <= 0` → `'日志同步完成但界面刷新失败: $error；可切换源 URL 重新加载'`（防御负数走同档，与 `_runLogDataAction` 默认初始值 0 同义）。
    - `_runLogDataAction` 拆成两段 try：外层 `int addedCount = 0;` 在两段 try 之前声明并初始化，sync 段独立 try-catch（catch 内 `AppLogger.ui.error('日志数据操作失败（sync 段）', ...)` + `_showError('日志同步失败: $e')` + `return;` 跳过 apply 段不让 UI 段空跑）；apply 段独立 try-catch（catch 内 `AppLogger.ui.error('日志数据操作失败（apply 段）', ...)` + `_showError(formatLogApplyFailureFeedback(addedCount, error))` + `return;`）；finally 块仍统一 `setLoadingData(false)` 保留 loading 复位。
  - **决策权衡**：
    - **拆段而非加 bool flag**：原代码加 `bool synced = false;` 在 catch 内分支判定也能实现，但拆两段 try 让两类失败的执行路径在源码层面就完全分离，更难再写出"先弹通用 SnackBar 再判 synced"的回归。
    - **catch 标签 "（sync 段）" / "（apply 段）"**：日志层面让排查者一眼分辨失败来自哪段，不靠堆栈猜。
    - **`addedCount > 0` 文案显式提示"重试同步或切换源 URL 重新加载"**：给用户具体下一步操作锚点，避免"刷新失败"四个字让人不知所措；切换源 URL 是已知能触发 `_autoLoadLogsIfPossible` → `_applySelectionContext` 重跑的路径，是最可靠的恢复手段。
    - **不在 apply 失败时回滚 addedCount**：sync 段已落盘的数据是真实的（DB 已 commit），回滚 UI 反而隐瞒了"DB 里已经有 N 条新数据"的事实；下次任意路径触发 apply 都会显示出来。
    - **保留 sync 段 catch 内的"日志同步失败: \$e"原文案**：sync 段失败 = 没拿到新数据，原文案语义准确，不必造新文案。
  - +6 测试（test/main_screen_v3_test.dart 末尾新 group `formatLogApplyFailureFeedback（sync 段成功 / apply 段失败的反馈分流，第四十一轮）`）：
    - 4 helper 真值表：addedCount=12 多条 / addedCount=1 单条边界 / addedCount=0 无新数据 / addedCount=-1 防御负数
    - 1 lib 字面量锁：helper 定义 + 两档文案字面量 + sync/apply catch 标签 + sync 段保留原文案 + apply 段调 helper
    - 1 lib 顺序锁：`int addedCount = 0;` 在两段 try 之前外层声明 / sync catch 在 apply catch 之前 / sync catch 内 return 跳过 apply / 旧统一 catch（无段标签）已被替换
- 验证：`flutter analyze` 0 issues + `flutter test` **2963 全绿**（baseline 2957 → 2963，+6）。
- **缺口**：（已无 — `_runLogDataAction` 是项目内唯一"sync + apply 双段同 try 块"路径；`_runMergeStep` / `_runUpdateStep` 等步骤型方法是单段语义、`_addSelectedToPending` 是纯 UI 段无远程，均无对称漏洞）
- **关联文件**：`lib/screens/main_screen_v3.dart::formatLogApplyFailureFeedback / _runLogDataAction`、`test/main_screen_v3_test.dart`。

### P2 加载更多按钮 loading 状态指示器（第四十轮）

- **现状**：2026-06-02 第四十轮落地。
  - 真 bug：`lib/screens/components/log_list_panel.dart` `加载更多` `OutlinedButton.icon`（line 871+）在 `isLoading` 时仅 disable，icon 始终是 `Icons.unfold_more` 不变；同 panel 内"过滤"（第二十二轮已加 spinner）/ "同步最新"（长期已有 spinner）的 loading-aware icon 切换不对称。慢网络下点"加载更多"触发 `svn log` 远程拉更旧 revision 0.5-2s 期间按钮无视觉反馈，用户感知不到按钮在工作，反复点击或误以为按钮坏了。
  - 落地：`加载更多` 按钮 icon 三元化为 `isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.unfold_more, size: 16)`；文案 `'加载更多'` 不变（避免按钮宽度抖动），`onPressed: canLoadMore && !isLoading ? onLoadMore : null` 接线保留。
  - **决策权衡**：
    - **复用同款 16x16 SizedBox + strokeWidth: 2 spinner 而非新尺寸**：与"过滤"/"同步最新"按钮 spinner 完全同款，三按钮视觉对称；引入新尺寸会破坏 panel 内 loading 一致性。
    - **保留 `Icons.unfold_more` 非 loading 状态图标不变**：unfold_more 语义指"展开更多"，与"加载更多"文案对应；不需要单独换 icon。
    - **不改 label 文案**：label 是 `Text('加载更多')` 不动；如果改成"加载中..."，loading/idle 切换时按钮宽度会跳，三按钮 label 也都不变 spinner 期间，保持一致性。
    - **不抽 helper widget**：三按钮 spinner 字面量极短（5 行），抽 helper 引入间接层不值；contract test 用 "三按钮 spinner 字面量出现至少 3 次" 锁同款规格。
  - +5 测试（test/log_list_panel_test.dart 末尾新 group `加载更多按钮 loading 状态指示器（doc-as-test，第四十轮）`）：
    - isLoading 时 icon 走 CircularProgressIndicator(strokeWidth: 2) + 16x16 容器（字面量锁）
    - 非 loading 时 icon 仍走 `Icons.unfold_more`
    - label 保持 `'加载更多'` 不变（避免宽度抖动）
    - disabled 接线保持 `canLoadMore && !isLoading ? onLoadMore : null`
    - 三按钮 spinner 同款 contract — `CircularProgressIndicator(strokeWidth: 2),` 字面量在文件中至少出现 3 次（过滤 / 同步最新 / 加载更多）
- 验证：`flutter analyze` 0 issues + `flutter test` **2957 全绿**（baseline 2952 → 2957，+5）。
- **缺口**：（已无 — log_list_panel 内 3 个慢异步触发按钮 spinner 全部对齐；停止预加载 / 导出 CSV / 全选可选 / 清空选择 / 刷新列表均为本地操作或 fire-and-forget，不需要 spinner）
- **关联文件**：`lib/screens/components/log_list_panel.dart`、`test/log_list_panel_test.dart`。

### P1 打开冲突文件成功反馈与剩余数量提示（第三十九轮）

- **现状**：2026-06-02 第三十九轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_openConflictFile` 成功路径 `Process.run(command.executable, command.args)` 后**完全无 SnackBar 反馈**——异步 OS 命令打开文件，编辑器可能被 dock 隐藏 / 后台启动 / 启动慢，用户没有任何视觉确认按钮真的工作了，与项目内 `_openWorkingCopyDirectory` / cleanup / update / markResolved 等"调 SVN 后给反馈"家族不对称（不支持平台分支与异常分支已有 SnackBar，唯独成功分支沉默）。同时 `listConflictedFiles` 返回 N>1 时只取 `conflicted.first` 但**不告诉用户还有几个待处理**——SVN textConflict 通常一次暴露多个文件，用户改完点"继续"才会重检测，期间不知道还有几个，体感像是"按钮只能解决一个冲突"。
  - 落地：
    - 顶层 helper `formatOpenConflictFileFeedback({totalCount, openedRelative})`（`@visibleForTesting`，置于 `formatPendingAddSnackBar` 之后、`_LogSelectionContext` 之前）：两档分流 — `totalCount <= 1` → `'已打开冲突文件: $openedRelative'`；`totalCount > 1` → `'已打开冲突文件 1/$totalCount: $openedRelative；改完后点"继续"会自动检测剩余冲突'`。
    - `_openConflictFile` 在 `await Process.run(command.executable, command.args);` 后追加 `if (!mounted) return;` 守卫（R131 档 3 不变量 I1：跨 await SnackBar 必须前置 mounted check）+ `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatOpenConflictFileFeedback(totalCount: conflicted.length, openedRelative: relative))))`。
  - **决策权衡**：
    - **两档而非三档**：`totalCount == 0` 由外层 `if (conflicted.isEmpty)` 路径已弹"未发现冲突文件"拦掉，到 helper 时必有 ≥1；防御档 `totalCount <= 0` 走单冲突文案不崩（`<=` 而非 `==` 的边界容错）。
    - **"1/N" 文案而非 "1 of N"**：与项目内中文文案家族一致（`'已添加 X 个'` / `'已清空 N 个'` / `'已删除任务 #ID'`），且 `1/N` 比纯数字更直观传达"还有剩余"语义。
    - **明示"改完后点继续"**：用户改完 IDE 里的冲突文件后应当点暂停态的"继续"按钮，触发 `_runRevision` 复跑，merge 步后验（第三十三轮 `listConflictedFiles`）会重检测剩余冲突。如果不明示路径锚点，用户可能误以为要点"标记已解决"或"跳过"。
    - **保留"只开第一条"行为不变**：textConflict 一次解一个最聚焦，与 SVN 串行解决习惯一致（line 2708-2710 dartdoc 已说明）；改成一次性打开所有冲突反而难以聚焦、且与"跳过/继续"语义割裂。
    - **不弹反馈在不支持平台分支**：原 `else` 分支已有专门 SnackBar 提示绝对路径让用户手工打开；命令解析失败不属于"打开成功"，文案不应套用同款。
  - +5 测试（test/main_screen_v3_test.dart 新 group `formatOpenConflictFileFeedback`）：
    - 4 helper 真值表：`totalCount=1` 简版 / `totalCount=2` 含 1/2 + 改完点继续 / `totalCount=10` 含 1/10 + 改完点继续 / 防御 `totalCount=0` 走单冲突分支不崩。
    - 1 lib 字面量锁：helper 函数定义存在 / 两档文案字面量（`'已打开冲突文件: $openedRelative'` 与 `'已打开冲突文件 1/$totalCount: $openedRelative；改完后点"继续"会自动检测剩余冲突'`）/ `_openConflictFile` 调 helper 而非内联 / `Process.run → if (!mounted) return; → helper` 顺序锁（同一路径内 mounted 守卫先于 helper 调用）。
- 验证：`flutter analyze` 0 issues + `flutter test` **2952 全绿**（baseline 2947 → 2952，+5）。
- **缺口**：（已无 — `_openConflictFile` 是项目内最后一处"调外部命令成功路径无反馈"的破坏性 / 阻塞性按钮；与 cleanup/update/markResolved 后验家族对称闭合）
- **关联文件**：`lib/screens/main_screen_v3.dart::formatOpenConflictFileFeedback / _openConflictFile`、`test/main_screen_v3_test.dart`。

### P2 调整重试上限 dialog 数字输入过滤对齐设置页（第三十八轮）

- **现状**：2026-06-02 第三十八轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_adjustJobMaxRetries` AlertDialog 内的 TextField（line 2606+）仅设 `keyboardType: TextInputType.number`，**缺 `inputFormatters: [FilteringTextInputFormatter.digitsOnly]`**，与 `lib/screens/settings_screen.dart` 内 4 个数字字段（`_maxRetriesController` / `_maxDaysController` / `_maxCountController` / `_stopRevisionController`）的 input filtering 家族不一致——用户可输入 `-5` / `1.5` / `abc`，被 `updateJobMaxRetries` 的 `< 0` 守卫拒掉，弹通用 SnackBar `'调整失败：新值必须是大于当前上限的非负整数'`，把"格式无效"和"小于上限"两个语义混在一条文案里。
  - 落地：
    - 主屏文件 `import 'package:flutter/services.dart';` 加入 import 块（原仅有 material / file_picker / path / provider）。
    - TextField 加 `inputFormatters: [FilteringTextInputFormatter.digitsOnly]`，与 settings_screen 完全同款。
    - SnackBar 失败文案改为 `'调整失败：新值必须大于当前上限 ${job.maxRetries}'`——formatter 已挡住非数字 / 负号 / 小数点 / 字符，剩余唯一失败路径就是 `≤ 当前上限`，文案精确指向用户实际输入与拒绝条件的差距。
  - **决策权衡**：
    - **复用 settings_screen 同款 formatter 而非新写 helper**：FilteringTextInputFormatter 是 framework 层 stable API，formatter list 内字面量极短（一行），不值得抽 helper 引入间接层；input filtering 家族一致性靠 doc-as-test 字面量锁。
    - **不加上限校验**：`updateJobMaxRetries` 的 `<= job.maxRetries` 守卫已是上限策略；若加任意上限（如 `<= 1000`）反而限制用户合理使用场景（用户可能确实想跑大量 out-of-date 重试）。
    - **改文案而非保留**：原文案"非负整数"在 formatter 加入后变成不可达分支，留着会误导未来 reader 以为还有此校验路径。
  - +2 测试（test/main_screen_v3_test.dart `_adjustJobMaxRetries` group 内）：
    - inputFormatters 字面量锁（`inputFormatters: [FilteringTextInputFormatter.digitsOnly]` 在方法 body 内出现）。
    - import 锁（`import 'package:flutter/services.dart';` 在文件中出现）。
    - 同时改写既有"失败 SnackBar 文案"测试以匹配新文案 `'调整失败：新值必须大于当前上限 ${job.maxRetries}'`。
- 验证：`flutter analyze` 0 issues + `flutter test` **2947 全绿**（baseline 2945 → 2947，+2）。
- **缺口**：（已无 — 主屏唯一的运行时数字输入 dialog 已对齐设置页 input filtering 家族；ConfigDialog 内为 URL / 路径输入，非数字字段不适用）
- **关联文件**：`lib/screens/main_screen_v3.dart::_adjustJobMaxRetries`、`test/main_screen_v3_test.dart`。

### P1 添加到待合并 SnackBar 反馈数对齐真实新增数（第三十七轮）

- **现状**：2026-06-02 第三十七轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_addSelectedToPending` 早期版本固定弹 `_showSuccess('已添加 $count 个 revision')`，`count = _selectedRevisions.length`。但 `appState.addPendingRevisions` 转发到 `mergePendingRevisions`，对 incoming 与 existing 做 union 去重——如果用户选中的 revision 已在 pendingRevisions（再次添加 / 跨筛选切换 / 跨页选择），实际新增数 `< count`，但 SnackBar 仍报 count，与项目其它"反馈数 == 真实数"家族（`_showInfo('已清空 N 个待合并 revision')` / `_showSuccess('已删除任务 #ID')`）不一致——属于真 UX bug 而非纯样式分歧。
  - 落地：
    - 顶层 helper `formatPendingAddSnackBar({required int selectedCount, required int addedCount}) -> String`（`@visibleForTesting`，置于 `resolveCanLoadMore` 之后、`_LogSelectionContext` 之前）：三档分流——`addedCount == 0` → `'全部 $selectedCount 个 revision 已在待合并列表中'`；`addedCount == selectedCount` → 保留原文案 `'已添加 $addedCount 个 revision'`（兼容用户肌肉记忆）；`0 < addedCount < selectedCount` → `'已添加 $addedCount 个 revision（其中 ${selectedCount - addedCount} 个已在列表中跳过）'`。
    - `_addSelectedToPending`：在 `appState.addPendingRevisions(...)` 调用前后取 `appState.pendingRevisions.length` 差值算 `addedCount`，喂给 helper；保留 `selectedCount = _selectedRevisions.length` 快照（在 setState clear 之前取）。`_showSuccess` 由内联文案改为 `_showSuccess(formatPendingAddSnackBar(...))`。
  - **决策权衡**：
    - **三档而非两档**：`addedCount == 0` 单独成档，避免"已添加 0 个 revision（其中 N 个已在列表中跳过）"这种语义割裂的文案；用户全选已存在 revision 是真实存在的误操作场景。
    - **保留原文案在 `addedCount == selectedCount` 档**：兼容现有用户肌肉记忆，不必在"全新增"路径上动文案；只在真有去重发生的场景上加额外信息。
    - **不改 `addPendingRevisions` 返回值**：保持 AppState API 表面不变，由 caller 自己取 length 差值算新增数（与现有代码风格一致——provider mutator 多为 void 风格）。
  - +7 测试（test/main_screen_v3_test.dart 末尾新 group `formatPendingAddSnackBar`）：
    - 6 helper 真值表：`addedCount == 0` / `addedCount == selectedCount`（多元素）/ 部分跳过（7→4）/ 单元素全新增 / 单新增多跳过（5→1）/ 防御 `selectedCount == 0`。
    - 1 lib 字面量锁：helper 函数定义存在 / `_addSelectedToPending` 调 `_showSuccess(formatPendingAddSnackBar(...))` / 前后取 `pendingRevisions.length` 差值（`beforeLen` + `addedCount`）/ 原内联 `_showSuccess('已添加 \$count 个 revision')` 已消失。
- 验证：`flutter analyze` 0 issues + `flutter test` **2945 全绿**（baseline 2938 → 2945，+7）。
- **缺口**：（已无 — `_addSelectedToPending` 是项目内最后一处"反馈数与真实数可能背离"的破坏性 / 数量类 SnackBar 站点）
- **关联文件**：`lib/screens/main_screen_v3.dart::formatPendingAddSnackBar / _addSelectedToPending`、`test/main_screen_v3_test.dart`。

### P1 日志对话框清空按钮二次确认（第三十六轮）

- **现状**：2026-06-02 第三十六轮落地。
  - 真 bug：`lib/screens/components/dialogs/log_dialog.dart` "清空"按钮（IconButton, Icons.clear_all）原直连 `widget.onClear() + Navigator.pop()`，与紧邻的"复制"按钮（Icons.copy_all）极易误点；日志栏内含上百行 SVN/合并排查信息（MergeExecutor 限 600 行），误清不可恢复。同期 PendingPanel + JobQueuePanel 内 5 个破坏性操作（删除单条 / 清空待执行 / 终止任务 / 清理历史 / 清空待合并）已 100% 走 `_confirmQueueAction` 兜底，log_dialog 清空按钮是这条覆盖率收口的对称漏洞。
  - 落地：
    - 顶层 helper `buildClearLogConfirmMessage({required int lineCount}) -> String`（`@visibleForTesting`）：`lineCount > 0` 走 `'将清空当前 \$lineCount 行日志，操作不可恢复。'`（与第三十五轮 `_clearPendingRevisions` 文案家族同型）；`<= 0` 走占位 `'当前没有日志可清空。'`（防御 caller 传 0 / 负数，UI 已 isEmpty 早退跳过 dialog）。
    - 实例方法 `Future<void> _confirmClearLog(BuildContext context) async`：① `widget.log.isEmpty` → `Navigator.of(context).pop()` 早退（不弹 confirm dialog；空日志清空是 no-op，不打扰用户）→ ② `await showDialog<bool>` AlertDialog（标题 `'清空日志？'` + content 调 helper 渲染 + 取消默认 false / 清空 true 红色 TextButton 双按钮）→ ③ `if (confirmed != true) return;` → ④ `if (!context.mounted) return;`（跨 await 守卫先于 widget.onClear() 满足 R131 档 3 不变量 I1）→ ⑤ `widget.onClear();` → ⑥ `Navigator.of(context).pop();`。
    - IconButton onPressed 由裸调 `() { widget.onClear(); Navigator.of(context).pop(); }` 改为 `() => _confirmClearLog(context)`。`widget.onClear()` 字面量在源码中只剩 1 处（在 `_confirmClearLog` 内）。
  - **决策权衡**：
    - **不复用 `_confirmQueueAction`**：log_dialog 是独立 widget 自带 BuildContext，main_screen_v3 的 helper 是 private 跨库不可用；写 inline showDialog 更内聚。
    - **空日志早退跳过 dialog 直接 pop**：与 `_clearPendingRevisions` 的 `isEmpty` 早退对偶（空列表清空是 no-op）；不弹 dialog 让"复制错误的按钮"行为退化为"什么也不做但关闭对话框"，对用户最少打扰。
    - **取消按钮在左、清空在右红色警示**：与系统对话框惯例一致；红色用 `style: TextButton.styleFrom(foregroundColor: Colors.red)`。
    - **跨 await `context.mounted` 守卫先于 widget.onClear()**：满足 R131 档 3 不变量 I1（StatefulWidget 跨 await setState/破坏性副作用必须前置 mounted check），与第三十五轮 `_clearPendingRevisions` 同款守护。
  - +15 测试：
    - 5 helper 真值表：`lineCount > 0` / `= 1` / `= 0` / `< 0` / 末尾"操作不可恢复"。
    - 4 widget 行为：非空日志点清空弹 confirm 不立刻清 / 取消不调 onClear / 确认调 onClear + 关 LogDialog / 空日志跳过 confirm 直接关。
    - 6 doc-as-test：helper 签名 + `@visibleForTesting` / 字面量锁 / `_confirmClearLog` 方法签名 + isEmpty 早退顺序 / showDialog content 复用 helper + pop(false)/pop(true) / `!confirmed → mounted → onClear → pop` 顺序锁 / IconButton onPressed 切到 `_confirmClearLog` + `widget.onClear()` 计数=1。
- 验证：`flutter analyze` 0 issues + `flutter test` **2938 全绿**（baseline 2923 → 2938，+15）。
- **缺口**：（已无 — log_dialog "清空"是该 widget 唯一破坏性按钮，"复制"非破坏性无需 confirm；主屏 PendingPanel + JobQueuePanel + log_dialog 内所有破坏性按钮 100% 走二次确认兜底）
- **关联文件**：`lib/screens/components/dialogs/log_dialog.dart::buildClearLogConfirmMessage / _confirmClearLog`、`test/log_dialog_test.dart`。

### P1 清空待合并列表二次确认（第三十五轮）

- **现状**：2026-06-02 第三十五轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_clearPendingRevisions` 原是同步函数，PendingPanel 标题区"清空待合并"按钮（IconButton onPressed: onClearPending）直连 `appState.clearPendingRevisions()` 无任何确认。用户手工挑选数十/上百个 revision 加入"待合并"列表后误点该按钮 → 整个列表丢失、不可恢复。同 panel 的 `_cancelPausedJobWithConfirm` / `_deleteQueueJob` / `_clearPendingJobs` / `_clearFinishedJobs` 已 100% 走 `_confirmQueueAction` AlertDialog 二次确认，唯有此处裸调，破坏性操作 confirm 覆盖率有缺口。
  - 落地：
    - `_clearPendingRevisions` 升级为 `Future<void>` async：在 `pendingRevisions.isEmpty` 早退之后、`appState.clearPendingRevisions()` 之前 `await _confirmQueueAction(title: '清空待合并列表', message: '将移除 \$count 个待合并 revision，操作不可恢复。', confirmLabel: '清空')`。`!confirmed` → return。
    - 跨 await 边界后追加 `if (!mounted) return;`（R131 档 3 不变量 I1：跨 await 后 setState 必须前置 mounted check）。
    - `widget_setstate_protocol_test.dart` R131 档 1 测试中关于 `_clearPendingRevisions` 的 reason 文本同步改写为"档 3：confirm 后清 pendingSourceUrl，前置 mounted 守护"。
  - **决策权衡**：
    - **复用 `_confirmQueueAction` helper**：与同 panel 其它破坏性按钮（删除单条 / 清空待执行 / 终止任务 / 清理历史）对偶，模式一致；不重新造 dialog。
    - **message 透传 `\$count` + 含"不可恢复"四字**：让用户从 SnackBar 头部就能感知"这次清空会丢什么"，并明示不可恢复，不诱导误点。
    - **保留 isEmpty 早退在 confirm 之前**：空列表无需弹无意义对话框；与 `_deleteQueueJob` 的 `job==null` 早退顺序对偶。
    - **保留 `setState(() => _pendingSourceUrl = null)` + `_showInfo('已清空 $count 个待合并 revision')`**：confirm 后清状态 + 反馈，与裸调时一致；唯一区别是 confirm 与 mounted 守卫前置。
  - +4 doc-as-test：async 方法签名锁 / `await _confirmQueueAction(` 调用 + 文案字面量（title / confirmLabel / `\$count` 透传 / "不可恢复"）/ `!confirmed return` 顺序锁（confirm 前 isEmpty 早退、confirm 后 clear 调用）/ R131 档 3 mounted 守卫前置 setState。
- 验证：`flutter analyze` 0 issues + `flutter test` **2923 全绿**（baseline 2920 → 2923，+3）。
- **缺口**：（已无 — 主屏 PendingPanel + JobQueuePanel 内所有破坏性操作 100% 走 `_confirmQueueAction` 兜底）
- **关联文件**：`lib/screens/main_screen_v3.dart::_clearPendingRevisions`、`test/main_screen_v3_test.dart`、`test/widget_setstate_protocol_test.dart`。

### P1 svn merge 后补 listConflictedFiles 后验（_runMergeStep）

- **现状**：2026-06-02 第三十三轮落地。
  - 真 bug：`lib/providers/merge_execution_state.dart::_runMergeStep` 原仅 `await _wcManager.merge() / _appendLog('r$revision 合并成功')` 后即把步骤快照标记为 completed，跳进下一步 commit。但 `svn merge` 在文件级冲突时仅把冲突文件标 'C' 状态、**仍正常返回（不抛 SvnException）**——也就是说 merge step 看似"成功"，实际工作副本里有冲突。然后下一步 commit 时才以 `'svn: E155015 commit failed: ... remains in conflict'` 形式抛错——错误归 commit 步而非 merge 步、`_resolveResumeStepId(failedSnapshot)` 把 `resumeFromStepId` 设到 commit、暂停语境也对应到 commit 步而非 merge 步，跟用户实际的失败点（merge 触发的冲突）严重错位。与第二十八轮 markResolved / 第三十/三十一轮 cleanup / 第三十二轮 update 后验家族**完美对称**——这是"成功后调 SVN 后验"在 merge 步的最后一块对称版图。
  - 落地：
    - `_runMergeStep` 在 `await _wcManager.merge(...)` 后追加 `final conflicts = await _svnService.listConflictedFiles(job.targetWc); if (conflicts.isNotEmpty) throw StateError('合并 r$revision 产生 ${conflicts.length} 个冲突文件，请手动解决');`。
    - throw 文案故意含"冲突"中文字面量 → 外层 `_runRevision` catch 块通过 `step.id == kMergeStepId && _looksLikeConflict(message)`（即 `isMergeConflictMessage`）路径直接 `return _RevisionRunResult.paused`，把任务挂起。
    - 暂停归位到 merge 步：`_currentStepId == kMergeStepId` 时抛错 → `_failSnapshot` 标 merge 步 failed → `_currentFailedSnapshot()` 拿到该 snapshot → `_resolveResumeStepId` 走 `kMergeStepId` 分支返回 merge → `pausedJob.resumeFromStepId == 'merge'` → 用户点"继续"时从 merge 步重跑（先 prepare-revert 把冲突 'C' 文件 revert 干净，再重新 merge），不会错位到 commit。
    - 测试：`_FakeSvn` 加 `listConflictedFilesScript: List<List<String>>` scriptable + `listConflictedFilesCalls` 调用计数；新增 group "_runMergeStep merge 后补 listConflictedFiles 后验"（端到端：merge 后 'C' 状态 → 任务暂停归 merge 步 / wc.commitCalls=0 / mergeinfo 不收录 + merge 后无 'C' → 正常进 commit、最终 done）+ group "_runMergeStep doc-as-test"（方法签名锁 / `listConflictedFiles` 调用 / `throw StateError` + 字面量 / `conflicts.length` 透传 / merge → listConflictedFiles 顺序锁 / "冲突文件" 字面量是 `_looksLikeConflict` 锚点 / 成功路径仍输出 "r\$revision 合并成功" 日志）。
  - **决策权衡**：
    - **抛 StateError 而非 return paused enum**：复用 `_runRevision` 现成的 catch 块——一旦走 catch 路径，`_failSnapshot` / `_currentStepId == kMergeStepId` / `_looksLikeConflict` 路由全部自动归位到 merge 步，不需要在 `_runMergeStep` 内手动构造 _RevisionRunResult。throw 是契约载体，外层是契约消费者，与 `_runUpdateStep` 抛 StateError 触发 retryFromUpdate / pause 决策完全同构（R98 throw 对称性维度）。
    - **throw 文案含"冲突"中文字面量**：`isMergeConflictMessage` 接受 'conflict' / '冲突' / 'tree conflict' 三种碎片，本 throw 走中文路径让 catch 块的 `_looksLikeConflict(message)` 判定立刻命中 → 走 merge 步特化暂停路径（line 1439-1441）。如果文案不含这些 token，会回落到 `evaluateStepFailure` → 默认仍 pause，行为正确但语义锚点错位。
    - **不复用 `hasConflicts`**：bool 没法报具体数量；用 `listConflictedFiles` 的 `.length` 让用户从 pauseReason 文本里立刻看到"产生 N 个冲突文件"，与第三十二轮 update 后验同款数量透传。
    - +9 新测试：2 端到端 flow（暂停归 merge 步 / 正常进 commit）+ 7 doc-as-test（方法签名 / listConflictedFiles 调用 / throw 字面量 / .length 透传 / 顺序锁 / "冲突"锚点 / 成功日志保留）。
- 验证：`flutter analyze` 0 issues + `flutter test` **2911 全绿**（baseline 2902 → 2911，+9）。
- **缺口**：（已无 — "成功后调 SVN 后验"家族在 markResolved / cleanup（暂停态+工具栏）/ update（工具栏 + merge job）/ merge 五个入口全部闭合。`_runPrepareStep` 的 revert 不会产生冲突，`_runCommitStep` 的 commit 失败本就在 _runRevision catch 块里直接 pause/retry，无对称漏洞）
- **关联文件**：`lib/providers/merge_execution_state.dart::_runMergeStep`、`test/merge_execution_state_flow_test.dart`。

### P1 svn update 后补 listConflictedFiles 后验（_runUpdateStep / merge job 内部）

- **现状**：2026-06-02 第三十四轮落地。
  - 真 bug：`lib/providers/merge_execution_state.dart::_runUpdateStep` 原仅检查 `result.isSuccess`，成功就直接 `_appendLog('工作副本已更新到最新版本')` 把步骤标 completed 进入 merge 步。但 `svn update` 在服务器侧改动与本地修改产生冲突时仅把文件标 'C' 状态、**仍 exit 0**（`result.isSuccess == true` 不保证 WC 干净）——update 步看似成功，'C' 状态文件留在 WC 里被下一步 merge 步的后验（第三十三轮）误判为"merge 产生的冲突"，错位归到 merge 步暂停。用户点"继续"→ prepare 又 revert 把 'C' 文件清掉、update 又出 'C'、merge 又误判，**形成循环**。第三十二轮闭合的是主屏工具栏 `_svnUpdate` 入口，本轮闭合的是 merge job 流程内部的 `_runUpdateStep` 入口——两个 update 入口对称，**第三十二轮只覆盖了一半**，本轮才补齐。
  - 落地：
    - `_runUpdateStep` 在 `result.isSuccess` 后追加 `final conflicts = await _svnService.listConflictedFiles(job.targetWc); if (conflicts.isNotEmpty) throw StateError('更新工作副本产生 ${conflicts.length} 个冲突文件，请手动解决');`，**在 "已更新到最新版本" 日志之前**（成功语义保护——后验失败必须先抛错，不能让"已更新"日志误导用户）。
    - 外层 `_runRevision` catch 块通过 `evaluateStepFailure(stepId: 'update', ...)` 默认走 `StepFailureAction.pause` 分支，pauseReason / resumeFromStepId 都归到 update 步，与第三十三轮 merge 后验归 merge 步形成对称归位（不复用 merge 步的 `_looksLikeConflict` 特判路径——update 步本身没有 conflict-step 特化分支，evaluateStepFailure 默认 pause 已经够用）。
    - 测试：第三十三轮的 _runMergeStep 端到端 test 需要在 `listConflictedFilesScript` 里先垫一项空列表（update 步先调一次后验返回干净），merge 后验才能拿到第二项的 'C' 文件。新增 group "_runUpdateStep update 后补 listConflictedFiles 后验"（端到端：update 后 'C' 状态 → 任务暂停归 update 步 / wc.mergeCalls=0 / wc.commitCalls=0 / mergeinfo 不收录 + update 后无 'C' → 正常进 merge 步、最终 done、listConflictedFilesCalls ≥ 2 + group "_runUpdateStep doc-as-test"（方法签名锁 / `listConflictedFiles` 调用 / `throw StateError` + "更新工作副本产生" + "冲突文件" 字面量 / `.length` 透传 / 顺序锁（update 后 → list 调用） / 后验调用必须在 "已更新到最新版本" 日志之前）。
  - **决策权衡**：
    - **同款 throw StateError + 默认 pause 路径**：与第三十三轮 _runMergeStep 形态完全对称，唯一区别是 update 步不走 `_looksLikeConflict` 特判（merge 步特判仅用于 conflict-step 特化）；update 步走 `evaluateStepFailure` 默认 pause 即可正确归位。
    - **后验调用先于"已更新"日志**：成功语义保护——如果先打"已更新到最新版本"再后验失败抛错，日志流里会先写"成功"再写"失败"，自相矛盾。`flow_test.dart` 用 `body.indexOf` 锁顺序。
    - **不复用 hasConflicts**：bool 没法报具体数量；用 `.length` 让 pauseReason 文本立刻显示"产生 N 个冲突文件"，与第三十二/三十三轮同款数量透传。
    - +9 新测试：2 端到端 flow + 7 doc-as-test。
- 验证：`flutter analyze` 0 issues + `flutter test` **2920 全绿**（baseline 2911 → 2920，+9）。
- **缺口**：（已无 — "成功后调 SVN 后验"家族在 markResolved / cleanup×2 / update（工具栏 + merge job）/ merge **六个入口全部闭合**）
- **关联文件**：`lib/providers/merge_execution_state.dart::_runUpdateStep`、`test/merge_execution_state_flow_test.dart`。

### P1 svn update 后补 listConflictedFiles 后验（工具栏入口，第三十二轮）

- **现状**：2026-06-02 第三十二轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_svnUpdate`（主屏工具栏"更新"按钮入口）原仅检查 `result.isSuccess`，弹"更新完成"成功 SnackBar。但 `svn update` 在服务器侧改动与本地修改产生冲突时，svn 仅把冲突文件标 'C' 状态并仍返回 exit 0——也就是说 `result.isSuccess == true` **不**保证 working copy 真的干净。用户随后启动合并任务又因 'C' 状态文件再次冲突暂停，体验割裂（点了"更新"但 WC 实际仍有冲突）。与第二十八轮 `_markConflictsResolved` / 第三十/三十一轮 `_runSvnCleanup` + `_svnCleanup` 的"成功后调 SVN 后验"家族**完美对称**。
  - 落地：
    - 顶层 helper `formatUpdateFeedback({int remainingConflictCount = 0}) -> String`（`@visibleForTesting`）—— 两档分流：`remainingConflictCount <= 0`（含负数防御）走 `'更新完成，工作副本干净'`；`> 0` 走 `'已执行 svn update，但仍有 N 个冲突文件，请手动解决'`，显式不含"继续"二字（不诱导用户点继续）。
    - `_svnUpdate` 成功分支重写：`final conflicts = await _svnService.listConflictedFiles(targetWc); if (!mounted) return; final message = formatUpdateFeedback(remainingConflictCount: conflicts.length); conflicts.isEmpty ? _showSuccess(message) : _showError(message);`。失败分支 / catch 分支保持原文案完全不变。`_updateMergedStatus` 副作用保留（无论是否有冲突，merged 状态都需刷新）。
    - 冲突非空时额外补 `AppLogger.ui.error('update 后仍有冲突: ${conflicts.length} 个')` —— SnackBar 转瞬即逝，运行日志须留痕便于事后排查。
  - **决策权衡**：
    - **helper 命名维度对齐 `formatMarkResolvedFeedback` 而非 `formatCleanupFeedback`**：update 后验维度是冲突数 int（同 markResolved），而非 cleanup 的 probe 错误 String?。helper 接 int 把"是否警告"和"剩余数量"统一在一个入参，单测真值表更紧凑。
    - **复用 `listConflictedFiles` 而非 `hasConflicts`**：bool 没法在文案里报"还剩 N 个"具体数量；同一份 svn status 解析既能反映 bool 等价语义又能告诉用户具体数量。
    - **保留 `_updateMergedStatus`**：本轮仅补冲突后验，不动"更新成功后刷新 merged 状态"现有副作用——已下载到本地的 revision 仍应当被刷新到 mergeinfo 缓存便于待合并列表反映最新状态。
    - **`_showSuccess` / `_showError` 视觉立辨**：与第三十一轮 `_svnCleanup` 同款，让用户从 SnackBar 颜色立辨"WC 真干净 vs 仍有冲突"。
    - +17 doc-as-test：helper 7（0 / 默认 / 负数 / 1 / N / 视觉立辨 / 警告不诱导继续）+ `_svnUpdate` 接线 10（方法签名锁 / listConflictedFiles 调用 / formatUpdateFeedback 调用 / conflicts.length 透传 / mounted 守卫 / `_showSuccess(message)` + `_showError(message)` 视觉立辨 / `'更新完成'` inline 已删 / 失败分支不变 / catch 分支不变 / `AppLogger.ui.error('update 后仍有冲突'` 留痕 / 保留 `_updateMergedStatus` 副作用）。
- 验证：`flutter analyze` 0 issues + `flutter test` **2902 全绿**（baseline 2885 → 2902，+17）。
- **缺口**：（已无 — `_svnRevert` 经确认无此缺口，`svn revert` 总是回退到 BASE 不会产生冲突；`_svnUpdate` 主屏入口闭合后 update 路径无对称漏洞）
- **关联文件**：`lib/screens/main_screen_v3.dart::formatUpdateFeedback / _svnUpdate`、`test/main_screen_v3_test.dart`。

### P1 cleanup 后补 probeSvnLocation 后验（暂停态 + 主屏工具栏双入口）

- **现状**：2026-06-02 第三十一轮落地（第三十轮 + 第三十一轮分别闭合两个 cleanup 入口的对称漏洞）。

#### 第三十一轮（2026-06-02）：主屏工具栏 `_svnCleanup` 同款补后验

- 真 bug：第三十轮闭合了暂停态 `_runSvnCleanup` 的隐藏漏洞，但主屏工具栏 `lib/screens/main_screen_v3.dart::_svnCleanup`（用户点击"清理工作副本"按钮入口）仍是 `if (result.isSuccess) _showSuccess('清理完成');` 的旧实现——同款 cleanup exit 0 不保证 WC 可用的逻辑漏洞，与第三十轮的隐藏漏洞**完美对称**（同样的"WC 结构性损坏 / 文件锁未释放 / .svn 元数据损坏"场景下，主屏入口仍会误报清理完成，让用户继续操作 WC 时再次踩坑）。
- 落地：
  - 扩展 helper `formatCleanupFeedback({String? probeError, bool resumePrompt = true}) -> String` —— 加 `resumePrompt` 入参分流两个 caller 的语境。`true`（默认，向后兼容暂停态）：成功 `'已执行 svn cleanup，可点击"继续"重试'` / 警告末尾 `'请手动检查后再继续'`。`false`（主屏工具栏）：成功 `'清理完成，工作副本已可用'` / 警告末尾 `'请手动检查'`（无"再继续"，主屏不在 暂停 → 继续 语境）。
  - `_svnCleanup` 成功分支重写：`final probeError = await _svnService.probeSvnLocation(targetWc, role: '工作副本'); if (!mounted) return; final message = formatCleanupFeedback(probeError: probeError, resumePrompt: false); probeError == null || probeError.isEmpty ? _showSuccess(message) : _showError(message);`。失败分支 / catch 分支保持原文案完全不变。
  - probe 失败时额外补 `AppLogger.ui.error('cleanup 后 WC 仍不可用: $probeError')` —— SnackBar 转瞬即逝，运行日志须留痕便于事后排查。
- **决策权衡**：
  - **复用同一 helper 而非新增 `formatToolbarCleanupFeedback`**：两个入口语境差异仅是"是否在 暂停 → 继续 流程中"，单一参数即可表达，避免 helper 家族分裂。资料库（test 文件）的真值表也得以横向扩展而非新增。
  - **用 `_showSuccess` / `_showError`（绿/红 SnackBar）而非 `ScaffoldMessenger.showSnackBar` 中性背景**：主屏工具栏是用户主动操作，需要让用户从 SnackBar 颜色立辨"WC 真的可用 vs WC 仍不可用"。这与 `_runSvnCleanup`（暂停态）走 `ScaffoldMessenger.showSnackBar(SnackBar(content: ...))` 中性显示**有意不同**——暂停态用户已经知道 WC 出过问题，关注重点是"下一步是否能继续"；主屏入口用户的关注重点是"清理动作的结果"。
  - **resumePrompt: false 时去掉"再继续"尾巴**：主屏工具栏点完 cleanup 通常不会立即跑 merge，"请手动检查后再继续" 反而显得 push；改为 "请手动检查" 让指引止于 actionable 单步。
  - +17 doc-as-test：helper resumePrompt 维度 7（默认值兼容 / false × null / false × empty / false × 非空不诱导继续 / true vs false 成功文案首字母不同 / true vs false 警告 tail 不同 / 两种语境都不二次翻译 probeError）+ `_svnCleanup` 接线 10（方法签名锁 / probe 调用 + role 字面量 / formatCleanupFeedback 调用 / resumePrompt: false / mounted 守卫 / `_showSuccess(message)` + `_showError(message)` 视觉立辨 / `'清理完成'` inline 已删 / 失败分支不变 / catch 分支不变 / `AppLogger.ui.error('cleanup 后 WC 仍不可用'` 留痕）。
- 验证：`flutter analyze` 0 issues + `flutter test` **2885 全绿**（baseline 2868 → 2885，+17）。

#### 第三十轮（2026-06-02）：暂停态 `_runSvnCleanup` 首启 `formatCleanupFeedback` + WC 后验

- 真 bug：`lib/screens/main_screen_v3.dart::_runSvnCleanup` 原仅检查 `result.isSuccess`，弹"已执行 svn cleanup"成功 SnackBar。但 `svn cleanup` exit 0 **不**保证 working copy 真的可用——cleanup 只能处理"卡住的事务"，处理不了"WC 结构性损坏 / 外部进程仍占用文件 / .svn 元数据被破坏 / 磁盘 / 权限故障"。用户看到成功后点"继续"，任务又在下一步因 .svn 不可读 / 文件锁未释放再次暂停，体验割裂（点了"清理"但 WC 仍不可用）。与第二十八轮 `_markConflictsResolved` 后验 `listConflictedFiles` 完全对称（成功 + 后验文案家族）。
- 落地：
  - 顶层 helper `formatCleanupFeedback({String? probeError}) -> String`（`@visibleForTesting`）—— 两档分流：`probeError == null || probeError.isEmpty` 走原成功文案 `'已执行 svn cleanup，可点击"继续"重试'`；非空走警告 `'已运行 svn cleanup，但工作副本仍不可用：<probeError>，请手动检查后再继续'`，显式禁止用户直接点"继续"。
  - `_runSvnCleanup` 在 `result.isSuccess` 后追加 `final probeError = await _svnService.probeSvnLocation(targetWc, role: '工作副本');`（复用第二十六/二十九轮同款 probe 入口家族），守 mounted，结果直接透传给 helper 决定文案分流。
- **决策权衡**：
  - 用 `probeSvnLocation`（svn info）而非 `hasConflicts` / `status` —— cleanup 修复的是事务锁/元数据，后验维度应当是"WC 元数据是否可读"而非"是否有冲突标记"；`svn info <wc>` 是最直接的"WC 是否可用"探针，错误翻译复用 `formatProbeFailureReason` 单一来源。
  - role 入参 `'工作副本'`（非 `'目标工作副本'`）—— cleanup 仅 probe 一项 path，role 表语境而非区分谁是谁；与 `_startMerge` / `_testSvnConnectivity` 双 probe role 风格区分但同款入口家族。
  - 失败分支文案完全不变（保留原 `'cleanup 失败: <stderr>'`）—— 本轮仅修复"成功但 WC 仍不可用"的隐藏漏洞，不动 cleanup 自身失败语义。
  - +14 doc-as-test：helper 7（null/缺省/empty/非空 probeError 真值表 + 警告"请手动检查"指引 + 首字母视觉差异 + 不诱导"继续"二字）+ `_runSvnCleanup` 接线 7（签名锁 / probe 调用 + role 字面量 / formatCleanupFeedback 调用 / probeError 透传 / mounted 守卫 / inline 字面量已删 / 失败分支不变）。
- 验证：`flutter analyze` 0 issues + `flutter test` **2868 全绿**（baseline 2854 → 2868，+14）。

- **缺口**：（已无 — locked / unknown 暂停态再无 cleanup 后验缺口；主屏与暂停态两个 cleanup 入口 100% 对称闭合）
- **关联文件**：`lib/screens/main_screen_v3.dart::formatCleanupFeedback / _runSvnCleanup / _svnCleanup`、`test/main_screen_v3_test.dart`。

### P1 network 暂停态测试连通性按钮

- **现状**：2026-06-02 第二十九轮落地。
  - 真缺口：第二十六轮已落地"启动合并前 SVN 连通性预校验"（`_startMerge` 调 `probeSvnLocation` 探测 sourceUrl/targetWc），但任务执行中遇到 network 故障暂停后，用户**没有同款入口**验证网络是否恢复——只能盲点"继续"重试整个 merge step（耗时长 + 失败后再次入暂停 + 浪费一次重试计数）。与 `cleanup`（locked） / `adjustMaxRetries`（outOfDate）等"暂停态专属恢复入口"家族形成对称漏洞。
  - 落地：
    - `lib/screens/components/merge_execution_panel.dart` 顶层谓词 `shouldShowTestConnectivityButton(SvnFailureKind)` (`@visibleForTesting`)：仅 `network` 返回 true，其他 8 mode 返回 false。dartdoc 详述每种 failureKind 不渲染的理由（authFailed → 匿名 probe 误导；notFound → URL 配置错误本按钮无修复能力；textConflict / treeConflict / locked / outOfDate / workingCopyCorrupt / unknown → 与网络无关或具误导性）。
    - `MergeExecutionPanel.onTestConnectivity: VoidCallback?` 字段 + 构造函数加 `this.onTestConnectivity`。Wrap 内紧跟 `onAdjustMaxRetries` 后追加 `OutlinedButton.icon(icon: Icons.wifi_find, label: '测试连通性')`，cyan 配色（区别于 cleanup teal / adjustMaxRetries indigo / mark-resolved 绿 / open-conflict 紫）。
    - `lib/screens/main_screen_v3.dart::_testSvnConnectivity(MergeJob job)` —— 复用第二十六轮 `probeSvnLocation`，依次 probe `job.sourceUrl` 与 `job.targetWc`，每个 await 后立即 mounted 守卫；任一非 null → `_showError(reason)` + return；双 null → `_showSuccess('连通性正常，SVN 可访问，可点击"继续"重试')`。**不**自动 resume，与 cleanup / mark-resolved / adjustMaxRetries 同款显式触发。
    - 接线 `onTestConnectivity: mergeState.pausedJob == null ? null : () => _testSvnConnectivity(mergeState.pausedJob!)`。
  - **决策权衡**：
    - 用 `pausedJob` 自带的 sourceUrl/targetWc 而非主屏 controller —— 暂停态任务的配置是创建时的副本（与第十轮 `shouldWarnBeforeEditingConfig` 文案"任务自带配置副本"一致），用主屏 controller 可能测的是用户后改的新配置，跟当前任务无关。
    - 顺序 probe 而非并行 —— 错误信息要明确告诉用户哪一项不通（与第二十六轮 `_startMerge` 同款决策）；并行 then 写"两项都失败"反而模糊。
    - 仅 `network` 一档暴露按钮，**不**为 `notFound` / `unknown` 提供 —— `notFound` 需要用户去配置页改 URL，`unknown` 失败原因未知盲推"测试网络"会误导；`authFailed` 因匿名 probe 必然失败反而错误诱导用户怀疑网络问题。
    - +24 doc-as-test：panel 16（谓词 9 mode 真值表 + 字段渲染 7 场景）+ main_screen_v3 8（签名锁 / 双 probe 调用 / 双 mounted 守卫 / sourceUrl 早退 / targetWc 早退 / 成功文案 / 不调 resume / panel 接线）。
  - 验证：`flutter analyze` 0 issues + `flutter test` **2854 全绿**（baseline 2830 → 2854，+24）。
- **缺口**：（已无）
- **关联文件**：`lib/screens/components/merge_execution_panel.dart::shouldShowTestConnectivityButton / onTestConnectivity`、`lib/screens/main_screen_v3.dart::_testSvnConnectivity`、`test/merge_execution_panel_test_connectivity_test.dart`、`test/main_screen_v3_test.dart`。

### P1 标记冲突已解决后补 svn status 后验

- **现状**：2026-06-02 第二十八轮落地。
  - 真 bug：`lib/screens/main_screen_v3.dart::_markConflictsResolved` 原仅检查 `result.isSuccess` 一档，弹"已标记冲突为已解决"成功 SnackBar。但 `svn resolve --accept <mode> -R .` exit 0 **不**保证 working copy 真的清干净——tree conflict / mode 与文件实际状态不匹配 / 部分文件未被 -R 命中等场景下 svn 可能 exit 0 但 `svn status` 仍出现 'C' 行。用户看到成功提示后点"继续"，任务再跑 prepare→update→merge 又在 merge 步重新冲突暂停，浪费时间且体验割裂（点了"已解决"但居然没真解决）。
  - 落地：
    - 顶层 helper `formatMarkResolvedFeedback({modeFlag, remainingConflictCount}) -> String`（`@visibleForTesting`）—— 两档分流：`remainingConflictCount <= 0` 走原成功文案 `'已标记冲突为已解决（accept X），可点击"继续"重试'`；`> 0` 走警告文案 `'已运行 svn resolve（accept X），但仍检测到 N 个冲突文件，请手动检查后再继续'`，显式禁止用户直接点"继续"。
    - `_markConflictsResolved` 在 `result.isSuccess` 后追加 `final remaining = await _svnService.listConflictedFiles(targetWc);`（复用既有方法，svn status 解析），守 mounted（svn status 也是 await），把 `remaining.length` 喂给 helper 决定文案。
  - **决策权衡**：
    - 用 `listConflictedFiles` 而非 `hasConflicts(bool)` —— bool 没法在文案里报"还剩 N 个"具体数量；helper 接 int 把"是否警告"和"剩余数量"两个语义统一在一个入参，单测真值表更紧凑。
    - 警告文案不诱导点继续 —— 含"请手动检查后再继续"，并显式断言不含 `"继续"`（成功文案才有）；警告 / 成功首字母不同（"已运行 svn resolve" vs "已标记冲突为已解决"）让用户扫一眼 SnackBar 头部就能区分。
    - 仅成功分支补后验，**不**动失败分支语义 —— 失败分支（`result.isSuccess == false`）保持原 SnackBar `'标记失败: <stderr>'`，因为 svn resolve 直接 exit 非 0 时 stderr 已是权威错误源；本轮仅修复"成功但实际仍有冲突"的隐藏漏洞。
    - +13 doc-as-test：helper 7 测覆盖 0/<0/1/>1/4mode 透传/警告禁继续/首字母对照；接线 6 测覆盖 listConflictedFiles 调用 / formatMarkResolvedFeedback 调用 + 三 named 参数 / mounted 守卫保留 / inline 字面量已删除 / 失败分支文案不变。analyze 0 / test 2830 全绿（baseline 2817 → 2830，+13）。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::formatMarkResolvedFeedback / _markConflictsResolved`、`test/main_screen_v3_test.dart`。

### P1 启动合并前 SVN 连通性预校验
  - 真 bug：`lib/screens/main_screen_v3.dart::_startMerge` 原仅做 `validateMergeStartPreconditions`（字段 `isNotEmpty` 存在性校验），**不**做 SVN 连通性测试。用户复制错误的 SVN URL（已删除分支 / typo / 网络断开）或输入不存在的工作副本路径，点"开始合并"后任务直接入队，跑到第一步 `prepare`（`svn revert` / `svn cleanup`）才报错；此时已占用执行 slot，必须先"跳过 / 终止"才能改配置——冷启动延迟 5+ 秒、错误信息埋在执行日志里、用户感知割裂。
  - 落地：
    - `lib/services/svn_service.dart` 新增顶层 `formatProbeFailureReason({role, error})`（`@visibleForTesting`）—— 三档：SvnException + 输出含鉴权关键词 → `'<role> 校验失败：需要 SVN 凭据，请在设置中配置'`；其他 SvnException → `'<role> 校验失败：<message>'`（仅 e.message，**不**带 Command/Exit code/Output 多行噪音）；其他 error → toString 兜底。
    - `SvnService.probeSvnLocation(path, {role, username, password}) -> Future<String?>` 实例方法 —— 调 `getInfo(path, item: 'url')`（`svn info` 是最轻量连通性探针），try/catch 转译异常为字符串错误。返回 null = 通过；非空 = SnackBar 文案。
    - `_startMerge` 在 `validateMergeStartPreconditions` 通过后、`addJob` 之前依次 probe `effectiveSourceUrl` 与 `targetWc`，任一失败 `_showError` + return 不入队。
    - 新增 `_isValidatingMerge` 状态字段——`_startMerge` 入口 `if (_isValidatingMerge) return;` 早退防双击；probe 期间 try/finally 包裹 `setState(true)` / `setState(false)`；两个 await 后各自 `if (!mounted) return;` 守卫。
    - `PendingPanel.canStartMerge` 增加 `&& !_isValidatingMerge` 让按钮在 probe 期间 disabled。
  - **决策权衡**：
    - 用 `svn info` 而非 `svn st` —— svn info 同时支持 URL 与本地路径，且只读元数据不锁工作副本；目标 WC 校验也复用同一个方法（path 为本地路径时 svn info 会读 .svn 目录）。
    - 错误文案**不**透传 `SvnException.toString()` 的多行格式 —— SnackBar 只能放一行，多行会被截断；分流："鉴权" / "其他"两档对用户最有指导意义。
    - **顺序 probe** 而非并行 —— 错误信息要明确告诉用户哪一项错了；并行 then 写"两项都校验失败"反而模糊。
    - **不**在 ConfigDialog 关闭时校验 —— 配置可以暂时无效（用户先抄 URL 再粘 WC 再切其它窗口），仅在"开始合并"那一刻校验才符合用户操作模型。
    - +19 doc-as-test：svn_service +14（formatProbeFailureReason 5 测覆盖三档 + 多行噪音锁 + role 定制；probeSvnLocation 4 测锁方法签名 / getInfo+url 调用 / null 返回 / catch 走 helper）+ main_screen_v3 +10（_isValidatingMerge 字段声明 / 入口早退 / setState true/false / probe 在 validate 之后 / 双 probe 调用文案 / role 字面量 / probe 失败 _showError + return / 双 mounted 守卫 / canStartMerge 集成 / probe 在 addJob 之前）。analyze 0 / test 2786 全绿。
- **缺口**：（已无）—— 网络层超时 / 重试未实现（svn info 默认 timeout 已能覆盖大多数场景，过度工程，用户没明确要求）。
- **关联文件**：`lib/services/svn_service.dart::formatProbeFailureReason / probeSvnLocation`、`lib/screens/main_screen_v3.dart::_startMerge / _isValidatingMerge`、`test/svn_service_test.dart`、`test/main_screen_v3_test.dart`。

### P2 title/message filter 持久化对称补齐

- **现状**：2026-06-02 第二十五轮落地。
  - 漏洞：`StorageService` 已对 `last_author_filter` 提供 `getLastAuthorFilter` / `saveLastAuthorFilter` 持久化对，`main_screen_v3.dart::_loadAuthorFilterHistory` 启动恢复 + `_applyFilter` 写入，但 `last_title_filter` / `last_message_filter` 同 surface 缺失——用户重启应用后 author 自动还原而 title/message 三 controller 中两条被清空，对称漏洞每次启动都要重输是真实摩擦。
  - 落地：
    - `lib/services/storage_service.dart` 镜像 author 模板加 4 方法 `getLastTitleFilter / saveLastTitleFilter / getLastMessageFilter / saveLastMessageFilter`（trim + isEmpty skip + setString 同款，与 `saveLastAuthorFilter` 完全同型）；line 300 业务 key 矩阵 doc 表 14→16 keys 同步加两行 string 槽位。
    - `lib/screens/main_screen_v3.dart::_loadAuthorFilterHistory` 扩展为同时载 author/title/message 三 controller —— 三个 await 顺序后单一 `if (!mounted) return;` guard，再三段 `if (!= null && isNotEmpty) controller.text = ...`。
    - `_applyFilter` 同时 save 三个 filter —— 局部抽 `authorFilter / titleFilter / messageFilter` 三 vars，三段 `if (xxxFilter.isNotEmpty)` 守卫调对应 saveLastXxxFilter（仅 author 仍带 `addAuthorToFilterHistory` 历史下拉调用，title/message 不进历史菜单）。
  - **决策权衡**：单一 mounted guard 而非每 await 后 guard——Dart Future 顺序 await 在同一执行链上，单 guard 已覆盖最后写 .text 时的状态翻转风险；不为 title/message 引入历史下拉（用户没明确要求且面板宽度紧张）；持久化复用 author 模板的 trim + isEmpty skip 防御链。+13 doc-as-test：storage_service_test +8（title 4 + message 4，覆盖读写 + trim + 空字符串 skip）+ main_screen_v3_test +5（_loadAuthorFilterHistory 三测覆盖三 await 顺序 + mounted 守卫位置 + 三 isNotEmpty 守卫；_applyFilter 二测覆盖三 save 调用 + 三 isNotEmpty 守卫）；shared_preferences_type_protocol_test 矩阵 14→16 keys 同步；widget_text_controller_write_protocol_test R132 档 3 regex 扩到三 await 序列后单一 mounted guard。analyze 0 / test 2767 全绿。
- **缺口**：（已无）
- **关联文件**：`lib/services/storage_service.dart::getLastTitleFilter / saveLastTitleFilter / getLastMessageFilter / saveLastMessageFilter`、`lib/screens/main_screen_v3.dart::_loadAuthorFilterHistory / _applyFilter`、`test/storage_service_test.dart`、`test/main_screen_v3_test.dart`、`test/shared_preferences_type_protocol_test.dart`、`test/widget_text_controller_write_protocol_test.dart`。

### P1 删除单条任务二次确认

- **现状**：2026-06-02 第二十四轮落地。
  - 漏洞：`lib/screens/main_screen_v3.dart::_deleteQueueJob` 原 `await mergeState.deleteJob(jobId)` 直连，无二次确认。同 panel 同级破坏性操作 `_clearPendingJobs` / `_cancelPausedJobWithConfirm` / `_clearHistoryJobs` 都走 `_confirmQueueAction`，唯有单条删除裸调——失败任务可能含数十至数百已合并 revision 的进度记录，误点不可恢复且体验不一致。
  - 落地：抽顶层 helper `buildDeleteJobConfirmMessage({completedIndex, totalRevisions})`（`@visibleForTesting`）—— `clamp(0, total) == 0` 走 `'删除后任务将从队列移除，任务无法恢复。'`；`> 0` 走 `'删除后任务将从队列移除，已合并 X / Y 个 revision 不会回滚但任务无法恢复。'`，与 R13 终止任务句式同型保持破坏性操作家族文案一致。`_deleteQueueJob` 在 `job == null` sanity check 之后、`mergeState.deleteJob(jobId)` 之前插 `_confirmQueueAction(title: '删除任务 #$jobId', message: buildDeleteJobConfirmMessage(...), confirmLabel: '删除')` + `if (!confirmed) return;` 早退守卫。
  - **决策权衡**：`completedIndex` 走 `clamp(0, totalRevisions)` 与 `clampedCompletedRevisionCount` 同款边界保护，避免越界；title 含 `#$jobId` 而非泛指——dialog 显示具体 jobId 让用户在多任务场景下确认是哪一个；不复用 `formatJobProgressText` 等 helper——文案语境是 confirm dialog 而非 status bar，语序与 join 字符不同。+11 doc-as-test：buildDeleteJobConfirmMessage 7 测覆盖 0/X/边界/越界/负数/total=0/句式锁；_deleteQueueJob 接线 4 测覆盖 _confirmQueueAction 调用、message 复用 helper、!confirmed 早退、job==null 先于 confirm。analyze 0 / test 2754 全绿。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::_deleteQueueJob / buildDeleteJobConfirmMessage`、`test/main_screen_v3_test.dart`。

### P2 _loadPreloadSettings 加载失败 SnackBar 反馈

- **现状**：2026-06-02 第二十三轮落地。
  - 漏洞：`lib/screens/main_screen_v3.dart::_loadPreloadSettings` catch 原仅 `AppLogger.ui.error('加载设置失败', e)`，无任何 UI 反馈。应用启动 initState 链路中若 SharedPreferences / 持久化文件读取失败（磁盘权限拒绝 / 文件损坏），配置静默回退到默认值，用户启动后看不到错误，以为偏好被重置但不确定。与已落地 R21 设置保存 / R20 CSV 导出 / R8 svn cleanup 等 SnackBar 反馈体系形成对称漏洞——初始化失败本应反馈等级更高而非更低。
  - 落地：catch 内 `AppLogger.ui.error` 之后追加 `if (mounted)` 守卫 + `WidgetsBinding.instance.addPostFrameCallback` 推迟到下一帧（_loadPreloadSettings 在 initState 链路 await 调用，catch 触发时 first frame 可能尚未渲染） + 二次 mounted 检查 + `_showError('加载设置失败，已使用默认值: $e')`。logger 旁路保留——SnackBar 是补充反馈而非替代日志。
  - **决策权衡**：用 `_showError`（红色）而非 `_showInfo`——突出"配置未按用户预期加载"严重性；文案"已使用默认值"明确告知 fallback 行为，避免用户以为应用挂掉；`addPostFrameCallback` 推迟一帧——initState 链路中 ScaffoldMessenger 入队虽安全，但确保首帧渲染完后再展示更稳。+4 doc-as-test：catch 内 `_showError` 字面量锁、mounted 守卫之内位置锁、`addPostFrameCallback` 推迟锁、logger 旁路 + 顺序锁。analyze 0 / test 2743 全绿。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::_loadPreloadSettings`、`test/main_screen_v3_test.dart`。

### P2 过滤按钮 loading 状态指示器

- **现状**：2026-06-02 第二十二轮落地。
  - 漏洞：`lib/screens/components/log_list_panel.dart:836` "过滤" `ElevatedButton` 在 `isLoading` 时仅 disabled（`onPressed: isLoading ? null : onApplyFilter`），无任何视觉反馈；同面板 853-863 "同步最新" `FilledButton.icon` 在 isLoading 时已展示 16x16 `CircularProgressIndicator(strokeWidth: 2)` 反例标本。当数据库扫描 + 过滤耗时较长时用户无法判断进度，可能反复点击。
  - 落地：`ElevatedButton` → `ElevatedButton.icon`。`isLoading` 时 icon 渲染同款 16x16 `CircularProgressIndicator(strokeWidth: 2)`（与"同步最新"完全一致），非 loading 时 icon 走 `Icons.filter_alt`（与"清空筛选"的 `filter_alt_off` 形成对照），`label: const Text('过滤')` 不变（避免按钮宽度抖动），padding / disabled 接线全部保留。
  - **决策权衡**：复用与"同步最新"完全一致的进度指示器（尺寸 / strokeWidth / SizedBox 容器结构），不造新 spinner——让用户在面板内见到同款反馈即知道操作语义。文案保持"过滤"不变而非"过滤中..."，避免按钮宽度在状态切换时抖动导致点击位移。+5 doc-as-test：`ElevatedButton.icon` 升级锁、`CircularProgressIndicator(strokeWidth: 2)` 复用锁、`Icons.filter_alt` 非 loading 锁、label `'过滤'` 不变锁、disabled 接线 `isLoading ? null : onApplyFilter` 不变锁。analyze 0 / test 2739 全绿。
- **缺口**：（已无）
- **关联文件**：`lib/screens/components/log_list_panel.dart`、`test/log_list_panel_test.dart`。

### P2 设置保存成功后主屏 SnackBar 反馈

- **现状**：2026-06-02 第二十一轮落地。
  - 漏洞：`lib/screens/main_screen_v3.dart::_openSettings` await `SettingsScreen.show` 返回 `result != null`（保存成功）后仅 `setState` 更新本地缓存（`_preloadSettings` / `_maxRetries`），主屏无任何视觉反馈——与同期 resume / skip / CSV 导出 / 待合并移除等多处 SnackBar 反馈风格不一致，用户无法判断设置是否真的保存成功。
  - 落地：`_openSettings` 在 `result != null && mounted` 守卫内、`setState` 之后追加 `_showSuccess('已保存设置')`。`SettingsScreen.show` 仅在保存成功才 pop result，所以 result != null 一定是"成功"分支，复用绿色 SnackBar。
  - **决策权衡**：用 `_showSuccess`（绿色）而非 `_showInfo`（默认色）——与 `_cancelPausedJobWithConfirm` 后的 `_showSuccess('已终止任务')` 同款语义"破坏性 / 持久化操作成功"反馈；位置在 `setState` 之后——先持久化再反馈，避免反馈渲染时 _preloadSettings 仍是旧值；包在 `result != null && mounted` 守卫内复用既有路径——保护 ScaffoldMessenger 上下文不抛 Looking up a deactivated widget。+3 doc-as-test 锁 `_showSuccess('已保存设置')` 字面量、setState 之后顺序、mounted 守卫之内位置。analyze 0 / test 2734 全绿。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::_openSettings`、`test/main_screen_v3_test.dart`。

### P2 CSV 导出 SnackBar 加 "打开" 按钮

- **现状**：2026-06-01 第二十轮落地。
  - 漏洞：`lib/screens/main_screen_v3.dart::_exportFilteredAsCsv` 成功 SnackBar 仅文案 `已导出 N 条到 <path>`，用户想验证导出结果必须手动复制路径打开；同 panel `_openConflictFile` 已用 `resolveOpenFileCommand + Process.run` 跨平台打开文件，体验不一致。
  - 落地：`_exportFilteredAsCsv` 成功路径 SnackBar 加 `SnackBarAction(label: '打开', onPressed: () => _openExportedCsvFile(savePath))` + `duration: 6 秒`（默认 4 秒太短）。新增 `Future<void> _openExportedCsvFile(String path)` 方法：复用 `resolveOpenFileCommand(platform: Platform.operatingSystem, path: path)`（与 `_openConflictFile` 同款跨平台命令解析）+ `Process.run(command.executable, command.args)`，null / 异常 → SnackBar 反馈不抛。
  - **决策权衡**：抽 `_openExportedCsvFile` 而非 inline 进 `_exportFilteredAsCsv` catch 之外——SnackBarAction.onPressed 触发时设置页可能已切，需要 mounted 守卫，单独方法清晰；duration 6 秒而非 8 秒——再长会遮挡用户后续操作；不弹"是否打开"二次确认——单击 SnackBarAction 已是用户主动意愿。+4 doc-as-test 锁 SnackBarAction 字面量、`_openExportedCsvFile` 接线、`resolveOpenFileCommand` + `Process.run` 复用、duration 6 秒。analyze 0 / test 2731 全绿。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::_exportFilteredAsCsv / _openExportedCsvFile`、`test/main_screen_v3_test.dart`。

### P1 设置页 X 关闭未保存确认

- **现状**：2026-06-01 第十九轮落地。
  - **真 bug**：`lib/screens/settings_screen.dart` AppBar leading IconButton（左上 X 按钮）原 `onPressed: () => Navigator.of(context).pop()` 直连，用户在设置页编辑 5 个数字 / 1 个日期 / 2 个 toggle 后误点 X，**所有未保存输入静默丢失**——与"保存"按钮走 `_save()` 持久化的对照下尤其反差。同 panel "终止"/"清空" 这种破坏性操作都走 confirm dialog，唯有这条最容易误点的退出路径裸调没有兜底。
  - 落地：`lib/screens/settings_screen.dart` 新增顶层 `isSettingsFormDirty({current, baselinePreload, baselineMaxRetries})` 纯函数（`@visibleForTesting`），逐字段对比 PreloadSettings 7 字段（enabled / stopOnBranchPoint / maxDays / maxCount / stopRevision / stopDate / maxRetries）——`PreloadSettings` 类无 `operator ==` 不能用引用相等。新增 `_onClosePressed()` 实例方法：调 `parseSettingsFormInputs` 翻译当前表单 → `isSettingsFormDirty` 比基线 → 非 dirty 直接 `Navigator.pop()`，dirty 时 `showDialog<bool>` 弹 AlertDialog `'丢弃未保存的修改？' / '设置页有未保存的修改，关闭后将丢失。是否继续？'` + 取消 / 丢弃 双 TextButton，用户选丢弃才 pop。AppBar leading IconButton onPressed 接到 `_onClosePressed`。
  - **决策权衡**：不引入 PreloadSettings 的 `==`/`hashCode` 强行统一（`copyWith` 三种 nullable 模式已 doc 化、`==` 改写涉及 9 个 copyWith 跨文件影响面太大）——直接在 settings_screen 抽 `isSettingsFormDirty` 局部函数对比即可。dirty 检测复用 `parseSettingsFormInputs` 而非读 controller.text 字符串裸比——保持"0" / "" / 空白与 0 的归一化语义与 `_save` 一致，避免"用户输入 '0' 与基线 0 报 dirty"的误报。dialog 文案"丢弃未保存的修改？"主语是修改本身、不是"修改后退出"——更聚焦用户即将丢失的对象；按钮顺序"取消 / 丢弃"——破坏性放右、保守放左与系统对话框惯例一致。+12 doc-as-test：`isSettingsFormDirty` 8 测覆盖全字段每个 single-field flip + 全字段同基线 false 基线；4 测锁 X 按钮接线契约（`onPressed: _onClosePressed,` 字面量、`isSettingsFormDirty(` 调用点、4 段文案字面量、`if (!dirty)` 早退路径）。analyze 0 / test 2727 全绿。
- **缺口**：（已无）
- **关联文件**：`lib/screens/settings_screen.dart::isSettingsFormDirty / _onClosePressed`、`test/settings_screen_test.dart`。

### P1 settings _save 持久化失败静默 + 错误 pop

- **现状**：2026-06-01 第十八轮落地。
  - **真 bug**：`lib/screens/settings_screen.dart::_save()` 原 try/catch 把 `StorageService` 写入异常仅 `AppLogger.ui.error('保存设置失败', e, stackTrace)`，**catch 后仍 fallthrough 到 `Navigator.of(context).pop(result)`**——UI 表现为"保存成功并关闭设置页"，实际 SharedPreferences 未持久化；磁盘满 / 权限拒绝 / 文件锁定时下次启动配置丢失。这是真功能 bug 而非边际 UX。
  - 落地：catch 分支改为 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存设置失败：$e'), backgroundColor: Colors.red))` + `return;` 提前退出（不 pop），让用户感知失败并选择重试或手动取消；成功路径仍 pop(result) 不变。`mounted` 守卫保留防异步 dispose 后 context 失效。
  - **决策权衡**：用 SnackBar 红底而非 AlertDialog——保持设置页可见、不打断用户重试节奏；选择直接 `Text('保存设置失败：$e')` 拼接异常对象而非"保存设置失败，请重试"通用文案——实际错误（permission denied / disk full）对用户判断处理路径有指导意义；`return;` 而非 `if/else` 分支结构——单层 try 内 catch 后早退是 dart idiomatic，避免 success 路径被嵌套缩进多一层。+3 doc-as-test：catch 分支 SnackBar 红底字面量锁、`Navigator.pop(result)` 在 _save 内出现且仅出现 1 次（成功路径独占）+ `return;` 存在的双重保险锁、成功路径 pop 仍存在的反向锁。
- **缺口**：（已无）
- **关联文件**：`lib/screens/settings_screen.dart::_save`、`test/settings_screen_test.dart`。

### P2 onResume / onSkip 暂停态按钮 SnackBar 反馈

- **现状**：2026-06-01 第十七轮落地。
  - 漏洞：`MergeExecutionPanel` 暂停态"继续执行" / "跳过 (rN)" 按钮原本直连 `mergeState.resumePausedJob()` / `mergeState.skipCurrentRevision()`，**无任何 SnackBar 反馈**——与同 panel "终止"（第十三轮 `_cancelPausedJobWithConfirm`）+ locked 态 "执行 cleanup"（第八轮 `_runSvnCleanup`）+ "标记为已解决"（第七轮 `_markConflictsResolved`）反馈体验不一致；用户点完看到 status 翻转但若网络/IO 慢一拍会"不知道按下去到底有没有用"。
  - 落地：`lib/screens/main_screen_v3.dart` 新增 `_resumePausedJobWithFeedback(mergeState)` / `_skipCurrentRevisionWithFeedback(mergeState)` 两个 `Future<void>` 包装方法。
    - `_resumePausedJobWithFeedback`：pausedJob == null → `_showInfo('当前没有暂停中的任务')` 早退；否则**乐观**先 `_showInfo('继续执行任务 #$jobId')` 再 `await mergeState.resumePausedJob()`（resume 是长时操作不能等 await 完才弹反馈，否则 SnackBar 出现晚于实际执行）。
    - `_skipCurrentRevisionWithFeedback`：双重早退（pausedJob == null + paused.currentRevision == null），通过则 `_showInfo('已跳过 r$rev，继续执行任务 #$jobId')` 同时给 revision + jobId 双信息（用户最关心的两条上下文都拿到）再 `await skipCurrentRevision()`。
  - panel 接线：`onResume: () => _resumePausedJobWithFeedback(mergeState)`、`onSkip: () => _skipCurrentRevisionWithFeedback(mergeState)`。
  - **决策权衡**：乐观反馈（先 `_showInfo` 再 `await`）而非完成后反馈——resume / skip 内部 await 远长于 SnackBar 持续时间，等完了再弹反馈太晚，与第八轮 `_runSvnCleanup` "完成后弹"语义不同（cleanup 是用户期望"等结果"的同步工具，resume/skip 是"启动后继续推进"的指令）。两包装都做 null 早退，避免 panel 渲染态与 mergeState 异步态翻转的竞态。+5 doc-as-test：onResume/onSkip 接线锁、双裸调路径反向锁、`#$jobId` / `r$rev` 字面量锁、null 兜底文案锁。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::_resumePausedJobWithFeedback / _skipCurrentRevisionWithFeedback`、`test/main_screen_v3_test.dart`。

### P2 待合并单条移除 SnackBar 反馈

- **现状**：2026-06-01 第十六轮落地。
  - 漏洞：`PendingPanel` 行尾 close 按钮调 `_removePendingRevision(int revision)`，操作后列表确实立刻少一条，但**没有任何 SnackBar 反馈**——与同文件 `_clearPendingRevisions`（"已清空 N 个"）/ `_deleteQueueJob`（"已删除任务 #ID"）的体验不一致；列表行很短时用户视线没盯着会怀疑"是否生效"。
  - 落地：`lib/screens/main_screen_v3.dart::_removePendingRevision` 末尾追加 `_showInfo('已从待合并移除 r$revision');`；保留原 `_pendingSourceUrl` 清理副作用（pending 变空时清回 null）。+2 doc-as-test 锁定 SnackBar 字面量 + 副作用保留契约（防"加 SnackBar 时不小心删了原副作用"的回归）。
  - **决策权衡**：不引入二次确认对话框（单条移除是低破坏操作，与"清空待合并 N 条"批量操作语义不同；批量改写有累积成本所以加 confirm，单条只是 1 个 revision 损失低）；SnackBar 文案与 `formatPendingRemoveTooltip(revision)` 的 hover tooltip "从待合并移除 rXXX" 形成"操作前看 tooltip / 操作后看 SnackBar"对照协议，rXXX 字面量两处保持一致。
- **缺口**：（已无）
- **关联文件**：`lib/screens/main_screen_v3.dart::_removePendingRevision`、`test/main_screen_v3_test.dart`。

### P2 预加载 loading 状态展示进度

- **现状**：2026-06-01 第十五轮落地。
  - 漏洞：`PreloadProgress.statusDescription` 在 loading 阶段一律返回干瘪的 `'加载中...'`，丢掉了 `loadedCount` 与 `earliestRevision` 信息；5 万 commit 仓库首次预加载常常持续几分钟，用户看不到进度只能靠"听硬盘"判断是否卡死。
  - 落地：`lib/services/preload_service.dart` `describePreloadStatusDescription` 顶层 helper 新增 `int? earliestRevision` 入参，loading 分支三档：
    - `loadedCount <= 0` → 仍走 `'加载中...'` 兜底（冷启动期不写"已 0 条"避免"还没开始就显示 0"的视觉误导）。
    - `loadedCount > 0` + `earliestRevision == null` 或经 `normalizeOptionalRevision(<=0 视作 null)` 归一化后为 null → `'加载中... (已 N 条)'`。
    - `loadedCount > 0` + `earliestRevision > 0` → `'加载中... (已 N 条, 最早 rXXXX)'`。
  - `PreloadProgress.statusDescription` getter 同步透传 `earliestRevision: earliestRevision`（薄包装委托给顶层 helper，未来改文案只动一处）。
  - **决策权衡**：用 `normalizeOptionalRevision` 统一守卫 `<=0` 视作未知（与项目其它路径同口径），不在 helper 内重复写边界判定；`statusDescription` 走 getter 委托而非 inline 字符串拼接，保证 helper 单测就能锁住完整语义；不引入新 widget 测试 — `describePreloadStatusDescription` 4 新 case + getter 透传 1 lock 已覆盖契约。
- **缺口**：（已无）— 预估剩余时间 / loadingRate 未做（需要时间序列采样，过度工程，用户没明确要求）。
- **关联文件**：`lib/services/preload_service.dart`、`test/preload_service_test.dart`。

### P2 任务队列拖拽 reorder / 优先级

- **现状**：2026-06-01 第六轮落地。
  - 顶层 helper（`lib/providers/merge_execution_state.dart::reorderPendingJobsList(jobs, oldPendingIndex, newPendingIndex)`）— 把 pending 子列表内位置 oldIndex → newIndex 重排，沿用 `ReorderableListView.onReorder` 约定（newIndex > oldIndex 时减 1 还原到删除前的目标位）。**只重排 pending 任务**——running / paused / done / failed 的绝对索引保持不变。边界条件返回原 list 不变（identical）：pending 为空 / 索引越界 / no-op。`@visibleForTesting`。
  - 实例方法 `MergeExecutionState.reorderPendingJobs(oldIndex, newIndex)` — 调 helper、若 identical 则返回 false 不持久化、否则 `_restoreCurrentJobIndex` 修正 `_currentJobIndex` 后写 storage + appendLog `'已重新排序待执行任务'` + notify。
  - UI：`JobQueuePanel` 新增 `onReorderPendingJobs` 回调，把 queueJobs 拆成 nonPending（running/paused 静态渲染）+ pending（`ReorderableListView.builder` 拖拽渲染，每个 tile key=`'pending-job-#${jobId}'`）。pending 数 ≤ 1 或回调为 null 时降级为普通 Column。
  - 接线：`main_screen_v3.dart` `JobQueuePanel(... onReorderPendingJobs: (a, b) => mergeState.reorderPendingJobs(a, b))`。
- **缺口**：（已无）— pause-all / 优先级标签未做（用户没明确要求）。
- **关联文件**：`lib/providers/merge_execution_state.dart`、`lib/screens/components/job_queue_panel.dart`、`lib/screens/main_screen_v3.dart`、`test/merge_execution_state_test.dart`。

### P2 步骤快照错误信息复制按钮

- **现状**：2026-06-01 第十一轮落地。
  - 顶层 helper `formatStepErrorClipboardText(String? error)` (`lib/screens/components/merge_execution_panel.dart`)：null / empty → `'暂无错误信息'`（占位符避免空串粘贴的 no-op 体验），非空 → `decodeUnicodeEscapes(error)`（与展示同口径，`{U+xxxx}` → 字符）。`@visibleForTesting`。
  - UI：`_buildStepDetailView` 错误区块（红色卡片）标题行右上角追加 `IconButton(Icons.copy_all, 28x28, visualDensity=compact, padding=zero, 红色)`。点击调 `_copyStepError(snapshot.error)` → `Clipboard.setData` + SnackBar `'步骤错误已复制到剪贴板'`（与 log_dialog._copyLog 同款体验）。
  - **R131 兼容写法**：`_copyStepError` 在 `await Clipboard.setData(...)` 之前先抓 `final messenger = ScaffoldMessenger.of(context);`，全程不引用 `mounted`，避开 R131 锁的 lib/ 内 `mounted` 站点白名单。
- **缺口**：（已无）
- **关联文件**：`lib/screens/components/merge_execution_panel.dart`、`test/merge_execution_panel_copy_step_error_test.dart`。

### P2 log_dialog 关键字搜索过滤

- **现状**：2026-06-01 第十二轮落地。
  - `lib/screens/components/dialogs/log_dialog.dart` 由 `StatelessWidget` → `StatefulWidget`，标题行下方加 `TextField` "按关键字过滤（不区分大小写）"，`onChanged` → `setState(() => _query = v)`（**档 1 sync 直接 setState**，不引入 `addListener`，避开 R130 lib 0 处 listener 不变量）。
  - 顶层 helper `filterLogLinesByQuery(String log, String query)` (`@visibleForTesting`)：query 空 → 原 log 直出（不 split / 不重组，避免 trailing newline 副作用）；非空 → split `\n` + case-insensitive substring 过滤，原序保留，join 回 `\n`。**不** trim query / **不** trim 行（用户搜含前导空格的子串应能精确匹配）。
  - `formatLogDialogHeaderText` 加可选 `query` / `matchedCount` 参数：query null/'' 时按原契约渲染（向后兼容，单测显式锁定），非空时切换为 `'匹配 X / 共 Y 行（关键字: q）'`。空日志分支始终走 `'暂无执行日志'`，与 query 状态无关（log 优先判定）。
  - 复制按钮复制**过滤后**内容，保持"所见即所粘"协议（用户搜索后期望粘贴出的就是当前看到的内容）。
  - **R131 setState 锁扩展**：log_dialog 加入白名单成为 lib/ 第三个含 `setState` 的 State 类，`widget_setstate_protocol_test.dart` 站点全集统计同步更新（双锁 → 三锁）。`mounted` 仍仅出现在原 `_copyLog` 的 `context.mounted`，不引入新 mounted 站点。
- **缺口**：（已无）— 正则模式 / 高亮匹配未做（用户没明确要求，contains 满足绝大多数日志查找）。
- **关联文件**：`lib/screens/components/dialogs/log_dialog.dart`、`test/log_dialog_test.dart`、`test/widget_setstate_protocol_test.dart`。

### P2 MergeExecutionState 服务注入（结构性，已闭合）

- **现状**：构造函数注入已落地（`lib/providers/merge_execution_state.dart:621-629`）。`MergeExecutionState({StorageService?, WorkingCopyManager?, MergeInfoCacheService?, SvnService?})` 4 个服务全部带默认值不破坏现有调用点；`merge_execution_state_flow_test.dart` 已有 8 个状态机级测试使用 fake 注入跑真实流程（resume / skip / out-of-date 重试 / 中断恢复）。
- **缺口**：（已无）
- **关联文件**：`lib/providers/merge_execution_state.dart`、`test/merge_execution_state_flow_test.dart`。

---

## 当前关键文件

### 核心状态
- `lib/providers/merge_execution_state.dart`
- `lib/models/merge_job.dart`
- `lib/execution/svn_failure_kind.dart`

### 主界面与面板
- `lib/screens/main_screen_v3.dart`
- `lib/screens/components/log_list_panel.dart`
- `lib/screens/components/pending_panel.dart`
- `lib/screens/components/job_queue_panel.dart`
- `lib/screens/components/merge_execution_panel.dart`
- `lib/screens/components/step_execution_view.dart`
- `lib/screens/components/dialogs/log_dialog.dart`
- `lib/screens/components/status_bar.dart`
- `lib/screens/settings_screen.dart`

### 服务层
- `lib/services/svn_service.dart`
- `lib/services/preload_service.dart`
- `lib/services/log_filter_service.dart`
- `lib/services/log_cache_service.dart`
- `lib/services/storage_service.dart`
- `lib/services/mergeinfo_cache_service.dart`
- `lib/working_copy/working_copy_manager.dart`

---

## 不建议做的事

- 不要恢复 pipeline / workflow / script node / flow editor 相关设计。
- 不要为"通用性"重新引入外部脚本节点。
- 不要做兼容旧流程数据的复杂迁移。
- 不要把固定四步重新抽象成可配置图编排。
- **不要再写 R-series doc-only cascade**（见顶部"避免循环空转"）。
- 不要为"提升测试数量"而新增测试，测试必须服务于真实代码路径。

---

## 当前验证状态

最近一次执行通过：
- `flutter analyze` — 0 issues
- `flutter test` — 全绿（2977 tests）

最近一次落地（2026-06-02，第四十五轮）：P0 "合并完成提示分不清真有产出 vs 空合并 no-op" 真 dogfood 痛点修复 — 用户在 19:14 那次尝试中把源 URL 选成 `branches/b1`、目标 WC 也选成 `b1`、合并 r3（b1 自身被创建那个 revision），SVN 全成功（svn merge -c 3 + 空 commit 全部退出码 0），app 显示"成功"，但 `1.txt` 一字未改 — 用户误以为"流程没成功"，实际是**自合并 no-op**。这类场景包括：① 自合并（源 URL == 目标分支 URL）；② 已合并过的 revision 重跑；③ cherry-pick 同分支历史 commit。`_runMergeStep` 原日志只输出 `r$revision 合并成功` 单行，无任何"实际产出量"反馈，用户从日志面板和步骤快照都看不到差别。修复：① 加顶层 helper `parseChangedFilesCount(statusOutput)`（`lib/services/svn_service.dart`，`@visibleForTesting`）— 数 svn status 非空行（不区分 M/A/D/C/G/U 等状态码，0 行 = 空合并；7 测试覆盖空字符串 / 全空行 / 单 M / 多状态混合 / 混合空行 / 属性变更 ` M ...` / 冲突行 `C ...`）；② 加实例方法 `SvnService.countChangedFiles(targetWc, {username, password})` — 跑 `svn status` + 调 helper；③ `MergeExecutionState._runMergeStep` 在 `listConflictedFiles` 后验通过后调 `await _svnService.countChangedFiles(job.targetWc)`，分两路 log：`changedCount > 0` → `'[INFO] r$revision 合并成功 — 实际改动 N 个文件'`；`changedCount == 0` → `'[INFO] r$revision 合并成功 — 但未产生任何差异（空合并 / no-op，源与目标可能无新增提交）'`；step output map 加 `'changedFilesCount': changedCount` 字段（步骤快照对话框可见）；④ 测试 `_FakeSvn` 加 `countChangedFiles` override + `countChangedFilesScript`（默认返 1）；⑤ 第三十三轮 doc-as-test "成功路径输出 r\$revision 合并成功" 字面量锁更新为前缀 + "实际改动" + "空合并" 三段锁，+1 顺序锁（merge → listConflictedFiles → countChangedFiles → step output）。**决策权衡**：① 不复用 listConflictedFiles 内部已跑的 status 输出（让它返回 ({conflicts, statusOutput}) 是 breaking change，全 lib 7 处 caller 需要逐一迁移），新调一次 svn status ~40ms 相对 svn merge 远程调用可忽略；② 不区分文件 vs 属性变更 vs 冲突 — 用户从 "实际改动 N 个文件" 角度看 ` M .` （mergeinfo 属性变更）和 `M 1.txt`（文件改动）都是"合并干了一件事"；③ 不改 SnackBar — 这是"任务完成"层的反馈、`MergeExecutionPanel` 的 SnackBar 路径还需要单独考虑「单任务多 revision 求和」语义，本轮先把可见性堵进**日志 / 步骤快照**两个用户最容易看到的入口；④ 仍输出 `r$revision 合并成功` 前缀 — 第三十三轮 doc-as-test 锁定的字面量公共前缀必须保留，避免回退到没有任何"成功"标记的状态。+8 测试（7 helper + 1 doc-as-test，2969 → 2977）。analyze 0 / test 2977 全绿。

历史落地：
- 2026-06-02 第四十四轮：P2 "deploy 脚本桌面平台无设备时跳过启动" 真 dogfood 痛点修复 — `scripts/deploy.py::check_devices` 在 `device_count == 0` 时统一 `return 0, True` 让 `build_only=True`，step 7 直接 `跳过启动（仅构建模式）` 退出。但 macOS / Windows / Linux **桌面平台无需 device 就能启动**（`open .app` / 直接运行 `.exe` / Linux bundle binary），脚本的判定语义和注释互相打架。修复：① `check_devices` 提示消息纠正；② step 7 改为按平台分支（`is_desktop` 真时不看 `build_only`，按平台 `subprocess.run(['open', .app])` / `subprocess.Popen([.exe])` / `subprocess.Popen([linux bundle binary])` 启动）。verify：`./scripts/deploy.sh` 实测 63.9s，step 7 显示 "启动桌面应用"，结果 `SUCCESS - 部署完成`，`pgrep` 确认进程在跑。analyze 0 / test 2969 全绿（无 lib 改动）。
- 2026-06-02 第四十三轮：P0 "_svnUpdate / _svnCleanup R131 档 3 mounted 守卫漏档" 真 bug 修复 — 上一轮闭合 `_svnRevert` 三处漏档后巡检主屏 SVN 三入口家族，发现 `_svnUpdate` / `_svnCleanup` 同型漏档 4 处：① `_svnUpdate` isSuccess=false 分支跨 `await _wcManager.update(...)` 后裸调 `_showError('更新失败: ...')`；② `_svnUpdate` catch 块 `_showError('更新异常: $e')` 同模式；③ `_svnCleanup` isSuccess=false 分支同模式；④ `_svnCleanup` catch 块同模式。注：两方法 isSuccess=true 分支已分别在第三十二/三十一轮补过（用于后验 `listConflictedFiles` / `probeSvnLocation` 之后）。四处都补 `if (!mounted) return;`。主屏 SVN 三入口家族 update / revert / cleanup 跨 await 后 SnackBar 守卫**全部对称收口**。+4 测试。analyze 0 / test 2969 全绿。
- 2026-06-02 第四十二轮：P0 "_svnRevert R131 档 3 mounted 守卫漏档" 真 bug 修复 — `lib/screens/main_screen_v3.dart::_svnRevert` 三处跨 await 后漏 mounted 守卫：① `await showDialog<bool>` 后裸调 `_showInfo`；② `await _wcManager.revert(...)`（耗时分钟级）后裸调 `_showSuccess` / `_showError`；③ catch 块 `_showError('还原异常: $e')` 同模式。三处都补 `if (!mounted) return;`。+2 测试。analyze 0 / test 2965 全绿。

- 2026-06-02 第四十一轮：P1 "sync/apply 拆段反馈避免误导" 真 bug 修复 — `lib/screens/main_screen_v3.dart::_runLogDataAction`（"同步最新" / "加载更多" 共用入口）原 try 块同时包 `action()`（sync 段：远程 SVN log 拉取 + DB 写入）与 `_applySelectionContext()`（apply 段：刷 minRevision / mergeinfo / log cache summary），sync 已落盘但 apply 抛错时统一弹 `'日志同步失败: \$e'` 与实际状态背离 — 用户误以为"啥也没干成"重复点 sync 浪费带宽。抽顶层 helper `formatLogApplyFailureFeedback({addedCount, error})` 两档分流，`_runLogDataAction` 拆两段 try：外层 `int addedCount = 0;` 在两段 try 之前声明，sync 段独立 catch（标签 + 原文案 + return）/ apply 段独立 catch（标签 + helper 文案 + return）。+6 测试。analyze 0 / test 2963 全绿。
- 2026-06-02 第三十九轮：P1 "打开冲突文件成功反馈与剩余数量提示" 真 bug 修复 — `_openConflictFile` 成功路径 `Process.run` 后**完全无 SnackBar 反馈**与"调外部命令成功路径加反馈"家族不对称；同时 `listConflictedFiles` N>1 时只取 first 但**不告诉用户还有几个待处理**。抽顶层 helper `formatOpenConflictFileFeedback({totalCount, openedRelative})` 两档分流 + `if (!mounted) return;` 守卫 + SnackBar。+5 测试（4 helper 真值表 + 1 lib 字面量锁）。analyze 0 / test 2952 全绿（2947 → 2952，+5）。
- 2026-06-02 第三十八轮：P2 "调整重试上限 dialog 数字输入过滤对齐设置页" 真 bug 修复 — `_adjustJobMaxRetries` AlertDialog TextField 缺 `inputFormatters: [FilteringTextInputFormatter.digitsOnly]` 与 settings_screen 4 字段不一致。补 import flutter/services + inputFormatters + SnackBar 文案改为精确指向 `'必须大于当前上限 ${job.maxRetries}'`。+2 doc-as-test。analyze 0 / test 2947 全绿。
- 2026-06-02 第三十七轮：P1 "添加到待合并 SnackBar 反馈数对齐真实新增数" 真 bug 修复 — `_addSelectedToPending` 原 `_showSuccess('已添加 $count 个 revision')` count 用 `_selectedRevisions.length`，但 `addPendingRevisions → mergePendingRevisions` 做 union 去重，反馈数与真实新增数背离。抽顶层 helper `formatPendingAddSnackBar({selectedCount, addedCount})` 三档分流。+7 测试。analyze 0 / test 2945 全绿。
- 2026-06-02 第三十六轮：P1 "日志对话框清空按钮二次确认" 真 bug 修复 — `lib/screens/components/dialogs/log_dialog.dart` "清空"按钮原直连 `widget.onClear() + Navigator.pop()`，与紧邻"复制"按钮极易误点。抽 `buildClearLogConfirmMessage({lineCount})` helper + `_confirmClearLog` async（isEmpty 早退 → showDialog → mounted 守 → onClear → pop）。+15 测试（5 helper + 4 widget + 6 doc-as-test）。analyze 0 / test 2938 全绿。
- 2026-06-02 第三十四轮：P1 "svn update 后补 listConflictedFiles 后验（_runUpdateStep / merge job 内部）" 真 bug 修复 — 第三十二轮闭合的是主屏工具栏 `_svnUpdate`，但 merge job 流程内部的 `_runUpdateStep` 仍是 `if (!result.isSuccess) throw; _appendLog('已更新')` 旧实现。`svn update` 在服务端 vs 本地冲突时仅把文件标 'C' 状态并 exit 0，update 步标 completed 进 merge 步，'C' 状态文件被 merge 步后验（第三十三轮）误判为 merge 产生 → 错位归 merge 步暂停 → 用户继续 → prepare revert + update 又出 'C' + merge 又误判，**循环**。在 `_runUpdateStep` `result.isSuccess` 后追加 `final conflicts = await _svnService.listConflictedFiles(job.targetWc); if (conflicts.isNotEmpty) throw StateError('更新工作副本产生 ${conflicts.length} 个冲突文件，请手动解决');`，**先于 "已更新到最新版本" 日志**（成功语义保护）。外层 catch 走 `evaluateStepFailure(stepId='update')` 默认 pause，归 update 步。第三十三轮的 merge 端到端 test 需要在 `listConflictedFilesScript` 里先垫一项空列表（update 步后验先返回干净）。+9 测试（2 端到端 flow + 7 doc-as-test）。"成功后调 SVN 后验"家族**六入口闭合**（markResolved / cleanup×2 / update×2 / merge）。analyze 0 / test 2920 全绿。
- 2026-06-02 第三十二轮：P1 "svn update 后补 listConflictedFiles 后验" 真 bug 修复 — `_svnUpdate`（主屏工具栏）原仅检查 `result.isSuccess`，但 `svn update` 在服务器侧改动与本地修改冲突时仅把文件标 'C' 状态、仍 exit 0，WC 实际仍有冲突。新增 `formatUpdateFeedback({int remainingConflictCount = 0})` 顶层 helper 两档分流 + 成功路径追加 `await _svnService.listConflictedFiles(targetWc)` 后验 + mounted 守卫 + `_showSuccess(message)` / `_showError(message)` 视觉立辨 + `AppLogger.ui.error` 留痕。+17 doc-as-test。
- 2026-06-02 第三十一轮：P1 "cleanup 后补 probeSvnLocation 后验" 第二入口对称闭合 — 第三十轮闭合了暂停态 `_runSvnCleanup`，但主屏工具栏 `_svnCleanup` 仍是 `_showSuccess('清理完成')` 旧实现。扩展 `formatCleanupFeedback` 加 `bool resumePrompt = true` 入参分流两个语境。`_svnCleanup` 成功分支补 `await _svnService.probeSvnLocation(targetWc, role: '工作副本')` + `_showSuccess(message)` / `_showError(message)` 视觉立辨 + `AppLogger.ui.error` 留痕。+17 doc-as-test。
- 2026-06-02 第三十轮：P1 "cleanup 后补 probeSvnLocation 后验" 真 bug 修复 — `_runSvnCleanup` 原仅检查 `result.isSuccess`，但 svn cleanup exit 0 不保证 WC 真可用。新增 `formatCleanupFeedback({String? probeError})` 顶层 helper 两档分流文案 + 成功路径追加 `await _svnService.probeSvnLocation(targetWc, role: '工作副本')` 后验。+14 doc-as-test。
- 2026-06-02 第二十九轮：P1 "network 暂停态测试连通性按钮" 真缺口 — 第二十六轮已落地启动前预校验，但 network 暂停态没有同款入口验证网络恢复。新增 `shouldShowTestConnectivityButton(SvnFailureKind)` 顶层谓词（仅 network 返回 true）+ `MergeExecutionPanel.onTestConnectivity` 字段（cyan OutlinedButton，Icons.wifi_find）+ `_testSvnConnectivity(MergeJob job)` 复用 `probeSvnLocation` 顺序探测 sourceUrl/targetWc + 双 mounted 守卫 + `_showSuccess('连通性正常...')` / `_showError(reason)` 反馈，**不**自动 resume。+24 doc-as-test。
- 2026-06-02 第二十八轮：P1 "标记冲突已解决后补 svn status 后验" 真 bug 修复 — `_markConflictsResolved` 原仅检查 `result.isSuccess`，但 svn resolve exit 0 不保证 WC 干净。新增 `formatMarkResolvedFeedback(modeFlag, remainingConflictCount)` 两档分流文案 + 成功路径追加 `await _svnService.listConflictedFiles(targetWc)` 后验。+13 doc-as-test。
- 2026-06-02 第二十七轮：P1 "outOfDate 暂停态调整 maxRetries" — `MergeExecutionPanel` 加 `shouldShowAdjustMaxRetriesButton` 顶层谓词 + `onAdjustMaxRetries` 回调字段；provider 加 `updateJobMaxRetries(jobId, newMax) -> Future<bool>`；`main_screen_v3` 加 `_adjustJobMaxRetries(MergeJob)` AlertDialog 流程。+31 doc-as-test。
- 2026-06-02 第二十六轮：P1 "启动合并前 SVN 连通性预校验" — `formatProbeFailureReason` + `probeSvnLocation` + `_isValidatingMerge`，依次 probe sourceUrl / targetWc。+19 doc-as-test。
- 2026-06-02 第二十五轮：P2 "title/message filter 持久化对称补齐" — `StorageService` 镜像 author 模板加 4 方法；`_loadAuthorFilterHistory` 三 await 顺序后单一 mounted guard 同载三 controller；`_applyFilter` 同时 save 三 filter。+13 doc-as-test。
- 2026-06-02 第二十四轮：P1 "删除单条任务二次确认" — `_deleteQueueJob` 在 sanity check 后插 `_confirmQueueAction` + 顶层 helper `buildDeleteJobConfirmMessage(completedIndex, totalRevisions)` 双分支文案。+11 doc-as-test。
- 2026-06-02 第二十三轮：P2 "_loadPreloadSettings 加载失败 SnackBar 反馈" — catch 内追加 mounted 守卫 + addPostFrameCallback + `_showError('加载设置失败，已使用默认值: $e')`。+4 doc-as-test。
- 2026-06-02 第二十二轮：P2 "过滤按钮 loading 状态指示器" — `log_list_panel.dart` 过滤按钮 `ElevatedButton` → `ElevatedButton.icon`，isLoading 时复用与"同步最新"一致的 16x16 `CircularProgressIndicator(strokeWidth: 2)`。+5 doc-as-test。
- 2026-06-02 第二十一轮：P2 "设置保存成功后主屏 SnackBar 反馈" — `_openSettings` 在 `result != null && mounted` 守卫内、setState 之后追加 `_showSuccess('已保存设置')`。+3 doc-as-test。
- 2026-06-01 第二十轮：P2 "CSV 导出 SnackBar 加打开按钮" — `_exportFilteredAsCsv` 成功 SnackBar 加 `SnackBarAction(label: '打开')` + duration 6 秒；新增 `_openExportedCsvFile` 复用 `resolveOpenFileCommand`。+4 doc-as-test。
- 2026-06-01 第十九轮：P1 "设置页 X 关闭未保存确认" 真 bug 修复 — AppBar leading IconButton 直连 `Navigator.pop` 静默丢弃漏洞修复，新增 `isSettingsFormDirty` + `_onClosePressed` 弹 AlertDialog。+12 doc-as-test。
- 2026-06-01 第十八轮：P1 "settings _save 持久化失败静默 + 错误 pop" 真 bug 修复 — catch 改为 SnackBar 红底 + `return;` 不再 pop。+3 doc-as-test。
- 2026-06-01 第十七轮：P2 "onResume / onSkip 暂停态按钮 SnackBar 反馈" — `_resumePausedJobWithFeedback / _skipCurrentRevisionWithFeedback` 乐观反馈包装。+5 doc-as-test。
- 2026-06-01 第十六轮：P2 "待合并单条移除补 SnackBar 反馈" — `_removePendingRevision` 末尾追加 `_showInfo('已从待合并移除 r$revision');`。+2 doc-as-test。
- 2026-06-01 第十五轮：P2 "预加载 loading 状态展示进度" — `describePreloadStatusDescription` helper 新增 `int? earliestRevision` 入参三档分支。+5 测试。
- 2026-06-01 第十四轮：P1 "sourceUrl 粘贴自动剥空白字符" — `stripUrlWhitespace` + `UrlInputFormatter`，TextField 加 inputFormatters，历史记录 PopupMenuButton.onSelected 也走 strip 净化。+20 测试。
- 2026-06-01 第十三轮：P1 "终止任务按钮加二次确认" — `_cancelPausedJobWithConfirm` 异步包装复用 `_confirmQueueAction`。
- 2026-06-01 第十二轮：P2 "log_dialog 关键字搜索过滤" — StatelessWidget → StatefulWidget，`filterLogLinesByQuery` helper，复制按钮复制过滤后内容。+20 测试。
- 2026-06-01 第十一轮：P2 "步骤快照错误信息复制按钮" — 错误区块加 IconButton(copy_all)，新增 `formatStepErrorClipboardText` helper，R131-friendly 模式抓 messenger。+7 测试。
- 2026-06-01 第十轮：P1 "暂停/执行中改 sourceUrl/targetWc 二次确认" — `shouldWarnBeforeEditingConfig` 谓词 + `_confirmEditConfigWhileBusy` AlertDialog。+5 测试。
- 2026-06-01 第九轮：P1 "日志筛选一键清空按钮" — `hasActiveLogTextFilter` 谓词 + `onClearFilter` 黄褐 OutlinedButton.icon。+14 测试。
- 2026-06-01 第八轮：P1 "locked 暂停态 svn cleanup 按钮" — `shouldShowCleanupButton` 谓词 + `_runSvnCleanup`。+15 测试。
- 2026-06-01 第七轮：P0 "高级 accept 模式 dialog" — `SvnResolveAccept` enum + `cliFlag` getter + UI 主按钮 + PopupMenuButton 3 项。+10 测试。
- 2026-06-01 第六轮：P2 "任务队列拖拽 reorder" — `reorderPendingJobsList` helper + `MergeExecutionState.reorderPendingJobs`，JobQueuePanel 拆 nonPending + pending（ReorderableListView）。+8 测试。
- 2026-06-01 第五轮：P1 "导出过滤后日志为 CSV" — 3 个顶层 helper + AppState 桥接 + `_exportFilteredAsCsv` + FilePicker.saveFile。+14 测试。
- 2026-06-01 第四轮：P1 "停止预加载" 按钮反馈完善 — `_stopPreloadWithFeedback` 包装 + SnackBar。
- 2026-06-01 第三轮：P0 "打开冲突文件" 按钮 — `parseConflictedFiles` + `listConflictedFiles` + `resolveOpenFileCommand` 跨平台。
- 2026-06-01 第二轮：P0 "标记为已解决" — `SvnService.resolveAccept` + `buildSvnResolveAcceptWorkingArgs`。
- 2026-06-01 第一轮：日志 message 全文搜索维度上线（LogFilter 第 4 字段 + UI 第 4 个 TextField）。

这份推进板对齐了"稳定好用的 SVN 合并助手"主线，
**下一位 agent 请直接从"实证过的功能缺口清单"P0 / P1 项里选一项推进**，
不要回到 R-series cascade 老路。
