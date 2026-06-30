/// 合并任务模型
///
/// 表示一个待执行或已执行的合并任务，包含完整的参数和状态信息

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';

import 'merge_config.dart';

part 'merge_job.g.dart';

/// 任务状态枚举
enum JobStatus {
  @JsonValue('pending')
  pending, // 等待执行

  @JsonValue('running')
  running, // 执行中

  @JsonValue('paused')
  paused, // 暂停（需要人工介入）

  @JsonValue('done')
  done, // 完成

  @JsonValue('failed')
  failed, // 失败（已放弃）
}

extension JobStatusExtension on JobStatus {
  /// 获取中文显示名称
  String get displayName {
    switch (this) {
      case JobStatus.pending:
        return '等待';
      case JobStatus.running:
        return '执行中';
      case JobStatus.paused:
        return '已暂停';
      case JobStatus.done:
        return '完成';
      case JobStatus.failed:
        return '失败';
    }
  }

  /// 是否是活跃状态（需要显示在任务列表中）
  bool get isActive {
    return this == JobStatus.pending ||
        this == JobStatus.running ||
        this == JobStatus.paused;
  }

  /// 是否是已结束状态（完成或失败）
  bool get isFinished {
    return this == JobStatus.done || this == JobStatus.failed;
  }
}

const String kInterruptedJobPauseReason = '检测到上次执行在中途中断，请检查工作副本后继续或终止';

/// 从工作副本路径中抽出"末段"作为展示名（人类可读的简称）。
///
/// 例：`/Users/foo/wc/projectA` → `'projectA'`；`C:\\foo\\wc\\projectA` → `'C:\\foo\\wc\\projectA'`
/// （**注意**：仅按 `/` 切分，不识别 Windows 反斜杠——SvnAutoMerge 工作副本路径在
/// `WorkingCopyManager.normalizeWorkingCopyPath` 早已统一为正斜杠，到 [MergeJob.targetWc]
/// 时不会再有反斜杠路径；这里**故意不**重复做规范化，让上游路径规范化是唯一事实源）。
///
/// **行为契约**：
/// - 末段为空（路径以 `/` 结尾，例如 `/tmp/wc/`）→ 返回空串，**不**回退到倒数第二段。
///   这是非防御性的：路径以 `/` 结尾通常是上游 bug 信号（例如 `targetWc` 拼接时多
///   加了一个 `/`），让空字符串显眼出现比"猜上一段"更利于排查。
/// - 输入不含 `/`（例如 `'projectA'`）→ 整段返回，与 `String.split('/').last` 一致。
/// - 空字符串 → 空字符串。
@visibleForTesting
String extractWcDisplayName(String targetWc) => targetWc.split('/').last;

/// 从源 URL 中抽出"末段"作为分支名（如 trunk / branches/feature-x → `feature-x`）。
///
/// **行为契约**：
/// - 与 [extractWcDisplayName] **共享实现细节**（都是 `split('/').last`），但**刻意保留
///   两个独立函数**——语义不同：一个在文件系统路径上工作、一个在 URL 上工作。未来若
///   URL 末段提取需要做 query string / fragment 剥离（如 `?revision=100`），独立函数让
///   修改不会污染路径侧。
/// - SVN URL 不允许 fragment / query，所以当前实现完全相同；测试也用对仗式断言来
///   表达"今天相同、明天可能不同"的预期。
///
/// **R89 漏迁巡检收口**：[buildJobSubtitle]（`screens/components/job_queue_panel.dart:37`）
/// 内联了 `job.sourceUrl.split('/').last`——与本函数行为完全等价。原 `@visibleForTesting`
/// 因跨库调用会触发 analyzer `invalid_use_of_visible_for_testing_member`（与 R84
/// `clampedCompletedRevisionCount`、R88 `isUsableSourceUrl` 同坑），R89 主动放弃
/// `@visibleForTesting`、把第 2 处 callsite 收回。callsite 数：merge_job.dart × 1 +
/// job_queue_panel.dart × 1 = 2。
///
/// **为什么主动放弃 `@visibleForTesting`（R89）**：本函数是项目内"SVN URL 末段提取"
/// 的唯一事实源，跨库 caller `job_queue_panel.buildJobSubtitle` 在生产代码中调用是
/// 设计本意（subtitle 渲染需要短分支名）。单测仍可通过普通 import 访问。
String extractSourceDisplayName(String sourceUrl) => sourceUrl.split('/').last;

/// 把 revision 列表渲染成 `'r100, r101, r102'` 的紧凑字符串。
///
/// **行为契约**：
/// - 每个数字加 `'r'` 前缀，半角逗号 + 空格分隔；
/// - 空列表 → 空字符串（**不**返回 `'(无)'` 或 `'-'` 之类的占位符——上层调用站本身
///   就是 [formatJobDescription]，列表为空时整体描述行的 `'| r...'` 段会变成 `'| '`，
///   作为 bug 信号显眼出现，比静默替换占位更利排查）；
/// - 单元素 → 不加分隔符（`[100]` → `'r100'`）；
/// - 不对负数做防御（SVN revision >= 1，传负数 = 上游 bug 应当暴露成 `'r-1'`）；
/// - 不去重、不排序——保持入参顺序，让"乱序的 revisions"在日志里直接显眼。
///
/// **R92 主动放弃 `@visibleForTesting`**：与 R84 / R88 / R89 / R90 同模式——
/// 本 helper 的 callsite 从 R92 起跨库扩展（`screens/components/job_queue_panel.dart`
/// 的 `formatJobRevisionList` 内部 delegate 进来，把"revision 列表渲染"统一成
/// 唯一逻辑源，避免 `revisions.map((r) => 'r$r').join(', ')` 在 model/ 与 screens/
/// 各写一份）。跨库 caller 命中 `invalid_use_of_visible_for_testing_member`
/// 警告，按已稳定的"helper 跨库后放弃 visibleForTesting"模式收口。
String formatRevisionListShort(List<int> revisions) =>
    revisions.map((r) => 'r$r').join(', ');

/// 计算 [job] 的「夹紧后的已完成 revision 数」——`completedIndex` 经
/// `clamp(0, revisions.length)` 后的值。
///
/// **核心契约**：返回值始终落在 `[0, job.revisions.length]` 闭区间内。
/// - `completedIndex < 0` → 返回 0；
/// - `completedIndex > revisions.length` → 返回 `revisions.length`；
/// - 否则原样返回。
///
/// **为什么这个 helper 单独抽**：项目内 4 处汇总函数（[formatJobProgress]
/// / [computeJobProgressRatio] in `job_queue_panel.dart`、
/// [formatRevisionProgress] / [computeJobProgressFraction] in
/// `merge_execution_panel.dart`）各自内联了同一句
/// `job.completedIndex.clamp(0, job.revisions.length)`，只是局部变量名
/// 不同（`total` / `length` / `revisions.length`）。任何一处把
/// `clamp(0, ...)` 误改成 `clamp(1, ...)`、或漏掉 clamp 直接用 raw
/// `completedIndex`，都会让 UI 渲染 `-1/5`、`7/5` 这种越界进度——视觉上
/// 立刻穿帮，但单测层若没锁，回归就会偶发。
///
/// **作用域明确：仅 UI 显示路径——日志路径刻意保留 raw**：
/// 「唯一逻辑源」的承诺只覆盖**面向用户的 UI 渲染路径**（progress bar、
/// `N/M` 进度文案、ratio 计算）。诊断日志路径**刻意不走本 helper**——
/// `merge_execution_state.dart:502` 在 `_appendLog('  进度: ${...}/${...}')`
/// 里直接拼 `job.completedIndex` 与 `job.revisions.length` 是有意的：
/// 日志的 *目的* 是暴露状态，若 `completedIndex` 因持久化损坏 / 上游 bug
/// 跑出 `[0, length]` 区间，UI 已经被 clamp 静默掉了——日志是开发者
/// 看见 `-1/5`、`7/5` 这种异常进度的**唯一窗口**。把日志也 clamp 等于
/// 把诊断信号也吞了。属设计模式 #9（同形不同义）：UI 显示要 clamp
/// 防视觉穿帮，日志要 raw 防诊断盲区。R94 巡检"日志路径 helper-vs-inline 漏迁"
/// 时显式确认了这一例外，并把它写进本 doc，避免将来 R85-R89 风格的
/// 漏迁巡检反复标记此 callsite 为候选漏迁。
///
/// **故意以 `MergeJob` 为入参而非 `(int, int)` 拆分参数**：4 处 callsite
/// 都拿到完整 `MergeJob` 后才算 clamp，拆参数会让 caller 多写一行
/// `helper(job.completedIndex, job.revisions.length)`，阅读时反而要在大脑里
/// 把两个参数和"job 的两个字段"对应起来——直接以 job 为入参，callsite
/// 写成 `clampedCompletedRevisionCount(job)` 就是 4 处通用的"自描述"调用。
///
/// **形态首次出现**：`MergeJob -> int`，与 R79-R83 的 `String? -> bool`
/// 五谓词矩阵、R82 的 `int? -> bool` 双谓词矩阵都不同形——本轮是项目内
/// 第三种 helper 形态，但**不构成新矩阵**——`MergeJob -> int` 形态在项目内
/// 无第二个语义不同的同形函数候选（job 本身的衍生计算只有一个语义维度
/// "完成多少 revision"），矩阵需要 ≥ 2 个 callsite 语境不同的同形函数才
/// 成立。后续若出现 `clampedFailedRevisionCount` / `clampedSkippedCount`
/// 之类的同形 helper，可以补成两谓词矩阵。
///
/// **故意不加 `@visibleForTesting`**：与本文件内其它仅本库调用的 helper
/// 不同，本 helper 跨库被 4 处 callsite 使用（`job_queue_panel.dart` ×2 +
/// `merge_execution_panel.dart` ×2），跨库 `@visibleForTesting` 会触发
/// `invalid_use_of_visible_for_testing_member` analyzer 警告。tests 仍可
/// 通过普通 import 访问。
int clampedCompletedRevisionCount(MergeJob job) =>
    job.completedIndex.clamp(0, job.revisions.length);

/// 渲染任务状态显示段：仅 paused 状态附加进度括号 `(i/n)`，其它状态原样返回 displayName。
///
/// **行为契约**：
/// - paused → `'已暂停 (i/n)'`，半角空格 + 半角括号；
/// - 其它 4 个状态 → `JobStatus.displayName` 原样；
/// - **i 与 n 不做边界守卫**（`i > n` / `i < 0` / `n == 0` 都直接拼字面）：异常进度
///   值正是 paused 任务的潜在 bug 信号（例如 completedIndex 越界），让 `'(5/3)'` /
///   `'(-1/3)'` 显眼出现比静默 clamp 好。
/// - 不复用 [extractWcDisplayName] 的"上游负责规范化"思路：这里是**渲染**而非**提取**，
///   不应改变上游数据，只需忠实展示。
@visibleForTesting
String formatJobStatusWithProgress(
  JobStatus status,
  int completedIndex,
  int total,
) {
  final base = status.displayName;
  if (status != JobStatus.paused) return base;
  return '$base ($completedIndex/$total)';
}

/// 装配 [MergeJob.description] 的完整描述行：`'#$jobId [$status] WC=$wc | 源=$src | $revStr'`。
///
/// **行为契约**：
/// - **结构固定**为"#id [状态] WC=名 | 源=名 | rev 列表"，**4 个 `|` 段** 顺序与字面
///   都是日志生态的核心：运维通过 `' | WC='` / `' | 源='` 做 grep 切片，任何顺序调整
///   都会破坏现有运维脚本，单测显式断言这 4 段在结果里的相对位置；
/// - `wc` / `src` 两个展示名由调用方传入（即 [extractWcDisplayName] / [extractSourceDisplayName]
///   的输出），**不**在本函数内调用——保持本函数纯渲染、零字符串切分；
/// - `revStr` 同样由 [formatRevisionListShort] 提前算好——本函数只负责拼接。
/// - 任意字段为空字符串都直接拼，不做"占位文案"——空 wc 渲染成 `'WC= |'`（等号后空白）
///   作为 bug 信号显眼。
@visibleForTesting
String formatJobDescription({
  required int jobId,
  required String statusText,
  required String wcDisplayName,
  required String sourceDisplayName,
  required String revisionListText,
}) =>
    '#$jobId [$statusText] WC=$wcDisplayName | 源=$sourceDisplayName | $revisionListText';

/// 解析"中断恢复"使用的暂停原因：去首尾空白；trim 后为空 → 用全局默认 [kInterruptedJobPauseReason]。
///
/// **行为契约**：
/// - 入参 `'   '`（仅空白） → 兜底为默认；这与 `String.isEmpty` 不同——空白字符串在
///   UI 上是不可见的，等同于"没填原因"，应该走默认；
/// - 入参非空白 → trim 后返回（**不**保留首尾空白——pauseReason 会被渲染到状态条与
///   日志中，前后空白会让排版错位）；
/// - 入参恰好等于默认值 → trim 后返回该字符串本身（不做 identity 优化）；
/// - 此函数从 [MergeJob.recoverInterrupted] 中抽出，使该 3 行决策可以脱离 `copyWith`
///   单独被测，且未来若新增"原因长度限制"等规则只改一处。
@visibleForTesting
String resolveRecoveryReason(String reason) {
  final trimmed = reason.trim();
  return trimmed.isEmpty ? kInterruptedJobPauseReason : trimmed;
}

/// 判定任务是否需要人工介入（即 [MergeJob.needsIntervention] 的纯函数版）。
///
/// **行为契约**：仅 [JobStatus.paused] 返回 true，其他 4 个状态全返回 false。
/// 与 [JobStatusExtension.isActive]（pending/running/paused 三态）刻意**不重合**：
/// "活跃"是"在队列里有显示"，"需要介入"是"等用户操作"——一个是 UI 列表过滤、
/// 一个是 UI 强提示信号，独立维度独立函数。
@visibleForTesting
bool evaluateNeedsIntervention(JobStatus status) => status == JobStatus.paused;

/// 判定任务是否允许从本地队列删除（即 [MergeJob.canDelete] 的纯函数版）。
///
/// **行为契约**：
/// - `running` → false（正在执行，强删会丢状态）；
/// - `paused` → false（在等用户处理冲突，强删会丢恢复入口）；
/// - `pending` / `done` / `failed` → true（队列首未启动 / 已结束 / 失败兜底，皆可删）。
///
/// **真值表 5 行**与 [JobStatus] 枚举一一对应；测试遍历 `JobStatus.values` 强制覆盖，
/// 任何新增枚举值会在测试侧立刻撞红——防止"加新状态时漏配 canDelete 默认值"
/// （设计模式 #11 防漏配 enum 真值表的延续）。
///
/// **不**接受 `completedIndex` / `pauseReason` 等附加状态：删除决策只看顶层状态码，
/// 业务上"已暂停的任务即使没进度也不能误删"是用户的强需求。
@visibleForTesting
bool evaluateCanDelete(JobStatus status) =>
    status != JobStatus.running && status != JobStatus.paused;

/// 判定失败任务能否"为剩余 revision 重新生成新任务"（即 [MergeJob.canRequeueRemaining]
/// 的纯函数版）。
///
/// **行为契约 — 双维度联合**：
/// - `status == failed` **且** `hasRemainingRevisions == true` → true；
/// - 任一不满足 → false。
///
/// **为什么把 `hasRemainingRevisions` 提为 bool 入参而非 `List<int>`**：本函数纯逻辑，
/// 不应让函数体读 list 的 `.isNotEmpty`——caller 已经从 [MergeJob.remainingRevisions]
/// 拿到了 list（或在测试里直接构造 bool）。**双维度 (status, hasRemaining)** 用 bool×enum
/// 笛卡尔积 (5×2=10 行) 比 enum × list 更易锁定，反向断言也更直接。
///
/// **核心独立性契约**（与 Round 65/66 设计模式 #17 同款）：status 与 hasRemaining
/// 是两条独立维度，单维度切换只能改变结果一半。**成对反向断言**：
/// - 固定 `hasRemaining=true`，对比 status=failed vs done → 仅 failed 为 true；
/// - 固定 `status=failed`，对比 hasRemaining=true vs false → 仅 hasRemaining=true 为 true。
@visibleForTesting
bool evaluateCanRequeueRemaining({
  required JobStatus status,
  required bool hasRemainingRevisions,
}) =>
    status == JobStatus.failed && hasRemainingRevisions;

/// 判定任务在"应用启动 / 队列恢复"时是否应该按"中断任务"恢复（即
/// [MergeJob.shouldRecoverAsInterrupted] 的纯函数版）。
///
/// **行为契约 — 3 段优先级判定**（与原 inline 实现严格等价）：
/// 1. `status == running` → **立刻** true；这种状态在持久化里出现意味着上次 app 异常
///    退出（正常关闭会先把 running 转成 paused 或 done），强制按中断处理；
/// 2. `status != pending`（即 paused / done / failed）→ **立刻** false；这些状态都是
///    上次会话的明确结束态，不需要按中断恢复；
/// 3. `status == pending` → 看是否有"已开始但未完成"信号：`completedIndex > 0` **或**
///    `resumeFromStepId?.isNotEmpty == true`（**注意是 isNotEmpty，不是 != null**——
///    空字符串 `''` 视作"无 resume 点"，与 `null` 等价）。
///
/// **关键边界**（单测显式覆盖）：
/// - `resumeFromStepId == null` → 走 `?? false`，`||` 短路看 completedIndex；
/// - `resumeFromStepId == ''`（空串）→ `''.isNotEmpty == false`，仍看 completedIndex；
/// - `resumeFromStepId == '   '`（仅空格）→ **isNotEmpty == true**（**不做 trim**），
///   视作有 resume 点。这是**故意保留**：上游写入时不应有空白污染；如果出现就让
///   `shouldRecoverAsInterrupted` 走 true 路径暴露问题，比静默忽略更安全。
/// - `resumeFromStepId == 'svn_update'` → isNotEmpty=true，恢复。
///
/// **3 段优先级是核心契约**（设计模式 #15 反向断言锁定 + #17 双维度独立性的扩展）：
/// 测试用反向断言锁定 "running 状态下 completedIndex / resumeFromStepId 完全不影响结果"
/// 与 "非 pending 非 running 状态下 completedIndex / resumeFromStepId 完全不影响结果"
/// 两条独立性。
@visibleForTesting
bool evaluateShouldRecoverAsInterrupted({
  required JobStatus status,
  required int completedIndex,
  required String? resumeFromStepId,
}) {
  if (status == JobStatus.running) {
    return true;
  }
  if (status != JobStatus.pending) {
    return false;
  }
  return completedIndex > 0 || (resumeFromStepId?.isNotEmpty ?? false);
}

@JsonSerializable()
class MergeJob {
  final int jobId;
  final String sourceUrl;
  final String targetWc;

  /// 目标工作副本对应的 SVN URL。
  ///
  /// 新任务创建时从 `svn info <targetWc>` 读取。旧队列文件没有此字段时为 null，
  /// UI 展示和 commit 模板会回退到 [targetWc]，保证向后兼容。
  final String? targetUrl;

  final int maxRetries;
  final List<int> revisions;
  final JobStatus status;
  final String error;

  /// 已完成合并的 revision 索引（用于暂停后继续）
  /// 例如：revisions = [100, 101, 102]，completedIndex = 1 表示 r100 和 r101 已完成
  final int completedIndex;

  /// 暂停原因（冲突、提交失败等）
  final String pauseReason;

  /// 提交信息模板（支持变量：{revision}, {sourceUrl}, {targetUrl}, {message}）
  final String? commitMessageTemplate;

  /// 源 SVN log 的完整原始 message，key 为 revision 字符串。
  ///
  /// 该字段只保存原始 message，不保存列表展示层的单行化文本。旧队列无该字段时默认为空，
  /// 执行层会回退到历史提交格式。
  final Map<String, String> sourceMessagesByRevision;

  /// 提交附加信息（人类自由补充，例如 CRID / 需求编号），不限制格式。
  ///
  /// **行为契约**：
  /// - `null` 或 `trim()` 后为空 → commit message 不追加任何内容；
  /// - 非空 → 在 [commitMessageTemplate] 渲染结果（或默认 `[Merge] r$revision from $sourceUrl`）
  ///   末尾追加 `\n\n$supplement`（两个换行做分段，与多数 SVN 服务端 CR rule 兼容）；
  /// - **不**做任何格式校验：本字段是 SVN 服务端 pre-commit hook（例如 cd.svn.woa.com 的
  ///   `Code-Review-Rule`）所要求的额外信息（如 CRID）的载体，由人类自行补全。
  ///   未来若接 SDK/API 自动获取 CRID，仍只是把指定格式的 CRID 拼到此字段、不动渲染逻辑。
  final String? commitSupplement;

  /// 合并成功后、提交前要执行的本地校验脚本路径。
  ///
  /// 配置值为相对目标工作副本的 `/` 风格路径。该值在任务入队时固化，避免待执行队列受后续设置变更影响。
  ///
  /// 旧队列数据可能为空；执行层会按兼容逻辑跳过校验。
  final String? mergeValidationScriptPath;

  /// 是否使用临时精简工作副本执行合并。
  ///
  /// 开关在任务入队时固化；旧队列数据缺失该字段时默认为 false，保持完整工作副本流程不变。
  final bool useTemporarySparseWorkingCopy;

  /// 临时精简工作副本路径。
  ///
  /// 仅在 [useTemporarySparseWorkingCopy] 为 true 且任务已开始准备后写入。暂停/失败时保留，
  /// 让用户能继续处理冲突现场；任务成功完成后执行层会清理目录并清空该字段。
  final String? temporaryWorkingCopyPath;

  /// 当前暂停 revision 的完整提交信息覆盖值。
  ///
  /// 用于服务端 hook 返回未知 message 规则失败时，让用户直接编辑完整原始 message。
  /// 与 [commitSupplement] 不同，本字段只应对 [commitMessageOverrideRevision] 指向的
  /// 单个 revision 生效，提交成功后由执行状态清除，避免污染后续 revision。
  final String? commitMessageOverride;

  /// [commitMessageOverride] 对应的 revision。
  final int? commitMessageOverrideRevision;

  /// 暂停后继续执行时的起始步骤 ID
  final String? resumeFromStepId;

  const MergeJob({
    required this.jobId,
    required this.sourceUrl,
    required this.targetWc,
    this.targetUrl,
    required this.maxRetries,
    required this.revisions,
    this.status = JobStatus.pending,
    this.error = '',
    this.completedIndex = 0,
    this.pauseReason = '',
    this.commitMessageTemplate,
    this.sourceMessagesByRevision = const {},
    this.commitSupplement,
    this.mergeValidationScriptPath,
    this.useTemporarySparseWorkingCopy = false,
    this.temporaryWorkingCopyPath,
    this.commitMessageOverride,
    this.commitMessageOverrideRevision,
    this.resumeFromStepId,
  });

  factory MergeJob.withConfig({
    required int jobId,
    required SourceConfig sourceConfig,
    required TargetConfig targetConfig,
    required int maxRetries,
    required List<int> revisions,
    JobStatus status = JobStatus.pending,
    String error = '',
    int completedIndex = 0,
    String pauseReason = '',
    String? commitMessageTemplate,
    Map<String, String> sourceMessagesByRevision = const {},
    String? commitSupplement,
    String? mergeValidationScriptPath,
    String? temporaryWorkingCopyPath,
    String? commitMessageOverride,
    int? commitMessageOverrideRevision,
    String? resumeFromStepId,
  }) {
    return MergeJob(
      jobId: jobId,
      sourceUrl: sourceConfig.url,
      targetWc: targetConfig.jobTargetWc,
      targetUrl: targetConfig.jobTargetUrl,
      maxRetries: maxRetries,
      revisions: revisions,
      status: status,
      error: error,
      completedIndex: completedIndex,
      pauseReason: pauseReason,
      commitMessageTemplate: commitMessageTemplate,
      sourceMessagesByRevision: sourceMessagesByRevision,
      commitSupplement: commitSupplement,
      mergeValidationScriptPath: mergeValidationScriptPath,
      useTemporarySparseWorkingCopy: targetConfig.isTemporarySparseWorkingCopy,
      temporaryWorkingCopyPath: temporaryWorkingCopyPath,
      commitMessageOverride: commitMessageOverride,
      commitMessageOverrideRevision: commitMessageOverrideRevision,
      resumeFromStepId: resumeFromStepId,
    );
  }

  /// 从 JSON 创建
  factory MergeJob.fromJson(Map<String, dynamic> json) =>
      _$MergeJobFromJson(json);

  /// 转换为 JSON
  Map<String, dynamic> toJson() => _$MergeJobToJson(this);

  SourceConfig get sourceConfig => SourceConfig(url: sourceUrl);

  TargetConfig get targetConfig {
    final config = TargetConfig.fromLegacy(
      targetWc: targetWc,
      targetUrl: targetUrl,
      useTemporarySparseWorkingCopy: useTemporarySparseWorkingCopy,
    );
    if (config.isFullWorkingCopy && (targetUrl ?? '').trim().isNotEmpty) {
      return config.withResolvedTargetUrl(targetUrl!.trim());
    }
    return config;
  }

  static const Object _unset = Object();

  /// 复制并修改部分字段
  MergeJob copyWith({
    int? jobId,
    String? sourceUrl,
    String? targetWc,
    Object? targetUrl = _unset,
    int? maxRetries,
    List<int>? revisions,
    JobStatus? status,
    String? error,
    int? completedIndex,
    String? pauseReason,
    Object? commitMessageTemplate = _unset,
    Object? sourceMessagesByRevision = _unset,
    Object? commitSupplement = _unset,
    Object? mergeValidationScriptPath = _unset,
    bool? useTemporarySparseWorkingCopy,
    Object? temporaryWorkingCopyPath = _unset,
    Object? commitMessageOverride = _unset,
    Object? commitMessageOverrideRevision = _unset,
    Object? resumeFromStepId = _unset,
  }) {
    return MergeJob(
      jobId: jobId ?? this.jobId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      targetWc: targetWc ?? this.targetWc,
      targetUrl:
          identical(targetUrl, _unset) ? this.targetUrl : targetUrl as String?,
      maxRetries: maxRetries ?? this.maxRetries,
      revisions: revisions ?? this.revisions,
      status: status ?? this.status,
      error: error ?? this.error,
      completedIndex: completedIndex ?? this.completedIndex,
      pauseReason: pauseReason ?? this.pauseReason,
      commitMessageTemplate: identical(commitMessageTemplate, _unset)
          ? this.commitMessageTemplate
          : commitMessageTemplate as String?,
      sourceMessagesByRevision: identical(sourceMessagesByRevision, _unset)
          ? this.sourceMessagesByRevision
          : sourceMessagesByRevision as Map<String, String>,
      commitSupplement: identical(commitSupplement, _unset)
          ? this.commitSupplement
          : commitSupplement as String?,
      mergeValidationScriptPath: identical(mergeValidationScriptPath, _unset)
          ? this.mergeValidationScriptPath
          : mergeValidationScriptPath as String?,
      useTemporarySparseWorkingCopy:
          useTemporarySparseWorkingCopy ?? this.useTemporarySparseWorkingCopy,
      temporaryWorkingCopyPath: identical(temporaryWorkingCopyPath, _unset)
          ? this.temporaryWorkingCopyPath
          : temporaryWorkingCopyPath as String?,
      commitMessageOverride: identical(commitMessageOverride, _unset)
          ? this.commitMessageOverride
          : commitMessageOverride as String?,
      commitMessageOverrideRevision:
          identical(commitMessageOverrideRevision, _unset)
              ? this.commitMessageOverrideRevision
              : commitMessageOverrideRevision as int?,
      resumeFromStepId: identical(resumeFromStepId, _unset)
          ? this.resumeFromStepId
          : resumeFromStepId as String?,
    );
  }

  /// 获取当前正在处理的 revision（如果有）
  int? get currentRevision {
    if (completedIndex < revisions.length) {
      return revisions[completedIndex];
    }
    return null;
  }

  /// 获取剩余待合并的 revision 列表
  List<int> get remainingRevisions {
    if (completedIndex >= revisions.length) {
      return [];
    }
    return revisions.sublist(completedIndex);
  }

  /// 获取已完成的 revision 列表
  List<int> get completedRevisions {
    if (completedIndex <= 0) {
      return [];
    }
    return revisions.sublist(0, completedIndex);
  }

  /// 是否需要人工介入
  bool get needsIntervention => evaluateNeedsIntervention(status);

  /// 是否允许删除本地队列记录
  bool get canDelete => evaluateCanDelete(status);

  /// 是否允许为失败任务重新生成剩余 revision 的新任务
  bool get canRequeueRemaining => evaluateCanRequeueRemaining(
        status: status,
        hasRemainingRevisions: remainingRevisions.isNotEmpty,
      );

  /// 是否需要按"中断任务"恢复
  bool get shouldRecoverAsInterrupted => evaluateShouldRecoverAsInterrupted(
        status: status,
        completedIndex: completedIndex,
        resumeFromStepId: resumeFromStepId,
      );

  /// 获取简短描述
  String get description {
    return formatJobDescription(
      jobId: jobId,
      statusText: formatJobStatusWithProgress(
        status,
        completedIndex,
        revisions.length,
      ),
      wcDisplayName: extractSourceDisplayName(targetUrl ?? targetWc),
      sourceDisplayName: extractSourceDisplayName(sourceUrl),
      revisionListText: formatRevisionListShort(revisions),
    );
  }

  MergeJob recoverInterrupted({
    String reason = kInterruptedJobPauseReason,
  }) {
    final recoveryReason = resolveRecoveryReason(reason);

    return copyWith(
      status: JobStatus.paused,
      error: recoveryReason,
      pauseReason: recoveryReason,
      resumeFromStepId: null,
    );
  }

  @override
  String toString() => description;
}
