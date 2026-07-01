/// 合并执行面板
///
/// 显示标准合并执行状态和控制指令。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../execution/executor_status.dart';
import '../../execution/paused_job_summary.dart';
import '../../execution/step_snapshot.dart';
import '../../execution/svn_failure_kind.dart';
import '../../models/merge_job.dart';
import '../../services/svn_service.dart' show SvnResolveAccept;
import '../../utils/process_output_decoder.dart'
    show decodeUnicodeEscapes;
import 'step_execution_view.dart' show formatStepTime;

export '../../utils/process_output_decoder.dart' show decodeUnicodeEscapes;

/// 渲染"复制步骤错误"按钮要写入剪贴板的文本。
///
/// **核心契约**（与 `log_dialog.dart::formatLogDialogClipboardText` 同型）：
/// - `error` 为 `null` 或空串 → 返回占位符 `'暂无错误信息'`；空串写剪贴板会导致
///   "粘贴时 no-op" 的体验 bug（macOS / Windows 默认行为），占位符至少给出
///   "操作成功了，但当时没错误"的信号；
/// - 非空 → 走 [decodeUnicodeEscapes]，与 UI 中 `SelectableText` 显示的内容**字面一致**
///   （所见即所粘）——错误信息里的 `{U+xxxx}` 转义由 step_snapshot 序列化时引入，
///   用户在面板看到的是已解码后的字符，剪贴板必须保持等价。
/// - **不**追加 stepId / 时间戳 / 元信息：caller 单测显式断言"按钮粘贴出来 ==
///   面板看到的字符串"，加修饰会破坏这个等价。
@visibleForTesting
String formatStepErrorClipboardText(String? error) {
  if (error == null || error.isEmpty) return '暂无错误信息';
  return decodeUnicodeEscapes(error);
}

/// 把 [MergeJob] 渲染成 `已完成 N/M[，当前 rX]` 风格的进度短语。
///
/// - `completedIndex` 会被夹在 `[0, revisions.length]` 区间内，避免越界。
/// - 没有当前 revision 时（如全部完成或队列为空）不再附加 “当前 rX”。
@visibleForTesting
String formatRevisionProgress(MergeJob job) {
  final completed = clampedCompletedRevisionCount(job);
  final currentRevision = job.currentRevision;
  final currentText = currentRevision == null ? '' : '，当前 r$currentRevision';
  return '$completed/${job.revisions.length}$currentText';
}

/// 计算 [MergeJob] 的进度分数（`[0.0, 1.0]`），用于驱动 `LinearProgressIndicator`。
///
/// **契约**（对齐 `_buildCurrentJobSection` 与 `_buildProgressSection` 中**完全相同**的两段
/// 内联算式 `completedIndex.clamp(0, length)` + `length == 0 ? 0.0 : completed / length`）：
/// - `revisions.length == 0` → 返回 `0.0`，避免除零；
/// - `completedIndex` 先 `clamp(0, revisions.length)`，所以负数返回 `0.0`、超长返回 `1.0`，
///   永远不会越界——这是上游保护，理论上 `completedIndex` 不会在 `[0, length]` 之外，
///   但模型默认值/copyWith 异常时仍能优雅降级。
@visibleForTesting
double computeJobProgressFraction(MergeJob job) {
  final length = job.revisions.length;
  if (length == 0) return 0.0;
  final completed = clampedCompletedRevisionCount(job);
  return completed / length;
}

/// 把 Map 渲染成两空格缩进的 JSON 文本，并把其中 `{U+xxxx}` 还原成原字符。
///
/// 空 Map 直接返回 `{}`，避免出现 `{ }` 这种带换行的空对象。
@visibleForTesting
String formatJsonForDisplay(Map<String, dynamic> data) {
  if (data.isEmpty) return '{}';
  const encoder = JsonEncoder.withIndent('  ');
  return decodeUnicodeEscapes(encoder.convert(data));
}

/// 将步骤快照状态枚举映射为中文显示文本。
@visibleForTesting
String snapshotStatusText(StepExecutionStatus status) {
  switch (status) {
    case StepExecutionStatus.pending:
      return '待执行';
    case StepExecutionStatus.running:
      return '执行中';
    case StepExecutionStatus.completed:
      return '已完成';
    case StepExecutionStatus.failed:
      return '失败';
    case StepExecutionStatus.skipped:
      return '已跳过';
  }
}

/// 将步骤快照状态枚举映射为展示用颜色。
@visibleForTesting
Color snapshotStatusColor(StepExecutionStatus status) {
  switch (status) {
    case StepExecutionStatus.pending:
      return Colors.grey;
    case StepExecutionStatus.running:
      return Colors.blue;
    case StepExecutionStatus.completed:
      return Colors.green;
    case StepExecutionStatus.failed:
      return Colors.red;
    case StepExecutionStatus.skipped:
      return Colors.orange;
  }
}

/// 将步骤快照状态枚举映射为展示用图标。
///
/// 与 [snapshotStatusText] / [snapshotStatusColor] 配对，三者覆盖同一份枚举的"文案 / 颜色 / 图标"
/// 三联展示（之前 icon 一直内联在 `_MergeExecutionPanelState` 里没抽出来——补齐遗漏）。
@visibleForTesting
IconData snapshotStatusIcon(StepExecutionStatus status) {
  switch (status) {
    case StepExecutionStatus.pending:
      return Icons.schedule;
    case StepExecutionStatus.running:
      return Icons.play_circle;
    case StepExecutionStatus.completed:
      return Icons.check_circle;
    case StepExecutionStatus.failed:
      return Icons.error;
    case StepExecutionStatus.skipped:
      return Icons.skip_next;
  }
}

/// 将执行器状态枚举映射为中文标题。
@visibleForTesting
String executorStatusTitle(ExecutorStatus status) {
  switch (status) {
    case ExecutorStatus.idle:
      return '等待执行';
    case ExecutorStatus.running:
      return '执行中';
    case ExecutorStatus.paused:
      return '已暂停';
    case ExecutorStatus.completed:
      return '执行完成';
  }
}

/// 将执行器状态枚举映射为展示用图标。
@visibleForTesting
IconData executorStatusIcon(ExecutorStatus status) {
  switch (status) {
    case ExecutorStatus.idle:
      return Icons.schedule;
    case ExecutorStatus.running:
      return Icons.play_circle;
    case ExecutorStatus.paused:
      return Icons.pause_circle;
    case ExecutorStatus.completed:
      return Icons.check_circle;
  }
}

/// 将执行器状态枚举映射为展示用颜色。
@visibleForTesting
Color executorStatusColor(ExecutorStatus status) {
  switch (status) {
    case ExecutorStatus.idle:
      return Colors.grey;
    case ExecutorStatus.running:
      return Colors.blue;
    case ExecutorStatus.paused:
      return Colors.orange;
    case ExecutorStatus.completed:
      return Colors.green;
  }
}

/// 执行器是否处于"忙碌中"——即 header 区域的 status 图标应改为 spinner（旋转的进度环），
/// 而不是用 [executorStatusIcon] 给出的静态图标。
///
/// **契约**：仅 `running` 为 true，其他三态全为 false。
/// - `running` → true（用户视角：任务正在跑，应当显示动画反馈）
/// - `idle` / `paused` / `completed` → false（静态状态，用 [executorStatusIcon] 即可）
///
/// **为什么抽**：原 `_StatusIcon.build` 用 `switch + return SizedBox(... CircularProgressIndicator)` 这种
/// 提前返回的"特例分支"，让"running 用 spinner"这条契约埋在 widget 树里——三个静态状态用 `executorStatusIcon`
/// + `executorStatusColor`，唯独 running 走 spinner，是**唯一**的不对称点。
/// 抽到顶层后：
/// 1. 单测能直接断言"running 是唯一 busy 态"，未来若加 ExecutorStatus 第 5 态、或要给 paused
///    也加 spinner（不太可能但），改这一处即可，不必动 widget 树；
/// 2. `_StatusIcon` 不再用自己的 switch 重复 icon/color 字面量，全部走 `executorStatusIcon`/
///    `executorStatusColor`/`executorStatusIsBusy` 三个 helper，**消除字面量重复**。
///
/// **与 `shouldShowTerminateHint` 的关系**：两者都仅在 `running` 时为 true，但语义不同——
/// 前者是"图标动画 vs 静态"，后者是"是否显示文字提示"，前缀和用途完全分裂，刻意不合并
/// （遵循设计模式 #9 / #10：形似但语义不同的函数不合并）。
@visibleForTesting
bool executorStatusIsBusy(ExecutorStatus status) {
  return status == ExecutorStatus.running;
}

/// 将执行器状态枚举映射为状态栏中的描述信息。
@visibleForTesting
String executorStatusMessage(ExecutorStatus status) {
  switch (status) {
    case ExecutorStatus.idle:
      return '等待开始';
    case ExecutorStatus.running:
      return '正在执行...';
    case ExecutorStatus.paused:
      return '等待人工处理';
    case ExecutorStatus.completed:
      return '执行完成';
  }
}

/// 判断步骤快照的"详情"内容是否为空——即四个展示用字段全部空。
///
/// **契约**：`inputData.isEmpty && config.isEmpty && output == null && error == null`
/// 才算空。其他字段（startTime / endTime / status / durationMs）属于"元信息"，
/// 即便只有它们也不算"详情为空"——`_buildSnapshotInfoCard` 始终会展示元信息。
///
/// **为什么抽**：原 `_buildStepDetailView` 的 4 字段联合空判内联在 widget 树里，
/// 未来如果 [StepSnapshot] 加了新的"详情字段"（如 `metadata`、`logs`），改这一处
/// 比改 widget 树里的 if 条件更显眼——单测会立刻爆出"哪些字段算详情"。
@visibleForTesting
bool isStepSnapshotDetailEmpty(StepSnapshot snapshot) {
  return snapshot.inputData.isEmpty &&
      snapshot.config.isEmpty &&
      snapshot.output == null &&
      snapshot.error == null;
}

/// 当 [isStepSnapshotDetailEmpty] 为 true 时显示的占位文案。
///
/// **契约**：仅依赖 [StepExecutionStatus]：
/// - `pending` → `'该步骤尚未执行'`（用户视角：还没轮到，无数据正常）
/// - 其他状态（running/completed/failed/skipped）→ `'该步骤没有详细数据'`
///   （用户视角：执行过了但本步骤本来就没产出 input/config/output/error）
///
/// 把这两个分支提到顶层，避免和 [snapshotStatusText] 那套文案被混淆——
/// 它们是不同语义层（"占位提示" vs "状态徽标"），但同样依赖 status 枚举。
@visibleForTesting
String describeEmptySnapshotPlaceholder(StepExecutionStatus status) {
  return status == StepExecutionStatus.pending ? '该步骤尚未执行' : '该步骤没有详细数据';
}

/// `_buildStepDetailView` 内 6 个可选 section 的出现 / 消失规格。
///
/// **核心契约 — globalContext 与"详情空"判定相互独立**：原 widget 树里
/// `globalContext.isNotEmpty` 决定**全局上下文** section（行 449-457），与
/// [isStepSnapshotDetailEmpty] 的 4 字段判定（inputData / config / output / error）
/// **完全分离**：即使 4 字段全空、placeholder 显示中，**globalContext 仍然会单独显示**——
/// 这是有意行为，"步骤本身没有详细数据"和"全局上下文是否存在"是两件不相干的事，
/// 占位文案"该步骤没有详细数据"指的就是步骤本身的 4 个字段，不是 globalContext。
///
/// 6 个标志位按 widget 树渲染顺序排列（与原 `_buildStepDetailView` 行 448-537 严格对齐）：
/// 1. [showGlobalContext]：`globalContext.isNotEmpty`
/// 2. [showInputData]：`snapshot.inputData.isNotEmpty`
/// 3. [showConfig]：`snapshot.config.isNotEmpty`
/// 4. [showOutput]：`snapshot.output != null`
/// 5. [showError]：`snapshot.error != null`
/// 6. [showEmptyPlaceholder]：`isStepSnapshotDetailEmpty(snapshot)`——即 inputData/config/output/error
///    四者都空时才为 true。**注意 globalContext 不在这条判定里**。
///
/// **不变量**：[showEmptyPlaceholder] 蕴含 `!showInputData && !showConfig && !showOutput && !showError`
/// （但**不**蕴含 `!showGlobalContext`——见上文核心契约）。本类不强制此不变量、由 [resolveSnapshotDetailSections]
/// 的实现保证；测试用真值表显式锁定。
///
/// **为什么抽**：原 widget 树里 5 处 `if (...) ...[` 散落在 90 行 children list 里，
/// 哪一条 if 用什么字段、哪一条**不**计入 placeholder 判定，全靠人脑追代码——任何人
/// 把 "globalContext 也算 detail empty 一员"误改进 [isStepSnapshotDetailEmpty]，
/// 用户视角的 placeholder 文案就会在"全局上下文存在但步骤本身无数据"时消失。
/// 抽出后用 truth-table + 反向断言锁定独立性。
@visibleForTesting
class SnapshotDetailSectionFlags {
  final bool showGlobalContext;
  final bool showInputData;
  final bool showConfig;
  final bool showOutput;
  final bool showError;
  final bool showEmptyPlaceholder;

  const SnapshotDetailSectionFlags({
    required this.showGlobalContext,
    required this.showInputData,
    required this.showConfig,
    required this.showOutput,
    required this.showError,
    required this.showEmptyPlaceholder,
  });

  @override
  bool operator ==(Object other) {
    if (other is! SnapshotDetailSectionFlags) return false;
    return other.showGlobalContext == showGlobalContext &&
        other.showInputData == showInputData &&
        other.showConfig == showConfig &&
        other.showOutput == showOutput &&
        other.showError == showError &&
        other.showEmptyPlaceholder == showEmptyPlaceholder;
  }

  @override
  int get hashCode => Object.hash(
        showGlobalContext,
        showInputData,
        showConfig,
        showOutput,
        showError,
        showEmptyPlaceholder,
      );

  @override
  String toString() => 'SnapshotDetailSectionFlags('
      'showGlobalContext: $showGlobalContext, '
      'showInputData: $showInputData, '
      'showConfig: $showConfig, '
      'showOutput: $showOutput, '
      'showError: $showError, '
      'showEmptyPlaceholder: $showEmptyPlaceholder)';
}

/// 由 (snapshot, globalContext) 推断 6 个 detail section 的可见性。
///
/// 见 [SnapshotDetailSectionFlags] 的核心契约说明：globalContext 与"详情空"判定独立。
///
/// **字面量与原 `_buildStepDetailView` 严格一致**：
/// - showGlobalContext: `globalContext.isNotEmpty`
/// - showInputData: `snapshot.inputData.isNotEmpty`
/// - showConfig: `snapshot.config.isNotEmpty`
/// - showOutput: `snapshot.output != null`
/// - showError: `snapshot.error != null`
/// - showEmptyPlaceholder: `isStepSnapshotDetailEmpty(snapshot)`
@visibleForTesting
SnapshotDetailSectionFlags resolveSnapshotDetailSections({
  required StepSnapshot snapshot,
  required Map<String, dynamic> globalContext,
}) {
  return SnapshotDetailSectionFlags(
    showGlobalContext: globalContext.isNotEmpty,
    showInputData: snapshot.inputData.isNotEmpty,
    showConfig: snapshot.config.isNotEmpty,
    showOutput: snapshot.output != null,
    showError: snapshot.error != null,
    showEmptyPlaceholder: isStepSnapshotDetailEmpty(snapshot),
  );
}

/// 选中态 header 的两条文案：主标题（displayName）+ 副标题（typeId）。
///
/// **兜底优先级**（从高到低）：
/// - `displayName`：`snapshot.stepName` → `snapshot.stepTypeId` → `selectedStepId`
/// - `typeId`：`snapshot.stepTypeId` → `selectedStepId`
///
/// **契约**：`selectedStepId` 在 caller 已用 `widget.selectedStepId!` 解过空——
/// 此处接受非 null `String`。`snapshot == null` 时两个字段都直接落到 `selectedStepId`。
///
/// **抽离动机**：原 `_buildHeader` 用了 `??` 链，`stepName` 落到 `stepTypeId` 再落
/// `selectedStepId` 这条优先级是隐性约定——没有测试锁定，重构者很容易把"先 typeId 再
/// stepName"反掉而不被发现。
@visibleForTesting
({String displayName, String typeId}) resolveSelectedStepHeaderLabels({
  required StepSnapshot? snapshot,
  required String selectedStepId,
}) {
  final displayName =
      snapshot?.stepName ?? snapshot?.stepTypeId ?? selectedStepId;
  final typeId = snapshot?.stepTypeId ?? selectedStepId;
  return (displayName: displayName, typeId: typeId);
}

/// `_buildProgressSection` 中"当前 revision"那一行的文案。
///
/// **契约**：
/// - `currentRevision == null` → `'当前 revision 已完成'`（语义：进度条已走完，没有"正在做"的 revision）
/// - 非 null → `'当前: r$currentRevision'`（**全角冒号 + 空格**——与文件内其他展示文案如 `'已完成 N/M'` 保持中文 UI 风格）
///
/// **不接 `MergeJob`，只接 `int?`**：原 inline 取的就是 `job.currentRevision`，把这一层"从 job 取字段"的责任留给 caller，函数本体保持纯——单测无需构造 `MergeJob` fixture。
///
/// **与 `formatRevisionProgress` 的关系**：那个函数渲染"已完成 N/M[，当前 rX]"汇总短语，本函数渲染"当前: rX"独立一行；两者都涉及 `currentRevision` 但用在不同位置，文案/前缀都不同，**刻意不复用**——合并会逼出 mode 参数，违反"形似但语义不同的函数不合并"原则（设计模式 #9 / #10）。
@visibleForTesting
String describeCurrentRevisionLine(int? currentRevision) {
  return currentRevision == null ? '当前 revision 已完成' : '当前: r$currentRevision';
}

/// 是否在 `_buildControlSection` 渲染"跳过当前 revision"按钮。
///
/// **契约**：仅当 `pausedJob` 存在且 `pausedJob.currentRevision != null` 时显示。
/// - `pausedJob == null` → false（没有暂停的任务，无 revision 可跳过）
/// - `pausedJob != null` 但 `currentRevision == null` → false（任务里所有 revision 都做完了，无可跳过）
/// - 两者都非 null → true
///
/// **抽出动机**：原 widget 树里**完全相同**的判断 `widget.pausedJob?.currentRevision != null` 出现了两次（一次决定按钮 Expanded，一次决定 SizedBox 间隔）；抽到顶层后两处共用一个变量，未来若改条件（如加上 `paused` 状态判断），改一处即可。
@visibleForTesting
bool shouldShowSkipButton(MergeJob? pausedJob) {
  return pausedJob?.currentRevision != null;
}

/// 跳过按钮的标签文案：`'跳过 r{currentRevision}'`。
///
/// **契约**：接非 null `int`——caller 必须先用 [shouldShowSkipButton] 过滤。负数/0 也照常拼接（不做合法性校验，由上游 `MergeJob.currentRevision` 保证）。
///
/// **与 `describeCurrentRevisionLine` 区分**：那个是状态展示文本（用户视角的进度），这个是按钮 label（用户视角的动作）；前缀完全不同（`'当前: r'` vs `'跳过 r'`），不能合并。
@visibleForTesting
String formatSkipButtonLabel(int currentRevision) {
  return '跳过 r$currentRevision';
}

/// 是否在 `_buildControlSection` 底部渲染"终止指令将在当前步骤执行完成后生效"提示。
///
/// **契约**：仅在 `status == ExecutorStatus.running` 时显示。
/// - `running` → true（用户按下"终止任务"后命令不会立即生效，需要解释延迟）
/// - 其他状态（`idle`/`paused`/`completed`）→ false（暂停态终止立即生效；空闲/已完成态不显示终止按钮，提示无意义）
///
/// **为什么钉契约**：这条"延迟生效"提示的隐性假设是 `running` 状态下终止按钮**仍然可点**——日后若加上 disable 终止按钮的逻辑，这个提示也要联动；单测显式锁定四个 status 的真值表，未来漏改一处会立刻红。
@visibleForTesting
bool shouldShowTerminateHint(ExecutorStatus status) {
  return status == ExecutorStatus.running;
}

/// 是否在 `_buildPausedSummarySection` 渲染"标记为已解决"按钮。
///
/// **契约**：当且仅当 [failureKind] 是 conflict 类（textConflict / treeConflict）时返回 true。
/// 其他 failureKind（authFailed / outOfDate / locked / unknown）下 `svn resolve --accept working`
/// 没有合理语义——authFailed/locked 与冲突无关；outOfDate 应该走"继续"重跑提交；unknown
/// 不应该让用户瞎按 resolve（可能掩盖真实问题）。
///
/// **抽出动机**：`_buildPausedSummarySection` 的按钮渲染条件可读性较差（链式
/// `widget.onMarkResolved != null && (failureKind == textConflict || failureKind == treeConflict)`），
/// 抽到顶层后既能单测枚举所有 5 种 failureKind 的真值表，又能让 widget 树读起来更清晰。
@visibleForTesting
bool shouldShowMarkResolvedButton(SvnFailureKind failureKind) {
  return failureKind == SvnFailureKind.textConflict ||
      failureKind == SvnFailureKind.treeConflict;
}

/// 是否在 `_buildPausedSummarySection` 渲染"打开冲突文件"按钮。
///
/// **契约**：当且仅当 [failureKind] 为 [SvnFailureKind.textConflict] 时返回 true。
///
/// 与 [shouldShowMarkResolvedButton] 的差异——为什么 treeConflict 不显示？
/// - **textConflict**：SVN 在冲突文件中插入 `<<<<<<<` / `=======` / `>>>>>>>`
///   标记，存在一个具体的"可被编辑器打开"的文本文件，开了直接看 diff 改起来；
/// - **treeConflict**：源端动了文件本身的存在性 / 路径 / 类型（删除 / 重命名 /
///   类型变更），冲突点是"目录树结构"而非"文件内容"，没有"打开就能改"的具体
///   文本文件——用户应该走"打开工作副本目录"再 `svn st` 看局面，本按钮帮不上忙；
/// - 其他 failureKind（authFailed / outOfDate / locked / workingCopyCorrupt /
///   notFound / network / unknown）与文件内容冲突无关，不显示。
@visibleForTesting
bool shouldShowOpenConflictFileButton(SvnFailureKind failureKind) {
  return failureKind == SvnFailureKind.textConflict;
}

/// 是否在 `_buildPausedSummarySection` 渲染"执行 cleanup"按钮。
///
/// **契约**：当且仅当 [failureKind] 为 [SvnFailureKind.locked] 时返回 true。
///
/// 为什么只对 locked 暴露此按钮：
/// - **locked**：典型场景是 `svn: E155004` / `is locked` / `run 'svn cleanup'`，
///   `svn cleanup` 是官方推荐的恢复手段，一键执行后用户可点"继续"重跑；
/// - 其他 8 种 failureKind（textConflict / treeConflict / outOfDate / authFailed
///   / notFound / network / workingCopyCorrupt / unknown）下 `svn cleanup` 没有
///   合理语义——textConflict/treeConflict 是冲突，cleanup 不会清理冲突标记；
///   authFailed/network 与本地状态无关；workingCopyCorrupt 通常需要重新 checkout
///   而非 cleanup；不显示按钮可避免误用。
@visibleForTesting
bool shouldShowCleanupButton(SvnFailureKind failureKind) {
  return failureKind == SvnFailureKind.locked;
}

/// 是否在 `_buildPausedSummarySection` 渲染"调整重试次数"按钮。
///
/// **契约**：当且仅当 [failureKind] 为 [SvnFailureKind.outOfDate] 时返回 true。
///
/// 为什么只对 outOfDate 暴露此按钮：
/// - **outOfDate**：commit 时仓库已被他人更新，状态机已自动 update + 重试 N 次仍然
///   失败；hint 文案明示"多次失败请提高重试上限"，但若用户必须先终止任务、回到
///   设置改全局 `maxRetries`、再重新创建任务，会丢失已合并 revision 的进度——
///   本按钮让用户在暂停态原位临时调高**当前任务**的 `maxRetries`，调整后点
///   "继续"即可触发新一轮重试，无需中断流程；
/// - 其他 8 种 failureKind（textConflict / treeConflict / authFailed / locked /
///   notFound / network / workingCopyCorrupt / unknown）下提高重试次数无意义——
///   重试不会修复冲突 / 凭据 / 网络 / 路径问题，只是徒增等待时间。
@visibleForTesting
bool shouldShowAdjustMaxRetriesButton(SvnFailureKind failureKind) {
  return failureKind == SvnFailureKind.outOfDate;
}

@visibleForTesting
bool shouldShowEditCommitSupplementButton(SvnFailureKind failureKind) {
  return failureKind == SvnFailureKind.missingCrid;
}

@visibleForTesting
bool shouldShowCreateCodeReviewButton(SvnFailureKind failureKind) {
  return failureKind == SvnFailureKind.missingCrid;
}

@visibleForTesting
bool shouldShowEditCommitMessageButton({
  required SvnFailureKind failureKind,
  required String? failedStepName,
  required String? resumeFromStepId,
}) {
  final isCommitStep = failedStepName == '提交' || resumeFromStepId == 'commit';
  return failureKind == SvnFailureKind.unknown && isCommitStep;
}

@visibleForTesting
bool shouldShowResumeCommitButton(
  SvnFailureKind failureKind,
  String? commitSupplement,
  int? currentRevision,
  String? commitMessageOverride,
  int? commitMessageOverrideRevision,
) {
  final hasMessageOverride = currentRevision != null &&
      commitMessageOverrideRevision == currentRevision &&
      commitMessageOverride != null &&
      commitMessageOverride.trim().isNotEmpty;
  if (failureKind == SvnFailureKind.missingCrid) {
    final hasCommitSupplement =
        commitSupplement != null && commitSupplement.trim().isNotEmpty;
    return hasCommitSupplement || hasMessageOverride;
  }
  if (failureKind == SvnFailureKind.unknown) {
    return hasMessageOverride;
  }
  return false;
}

/// 判定暂停态摘要区是否渲染"测试连通性"按钮（仅 [SvnFailureKind.network] 一种触发）。
///
/// **何时渲染（合取）**：
/// - `pausedJob != null` —— `_buildPausedSummarySection` 调用前已守卫；
/// - 本谓词返回 true —— 仅 `failureKind == network` 一档；
/// - `widget.onTestConnectivity != null` —— caller 显式提供回调。
///
/// **为什么仅 network**：
/// - **network**：SVN 命令因 DNS / VPN / 仓库不可达 / TLS 握手失败等暂停；
///   提示用户"恢复网络后点继续"，但**用户在不中断暂停态的前提下没有快速校验
///   网络是否真的恢复的入口**——只能盲点"继续"重试整个 merge 步（耗时长 + 失败
///   后再次入暂停 + 浪费一次重试计数）。本按钮复用第二十六轮 `probeSvnLocation`
///   做一次轻量 `svn info` 探测让用户原位确认连通性。与 `cleanup`（locked） /
///   `adjustMaxRetries`（outOfDate）形成"暂停态专属恢复入口"家族；
/// - 其他 8 种 failureKind 下"测试连通性"语义无效或具误导性：
///   - `textConflict / treeConflict / locked / workingCopyCorrupt` —— 都不是网络问题，
///     连通性测试结果对解决无指导；
///   - `authFailed` —— 凭据问题，本按钮不传 username/password 反而会因匿名探测
///     失败给出错误信号；
///   - `outOfDate` —— commit 阶段竞争，连通性必然 OK；
///   - `notFound` —— URL 配置错误（如分支已删），用户应去配置页改 URL，
///     连通性按钮按钮无修复能力；
///   - `unknown` —— 失败原因未知，盲推"测试网络"按钮可能误导用户。
@visibleForTesting
bool shouldShowTestConnectivityButton(SvnFailureKind failureKind) {
  return failureKind == SvnFailureKind.network;
}

/// 整合：
/// - 执行状态显示
/// - 任务控制指令（恢复、取消、跳过）
/// - 步骤快照详情查看
class MergeExecutionPanel extends StatefulWidget {
  final ExecutorStatus status;
  final String? currentStepId;
  final String? currentStepName;
  final MergeJob? currentJob;
  final MergeJob? pausedJob;
  final VoidCallback onResume;
  final VoidCallback onSkip;
  final VoidCallback onCancel;
  final StepSnapshot? selectedSnapshot;
  final String? selectedStepId;
  final Map<String, dynamic> globalContext;
  final Map<String, StepSnapshot> snapshots;
  final VoidCallback? onClearSelection;

  /// "打开工作副本目录"按钮的回调。
  ///
  /// **契约**：
  /// - 仅在 `pausedJob != null` 时按钮才会渲染（按钮位于 `_buildPausedSummarySection` 内）。
  /// - `null` → 即使任务暂停也不渲染按钮（用于禁用整个能力，例如非桌面平台）。
  /// - 非 null → 渲染按钮，点击触发回调；caller 负责跨平台命令解析与 `Process.run`。
  ///
  /// **为什么留在 caller 而非 panel**：panel 是纯 UI 层，避免引入 `dart:io` /
  /// `Platform` / `Process` 依赖；caller (main_screen_v3) 已组装好 `pausedJob.targetWc`，
  /// 由它复用 `settings_screen.dart` 中的 `resolveOpenDirectoryCommand`。
  final VoidCallback? onOpenWorkingCopy;

  /// "标记为已解决"按钮的回调（svn resolve --accept &lt;mode&gt; -R）。
  ///
  /// **契约**：
  /// - 仅在 `pausedJob != null` **且** `failureKind ∈ {textConflict, treeConflict}`
  ///   时按钮才会渲染。其他 failureKind（authFailed / outOfDate / locked / unknown）
  ///   下"标记为已解决"语义无效，不显示按钮避免误用。
  /// - `null` → 即使条件满足也不渲染（用于禁用整个能力）。
  /// - 非 null → 渲染主按钮（默认 [SvnResolveAccept.working]）+ 紧邻的高级
  ///   PopupMenuButton（暴露 `mineFull` / `theirsFull` / `base` 三种破坏性递增的
  ///   accept 模式）。caller 根据传入的 mode 调
  ///   `SvnService.resolveAccept(targetWc, mode: mode)` 并在 SnackBar 提示成功 / 失败。
  ///   **不**自动 resume——用户在标记完后仍需手动点 "继续"，与三个原有控制按钮
  ///   （继续/跳过/终止）保持一致的"显式触发"语义。
  final void Function(SvnResolveAccept mode)? onMarkResolved;

  /// "打开冲突文件"按钮的回调。
  ///
  /// **契约**：
  /// - 仅在 `pausedJob != null` **且** `failureKind == textConflict`
  ///   时按钮才会渲染（参见 [shouldShowOpenConflictFileButton]）。treeConflict
  ///   不渲染——见该 helper 的 dartdoc。
  /// - `null` → 即使条件满足也不渲染（用于禁用整个能力）。
  /// - 非 null → 渲染按钮，点击触发回调；caller 负责调
  ///   `SvnService.listConflictedFiles(targetWc)` 取第一条冲突文件、解析为
  ///   绝对路径，再用 `resolveOpenFileCommand` + `Process.run` 打开，
  ///   并在 SnackBar 提示成功 / 失败 / 无冲突文件可打开。
  ///
  /// **为什么留在 caller**：与 `onOpenWorkingCopy` / `onMarkResolved` 同款架构——
  /// panel 不引 `dart:io` / `Platform`，所有平台命令解析与 `Process.run` 都在
  /// `main_screen_v3` 层完成，便于跨平台单元测试 panel。
  final VoidCallback? onOpenConflictFile;

  /// "执行 cleanup"按钮的回调（svn cleanup）。
  ///
  /// **契约**：
  /// - 仅在 `pausedJob != null` **且** `failureKind == locked` 时按钮才会渲染
  ///   （参见 [shouldShowCleanupButton]）。其他 failureKind 下 `svn cleanup`
  ///   没有合理语义。
  /// - `null` → 即使条件满足也不渲染。
  /// - 非 null → 渲染按钮，点击触发回调；caller 调
  ///   `SvnService.cleanup(targetWc)` 并 SnackBar 反馈成功 / 失败。
  ///   **不**自动 resume——与 `onMarkResolved` 一致，用户在 cleanup 完后仍需
  ///   手动点"继续"。
  final VoidCallback? onCleanup;

  /// "调整重试次数"按钮的回调（用户在 outOfDate 暂停态临时调高当前任务的 maxRetries）。
  ///
  /// **契约**：
  /// - 仅在 `pausedJob != null` **且** `failureKind == outOfDate` 时按钮才会渲染
  ///   （参见 [shouldShowAdjustMaxRetriesButton]）。其他 failureKind 下提高重试
  ///   次数无意义，不显示按钮避免误用。
  /// - `null` → 即使条件满足也不渲染。
  /// - 非 null → 渲染按钮，点击触发回调；caller 弹 dialog 让用户输入新值，校验
  ///   通过后调 `MergeExecutionState.updateJobMaxRetries(jobId, newMax)` 持久化，
  ///   并 SnackBar 反馈成功 / 失败。
  ///   **不**自动 resume——与 `onMarkResolved` / `onCleanup` 一致，用户在调整完
  ///   后仍需手动点"继续"。
  final VoidCallback? onAdjustMaxRetries;

  /// "补充 CRID"按钮的回调（missingCrid 暂停态专属）。
  final VoidCallback? onEditCommitSupplement;

  /// "发起 Code Review"按钮的回调（missingCrid 暂停态专属）。
  final VoidCallback? onCreateCodeReview;

  /// "修改提交 Message"按钮的回调（commit 未知失败时的人类兜底入口）。
  final VoidCallback? onEditCommitMessage;

  /// "测试连通性"按钮的回调（network 暂停态专属）。
  ///
  /// **契约**：
  /// - 仅在 `pausedJob != null` **且** `failureKind == network` 时按钮才会渲染
  ///   （参见 [shouldShowTestConnectivityButton]）。其他 failureKind 下此按钮
  ///   语义无效或误导，不渲染。
  /// - `null` → 即使条件满足也不渲染。
  /// - 非 null → 渲染按钮，点击触发回调；caller 走第二十六轮 `probeSvnLocation`
  ///   依次探测 sourceUrl / targetWc，并 SnackBar 反馈通过 / 失败原因。
  ///   **不**自动 resume——与 `onMarkResolved` / `onCleanup` / `onAdjustMaxRetries`
  ///   一致，测试通过后仍需用户手动点"继续"。
  final VoidCallback? onTestConnectivity;

  const MergeExecutionPanel({
    super.key,
    required this.status,
    this.currentStepId,
    this.currentStepName,
    this.currentJob,
    required this.pausedJob,
    required this.onResume,
    required this.onSkip,
    required this.onCancel,
    this.selectedSnapshot,
    this.selectedStepId,
    this.globalContext = const {},
    this.snapshots = const {},
    this.onClearSelection,
    this.onOpenWorkingCopy,
    this.onMarkResolved,
    this.onOpenConflictFile,
    this.onCleanup,
    this.onAdjustMaxRetries,
    this.onEditCommitSupplement,
    this.onCreateCodeReview,
    this.onEditCommitMessage,
    this.onTestConnectivity,
  });

  @override
  State<MergeExecutionPanel> createState() => _MergeExecutionPanelState();
}

class _MergeExecutionPanelState extends State<MergeExecutionPanel> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: widget.selectedStepId != null
                  ? _buildStepDetailView()
                  : _buildExecutionStatusView(),
            ),
          ),
          _buildControlSection(),
        ],
      ),
    );
  }

  Widget _buildExecutionStatusView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatusSection(),
        if (widget.currentJob != null) ...[
          const SizedBox(height: 16),
          _buildCurrentJobSection(),
        ],
        if (widget.pausedJob != null) ...[
          const SizedBox(height: 16),
          _buildProgressSection(),
          const SizedBox(height: 16),
          _buildPausedSummarySection(),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.touch_app, size: 20, color: Colors.grey.shade500),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '点击左侧步骤卡片可查看执行详情',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepDetailView() {
    final snapshot = widget.selectedSnapshot;
    if (snapshot == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Icon(Icons.schedule, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  '步骤尚未执行',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '执行到此步骤后将显示详细信息',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final sections = resolveSnapshotDetailSections(
      snapshot: snapshot,
      globalContext: widget.globalContext,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSnapshotInfoCard(snapshot),
        if (sections.showGlobalContext) ...[
          const SizedBox(height: 12),
          _buildExpandableSection(
            '全局上下文 (\${job.xxx})',
            widget.globalContext,
            Icons.public,
            initiallyExpanded: false,
          ),
        ],
        if (sections.showInputData) ...[
          const SizedBox(height: 8),
          _buildExpandableSection(
            '输入数据 (\${input.xxx})',
            snapshot.inputData,
            Icons.input,
          ),
        ],
        if (sections.showConfig) ...[
          const SizedBox(height: 8),
          _buildExpandableSection(
            '配置参数 (\${config.xxx})',
            snapshot.config,
            Icons.settings,
          ),
        ],
        if (sections.showOutput) ...[
          const SizedBox(height: 8),
          _buildExpandableSection(
            '输出结果 (${snapshot.output!.port})',
            snapshot.output!.data,
            Icons.output,
          ),
        ],
        if (sections.showError) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(
                      '错误信息',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_all, size: 16),
                      tooltip: '复制错误信息到剪贴板',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      color: Colors.red.shade700,
                      onPressed: () => _copyStepError(snapshot.error),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  decodeUnicodeEscapes(snapshot.error!),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (sections.showEmptyPlaceholder) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              describeEmptySnapshotPlaceholder(snapshot.status),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSnapshotInfoCard(StepSnapshot snapshot) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getSnapshotStatusColor(snapshot.status)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getSnapshotStatusIcon(snapshot.status),
                      size: 14,
                      color: _getSnapshotStatusColor(snapshot.status),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getSnapshotStatusText(snapshot.status),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _getSnapshotStatusColor(snapshot.status),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (snapshot.durationMs != null)
                Text(
                  '${snapshot.durationMs}ms',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '开始: ${_formatTime(snapshot.startTime)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
          if (snapshot.endTime != null)
            Text(
              '结束: ${_formatTime(snapshot.endTime!)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) => formatStepTime(time);

  IconData _getSnapshotStatusIcon(StepExecutionStatus status) =>
      snapshotStatusIcon(status);

  Widget _buildHeader() {
    final hasSelection = widget.selectedStepId != null;
    if (hasSelection) {
      final snapshot = widget.selectedSnapshot;
      final labels = resolveSelectedStepHeaderLabels(
        snapshot: snapshot,
        selectedStepId: widget.selectedStepId!,
      );
      final displayName = labels.displayName;
      final typeId = labels.typeId;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.purple.shade50,
        child: Row(
          children: [
            Icon(Icons.info, color: Colors.purple.shade700, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade900,
                    ),
                  ),
                  if (snapshot != null)
                    Text(
                      typeId,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.purple.shade600,
                      ),
                    ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: widget.onClearSelection,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('返回'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.purple.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _getStatusColor().withValues(alpha: 0.1),
      child: Row(
        children: [
          _StatusIcon(status: widget.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusTitle(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.currentStepName != null)
                  Text(
                    widget.currentStepName!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 复制步骤错误信息到剪贴板。
  ///
  /// 走 [formatStepErrorClipboardText] 把 `null` / 空串归一为占位符 `'暂无错误信息'`，
  /// 非空内容做 `decodeUnicodeEscapes` 还原与面板里 `SelectableText` 等价。点击后
  /// SnackBar `'步骤错误已复制到剪贴板'` 给反馈——和 `log_dialog._copyLog` 同款体验。
  ///
  /// **架构注意（R131 不变量）**：lib/ 内 `mounted` 出现位置被锁死在两个 State 类
  /// （main_screen_v3 / settings_screen）+ 两个 dialog（log_dialog / config_dialog 的
  /// context.mounted）。本方法在 `await` 前**先抓 ScaffoldMessenger**，从而完全
  /// 不引用 `mounted`——既保持 R131 锁，又避免 await-then-context lint。
  Future<void> _copyStepError(String? error) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = formatStepErrorClipboardText(error);
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      const SnackBar(content: Text('步骤错误已复制到剪贴板')),
    );
  }

  Widget _buildExpandableSection(
    String title,
    Map<String, dynamic> data,
    IconData icon, {
    bool initiallyExpanded = true,
  }) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Icon(icon, size: 16, color: Colors.purple.shade600),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.purple.shade800,
        ),
      ),
      initiallyExpanded: initiallyExpanded,
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            formatJsonForDisplay(data),
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  String _getSnapshotStatusText(StepExecutionStatus status) =>
      snapshotStatusText(status);

  Color _getSnapshotStatusColor(StepExecutionStatus status) =>
      snapshotStatusColor(status);

  Widget _buildStatusSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getStatusIcon(),
                size: 20,
                color: _getStatusColor(),
              ),
              const SizedBox(width: 8),
              Text(
                _getStatusMessage(),
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _getStatusColor(),
                ),
              ),
            ],
          ),
          if (widget.currentStepId != null) ...[
            const SizedBox(height: 8),
            Text(
              '步骤: ${widget.currentStepId}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentJobSection() {
    final job = widget.currentJob!;
    final progress = computeJobProgressFraction(job);
    final progressText = formatRevisionProgress(job);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                '当前任务 #${job.jobId}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '源: ${job.sourceUrl}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            '目标: ${job.targetWc}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已完成 $progressText',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final job = widget.pausedJob!;
    final progress = computeJobProgressFraction(job);
    final progressText = formatRevisionProgress(job);
    final currentRevision = job.currentRevision;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '执行进度',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                progressText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            describeCurrentRevisionLine(currentRevision),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          if (job.pauseReason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '原因: ${job.pauseReason}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPausedSummarySection() {
    final job = widget.pausedJob!;
    final summary = summarizePausedJob(
      job: job,
      snapshots: widget.snapshots,
    );

    final lines = <Widget>[
      Row(
        children: [
          Icon(Icons.pause_circle_filled,
              size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Text(
            '任务 #${summary.jobId} 已暂停',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          _buildFailureKindChip(summary.failureKind),
        ],
      ),
      const SizedBox(height: 8),
      _summaryLine('暂停原因', summary.pauseReason, Colors.orange.shade700),
      _summaryLine(
        '当前进度',
        summary.currentRevision == null
            ? '${summary.completedCount}/${summary.totalCount}'
            : '${summary.completedCount}/${summary.totalCount}（卡在 r${summary.currentRevision}）',
        Colors.grey.shade700,
      ),
    ];

    if (summary.hasFailedStepInfo) {
      final stepLabel = summary.failedStepName ?? '未知步骤';
      final errorText = summary.failedStepError ?? '';
      lines.add(_summaryLine(
        '失败步骤',
        errorText.isEmpty ? stepLabel : '$stepLabel：$errorText',
        Colors.red.shade700,
      ));
    }

    if (summary.hasCommitRetryInfo) {
      lines.add(_summaryLine(
        '提交重试',
        '${summary.commitRetryCount}/${summary.commitMaxRetries}（out-of-date）',
        Colors.blue.shade700,
      ));
    }

    // 操作建议 hint：分类不是 unknown 才显示（避免对未识别错误甩一句通用废话）。
    if (summary.failureKind != SvnFailureKind.unknown) {
      final presentation = presentationFor(summary.failureKind);
      lines.add(const SizedBox(height: 4));
      lines.add(_summaryLine(
        '建议',
        presentation.hint,
        Colors.blueGrey.shade700,
      ));
    }

    // "打开工作副本目录"按钮：暂停态用户最常需要的诊断动作之一——直接到工作副本
    // 查看冲突文件 / 跑 svn st。仅在 caller 提供 onOpenWorkingCopy 时渲染。
    // 与"标记为已解决"并排（Wrap 自动换行），二者语义独立、可单独提供。
    final actionButtons = <Widget>[];
    if (widget.onOpenWorkingCopy != null) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onOpenWorkingCopy,
        icon: const Icon(Icons.folder_open, size: 16),
        label: const Text('打开工作副本目录'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange.shade800,
          side: BorderSide(color: Colors.orange.shade300),
        ),
      ));
    }
    if (widget.onMarkResolved != null &&
        shouldShowMarkResolvedButton(summary.failureKind)) {
      final markResolved = widget.onMarkResolved!;
      // 主按钮：默认 working 模式（保留 WC 当前形态，最常见场景）。
      actionButtons.add(OutlinedButton.icon(
        onPressed: () => markResolved(SvnResolveAccept.working),
        icon: const Icon(Icons.check_circle_outline, size: 16),
        label: const Text('标记为已解决'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green.shade800,
          side: BorderSide(color: Colors.green.shade300),
        ),
      ));
      // 高级菜单：暴露另外 3 种破坏性递增的 accept 模式。
      // 单独按钮而非 SplitButton，因为 PopupMenuButton 自带 hover tooltip + 离散选择
      // 体验，避免误触主按钮。
      actionButtons.add(PopupMenuButton<SvnResolveAccept>(
        tooltip: '高级 accept 模式（覆盖 / 丢弃改动）',
        onSelected: markResolved,
        itemBuilder: (context) => const [
          PopupMenuItem<SvnResolveAccept>(
            value: SvnResolveAccept.mineFull,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('--accept mine-full'),
              subtitle: Text(
                '保留我方分支整个文件，丢弃 incoming 改动',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
          PopupMenuItem<SvnResolveAccept>(
            value: SvnResolveAccept.theirsFull,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('--accept theirs-full'),
              subtitle: Text(
                '采纳对方整个文件，丢弃我方改动',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
          PopupMenuItem<SvnResolveAccept>(
            value: SvnResolveAccept.base,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('--accept base'),
              subtitle: Text(
                '恢复到合并前 BASE 版本，丢弃所有改动',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.more_horiz, size: 16, color: Colors.green.shade800),
              const SizedBox(width: 4),
              Text(
                '更多…',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
        ),
      ));
    }
    if (widget.onOpenConflictFile != null &&
        shouldShowOpenConflictFileButton(summary.failureKind)) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onOpenConflictFile,
        icon: const Icon(Icons.description_outlined, size: 16),
        label: const Text('打开冲突文件'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.deepPurple.shade800,
          side: BorderSide(color: Colors.deepPurple.shade300),
        ),
      ));
    }
    if (widget.onCleanup != null &&
        shouldShowCleanupButton(summary.failureKind)) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onCleanup,
        icon: const Icon(Icons.cleaning_services, size: 16),
        label: const Text('执行 cleanup'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.teal.shade800,
          side: BorderSide(color: Colors.teal.shade300),
        ),
      ));
    }
    if (widget.onAdjustMaxRetries != null &&
        shouldShowAdjustMaxRetriesButton(summary.failureKind)) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onAdjustMaxRetries,
        icon: const Icon(Icons.tune, size: 16),
        label: const Text('调整重试次数'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.indigo.shade800,
          side: BorderSide(color: Colors.indigo.shade300),
        ),
      ));
    }
    if (widget.onEditCommitSupplement != null &&
        shouldShowEditCommitSupplementButton(summary.failureKind)) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onEditCommitSupplement,
        icon: const Icon(Icons.rate_review_outlined, size: 16),
        label: const Text('补充 CRID'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.deepOrange.shade800,
          side: BorderSide(color: Colors.deepOrange.shade300),
        ),
      ));
    }
    if (widget.onCreateCodeReview != null &&
        shouldShowCreateCodeReviewButton(summary.failureKind)) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onCreateCodeReview,
        icon: const Icon(Icons.add_link, size: 16),
        label: const Text('发起 Code Review'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.blueGrey.shade800,
          side: BorderSide(color: Colors.blueGrey.shade300),
        ),
      ));
    }
    if (widget.onEditCommitMessage != null &&
        shouldShowEditCommitMessageButton(
          failureKind: summary.failureKind,
          failedStepName: summary.failedStepName,
          resumeFromStepId: job.resumeFromStepId,
        )) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onEditCommitMessage,
        icon: const Icon(Icons.edit_note, size: 16),
        label: const Text('修改提交 Message'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.purple.shade800,
          side: BorderSide(color: Colors.purple.shade300),
        ),
      ));
    }
    if (shouldShowResumeCommitButton(
      summary.failureKind,
      job.commitSupplement,
      summary.currentRevision,
      job.commitMessageOverride,
      job.commitMessageOverrideRevision,
    )) {
      actionButtons.add(ElevatedButton.icon(
        onPressed: widget.onResume,
        icon: const Icon(Icons.play_arrow, size: 16),
        label: const Text('继续提交'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      ));
    }
    if (widget.onTestConnectivity != null &&
        shouldShowTestConnectivityButton(summary.failureKind)) {
      actionButtons.add(OutlinedButton.icon(
        onPressed: widget.onTestConnectivity,
        icon: const Icon(Icons.wifi_find, size: 16),
        label: const Text('测试连通性'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.cyan.shade800,
          side: BorderSide(color: Colors.cyan.shade300),
        ),
      ));
    }
    if (actionButtons.isNotEmpty) {
      lines.add(const SizedBox(height: 8));
      lines.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actionButtons,
      ));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  Widget _summaryLine(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureKindChip(SvnFailureKind kind) {
    final p = presentationFor(kind);
    final isSevere = p.severity == SvnFailureSeverity.severe;
    final bg = isSevere ? Colors.red.shade100 : Colors.orange.shade100;
    final fg = isSevere ? Colors.red.shade800 : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        p.label,
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildControlSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.status == ExecutorStatus.paused)
            ElevatedButton.icon(
              onPressed: widget.onResume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('继续执行'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (shouldShowSkipButton(widget.pausedJob))
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onSkip,
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: Text(
                      formatSkipButtonLabel(
                        widget.pausedJob!.currentRevision!,
                      ),
                    ),
                  ),
                ),
              if (shouldShowSkipButton(widget.pausedJob))
                const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('终止任务'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          if (shouldShowTerminateHint(widget.status)) ...[
            const SizedBox(height: 8),
            Text(
              '终止指令将在当前步骤执行完成后生效',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusTitle() => executorStatusTitle(widget.status);

  IconData _getStatusIcon() => executorStatusIcon(widget.status);

  Color _getStatusColor() => executorStatusColor(widget.status);

  String _getStatusMessage() => executorStatusMessage(widget.status);
}

class _StatusIcon extends StatelessWidget {
  final ExecutorStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = executorStatusColor(status);
    if (executorStatusIsBusy(status)) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    return Icon(executorStatusIcon(status), size: 24, color: color);
  }
}
