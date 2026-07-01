/// 失败/暂停摘要数据结构与聚合函数。
///
/// 目的：把"任务为什么停下"的所有可读取信号聚合成一个 widget 友好的纯数据
/// 对象，让 UI 渲染层不必再翻 [MergeJob] / [StepSnapshot] / [globalContext]
/// 三个来源拼字符串。这样：
///
/// - 暂停面板可以显示「停在哪一步 / 失败错误 / out-of-date 重试次数 / 当前
///   revision」四类信号，不需要在 widget 里写 if/else。
/// - 单测能直接断言"在不同输入组合下摘要应是什么"，不需要构造 widget tree。
/// - 未来加新信号（比如 conflict 文件列表、network/auth 失败子类）只需在
///   [PausedJobSummary] 加字段 + 在 [summarizePausedJob] 里聚合，UI 自动跟随。
library;

import '../models/merge_job.dart';
import 'step_snapshot.dart';
import 'svn_failure_kind.dart';

/// 暂停摘要——纯数据对象，不持有任何渲染状态。
///
/// 字段全部 null-safe；UI 渲染时按 `field == null` 决定是否显示对应一行。
class PausedJobSummary {
  /// 任务 id（用于面板标题，如 `任务 #1 暂停`）。
  final int jobId;

  /// 暂停原因（一般取自 `job.pauseReason` 或 fallback `'等待人工处理'`）；
  /// 永远非空字符串——空入参会被替换为占位文案。
  final String pauseReason;

  /// 当前卡在哪个 revision；任务全部完成则为 null。
  final int? currentRevision;

  /// 已完成多少条 / 总共多少条；用于 `已完成 a/b` 渲染。
  final int completedCount;
  final int totalCount;

  /// 失败步骤的展示名（"准备" / "更新" / "合并" / "提交"），无失败 snapshot
  /// 则为 null。
  final String? failedStepName;

  /// 失败步骤抛出的错误正文（已 trim）；无错误时 null。
  final String? failedStepError;

  /// 当前 commit out-of-date 重试次数 / 上限——只有任务真的开过重试才显示，
  /// 否则两者都为 null。
  final int? commitRetryCount;
  final int? commitMaxRetries;

  /// 失败原因分类（按错误正文/`pauseReason` 推断）。无错误信息时为
  /// [SvnFailureKind.unknown]。
  final SvnFailureKind failureKind;

  const PausedJobSummary({
    required this.jobId,
    required this.pauseReason,
    required this.currentRevision,
    required this.completedCount,
    required this.totalCount,
    required this.failedStepName,
    required this.failedStepError,
    required this.commitRetryCount,
    required this.commitMaxRetries,
    this.failureKind = SvnFailureKind.unknown,
  });

  /// 是否需要渲染 retry 行：两字段都非 null **且** count > 0（避免 `0/2` 噪音）。
  bool get hasCommitRetryInfo =>
      commitRetryCount != null &&
      commitMaxRetries != null &&
      commitRetryCount! > 0;

  /// 是否需要渲染失败步骤行（任意字段非空即显示）。
  bool get hasFailedStepInfo =>
      (failedStepName != null && failedStepName!.isNotEmpty) ||
      (failedStepError != null && failedStepError!.isNotEmpty);
}

/// 步骤 ID → 中文展示名映射；未知 id 直接返回 id 本身（不抛、不 fallback 空）。
///
/// 这里与 `kMergeExecutionSteps` 的 `title` 字段是平行的：故意**不**反查
/// `kMergeExecutionSteps`，因为：
/// 1. 保留 helper 为纯函数（不引入 provider 层依赖）；
/// 2. 步骤名只有 4 个，单测里用字面量断言更直观；
/// 3. 未来若 step 改名，单测会直接 fail 提示同步。
String resolveStepDisplayName(String stepId) {
  switch (stepId) {
    case 'prepare':
      return '准备';
    case 'update':
      return '更新';
    case 'merge':
      return '合并';
    case 'commit':
      return '提交';
    default:
      return stepId;
  }
}

/// 把 `Map<String, StepSnapshot>` 中第一个 `status == failed` 的 snapshot 拿出来。
///
/// 顺序按 4 个固定步骤顺序找：prepare → update → merge → commit。这样保证：
/// - 任意一步 fail 后，该步就是当前"失败步骤"；
/// - 多步同时 fail（理论上不可能，但 snapshot map 会保留所有 step 状态）时，
///   用最早的 fail step 当主因，与执行顺序一致。
StepSnapshot? findFailedSnapshot(Map<String, StepSnapshot> snapshots) {
  const order = ['prepare', 'update', 'merge', 'commit'];
  for (final id in order) {
    final s = snapshots[id];
    if (s != null && s.status == StepExecutionStatus.failed) {
      return s;
    }
  }
  return null;
}

/// 摘要聚合——这是面板渲染的唯一数据入口。
///
/// 行为契约：
/// - `pauseReason` 入参为 null/空白 → 用 `'等待人工处理'` 占位（与 provider
///   层 fallback 文案一致）。
/// - `completedCount` 经 `clamp(0, totalCount)` 防止 UI 上看到 `-1/3` /
///   `5/3` 这种越界值。
/// - 失败步骤名优先取 `snapshot.stepName`，缺失则用 `resolveStepDisplayName`
///   解析 `stepId`。
/// - `commitRetryCount` / `commitMaxRetries` 从 commit snapshot 的
///   `output.data` 中取——只有 commit 步真的失败过 retry 时这两个 key 才存
///   在；任何一个缺失则两值都为 null（hasCommitRetryInfo 自然为 false）。
PausedJobSummary summarizePausedJob({
  required MergeJob job,
  required Map<String, StepSnapshot> snapshots,
}) {
  final reason =
      job.pauseReason.trim().isEmpty ? '等待人工处理' : job.pauseReason.trim();
  final total = job.revisions.length;
  final completed = job.completedIndex.clamp(0, total);

  final failed = findFailedSnapshot(snapshots);
  final stepName = failed == null
      ? null
      : (failed.stepName?.isNotEmpty == true
          ? failed.stepName
          : resolveStepDisplayName(failed.stepId));
  final stepError = failed?.error?.trim();

  int? retryCount;
  int? maxRetries;
  final commitSnap = snapshots['commit'];
  if (commitSnap != null && commitSnap.status == StepExecutionStatus.failed) {
    final data = commitSnap.output?.data;
    if (data != null) {
      final rc = data['retryCount'];
      final mr = data['maxRetries'];
      if (rc is int && mr is int) {
        retryCount = rc;
        maxRetries = mr;
      }
    }
  }

  // 用 clamp 后的 completed 取当前 revision，防止 completedIndex 越界时
  // 触发 `revisions[completedIndex]` 抛 RangeError。
  // - completed == total → 已全部完成，没有"当前 revision"，返回 null；
  // - 其它情况返回 revisions[completed]（与 job.currentRevision 在合法
  //   completedIndex 下的语义一致）。
  final int? currentRevision =
      (completed >= 0 && completed < total) ? job.revisions[completed] : null;

  return PausedJobSummary(
    jobId: job.jobId,
    pauseReason: reason,
    currentRevision: currentRevision,
    completedCount: completed,
    totalCount: total,
    failedStepName: stepName,
    failedStepError: (stepError == null || stepError.isEmpty) ? null : stepError,
    commitRetryCount: retryCount,
    commitMaxRetries: maxRetries,
    failureKind: classifySvnFailure(
      // 优先用 failed snapshot 的 error；没有 snapshot 时用 pauseReason
      // （例如中断恢复场景，没有具体步骤失败但任务是 paused 状态）。
      stepError ?? job.pauseReason,
    ),
  );
}
