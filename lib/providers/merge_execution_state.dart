/// 标准合并执行状态管理
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../models/merge_config.dart';
import '../models/merge_job.dart';
import '../execution/executor_status.dart';
import '../execution/step_snapshot.dart';
import '../execution/step_output.dart';
import '../services/logger_service.dart';
import '../services/mergeinfo_cache_service.dart';
import '../services/storage_service.dart';
import '../services/svn_service.dart';
import '../services/svn_xml_parser.dart';
import '../services/working_copy_manager.dart';
import '../utils/process_output_decoder.dart';

const String kPrepareStepId = 'prepare';
const String kUpdateStepId = 'update';
const String kMergeStepId = 'merge';
const String kValidateStepId = 'validate';
const String kCommitStepId = 'commit';

const List<MergeExecutionStepDefinition> kMergeExecutionSteps = [
  MergeExecutionStepDefinition(
    id: kPrepareStepId,
    title: '准备',
    description: '还原并清理工作副本，确保从干净状态开始。',
  ),
  MergeExecutionStepDefinition(
    id: kUpdateStepId,
    title: '更新',
    description: '将工作副本更新到最新版本。',
  ),
  MergeExecutionStepDefinition(
    id: kMergeStepId,
    title: '合并',
    description: '把选中的 revision 合并到当前工作副本。',
  ),
  MergeExecutionStepDefinition(
    id: kValidateStepId,
    title: '校验',
    description: '在提交前运行本地脚本验证合并结果。',
  ),
  MergeExecutionStepDefinition(
    id: kCommitStepId,
    title: '提交',
    description: '提交本次合并结果，必要时处理 out-of-date 重试。',
  ),
];

class MergeExecutionStepDefinition {
  final String id;
  final String title;
  final String description;

  const MergeExecutionStepDefinition({
    required this.id,
    required this.title,
    required this.description,
  });
}

enum QueueMutationStatus {
  applied,
  blocked,
  notFound,
}

class QueueMutationResult {
  final QueueMutationStatus status;
  final int affectedCount;
  final int? jobId;

  const QueueMutationResult._({
    required this.status,
    this.affectedCount = 0,
    this.jobId,
  });

  const QueueMutationResult.applied({
    int affectedCount = 1,
    int? jobId,
  }) : this._(
          status: QueueMutationStatus.applied,
          affectedCount: affectedCount,
          jobId: jobId,
        );

  const QueueMutationResult.blocked({
    int affectedCount = 0,
    int? jobId,
  }) : this._(
          status: QueueMutationStatus.blocked,
          affectedCount: affectedCount,
          jobId: jobId,
        );

  const QueueMutationResult.notFound({int? jobId})
      : this._(
          status: QueueMutationStatus.notFound,
          jobId: jobId,
        );

  bool get isApplied => status == QueueMutationStatus.applied;
}

@visibleForTesting
MergeJob buildRunningJobState(
  MergeJob job, {
  int? completedIndex,
}) {
  return job.copyWith(
    status: JobStatus.running,
    completedIndex: completedIndex,
    pauseReason: '',
    error: '',
    resumeFromStepId: null,
  );
}

@visibleForTesting
MergeJob? buildRemainingJob(
  MergeJob job, {
  required int newJobId,
}) {
  if (!job.canRequeueRemaining) {
    return null;
  }

  return MergeJob.withConfig(
    jobId: newJobId,
    sourceConfig: job.sourceConfig,
    targetConfig: job.targetConfig,
    maxRetries: job.maxRetries,
    revisions: job.remainingRevisions,
    commitMessageTemplate: job.commitMessageTemplate,
    commitSupplement: job.commitSupplement,
    mergeValidationScriptPath: job.mergeValidationScriptPath,
    commitMessageOverride: job.commitMessageOverride,
    commitMessageOverrideRevision: job.commitMessageOverrideRevision,
  );
}

@visibleForTesting
QueueMutationResult resolveDeleteJobResult(List<MergeJob> jobs, int jobId) {
  for (final job in jobs) {
    if (job.jobId != jobId) {
      continue;
    }
    if (!job.canDelete) {
      return QueueMutationResult.blocked(jobId: jobId);
    }
    return QueueMutationResult.applied(jobId: jobId);
  }
  return QueueMutationResult.notFound(jobId: jobId);
}

@visibleForTesting
QueueMutationResult resolveEnqueueRemainingJobResult(
  List<MergeJob> jobs,
  int jobId, {
  required int nextJobId,
}) {
  for (final job in jobs) {
    if (job.jobId != jobId) {
      continue;
    }

    final newJob = buildRemainingJob(job, newJobId: nextJobId);
    if (newJob == null) {
      return QueueMutationResult.blocked(jobId: jobId);
    }

    return QueueMutationResult.applied(jobId: newJob.jobId);
  }

  return QueueMutationResult.notFound(jobId: jobId);
}

/// 把 [jobs] 中的 pending 子列表按 [oldPendingIndex] → [newPendingIndex] 重排。
///
/// **契约**：
/// - 索引语义为 **pending 子列表内位置**（不是 `_jobs` 全局位置，也不是 queueJobs
///   位置）。caller 只需把"用户拖动的可视卡片"映射到 pending 子列表索引即可，
///   无需关心 `_jobs` 中 running/paused 的混排细节。
/// - 沿用 [ReorderableListView] 的 onReorder 约定：当 `newPendingIndex >
///   oldPendingIndex` 时，`newPendingIndex` 是"删除被拖动项后"的目标位置 → 内部
///   减 1 还原成"想插入到第 X 个之前"的语义。
/// - **只动 pending 子列表的内部顺序**——running / paused / done / failed 任务
///   在 `_jobs` 中的绝对索引保持不变；pending 任务两两交换的也只是它们之间相对
///   位置。
/// - 边界保护（任一不满足返回原 list 不变）：
///   * `pendingIdxs.isEmpty`（队列里没 pending 可重排）；
///   * `oldPendingIndex` 越界；
///   * 调整后的 `adjusted` 越界（即拖到自己当前位置或越过末位）；
///   * `adjusted == oldPendingIndex`（no-op）。
/// - 不修改入参；返回新分配的 List。
///
/// **为什么取 pending-only 索引而非 queueJobs / _jobs 索引**：
/// - queueJobs 索引：UI 渲染上 pending 块和 running/paused 块可能并存，
///   可视索引语义混乱；
/// - _jobs 索引：还有 done/failed 历史段，距离用户视觉太远；
/// - pending 子列表索引：与"待执行任务列表"语义直接对齐，单测最易写。
@visibleForTesting
List<MergeJob> reorderPendingJobsList(
  List<MergeJob> jobs,
  int oldPendingIndex,
  int newPendingIndex,
) {
  final pendingIdxs = <int>[];
  for (var i = 0; i < jobs.length; i++) {
    if (jobs[i].status == JobStatus.pending) pendingIdxs.add(i);
  }
  if (pendingIdxs.isEmpty) return jobs;
  if (oldPendingIndex < 0 || oldPendingIndex >= pendingIdxs.length) return jobs;

  var adjusted = newPendingIndex;
  if (newPendingIndex > oldPendingIndex) adjusted -= 1;
  if (adjusted < 0 || adjusted >= pendingIdxs.length) return jobs;
  if (adjusted == oldPendingIndex) return jobs;

  // 在 pending 子列表内 reorder
  final pendingJobs = pendingIdxs.map((i) => jobs[i]).toList();
  final moved = pendingJobs.removeAt(oldPendingIndex);
  pendingJobs.insert(adjusted, moved);

  // 把重排后的 pending 子列表写回原绝对索引
  final result = List<MergeJob>.from(jobs);
  for (var k = 0; k < pendingIdxs.length; k++) {
    result[pendingIdxs[k]] = pendingJobs[k];
  }
  return result;
}

@visibleForTesting
QueueMutationResult resolveClearPendingJobsResult(List<MergeJob> jobs) {
  final count = jobs.where((job) => job.status == JobStatus.pending).length;
  if (count == 0) {
    return const QueueMutationResult.blocked(affectedCount: 0);
  }
  return QueueMutationResult.applied(affectedCount: count);
}

@visibleForTesting
QueueMutationResult resolveClearFinishedJobsResult(List<MergeJob> jobs) {
  final count = jobs.where((job) => job.status.isFinished).length;
  if (count == 0) {
    return const QueueMutationResult.blocked(affectedCount: 0);
  }
  return QueueMutationResult.applied(affectedCount: count);
}

@visibleForTesting
enum CommitOutcomeKind {
  /// 错误不是 out-of-date：直接按一般失败处理。
  otherFailure,

  /// 错误是 out-of-date 且仍在 maxRetries 配额内：返回 update 重试。
  retryFromUpdate,

  /// 错误是 out-of-date 但已耗尽 maxRetries 配额：按一般失败处理。
  exhaustedRetries,
}

@visibleForTesting
class CommitOutcome {
  final CommitOutcomeKind kind;

  /// 写回 commitRetryCount 用：retry 时为新计数；exhaustedRetries 时为耗尽前最后一次的计数。
  final int nextRetryCount;

  const CommitOutcome._(this.kind, this.nextRetryCount);
}

@visibleForTesting
bool isOutOfDateMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('out-of-date') || lower.contains('out of date');
}

/// 根据 commit 错误信息和当前重试计数，决定 commit 步骤后续走向。
///
/// - 非 out-of-date 错误 → otherFailure，不计入重试。
/// - out-of-date 且 previousRetryCount + 1 <= maxRetries → retryFromUpdate，nextRetryCount = previousRetryCount + 1。
/// - out-of-date 且 previousRetryCount + 1 > maxRetries → exhaustedRetries，nextRetryCount = previousRetryCount + 1。
///   maxRetries=0 时第一次 out-of-date 即耗尽。
@visibleForTesting
CommitOutcome evaluateCommitOutcome({
  required String errorMessage,
  required int previousRetryCount,
  required int maxRetries,
}) {
  if (!isOutOfDateMessage(errorMessage)) {
    return const CommitOutcome._(CommitOutcomeKind.otherFailure, 0);
  }

  final attempt = previousRetryCount + 1;
  if (attempt > maxRetries) {
    return CommitOutcome._(CommitOutcomeKind.exhaustedRetries, attempt);
  }
  return CommitOutcome._(CommitOutcomeKind.retryFromUpdate, attempt);
}

@visibleForTesting
bool isMergeConflictMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('conflict') ||
      lower.contains('冲突') ||
      lower.contains('tree conflict');
}

/// 从 commit 步的快照里抽取「上一次执行已用掉的 out-of-date 重试次数」。
///
/// `_runCommitStep` 在 paused 路径（exhaustedRetries）写入 snapshot 的
/// `output.data['retryCount']` 是 `outcome.nextRetryCount - 1`，恰好等于
/// 「触发耗尽时已经发生过的失败 commit 次数」，与 [PausedJobSummary] 的
/// `commitRetryCount` 是同一维度（已用配额数）。
///
/// Resume 时把它当成新一轮的 `previousRetryCount`，下一次 attempt 自然接续
/// 为 N+1，不会回退到 0。这是 [updateJobMaxRetries] doc 中「保留计数让用户
/// 清楚知道还剩多少次配额」契约的真正实现锚点。
///
/// 任意层缺失（snapshot 为 null / 非 failed / data 无 retryCount / 类型不
/// 对 / 负数）都退回 0；这样首次执行、非 commit 暂停、旧版 queue.json 都
/// 不会把 retryCount 倒过来污染。
@visibleForTesting
int extractPreviousRetryCountFromCommitSnapshot(StepSnapshot? commitSnap) {
  if (commitSnap == null || commitSnap.status != StepExecutionStatus.failed) {
    return 0;
  }
  final data = commitSnap.output?.data;
  if (data == null) return 0;
  final rc = data['retryCount'];
  return rc is int && rc >= 0 ? rc : 0;
}

@visibleForTesting
enum StepFailureAction {
  /// 把任务挂起，等待人工处理。
  pause,

  /// 回到 update 步骤重试（commit 抛错且此前已经走过 out-of-date 重试路径）。
  retryFromUpdate,
}

/// 当某一步在执行过程中抛异常时，决定 `_runRevision` 接下来怎么走。
///
/// - merge 步：冲突或其它错误统一暂停（区分仅用于将来想做"非冲突自动重试"时再扩展）。
/// - commit 步：如果之前曾因 out-of-date 切到 update（updateRequired=true），任何错误都回到 update 重试；
///   否则直接暂停。
/// - prepare/update 或未知步骤：直接暂停。
@visibleForTesting
StepFailureAction evaluateStepFailure({
  required String stepId,
  required String errorMessage,
  required bool updateRequired,
}) {
  if (stepId == kCommitStepId && updateRequired) {
    return StepFailureAction.retryFromUpdate;
  }
  return StepFailureAction.pause;
}

/// 把任意字符串规范成已知步骤 ID。
///
/// 返回 null 表示传入为空、未知步骤或不在已注册的执行步骤里——调用方通常会
/// 回落到 `kPrepareStepId`。
@visibleForTesting
String? normalizeStepId(String? stepId) {
  if (stepId == null || stepId.isEmpty) {
    return null;
  }
  for (final step in kMergeExecutionSteps) {
    if (step.id == stepId) {
      return step.id;
    }
  }
  return null;
}

/// 决定暂停时记录的 `resumeFromStepId`。
///
/// - 没有失败 snapshot → 回到 prepare 重来。
/// - prepare/update/merge 失败 → 从该步骤恢复。
/// - commit 失败：如果错误是 out-of-date，回到 update（等同 commit-retry 路径）；
///   否则停在 commit，等人工处理后从 commit 继续。
/// - 其它未知步骤 → 回到 prepare 重来。
@visibleForTesting
String resolveResumeStepId(StepSnapshot? failedSnapshot) {
  if (failedSnapshot == null) {
    return kPrepareStepId;
  }

  switch (failedSnapshot.stepId) {
    case kPrepareStepId:
      return kPrepareStepId;
    case kUpdateStepId:
      return kUpdateStepId;
    case kMergeStepId:
      return kMergeStepId;
    case kValidateStepId:
      return kValidateStepId;
    case kCommitStepId:
      if (isOutOfDateMessage(failedSnapshot.error ?? '')) {
        return kUpdateStepId;
      }
      return kCommitStepId;
    default:
      return kPrepareStepId;
  }
}

/// 根据模板生成 commit 信息。
///
/// 模板支持 `{revision}` / `$revision` / `{sourceUrl}` / `$sourceUrl` /
/// `{targetUrl}` / `$targetUrl`，会按字面替换。模板为 null 或空串时返回默认格式
/// `[Merge] r<rev> from <sourceUrl>`。
///
/// **附加信息（[MergeJob.commitSupplement]）拼接规则**：
/// - `null` 或 `trim()` 后为空 → 不追加；
/// - 否则在模板渲染结果末尾追加 `\n\n$supplement`（trim 后的值）。
///
/// 设计上 supplement 与 template 完全正交：template 决定**格式骨架**（运维/规范），
/// supplement 承载**人类按批输入的可变信息**（CRID / 需求编号），二者乘法组合。
String buildCommitMessage(MergeJob job, int revision) {
  final override = job.commitMessageOverride;
  if (override != null &&
      job.commitMessageOverrideRevision == revision &&
      override.trim().isNotEmpty) {
    return override;
  }

  final template = job.commitMessageTemplate;
  final base = template != null && template.isNotEmpty
      ? template
          .replaceAll('{revision}', revision.toString())
          .replaceAll(r'$revision', revision.toString())
          .replaceAll('{sourceUrl}', job.sourceUrl)
          .replaceAll(r'$sourceUrl', job.sourceUrl)
          .replaceAll('{targetUrl}', job.targetUrl ?? job.targetWc)
          .replaceAll(r'$targetUrl', job.targetUrl ?? job.targetWc)
      : '[Merge] r$revision from ${job.sourceUrl}';

  final supplement = job.commitSupplement?.trim();
  if (supplement == null || supplement.isEmpty) {
    return base;
  }
  return '$base\n\n$supplement';
}

@visibleForTesting
bool hasExplicitMergeValidationErrorOutput({
  required String stdout,
  required String stderr,
}) {
  if (stderr.trim().isNotEmpty) {
    return true;
  }

  final output = stdout.trim();
  if (output.isEmpty) {
    return false;
  }

  final errorPattern = RegExp(
    r'(^|\s|\[)(error|fatal)(\]|\s|:)',
    caseSensitive: false,
    multiLine: true,
  );
  return errorPattern.hasMatch(output) ||
      output.contains('错误') ||
      output.contains('失败');
}

@visibleForTesting
bool shouldSkipFullWorkingCopyValidation(MergeJob job) =>
    job.useTemporarySparseWorkingCopy;

@visibleForTesting
String describeSkippedFullWorkingCopyValidation(String validationName) {
  return '临时精简工作副本模式下跳过$validationName：该校验依赖完整目标工作副本，'
      '本次成功仍以 SVN 命令结果和仓库 mergeinfo 确认为准';
}

String _truncateValidationLog(String text, {int maxLen = 200}) {
  if (text.length <= maxLen) return text;
  return '${text.substring(0, maxLen)}...';
}

@visibleForTesting
class MergeValidationScriptCommand {
  final String executable;
  final List<String> args;
  final String relativePath;
  final String resolvedPath;

  const MergeValidationScriptCommand({
    required this.executable,
    required this.args,
    required this.relativePath,
    required this.resolvedPath,
  });
}

String _joinTargetWcAndRelativeScriptPath(
  String targetWc,
  String relativePath, {
  String? pathSeparator,
}) {
  final separator = pathSeparator ?? Platform.pathSeparator;
  final nativeRelativePath =
      relativePath.split('/').where((part) => part.isNotEmpty).join(separator);
  if (targetWc.endsWith('/') || targetWc.endsWith(r'\')) {
    return '$targetWc$nativeRelativePath';
  }
  return '$targetWc$separator$nativeRelativePath';
}

@visibleForTesting
MergeValidationScriptCommand resolveMergeValidationScriptCommand({
  required String targetWc,
  required String? scriptPath,
  String? operatingSystem,
  String? pathSeparator,
}) {
  final normalizedPath = normalizeMergeValidationScriptPath(scriptPath);
  if (!isRelativeMergeValidationScriptPath(normalizedPath)) {
    throw ArgumentError.value(
      scriptPath,
      'scriptPath',
      '合并校验脚本必须是相对目标工作副本的 / 风格路径',
    );
  }

  final resolvedPath = _joinTargetWcAndRelativeScriptPath(
    targetWc,
    normalizedPath,
    pathSeparator: pathSeparator,
  );
  final os = operatingSystem ?? Platform.operatingSystem;
  final lowerPath = normalizedPath.toLowerCase();
  if (lowerPath.endsWith('.py')) {
    return MergeValidationScriptCommand(
      executable: os == 'windows' ? 'python' : 'python3',
      args: [resolvedPath],
      relativePath: normalizedPath,
      resolvedPath: resolvedPath,
    );
  }
  if (lowerPath.endsWith('.sh')) {
    return MergeValidationScriptCommand(
      executable: os == 'windows' ? 'bash' : 'sh',
      args: [resolvedPath],
      relativePath: normalizedPath,
      resolvedPath: resolvedPath,
    );
  }
  if (lowerPath.endsWith('.bat')) {
    if (os != 'windows') {
      throw UnsupportedError('bat 校验脚本只能在 Windows 上执行');
    }
    return MergeValidationScriptCommand(
      executable: 'cmd',
      args: ['/c', resolvedPath],
      relativePath: normalizedPath,
      resolvedPath: resolvedPath,
    );
  }

  throw UnsupportedError('不支持的合并校验脚本后缀，仅支持 .sh / .bat / .py: $normalizedPath');
}

class SparseWorkingCopyUnsupportedException implements Exception {
  final String message;

  const SparseWorkingCopyUnsupportedException(this.message);

  @override
  String toString() => message;
}

class TemporarySparseCheckoutPlan {
  final List<String> directories;
  final List<String> files;

  const TemporarySparseCheckoutPlan({
    required this.directories,
    required this.files,
  });
}

String trimSvnPathSlashes(String path) =>
    path.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');

String? svnUrlPathRelativeToRepoRoot({
  required String url,
  required String repoRootUrl,
}) {
  final urlPath = trimSvnPathSlashes(Uri.parse(url).path);
  final rootPath = trimSvnPathSlashes(Uri.parse(repoRootUrl).path);
  if (rootPath.isEmpty) {
    return urlPath;
  }
  if (urlPath == rootPath) {
    return '';
  }
  final prefix = '$rootPath/';
  if (!urlPath.startsWith(prefix)) {
    return null;
  }
  return urlPath.substring(prefix.length);
}

List<String> parentDirectoriesForRelativePath(String relativePath) {
  final parts = trimSvnPathSlashes(relativePath)
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
  final dirs = <String>[];
  for (var i = 1; i < parts.length; i++) {
    dirs.add(parts.take(i).join('/'));
  }
  return dirs;
}

String? changedPathRelativeToSourceBranch({
  required String changedPath,
  required String sourceBranchPath,
}) {
  final changed = trimSvnPathSlashes(changedPath);
  final source = trimSvnPathSlashes(sourceBranchPath);
  if (changed == source) {
    return '';
  }
  final prefix = source.isEmpty ? '' : '$source/';
  if (prefix.isNotEmpty && !changed.startsWith(prefix)) {
    return null;
  }
  return prefix.isEmpty ? changed : changed.substring(prefix.length);
}

TemporarySparseCheckoutPlan buildTemporarySparseCheckoutPlan({
  required List<SvnLogChangedPath> changedPaths,
  required String sourceBranchPath,
  String? validationScriptPath,
}) {
  if (changedPaths.isEmpty) {
    throw const SparseWorkingCopyUnsupportedException(
      '无法从 SVN 日志计算本次合并涉及的路径，请使用完整工作副本',
    );
  }

  final directories = <String>{};
  final files = <String>{};

  void addFile(String relativePath) {
    final normalized = trimSvnPathSlashes(relativePath);
    if (normalized.isEmpty) {
      throw const SparseWorkingCopyUnsupportedException(
        '变更路径指向分支根目录，请使用完整工作副本',
      );
    }
    directories.addAll(parentDirectoriesForRelativePath(normalized));
    files.add(normalized);
  }

  void addParentOnly(String relativePath) {
    final normalized = trimSvnPathSlashes(relativePath);
    if (normalized.isEmpty) {
      throw const SparseWorkingCopyUnsupportedException(
        '变更路径指向分支根目录，请使用完整工作副本',
      );
    }
    directories.addAll(parentDirectoriesForRelativePath(normalized));
  }

  for (final changedPath in changedPaths) {
    final action = changedPath.action.toUpperCase();
    if (action != 'A' && action != 'M') {
      throw SparseWorkingCopyUnsupportedException(
        '变更包含 $action 操作（删除/替换/树冲突风险），请使用完整工作副本',
      );
    }
    if (changedPath.copyFromPath != null &&
        changedPath.copyFromPath!.trim().isNotEmpty) {
      throw const SparseWorkingCopyUnsupportedException(
        '变更包含复制/重命名来源，临时精简工作副本无法可靠处理，请使用完整工作副本',
      );
    }
    if (changedPath.kind != null && changedPath.kind != 'file') {
      throw const SparseWorkingCopyUnsupportedException(
        '变更包含目录级属性或目录结构操作，请使用完整工作副本',
      );
    }

    final relativePath = changedPathRelativeToSourceBranch(
      changedPath: changedPath.path,
      sourceBranchPath: sourceBranchPath,
    );
    if (relativePath == null) {
      throw SparseWorkingCopyUnsupportedException(
        '变更路径 ${changedPath.path} 不在源分支范围内，请使用完整工作副本',
      );
    }

    if (action == 'M') {
      addFile(relativePath);
    } else {
      addParentOnly(relativePath);
    }
  }

  final validationPath = validationScriptPath?.trim();
  if (validationPath != null && validationPath.isNotEmpty) {
    addFile(validationPath);
  }

  int depth(String path) => path.split('/').where((p) => p.isNotEmpty).length;
  final sortedDirs = directories.toList()
    ..sort((a, b) {
      final byDepth = depth(a).compareTo(depth(b));
      return byDepth != 0 ? byDepth : a.compareTo(b);
    });
  final sortedFiles = files.toList()..sort();

  return TemporarySparseCheckoutPlan(
    directories: sortedDirs,
    files: sortedFiles,
  );
}

@visibleForTesting
const int kExecutionLogMaxLines = 600;

@visibleForTesting
String appendExecutionLog(
  String currentLog,
  String message, {
  int maxLines = kExecutionLogMaxLines,
}) {
  final limit = maxLines <= 0 ? 1 : maxLines;
  final existingLines = currentLog.isEmpty
      ? <String>[]
      : currentLog.split('\n').where((line) => line.isNotEmpty).toList();
  final appendedLines =
      message.split('\n').where((line) => line.isNotEmpty).toList();

  if (appendedLines.isEmpty) {
    return existingLines.isEmpty ? '' : '${existingLines.join('\n')}\n';
  }

  existingLines.addAll(appendedLines);

  final startIndex =
      existingLines.length > limit ? existingLines.length - limit : 0;
  final visibleLines = existingLines.sublist(startIndex);
  return '${visibleLines.join('\n')}\n';
}

/// 计算执行日志的"显示行数"（与 `MergeExecutionState.logLineCount` 一致的口径）。
///
/// **契约**：
/// - 空字符串 → `0`（不是 1，避免空 log 显示 "1 行"）。
/// - 否则按 `\n` 切分，**过滤掉空行**再计数（与 `appendExecutionLog` 写入时的
///   "isNotEmpty" 过滤口径一致；末尾换行符产生的空字符串不算一行）。
/// - 不修剪行内空白（`'  hello  \n'` 仍算一行）。
///
/// 同口径的写入端（`appendExecutionLog`）做的也是 `split('\n').where(isNotEmpty)`，
/// 两端必须一致——否则"刚写入 N 行 → 读出 logLineCount" 会偏差。本函数把读端口径
/// 提到顶层，与写端形成对照测试的可能性。
@visibleForTesting
int countLogLines(String log) {
  if (log.isEmpty) return 0;
  return log.split('\n').where((line) => line.isNotEmpty).length;
}

/// 是否存在"暂停态"——任一 job 暂停 **或** 执行器整体暂停。
///
/// **契约 — 双条件 OR**：
/// - 任一 job 的 `status == JobStatus.paused` → true（job 自身暂停）。
/// - 或 `executorStatus == ExecutorStatus.paused` → true（执行器层级暂停，
///   例如所有 job 已运行完但执行器还在等用户决策）。
/// - 两个条件都不成立 → false。
///
/// **为什么是 OR 而不是 AND**：执行器的 `paused` 状态可能在 jobs 全部 finished
/// 之后还残留（直到用户清空），此时单看 jobs 不会有 paused，但 UI 仍要锁定
/// （`isLocked => hasPausedJob`）。反过来，单个 job paused 时执行器可能还在
/// `running`（尚未传播），此时单看 executor 也不够。OR 兜住两条路径。
///
/// **空 jobs**：jobs 为空时 `.any(...) == false`，纯靠 `executorStatus` 判定。
/// 这是有意行为——执行器可能在 jobs 被清空后仍处于 paused（例如刚清掉了一个
/// paused job 但执行器状态还没刷新），此时 hasPausedJob 仍应为 true。
@visibleForTesting
bool deriveHasPausedJob({
  required List<MergeJob> jobs,
  required ExecutorStatus executorStatus,
}) {
  return jobs.any((job) => job.status == JobStatus.paused) ||
      executorStatus == ExecutorStatus.paused;
}

/// 根据已加载的 `jobs` 列表，计算下一个新增 job 应使用的 `jobId`。
///
/// **契约**：
/// - `jobs` 为空 → 返回 `1`（首启动语义；与 `_nextJobId = 1` 默认值一致）。
/// - 否则返回 `max(job.jobId for job in jobs) + 1`。`reduce` 而非 `sort`，因为
///   只关心极值，不依赖输入顺序。
///
/// **为什么是 max+1 而不是 length+1**：jobId 在生命周期里只递增不复用——
/// 用户删除中间 job 后，长度回退但 jobId 必须继续单调递增，否则
/// `resolveCurrentJobIndex` / 持久化 currentJobId 会指向"复活的旧 jobId"。
/// max+1 保证全局单调；length+1 在删除场景下会塌缩。
///
/// **未做防御**：
/// - 不去重——jobId 全局唯一是上游契约（`addJob` 用 `_nextJobId++` 严格递增），
///   本函数纯数学 max。
/// - 不校验 `jobId >= 1`——MergeJob 自身负责该约束。
/// - 不假设 `jobs` 已按 jobId 升序——`reduce` 不依赖顺序。
@visibleForTesting
int deriveNextJobId(List<MergeJob> jobs) {
  if (jobs.isEmpty) return 1;
  return jobs.map((job) => job.jobId).reduce((a, b) => a > b ? a : b) + 1;
}

/// 在 `jobs` 列表里按 `jobId` 查找下标。
///
/// **契约**：
/// - 找到 → 该 job 在 `jobs` 中的首个下标（jobId 全局唯一是上游契约——`addJob`
///   通过 `_nextJobId++` 严格递增——多个匹配只可能在状态损坏时出现，此时
///   "取首个"是与 `indexWhere` 一致的兜底语义）。
/// - 找不到 → `-1`（哨兵；调用方需显式判断 `< 0` 兜底，**不抛异常**）。
///
/// **设计选择**：
/// - 不返回 `int?`：`-1` 哨兵与 lib 内 `_currentJobIndex = -1` 等"无当前选中"
///   状态对齐；改成 nullable 会让所有 caller 都包一层 `?? -1`。
/// - 不抛 `StateError`：jobs 列表常态下确实可能找不到（job 被删除后回放、并发
///   竞争导致快照过期），抛异常会强制每个 caller 加 try-catch，不如哨兵简洁。
/// - 不收敛 indexOf：`indexWhere(predicate)` 是按 `jobId == X` 谓词查找，
///   `indexOf(MergeJob)` 是按 `==` 整体比较，两者语义不同——helper 内必须用
///   `indexWhere`。
///
/// **与 `resolveCurrentJobIndex` 的关系**：后者是本 helper 的 nullable 包装——
/// `jobId == null` 也兜成 `-1`，避免 caller 写 `jobId == null ? -1 : findJobIndexById(...)`
/// 的样板。本 helper 是底层、`resolveCurrentJobIndex` 是带 null 兜底的入口。
@visibleForTesting
int findJobIndexById(List<MergeJob> jobs, int jobId) {
  return jobs.indexWhere((job) => job.jobId == jobId);
}

/// 在 `steps` 列表里按 `stepId` 查找下标。
///
/// **契约**：
/// - 找到 → 该 step 在 `steps` 中的首个下标（stepId 应在 `kMergeExecutionSteps`
///   常量列表中唯一，多个匹配只可能在常量被破坏时出现）。
/// - 找不到 → `-1`（哨兵；调用方需显式判断 `< 0` 兜底）。
///
/// **典型 caller**：`_runRevision` 用 `findStepIndexById(steps, startStepId)` 解析恢复点；
/// commit 步触发 retryFromUpdate 时回退到 `kUpdateStepId` 下标。
///
/// **设计选择**：
/// - 与 `findJobIndexById` 同形态（List + 唯一 id 字段）但**故意不抽出泛型 helper**——
///   Dart 没有"具有 String/int id 字段的对象"这种结构类型，泛型抽象需要引入
///   `int Function(T)` 提取器，反而比直接写两份 `indexWhere` 更复杂。两个 helper
///   故意保持平行（duplicate 但 doc 一致），不进一步收敛。
@visibleForTesting
int findStepIndexById(
  List<MergeExecutionStepDefinition> steps,
  String stepId,
) {
  return steps.indexWhere((step) => step.id == stepId);
}

/// 根据持久化的 `jobId` 还原 `_currentJobIndex`。
///
/// **契约 — 三条分支**：
/// - `jobId == null` → 返回 `-1`（哨兵：没有当前 job）。这条路径覆盖应用首次启动
///   或上次正常结束的场景。
/// - `jobId != null` 但 `jobs` 中找不到匹配的 jobId → 返回 `-1`（哨兵：原 job 已删除）。
///   这条路径覆盖"恢复时发现持久化的 currentJobId 已被清理"的边界。
/// - 找到匹配 → 返回该 job 在 `jobs` 中的下标（**委托给 [findJobIndexById]**，
///   保留 `indexWhere` 的语义：首个匹配，jobId 应当全局唯一）。
///
/// **`null` 与"找不到"返回相同的 `-1`** 是有意合并——caller `_restoreCurrentJobIndex`
/// 后续逻辑只关心"是否有 currentJob"，不区分原因。
@visibleForTesting
int resolveCurrentJobIndex({
  required int? jobId,
  required List<MergeJob> jobs,
}) {
  if (jobId == null) return -1;
  return findJobIndexById(jobs, jobId);
}

/// R128 provider notifyListeners 触发协议三档分类（MergeExecutionState 维度）
///
/// 全部 21+ 处 `notifyListeners()` 调用按"是否同步 / 是否条件化 / 是否在 finally"
/// 三个轴分到三档。**与 AppState（R128 同维度）共享同一三档框架**——不同点
/// 在于 MergeExecutionState 没有"loading-flag bracket"形态（execution 本身就
/// 是长跑流程、用 `_status: ExecutorStatus` 状态机表达进度，而不是布尔
/// loading），所以档 3 的形态变成"状态机阶段切换 + 中间 notify"。
///
/// - **档 1 sync 直接 notify**（最常见，约 12 处）：同步路径或 await 之后改
///   状态机字段后无条件 notify。形态：`_jobs.add(job); await
///   _storageService.saveQueue(_jobs); _appendLog(...); notifyListeners();`。
///   每段 await 之间的 notify 等同于一次 sync mutator + notify。例子：
///   `addJob` (line 652) / `removeQueuedJob` / `clearQueuedJobs` /
///   `clearHistory` / `cancelPausedJob` / `requestSkipCurrentRevision` /
///   `_executeJob` 中 status 切换 / `_runRevision` 中 step 切换 等。
///
/// - **档 2 conditional notify (guard-skip 或 guard-delegate)**（约 4 处）：
///   通过条件判断决定 notify。例子：
///   * **skip-on-noop**: `cancelPausedJob` 中 `if (_cancelRequestedJobId ==
///     job.jobId) return;` 守卫——重复请求不再 notify。
///   * **guard-on-relevance**: 中断核对路径（`_recoverInterruptedJobIfDone`
///     等）若仓库已合并则 notify + 续跑、否则提前 return 不 notify。
///
/// - **档 3 状态机阶段切换 + 中间 notify**（约 5 处，与 AppState 双 notify 形
///   态对偶）：long-running flow 内部多次 status 切换、每次切换都 notify 让
///   UI 实时跟踪。形态：`_status = ExecutorStatus.completed; _currentStepId =
///   null; notifyListeners(); _status = ExecutorStatus.idle; await
///   _startNextJob();`——两 notify 之间 status 显式从 completed → idle 但
///   **不再 notify**（因为 idle 是 internal 状态、_startNextJob 进入下一轮会
///   自己 notify）。例子：`_executeJob` (line 1152) / `_recoverInterruptedJob`
///   (line 862, 905) / `init` 末位（与 R127 init 序列共契）。
///
/// **判据**（拿到一处 notify 站点反向判档）：
/// 1. 在 try-finally 的 finally 块或 long-running flow 内 status 切换上？→ 档 3。
/// 2. 紧跟 if 守卫且只在条件成立时执行？→ 档 2。
/// 3. 同步路径无条件执行？→ 档 1。
///
/// **跨档不变量**（与 AppState 共享）：
/// - **notify 之前 mutator 必须已写完** —— 永远先改字段、后 notify。
/// - **notify 之后不再写"会被 listener 立即读"的字段** —— 多档下 notify 应
///   放方法体末位或 status 切换之后。
/// - **每个 mutator 至少有一条到达 notify 的路径** —— 档 1 必 notify、档 2
///   双路径都终结于 notify、档 3 状态机切换链中至少一次 notify。
///
/// **MergeExecutionState 特化（与 AppState 不同处）**：
/// - **status idle 切换可以不 notify** —— `_status = ExecutorStatus.idle` 是
///   internal cleanup, 紧跟 `_startNextJob()` 的下一轮会自己 notify, 中间无需
///   重复触发 listener。这是 R128 在状态机维度的一条"sub-rule"：状态机的
///   internal transient 状态可省略 notify、user-visible 状态必须 notify。
/// - **kick-after-notify 模式**（与 R127 init 末位 kick 同源）—— `notify();
///   await _startNextJob();` 形态遍布 _executeJob / _recoverInterruptedJob /
///   init——notify 让 UI 看到当前任务收尾、kick 启动下一任务进入新 notify
///   循环；这是状态机推进的标准 idiom。
///
/// 顺序锁见 `test/merge_execution_state_notify_protocol_test.dart`。
class MergeExecutionState extends ChangeNotifier {
  /// 构造函数注入：默认使用各服务单例（生产路径不变），测试可覆盖 4 个服务
  /// 以便对状态机做真实流程单测（暂停/继续、中断恢复、out-of-date 重试上限、
  /// 跳过推进等）。
  ///
  /// 4 个服务全部带默认值——既不破坏 `MergeExecutionState()` 调用点，又允许
  /// 任意子集替换。覆盖时传入实现了对应接口的对象（生产实现是 singleton，
  /// 测试实现可以是 hand-rolled fake / mocktail mock）。
  MergeExecutionState({
    StorageService? storageService,
    WorkingCopyManager? wcManager,
    MergeInfoCacheService? mergeInfoService,
    SvnService? svnService,
  })  : _storageService = storageService ?? StorageService(),
        _wcManager = wcManager ?? WorkingCopyManager(),
        _mergeInfoService = mergeInfoService ?? MergeInfoCacheService(),
        _svnService = svnService ?? SvnService();

  final StorageService _storageService;
  final WorkingCopyManager _wcManager;
  final MergeInfoCacheService _mergeInfoService;
  final SvnService _svnService;

  List<MergeJob> _jobs = [];
  int _currentJobIndex = -1;
  int _nextJobId = 1;
  String _log = '';
  ExecutorStatus _status = ExecutorStatus.idle;
  int? _cancelRequestedJobId;
  String? _currentStepId;
  final ExecutionStepSnapshots _snapshots = ExecutionStepSnapshots();
  Map<String, dynamic> _currentContext = const {};
  final Map<String, dynamic> _runtimeVariables = {};
  int? _activeRevision;

  List<MergeJob> get jobs => _jobs;
  int get currentJobIndex => _currentJobIndex;
  MergeJob? get currentJob =>
      (_currentJobIndex >= 0 && _currentJobIndex < _jobs.length)
          ? _jobs[_currentJobIndex]
          : null;
  String get log => _log;
  int get logLineCount => countLogLines(_log);
  bool get isProcessing => _status == ExecutorStatus.running;
  bool get hasPausedJob =>
      deriveHasPausedJob(jobs: _jobs, executorStatus: _status);

  /// 返回首个 paused 状态的 job；若无则返回 `null`。
  ///
  /// **为什么用 `firstWhere + try-catch` 而非 `firstWhereOrNull`**：项目刻意
  /// 不依赖 `package:collection` 的扩展方法，避免新增间接依赖。`firstWhere`
  /// 找不到时抛 `StateError`，本 getter 用 `try-catch` 兜底成 `null`——这是
  /// `firstWhereOrNull` 的等价等效实现。
  ///
  /// **为什么不抽 helper**：lib 内仅此 1 处需要 nullable 兜底的查找；其余
  /// 集合查找都用 `findJobIndexById` 返回 `-1` 哨兵，不存在第二个 caller。
  /// 单点使用 + 紧贴 `MergeExecutionState` 的状态语义（"返回 paused job 对象本身
  /// 而非 jobIndex"）→ 抽 helper 反而割裂上下文。
  MergeJob? get pausedJob {
    try {
      return _jobs.firstWhere((job) => job.status == JobStatus.paused);
    } catch (_) {
      return null;
    }
  }

  bool get isLocked => hasPausedJob;
  List<MergeJob> get activeJobs =>
      _jobs.where((job) => job.status.isActive).toList();
  List<MergeJob> get pendingJobs =>
      _jobs.where((job) => job.status == JobStatus.pending).toList();
  List<MergeJob> get finishedJobs =>
      _jobs.where((job) => job.status.isFinished).toList();
  ExecutorStatus get status => _status;
  String? get currentStepId => _currentStepId;
  String? get currentStepTitle =>
      _currentStepId == null ? null : _stepTitle(_currentStepId!);
  ExecutionStepSnapshots get snapshots => _snapshots;
  Map<String, dynamic> get currentContext =>
      Map<String, dynamic>.unmodifiable(_currentContext);
  List<MergeExecutionStepDefinition> get steps => kMergeExecutionSteps;
  int? get activeRevision => _activeRevision;

  Future<List<String>> _hydrateMissingTargetUrls() async {
    var changed = false;
    final updatedJobs = <MergeJob>[];
    final warnings = <String>[];

    for (final job in _jobs) {
      if ((job.targetUrl ?? '').isNotEmpty || job.targetWc.isEmpty) {
        updatedJobs.add(job);
        continue;
      }

      try {
        final targetUrl =
            (await _svnService.getInfo(job.targetWc, item: 'url')).trim();
        if (targetUrl.isEmpty) {
          updatedJobs.add(job);
          continue;
        }
        updatedJobs.add(job.copyWith(targetUrl: targetUrl));
        changed = true;
      } catch (e) {
        warnings.add(
          '补齐任务 #${job.jobId} 的目标 URL 失败，继续使用目标工作副本展示: $e',
        );
        updatedJobs.add(job);
      }
    }

    if (changed) {
      _jobs = updatedJobs;
      await _storageService.saveQueue(_jobs);
    }

    return warnings;
  }

  /// R127 启动方向单调原则（provider 维度，第二例）: **load → derive →
  /// hydrateTargetUrl → reset → log → notify → kick** —— 与 `app_state.init`
  /// 同族但终态多一档"kick 启动后台 job"（fire-and-forget）。
  ///
  /// 1. **load** (`_storageService.loadQueue()`) —— 从持久化拉队列。
  /// 2. **derive** (`deriveNextJobId(_jobs)`) —— 依赖第 1 步结果；queue 空时
  ///    跳过（保留构造期的初值）。
  /// 3. **hydrateTargetUrl** (`_hydrateMissingTargetUrls()`) —— 补齐旧任务缺失的
  ///    targetUrl；依赖第 1 步 load 和第 2 步 derive，但必须在 reset 前完成，
  ///    让首次 notify 时 UI 已能显示真实目标分支。
  /// 4. **reset** (`_log = ''` + `_clearExecutionState()`) —— 内存域清零，
  ///    必须在任何 `_appendLog` 之前，否则上一次会话残留会污染新一次启动日志。
  /// 5. **log** (paused-job 警告日志，条件性) —— reset 后才允许写日志。
  /// 6. **notify** (`notifyListeners()`) —— 必须在 kick 之前；UI 先看到队列
  ///    + 暂停状态，再被后台 job 异步推进。
  /// 7. **kick** (`_startNextJob()`，`!hasPausedJob && pendingJobs.isNotEmpty`)
  ///    —— 末位副作用，await 前面的 notify 已被 listener 串行化吃完。
  ///
  /// 与 `app_state.init` 共享前四档（load/derive/reset/log），第 5 档同样是
  /// notify；区别在于 merge_execution_state 多一档 kick（业务上必须自动续跑），
  /// 而 app_state 在 microtask 里 notify 完即返回（无续跑动作）。
  ///
  /// 顺序锁见 `test/merge_execution_state_init_sequence_test.dart`。
  Future<void> init() async {
    _jobs = await _storageService.loadQueue();
    var startupWarnings = const <String>[];

    if (_jobs.isNotEmpty) {
      _nextJobId = deriveNextJobId(_jobs);
      startupWarnings = await _hydrateMissingTargetUrls();
    }

    _log = '';
    _clearExecutionState();

    for (final warning in startupWarnings) {
      _appendLog('[WARN] $warning');
    }

    if (hasPausedJob) {
      final job = pausedJob!;
      _appendLog('[WARN] 检测到暂停的任务 #${job.jobId}');
      _appendLog('  暂停原因: ${job.pauseReason}');
      // 刻意不走 `clampedCompletedRevisionCount(job)`——日志路径要看 raw
      // `completedIndex`，若持久化状态损坏跑出 [0, length] 区间，本行
      // 是开发者看见越界进度（如 -1/5、7/5）的唯一窗口；UI 渲染走 clamp
      // 已经把异常静默掉了。详见 `clampedCompletedRevisionCount` doc 中的
      // "作用域明确"段（设计模式 #9：同形不同义，UI=clamp / 诊断=raw）。
      _appendLog('  进度: ${job.completedIndex}/${job.revisions.length}');
      if (job.pauseReason == kInterruptedJobPauseReason) {
        _appendLog('  上次执行被中断，继续时会从当前 revision 的准备步骤重新开始');
      }
      _appendLog('  请选择：继续任务 或 取消任务');
    }

    notifyListeners();

    if (!hasPausedJob) {
      final pendingJobs =
          _jobs.where((job) => job.status == JobStatus.pending).toList();
      if (pendingJobs.isNotEmpty) {
        _appendLog('[INFO] 检测到 ${pendingJobs.length} 个待执行任务，自动开始执行...');
        await _startNextJob();
      }
    }
  }

  Future<QueueMutationResult> addJob({
    SourceConfig? sourceConfig,
    TargetConfig? targetConfig,
    String? sourceUrl,
    String? targetWc,
    String? targetUrl,
    required List<int> revisions,
    required int maxRetries,
    String? commitMessageTemplate,
    String? commitSupplement,
    String? mergeValidationScriptPath,
    bool useTemporarySparseWorkingCopy = false,
  }) async {
    if (isLocked) {
      _appendLog('[WARN] 有暂停的任务需要处理，无法添加新任务');
      return const QueueMutationResult.blocked();
    }

    final effectiveSourceConfig =
        sourceConfig ?? SourceConfig(url: sourceUrl ?? '');
    final effectiveTargetConfig = targetConfig ??
        TargetConfig.fromLegacy(
          targetWc: targetWc ?? '',
          targetUrl: targetUrl,
          useTemporarySparseWorkingCopy: useTemporarySparseWorkingCopy,
        );

    final job = MergeJob.withConfig(
      jobId: _nextJobId++,
      sourceConfig: effectiveSourceConfig,
      targetConfig: effectiveTargetConfig,
      maxRetries: maxRetries,
      revisions: revisions,
      commitMessageTemplate: commitMessageTemplate,
      commitSupplement: commitSupplement,
      mergeValidationScriptPath:
          mergeValidationScriptPath?.trim().isEmpty == true
              ? null
              : mergeValidationScriptPath == null
                  ? null
                  : normalizeMergeValidationScriptPath(
                      mergeValidationScriptPath,
                    ),
    );

    _jobs.add(job);
    await _storageService.saveQueue(_jobs);

    _appendLog('[INFO] 已添加任务到队列：#${job.jobId}');
    notifyListeners();

    if (!isProcessing) {
      await _startNextJob();
    }

    return QueueMutationResult.applied(jobId: job.jobId);
  }

  Future<void> editJob(
    int jobId, {
    String? sourceUrl,
    String? targetWc,
    List<int>? revisions,
    int? maxRetries,
  }) async {
    final index = findJobIndexById(_jobs, jobId);
    if (index == -1) return;

    final job = _jobs[index];
    if (job.status == JobStatus.running || job.status == JobStatus.paused) {
      _appendLog('[WARN] 无法编辑运行中或暂停的任务');
      return;
    }

    _jobs[index] = job.copyWith(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      targetUrl: targetWc != null ? null : job.targetUrl,
      revisions: revisions,
      maxRetries: maxRetries,
      status: JobStatus.pending,
      error: '',
      completedIndex: 0,
      pauseReason: '',
      resumeFromStepId: null,
    );

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已更新');
    notifyListeners();

    if (!isProcessing && !isLocked) {
      await _startNextJob();
    }
  }

  Future<QueueMutationResult> deleteJob(int jobId) async {
    final result = resolveDeleteJobResult(_jobs, jobId);
    if (!result.isApplied) {
      if (result.status == QueueMutationStatus.blocked) {
        _appendLog('[WARN] 无法删除运行中或暂停的任务');
      }
      return result;
    }

    final index = findJobIndexById(_jobs, jobId);
    // **R123 removeAt arbitrary-index 二档判据**：index 由 `findJobIndexById`
    // 谓词命中决定，不是头部 drain——属档 2（任意 index removal）。故意保留
    // List 不改 Queue：(a) Queue 不暴露 `removeAt(int)`；(b) 上下行还需要
    // index 与 `_currentJobIndex` 做关系运算（`> index` / `== index`），
    // Queue 抹掉位置语义后无法表达；(c) 单次删除非热路径，无 R122 复杂度问题。
    _jobs.removeAt(index);

    if (_currentJobIndex > index) {
      _currentJobIndex--;
    } else if (_currentJobIndex == index) {
      _currentJobIndex = -1;
    }

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已删除');
    notifyListeners();
    return result;
  }

  Future<QueueMutationResult> enqueueRemainingJob(int jobId) async {
    final result = resolveEnqueueRemainingJobResult(
      _jobs,
      jobId,
      nextJobId: _nextJobId,
    );
    if (!result.isApplied) {
      if (result.status == QueueMutationStatus.notFound) {
        _appendLog('[WARN] 找不到要重新排队的任务');
      } else {
        _appendLog('[WARN] 任务 #$jobId 没有可重新排队的剩余 revision');
      }
      return result;
    }

    final index = findJobIndexById(_jobs, jobId);
    final sourceJob = _jobs[index];
    final newJob = buildRemainingJob(sourceJob, newJobId: _nextJobId)!;

    _nextJobId++;
    _jobs.add(newJob);
    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 已从任务 #$jobId 创建剩余任务 #${newJob.jobId}');
    notifyListeners();

    if (!isProcessing && !isLocked) {
      await _startNextJob();
    }

    return result;
  }

  Future<QueueMutationResult> clearPendingJobs() async {
    final result = resolveClearPendingJobsResult(_jobs);
    if (!result.isApplied) {
      _appendLog('[WARN] 没有可清空的待执行任务');
      return result;
    }

    final currentJobId = currentJob?.jobId;
    _jobs = _jobs.where((job) => job.status != JobStatus.pending).toList();
    _restoreCurrentJobIndex(currentJobId);

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 已清空 ${result.affectedCount} 个待执行任务');
    notifyListeners();
    return result;
  }

  Future<QueueMutationResult> clearFinishedJobs() async {
    final result = resolveClearFinishedJobsResult(_jobs);
    if (!result.isApplied) {
      _appendLog('[WARN] 没有可清理的历史任务');
      return result;
    }

    final currentJobId = currentJob?.jobId;
    _jobs = _jobs.where((job) => !job.status.isFinished).toList();
    _restoreCurrentJobIndex(currentJobId);

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 已清理 ${result.affectedCount} 条历史任务');
    notifyListeners();
    return result;
  }

  void _restoreCurrentJobIndex(int? jobId) {
    _currentJobIndex = resolveCurrentJobIndex(jobId: jobId, jobs: _jobs);
  }

  /// 用户在队列面板拖拽 reorder pending 子列表。
  ///
  /// 索引为 pending 子列表内位置（与 [ReorderableListView] onReorder 同款约定）。
  /// 任一边界条件不满足或拖动结果与原顺序相同 → 返回 false 不持久化、不 notify。
  /// 仅对 pending 任务生效；running / paused / done / failed 全程保持位置不变。
  ///
  /// 与 R123 任意 index removal 同源——`_jobs` 保持 List 不改 Queue，因为下游
  /// `_currentJobIndex` 仍要按绝对索引解析。
  Future<bool> reorderPendingJobs(
      int oldPendingIndex, int newPendingIndex) async {
    final next =
        reorderPendingJobsList(_jobs, oldPendingIndex, newPendingIndex);
    if (identical(next, _jobs)) return false;

    final currentJobId = currentJob?.jobId;
    _jobs = next;
    _restoreCurrentJobIndex(currentJobId);

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 已重新排序待执行任务');
    notifyListeners();
    return true;
  }

  Future<void> clearQueue() async {
    final activeJobs = _jobs
        .where((job) =>
            job.status == JobStatus.running || job.status == JobStatus.paused)
        .toList();
    _jobs = activeJobs;
    _currentJobIndex = activeJobs.isNotEmpty ? 0 : -1;

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 队列已清空');
    notifyListeners();
  }

  /// 在暂停态临时调高某个任务的 `maxRetries`，配合 outOfDate 暂停后的"调整重试
  /// 次数"按钮使用。
  ///
  /// **契约**：
  /// - 仅在 `newMaxRetries > job.maxRetries` 时才生效——禁止把上限调低，
  ///   避免出现"已重试次数 >= 新上限"导致下一次 update 立刻判定为耗尽的悖论；
  /// - `newMaxRetries` 必须 ≥ 0；负数会被当作无效输入直接 false 返回；
  /// - 找不到对应 jobId / 当前 maxRetries == newMaxRetries 时不持久化、不
  ///   notify、返回 false——与 [reorderPendingJobs] 同款"幂等输入返回 false"
  ///   语义；
  /// - 成功修改 → copyWith 持久化并 notifyListeners；不动 status / completedIndex /
  ///   resumeFromStepId，用户仍需手动点"继续"才会触发新一轮重试，与
  ///   `_markConflictsResolved` / `_runSvnCleanup` 同款显式触发语义。
  ///
  /// **为什么不在 outOfDate 自动重置 retryCount**：
  /// 状态机 `attemptOutOfDateRetry` 比较 `previousRetryCount + 1 vs maxRetries`，
  /// 抬高 `maxRetries` 已足够让"继续"恢复到 retryFromUpdate 路径，无需另外清零
  /// retryCount——保留计数让用户清楚地知道还剩多少次配额。
  Future<bool> updateJobMaxRetries(int jobId, int newMaxRetries) async {
    if (newMaxRetries < 0) return false;
    final jobIndex = findJobIndexById(_jobs, jobId);
    if (jobIndex == -1) return false;
    final job = _jobs[jobIndex];
    if (newMaxRetries <= job.maxRetries) return false;

    _jobs[jobIndex] = job.copyWith(maxRetries: newMaxRetries);
    await _storageService.saveQueue(_jobs);
    _appendLog(
      '[INFO] 任务 #$jobId 重试上限：${job.maxRetries} → $newMaxRetries',
    );
    notifyListeners();
    return true;
  }

  Future<bool> updateJobCommitSupplement(
    int jobId,
    String commitSupplement,
  ) async {
    final jobIndex = findJobIndexById(_jobs, jobId);
    if (jobIndex == -1) return false;

    final trimmed = commitSupplement.trim();
    if (trimmed.isEmpty) return false;

    _jobs[jobIndex] = _jobs[jobIndex].copyWith(commitSupplement: trimmed);
    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已更新提交附加信息');
    notifyListeners();
    return true;
  }

  Future<bool> updateJobCommitMessageOverride({
    required int jobId,
    required int revision,
    required String message,
  }) async {
    final jobIndex = findJobIndexById(_jobs, jobId);
    if (jobIndex == -1) return false;

    if (message.trim().isEmpty) return false;

    _jobs[jobIndex] = _jobs[jobIndex].copyWith(
      commitMessageOverride: message,
      commitMessageOverrideRevision: revision,
    );
    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已更新 r$revision 的完整提交信息');
    notifyListeners();
    return true;
  }

  Future<void> resumePausedJob() async {
    if (!hasPausedJob) {
      _appendLog('[WARN] 没有暂停的任务');
      return;
    }

    final job = pausedJob!;
    final jobIndex = findJobIndexById(_jobs, job.jobId);
    if (jobIndex == -1) return;

    _appendLog('[INFO] 继续执行暂停的任务 #${job.jobId}');
    if (await _resumeInterruptedJobIfNeeded(jobIndex, job)) {
      return;
    }

    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.running,
      pauseReason: '',
      error: '',
    );
    await _storageService.saveQueue(_jobs);
    notifyListeners();

    final resumeStepId =
        _normalizeStepId(job.resumeFromStepId) ?? kPrepareStepId;
    await _executeJob(jobIndex,
        resumeFromIndex: job.completedIndex, resumeStepId: resumeStepId);
  }

  Future<bool> _resumeInterruptedJobIfNeeded(
    int jobIndex,
    MergeJob job,
  ) async {
    if (job.pauseReason != kInterruptedJobPauseReason) {
      return false;
    }

    final revision = job.currentRevision;
    if (revision == null) {
      _appendLog('  当前任务没有待处理 revision，直接标记为完成');
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.done,
        completedIndex: job.revisions.length,
        pauseReason: '',
        error: '',
        resumeFromStepId: null,
      );
      await _storageService.saveQueue(_jobs);
      _appendLog('[INFO] 任务 #${job.jobId} 已恢复并完成');
      _status = ExecutorStatus.completed;
      _currentStepId = null;
      _activeRevision = null;
      notifyListeners();
      _status = ExecutorStatus.idle;
      await _startNextJob();
      return true;
    }

    _appendLog('  正在向仓库核对 r$revision 是否已经提交...');

    try {
      final targetUrl = (job.targetUrl ?? '').trim().isNotEmpty
          ? job.targetUrl!.trim()
          : await _svnService.getInfo(job.targetWc, item: 'url');
      final merged = await _svnService.isRevisionMerged(
        sourceUrl: job.sourceUrl,
        revision: revision,
        target: targetUrl,
      );

      if (!merged) {
        _appendLog('  仓库中未检测到 r$revision 的合并记录，将从准备步骤重新开始');
        return false;
      }

      await _mergeInfoService.getMergedRevisions(
        job.sourceUrl,
        _mergeInfoTargetForJob(job),
        forceRefresh: true,
      );

      final newCompletedIndex = job.completedIndex + 1;
      _appendLog('  仓库中已检测到 r$revision 的合并记录，跳过该 revision');

      if (newCompletedIndex >= job.revisions.length) {
        _jobs[jobIndex] = job.copyWith(
          status: JobStatus.done,
          completedIndex: newCompletedIndex,
          pauseReason: '',
          error: '',
          resumeFromStepId: null,
        );
        await _storageService.saveQueue(_jobs);
        _appendLog('[INFO] 任务 #${job.jobId} 已恢复并完成');
        _status = ExecutorStatus.completed;
        _currentStepId = null;
        _activeRevision = null;
        notifyListeners();
        _status = ExecutorStatus.idle;
        await _startNextJob();
        return true;
      }

      _jobs[jobIndex] = job.copyWith(
        completedIndex: newCompletedIndex,
        pauseReason: '',
        error: '',
        resumeFromStepId: null,
      );
      await _storageService.saveQueue(_jobs);
      _appendLog('[INFO] 已跳过已完成的 revision，继续处理后续任务');
      notifyListeners();
      await _executeJob(jobIndex, resumeFromIndex: newCompletedIndex);
      return true;
    } catch (e) {
      _appendLog('[WARN] 核对中断任务状态失败: $e');
      _appendLog('  将从当前 revision 的准备步骤重新开始');
      return false;
    }
  }

  Future<void> cancelPausedJob() async {
    if (_status == ExecutorStatus.running) {
      if (_currentJobIndex < 0 || _currentJobIndex >= _jobs.length) {
        _appendLog('[WARN] 没有可取消的任务');
        return;
      }

      final job = _jobs[_currentJobIndex];
      if (_cancelRequestedJobId == job.jobId) {
        _appendLog('[INFO] 任务 #${job.jobId} 的终止请求已提交，等待当前步骤结束');
        return;
      }

      _cancelRequestedJobId = job.jobId;
      _appendLog('[INFO] 已提交任务 #${job.jobId} 的终止请求，等待当前步骤结束...');
      notifyListeners();
      return;
    }

    if (!hasPausedJob) {
      _appendLog('[WARN] 没有可取消的任务');
      return;
    }

    final job = pausedJob!;
    final jobIndex = findJobIndexById(_jobs, job.jobId);
    if (jobIndex == -1) {
      _appendLog('[WARN] 找不到要取消的任务');
      return;
    }

    await _finalizeCancelledJob(jobIndex, job, reason: job.pauseReason);
  }

  Future<void> skipCurrentRevision() async {
    if (!hasPausedJob) {
      _appendLog('[WARN] 没有暂停的任务');
      return;
    }

    final job = pausedJob!;
    final jobIndex = findJobIndexById(_jobs, job.jobId);
    if (jobIndex == -1) return;

    final skippedRevision = job.currentRevision;
    if (skippedRevision == null) {
      _appendLog('[WARN] 没有可跳过的 revision');
      return;
    }

    _appendLog('[INFO] 跳过 revision r$skippedRevision');

    try {
      await _wcManager.revert(
        _effectiveTargetWc(job),
        recursive: true,
        refreshMergeInfo: false,
      );
    } catch (e) {
      _appendLog('[WARN] 还原工作副本失败: $e');
    }

    final newCompletedIndex = job.completedIndex + 1;

    if (newCompletedIndex >= job.revisions.length) {
      final cleanedJob = await _cleanupTemporarySparseWorkingCopy(job);
      _jobs[jobIndex] = cleanedJob.copyWith(
        status: JobStatus.done,
        completedIndex: newCompletedIndex,
        pauseReason: '',
        error: '部分 revision 被跳过',
        resumeFromStepId: null,
      );
      await _storageService.saveQueue(_jobs);
      _appendLog('[INFO] 任务 #${job.jobId} 已完成（部分 revision 被跳过）');
      _status = ExecutorStatus.completed;
      notifyListeners();
      _status = ExecutorStatus.idle;
      await _startNextJob();
      return;
    }

    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.running,
      completedIndex: newCompletedIndex,
      pauseReason: '',
      error: '',
      resumeFromStepId: null,
    );
    await _storageService.saveQueue(_jobs);
    notifyListeners();
    await _executeJob(jobIndex, resumeFromIndex: newCompletedIndex);
  }

  Future<void> _startNextJob() async {
    if (isProcessing || isLocked) return;

    int nextIndex = -1;
    for (int i = 0; i < _jobs.length; i++) {
      if (_jobs[i].status == JobStatus.pending) {
        nextIndex = i;
        break;
      }
    }

    if (nextIndex == -1) {
      _currentJobIndex = -1;
      _clearExecutionState();
      await _storageService.saveQueue(_jobs);
      _appendLog('[INFO] 所有任务已执行完成');
      notifyListeners();
      return;
    }

    await _executeJob(nextIndex, resumeFromIndex: 0);
  }

  String _effectiveTargetWc(MergeJob job) {
    final targetConfig = job.targetConfig;
    if (targetConfig.isFullWorkingCopy) {
      return targetConfig.workingCopyPath;
    }
    final tempPath = job.temporaryWorkingCopyPath;
    if (tempPath == null || tempPath.trim().isEmpty) {
      throw StateError('临时精简工作副本尚未准备，请重新开始任务或改用完整工作副本');
    }
    return tempPath;
  }

  String _mergeInfoTargetForJob(MergeJob job) {
    final targetConfig = job.targetConfig;
    return targetConfig.isTemporarySparseWorkingCopy
        ? targetConfig.svnUrl.trim()
        : targetConfig.workingCopyPath.trim();
  }

  Future<MergeJob> _prepareTemporarySparseWorkingCopy(
    int jobIndex,
    MergeJob job,
  ) async {
    final targetConfig = job.targetConfig;
    if (targetConfig.isFullWorkingCopy) {
      return job;
    }

    final existingPath = job.temporaryWorkingCopyPath;
    if (existingPath != null && existingPath.trim().isNotEmpty) {
      final svnDir = Directory('$existingPath${Platform.pathSeparator}.svn');
      if (await svnDir.exists()) {
        _appendLog('[INFO] 继续使用已保留的临时精简工作副本: $existingPath');
        return job;
      }
      _appendLog('[WARN] 已记录的临时精简工作副本不可用，将重新创建: $existingPath');
    }

    final targetUrl = targetConfig.svnUrl.trim();
    if (targetUrl.isEmpty) {
      throw const SparseWorkingCopyUnsupportedException(
        '临时精简工作副本需要目标 SVN URL，请先配置目标 SVN URL',
      );
    }
    final sourceRepoRoot =
        (await _svnService.getInfo(job.sourceUrl, item: 'repos-root-url'))
            .trim();
    final targetRepoRoot =
        (await _svnService.getInfo(targetUrl, item: 'repos-root-url')).trim();
    if (sourceRepoRoot != targetRepoRoot) {
      throw const SparseWorkingCopyUnsupportedException(
        '源分支与目标分支不在同一个 SVN 仓库根下，请使用完整工作副本',
      );
    }

    final sourceBranchPath = svnUrlPathRelativeToRepoRoot(
      url: job.sourceUrl,
      repoRootUrl: sourceRepoRoot,
    );
    if (sourceBranchPath == null || sourceBranchPath.isEmpty) {
      throw const SparseWorkingCopyUnsupportedException(
        '无法确定源分支相对仓库根路径，请使用完整工作副本',
      );
    }

    final changedPaths = <SvnLogChangedPath>[];
    for (final revision in job.revisions) {
      final revisionPaths = await _svnService.getRevisionChangedPaths(
        sourceUrl: job.sourceUrl,
        revision: revision,
      );
      if (revisionPaths.isEmpty) {
        throw SparseWorkingCopyUnsupportedException(
          '无法计算 r$revision 的变更路径，请使用完整工作副本',
        );
      }
      changedPaths.addAll(revisionPaths);
    }

    final plan = buildTemporarySparseCheckoutPlan(
      changedPaths: changedPaths,
      sourceBranchPath: sourceBranchPath,
      validationScriptPath: null,
    );

    final tempDir =
        await Directory.systemTemp.createTemp('svn_auto_merge_sparse_');
    var updatedJob = job.copyWith(
      targetUrl: targetUrl,
      temporaryWorkingCopyPath: tempDir.path,
    );
    _jobs[jobIndex] = updatedJob;
    await _storageService.saveQueue(_jobs);

    _appendLog('[INFO] 使用临时精简工作副本: ${tempDir.path}');
    _appendLog(
        '[INFO] 需检出目录 ${plan.directories.length} 个，文件 ${plan.files.length} 个');

    await _svnService.checkoutSparseRoot(targetUrl, tempDir.path);
    for (final dir in plan.directories) {
      await _svnService.updateSparsePath(
        tempDir.path,
        dir,
        setDepth: 'empty',
      );
    }
    for (final file in plan.files) {
      await _svnService.updateSparsePath(tempDir.path, file);
    }

    _appendLog('[INFO] 临时精简工作副本已准备完成');
    return updatedJob;
  }

  Future<MergeJob> _cleanupTemporarySparseWorkingCopy(MergeJob job) async {
    if (job.targetConfig.isFullWorkingCopy) {
      return job;
    }
    final tempPath = job.temporaryWorkingCopyPath;
    if (tempPath == null || tempPath.trim().isEmpty) {
      return job;
    }

    try {
      final tempDir = Directory(tempPath);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      _appendLog('[INFO] 已清理临时精简工作副本: $tempPath');
      return job.copyWith(temporaryWorkingCopyPath: null);
    } catch (e, stackTrace) {
      _appendLog('[WARN] 清理临时精简工作副本失败，已保留目录: $tempPath');
      AppLogger.merge.error('清理临时精简工作副本失败', e, stackTrace);
      return job;
    }
  }

  void _logTemporarySparseWorkingCopyPreserved(MergeJob job) {
    if (job.targetConfig.isFullWorkingCopy) {
      return;
    }
    final tempPath = job.temporaryWorkingCopyPath;
    if (tempPath == null || tempPath.trim().isEmpty) {
      return;
    }
    _appendLog('[WARN] 临时精简工作副本已保留，便于人工处理现场: $tempPath');
  }

  Future<void> _executeJob(
    int jobIndex, {
    required int resumeFromIndex,
    String? resumeStepId,
  }) async {
    _currentJobIndex = jobIndex;
    var job = _jobs[jobIndex];

    _jobs[jobIndex] = buildRunningJobState(job);
    job = _jobs[jobIndex];
    await _storageService.saveQueue(_jobs);

    try {
      job = await _prepareTemporarySparseWorkingCopy(jobIndex, job);
    } catch (e) {
      final message = e.toString();
      _appendLog('[ERROR] 准备临时精简工作副本失败: $message');
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.paused,
        error: message,
        pauseReason: message,
        resumeFromStepId: kPrepareStepId,
      );
      await _storageService.saveQueue(_jobs);
      _status = ExecutorStatus.paused;
      notifyListeners();
      return;
    }

    // resume 时从 paused 的 commit snapshot 抢救上轮 retryCount，否则
    // _clearExecutionRuntime 会把 _snapshots 一起擦掉。这是「保留计数让用户
    // 清楚知道还剩多少次配额」doc 契约的实现锚点（见 updateJobMaxRetries doc）。
    final preservedRetryCount =
        resumeStepId == null ? 0 : _readPreviousCommitRetryCount();

    _status = ExecutorStatus.running;
    _clearExecutionRuntime();
    _setGlobalContext(job);
    notifyListeners();

    _appendLog('[INFO] 开始执行任务 #${job.jobId}');
    _appendLog('  源 URL: ${job.sourceUrl}');
    if (job.targetConfig.isTemporarySparseWorkingCopy) {
      _appendLog('  目标 SVN URL: ${job.targetConfig.svnUrl}');
      _appendLog('  执行工作副本: ${_effectiveTargetWc(job)}（临时精简）');
    } else {
      _appendLog('  目标工作副本: ${job.targetConfig.workingCopyPath}');
    }
    _appendLog('  待合并 revision: ${formatRevisionListShort(job.revisions)}');
    if (resumeStepId != null) {
      _appendLog('  恢复步骤: ${_stepTitle(resumeStepId)}');
    }

    for (int i = resumeFromIndex; i < job.revisions.length; i++) {
      final revision = job.revisions[i];
      _activeRevision = revision;
      _runtimeVariables.clear();
      // 第一轮（resume 入口 revision）保留上轮 retryCount，后续 revision 清零。
      _runtimeVariables['commitRetryCount'] =
          i == resumeFromIndex ? preservedRetryCount : 0;
      _setGlobalContext(job.copyWith(completedIndex: i));

      _appendLog(
          '[INFO] 开始处理 revision r$revision (${i + 1}/${job.revisions.length})...');

      _jobs[jobIndex] = buildRunningJobState(job, completedIndex: i);
      job = _jobs[jobIndex];
      await _storageService.saveQueue(_jobs);

      final startStepId = i == resumeFromIndex
          ? _normalizeStepId(resumeStepId) ?? kPrepareStepId
          : kPrepareStepId;

      final result = await _runRevision(job, revision, startStepId);

      if (result == _RevisionRunResult.completed) {
        _jobs[jobIndex] = job.copyWith(
          completedIndex: i + 1,
          pauseReason: '',
          error: '',
          commitMessageOverride: null,
          commitMessageOverrideRevision: null,
          resumeFromStepId: null,
        );
        job = _jobs[jobIndex];
        await _storageService.saveQueue(_jobs);
        _appendLog('[INFO] r$revision 处理完成');

        await _mergeInfoService.getMergedRevisions(
          job.sourceUrl,
          _mergeInfoTargetForJob(job),
          forceRefresh: true,
        );
        _appendLog('[DEBUG] r$revision 已从仓库 mergeinfo 刷新为已合并');

        if (_isCancelRequestedFor(job.jobId)) {
          if (i + 1 < job.revisions.length) {
            await _finalizeCancelledJob(jobIndex, _jobs[jobIndex]);
            return;
          }
          _cancelRequestedJobId = null;
          _appendLog('[INFO] 当前任务已执行到最后一个 revision，忽略终止请求');
        }

        continue;
      }

      if (result == _RevisionRunResult.cancelled) {
        await _finalizeCancelledJob(jobIndex, _jobs[jobIndex]);
        return;
      }

      if (result == _RevisionRunResult.paused) {
        final failedSnapshot = _currentFailedSnapshot();
        final failedJob = job.copyWith(
          status: JobStatus.paused,
          completedIndex: i,
          pauseReason: failedSnapshot?.error ?? '等待人工处理',
          error: failedSnapshot?.error ?? '等待人工处理',
          resumeFromStepId: _resolveResumeStepId(failedSnapshot),
        );
        _jobs[jobIndex] = failedJob;
        await _storageService.saveQueue(_jobs);
        _logTemporarySparseWorkingCopyPreserved(failedJob);
        _status = ExecutorStatus.paused;
        notifyListeners();
        return;
      }
    }

    _appendLog('[INFO] 任务 #${job.jobId} 执行成功');
    job = await _cleanupTemporarySparseWorkingCopy(job);
    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.done,
      error: '',
      completedIndex: job.revisions.length,
      pauseReason: '',
      resumeFromStepId: null,
    );
    await _storageService.saveQueue(_jobs);
    _status = ExecutorStatus.completed;
    _currentStepId = null;
    _activeRevision = null;
    notifyListeners();

    _status = ExecutorStatus.idle;
    await _startNextJob();
  }

  Future<_RevisionRunResult> _runRevision(
    MergeJob job,
    int revision,
    String startStepId,
  ) async {
    final startIndex = findStepIndexById(steps, startStepId);
    if (startIndex == -1) {
      _appendLog('[ERROR] 未知的恢复步骤: $startStepId');
      return _RevisionRunResult.paused;
    }

    final contextJob =
        job.copyWith(completedIndex: job.revisions.indexOf(revision));
    _setGlobalContext(contextJob);
    bool updateRequired = false;
    bool mergeCompleted = startIndex > findStepIndexById(steps, kMergeStepId);

    for (int stepIndex = startIndex; stepIndex < steps.length;) {
      final step = steps[stepIndex];
      _currentStepId = step.id;
      notifyListeners();

      if (_isCancelRequestedFor(job.jobId)) {
        return _RevisionRunResult.cancelled;
      }

      final snapshot = _startSnapshot(step, job, revision);
      _snapshots.set(step.id, snapshot);
      notifyListeners();

      try {
        switch (step.id) {
          case kPrepareStepId:
            await _runPrepareStep(job);
            _snapshots.set(step.id, _completeSnapshot(snapshot));
            stepIndex++;
            break;
          case kUpdateStepId:
            final updateOutput = await _runUpdateStep(job, revision);
            _snapshots.set(
                step.id, _completeSnapshot(snapshot, output: updateOutput));
            updateRequired = false;
            stepIndex++;
            break;
          case kMergeStepId:
            final mergeOutput = await _runMergeStep(job, revision);
            mergeCompleted = true;
            _snapshots.set(
                step.id, _completeSnapshot(snapshot, output: mergeOutput));
            stepIndex++;
            break;
          case kValidateStepId:
            final validationOutput = await _runValidationStep(job, revision);
            _snapshots.set(
              step.id,
              _completeSnapshot(snapshot, output: validationOutput),
            );
            stepIndex++;
            break;
          case kCommitStepId:
            final commitResult = await _runCommitStep(job, revision);
            if (commitResult.status == _StepRunStatus.completed) {
              _snapshots.set(
                step.id,
                _completeSnapshot(snapshot, output: commitResult.output),
              );
              return _RevisionRunResult.completed;
            }

            if (commitResult.status == _StepRunStatus.retryFromUpdate) {
              _snapshots.set(
                step.id,
                _failSnapshot(
                  snapshot,
                  error: commitResult.error ?? '工作副本过期，需要更新后重试',
                  output: commitResult.output,
                ),
              );
              updateRequired = true;
              stepIndex = findStepIndexById(steps, kUpdateStepId);
              break;
            }

            _snapshots.set(
              step.id,
              _failSnapshot(
                snapshot,
                error: commitResult.error ?? '提交失败',
                output: commitResult.output,
              ),
            );
            return _RevisionRunResult.paused;
          default:
            _snapshots.set(
              step.id,
              _failSnapshot(snapshot, error: '未知步骤: ${step.id}'),
            );
            return _RevisionRunResult.paused;
        }
      } catch (e) {
        final message = e.toString();
        _appendLog('[ERROR] ${step.title}失败: $message');
        _snapshots.set(step.id, _failSnapshot(snapshot, error: message));

        // 显式记录 merge 步冲突：当前行为与其它失败一致都暂停，留作未来扩展锚点。
        if (step.id == kMergeStepId && _looksLikeConflict(message)) {
          return _RevisionRunResult.paused;
        }

        final action = evaluateStepFailure(
          stepId: step.id,
          errorMessage: message,
          updateRequired: updateRequired,
        );
        switch (action) {
          case StepFailureAction.retryFromUpdate:
            stepIndex = findStepIndexById(steps, kUpdateStepId);
            continue;
          case StepFailureAction.pause:
            return _RevisionRunResult.paused;
        }
      } finally {
        notifyListeners();
      }
    }

    if (mergeCompleted) {
      return _RevisionRunResult.completed;
    }
    return _RevisionRunResult.paused;
  }

  Future<void> _runPrepareStep(MergeJob job) async {
    final workingCopy = _effectiveTargetWc(job);
    _appendLog('[INFO] 开始执行步骤: 准备');
    _appendLog('[INFO] 开始还原工作副本到干净状态...');
    _appendLog('[INFO] 执行 svn revert...');
    await _wcManager.revert(workingCopy,
        recursive: true, refreshMergeInfo: false);
    _appendLog('[INFO] 执行 svn cleanup...');
    await _wcManager.cleanup(workingCopy);
    _appendLog('[INFO] 工作副本已还原到干净状态');
  }

  Future<Map<String, dynamic>> _runUpdateStep(
      MergeJob job, int revision) async {
    final workingCopy = _effectiveTargetWc(job);
    _appendLog('[INFO] 开始执行步骤: 更新');
    final result = await _wcManager.update(workingCopy);
    if (!result.isSuccess) {
      final message = result.stderr.isNotEmpty ? result.stderr : '更新失败';
      // R98 symmetric throw 标记（参见 feedback_audit_dimension_switch.md
      // "throw 对称性审计"维度）：本 throw 是契约，被外层 try-catch
      // （line ~1083-1144）捕获后路由到 evaluateStepFailure 决策——retry 或 pause。
      // **不直接对此 throw 写单测断言**，但**契约已锁**：决策结果是
      // StepFailureAction enum，evaluateStepFailure 已有 4 case 真值表测试
      // （test/merge_execution_state_test.dart）。Throw 是契约载体,
      // 测试锁的是"载体进入决策后的输出"，比直接断言 throw 类更稳健
      // （未来若改用 Result<T, E> 模式去掉 throw 也不会破测试）。
      throw StateError(message);
    }

    // 第三十四轮：`svn update` 在服务器侧改动与本地修改产生冲突时仅把文件标
    // 'C' 状态、仍 exit 0（result.isSuccess == true 不保证 WC 干净）。如果不在
    // update 步主动后验，update 残留的 'C' 文件会被下一步 merge 步的后验
    // （第三十三轮）误判为"merge 产生的冲突"——错位归 merge 步暂停，用户继续
    // 时 prepare 又 revert / update 又出 'C' / merge 又误判，形成循环。这里
    // 把"update 触发的冲突"归位到 update 步：throw StateError 后外层
    // _runRevision catch 块通过 evaluateStepFailure(stepId='update') 默认走
    // pause，pauseReason / resumeFromStepId 都归到 update 步而非 merge 步。
    // 与第三十二轮 _svnUpdate（主屏工具栏）后验家族**完美对称**——这是
    // "成功后调 SVN 后验" 在 merge job 内部 update 步的对称版图。
    if (shouldSkipFullWorkingCopyValidation(job)) {
      _appendLog(
        '[INFO] ${describeSkippedFullWorkingCopyValidation("更新后冲突检查")}',
      );
    } else {
      final conflicts = await _svnService.listConflictedFiles(workingCopy);
      if (conflicts.isNotEmpty) {
        throw StateError(
          '更新工作副本产生 ${conflicts.length} 个冲突文件，请手动解决',
        );
      }
    }

    _appendLog('[INFO] 工作副本已更新到最新版本');
    return {
      'stdout': result.stdout,
      'exitCode': result.exitCode,
      'workingCopy': workingCopy,
      'revision': revision,
    };
  }

  Future<Map<String, dynamic>> _runMergeStep(MergeJob job, int revision) async {
    final workingCopy = _effectiveTargetWc(job);
    _appendLog('[INFO] 开始执行步骤: 合并');
    _appendLog('[INFO] 开始合并 r$revision...');
    await _wcManager.merge(job.sourceUrl, revision, workingCopy);
    // R33：`svn merge` 在文件级冲突时仅把文件标 'C' 状态、仍正常返回（不抛
    // SvnException），如果不在 merge 步主动后验，错误会等到下一步 commit 抛
    // `svn: E155015 ... remains in conflict`——此时步骤快照、暂停语境都被
    // 错位归到 commit 步，跟用户实际的失败点（merge 触发的冲突）不一致。
    // 这里调 listConflictedFiles 把"merge 触发的冲突"归位到 merge 步：
    // throw 的 StateError 含"冲突"字面量，外层 _runRevision 的 catch 块通过
    // `step.id == kMergeStepId && _looksLikeConflict(message)` 路径把任务挂起
    // 到 merge 步，与 `_resolveResumeStepId(failedSnapshot)` 一起保证"继续"
    // 时回到 merge 步而非 commit 步。
    final skipFullWorkingCopyValidation =
        shouldSkipFullWorkingCopyValidation(job);
    if (skipFullWorkingCopyValidation) {
      _appendLog(
        '[INFO] ${describeSkippedFullWorkingCopyValidation("合并后冲突检查")}',
      );
    } else {
      final conflicts = await _svnService.listConflictedFiles(workingCopy);
      if (conflicts.isNotEmpty) {
        throw StateError(
          '合并 r$revision 产生 ${conflicts.length} 个冲突文件，请手动解决',
        );
      }
    }
    // 统计本次合并实际产生的工作副本差异条目数。
    // 用户痛点：自合并（源 URL == 目标分支 URL）/ 已合并过的 revision 重跑 / cherry-pick
    // 同分支历史 commit 等场景，svn merge 会成功返回但不产生任何工作副本变更，最终走到
    // 空 commit，从 app 角度看"合并成功"，但用户实际看不到任何文件被改，误以为流程坏了。
    // 这里跑一次 svn status，把"实际改动 N 个文件"或"空合并（无差异）"写进日志和步骤
    // output，让用户一眼分辨"成功 = 真有产出" vs "成功 = no-op"。
    int? changedCount;
    if (skipFullWorkingCopyValidation) {
      _appendLog(
        '[INFO] ${describeSkippedFullWorkingCopyValidation("本地变更数量统计")}',
      );
    } else {
      changedCount = await _svnService.countChangedFiles(workingCopy);
      if (changedCount == 0) {
        _appendLog(
            '[INFO] r$revision 合并成功 — 但未产生任何差异（空合并 / no-op，源与目标可能无新增提交）');
      } else {
        _appendLog('[INFO] r$revision 合并成功 — 实际改动 $changedCount 个文件');
      }
    }
    return {
      'revision': revision,
      'sourceUrl': job.sourceUrl,
      'changedFilesCount': changedCount,
      'changedFilesCountSkipped': skipFullWorkingCopyValidation,
      'workingCopy': workingCopy,
    };
  }

  Future<Map<String, dynamic>> _runValidationStep(
    MergeJob job,
    int revision,
  ) async {
    _appendLog('[INFO] 开始执行步骤: 校验');
    final workingCopy = _effectiveTargetWc(job);
    if (job.mergeValidationScriptPath == null ||
        job.mergeValidationScriptPath!.trim().isEmpty) {
      _appendLog('[INFO] 未配置合并校验脚本，跳过校验');
      return {
        'skipped': true,
        'revision': revision,
      };
    }
    if (shouldSkipFullWorkingCopyValidation(job)) {
      _appendLog(
        '[INFO] ${describeSkippedFullWorkingCopyValidation("合并校验脚本")}',
      );
      return {
        'skipped': true,
        'reason': 'temporarySparseWorkingCopy',
        'scriptPath': normalizeMergeValidationScriptPath(
          job.mergeValidationScriptPath,
        ),
        'revision': revision,
      };
    }

    final command = resolveMergeValidationScriptCommand(
      targetWc: workingCopy,
      scriptPath: job.mergeValidationScriptPath,
    );

    _appendLog(
      '[INFO] 执行合并校验脚本: ${command.relativePath} '
      '(resolved: ${command.resolvedPath})',
    );
    final result = await Process.run(
      command.executable,
      command.args,
      workingDirectory: workingCopy,
      stdoutEncoding: latin1,
      stderrEncoding: latin1,
      environment: {
        'SVN_AUTO_MERGE_SOURCE_URL': job.sourceUrl,
        'SVN_AUTO_MERGE_TARGET_WC': workingCopy,
        if (job.useTemporarySparseWorkingCopy)
          'SVN_AUTO_MERGE_ORIGINAL_TARGET_WC': job.targetWc,
        if (job.targetUrl != null) 'SVN_AUTO_MERGE_TARGET_URL': job.targetUrl!,
        'SVN_AUTO_MERGE_REVISION': revision.toString(),
      },
    );

    final stdout = decodeProcessOutput(result.stdout.toString());
    final stderr = decodeProcessOutput(result.stderr.toString());
    if (stdout.trim().isNotEmpty) {
      _appendLog('[INFO] 校验脚本输出: ${_truncateValidationLog(stdout.trim())}');
    }
    if (stderr.trim().isNotEmpty) {
      _appendLog(
        '[ERROR] 校验脚本错误输出: ${_truncateValidationLog(stderr.trim())}',
      );
    }

    if (result.exitCode != 0) {
      throw StateError('合并校验脚本失败 (退出码: ${result.exitCode})');
    }
    if (hasExplicitMergeValidationErrorOutput(
      stdout: stdout,
      stderr: stderr,
    )) {
      throw StateError('合并校验脚本输出包含明确错误信息');
    }

    _appendLog('[INFO] 合并校验脚本执行成功');
    return {
      'skipped': false,
      'scriptPath': command.relativePath,
      'resolvedPath': command.resolvedPath,
      'executable': command.executable,
      'args': command.args,
      'exitCode': result.exitCode,
      'revision': revision,
    };
  }

  Future<String> _resolveCommitVerificationTargetUrl(
    MergeJob job,
    String workingCopy,
  ) async {
    final configuredTargetUrl = (job.targetUrl ?? '').trim();
    if (configuredTargetUrl.isNotEmpty) {
      return configuredTargetUrl;
    }

    final targetUrl =
        (await _svnService.getInfo(workingCopy, item: 'url')).trim();
    if (targetUrl.isEmpty) {
      throw StateError('提交后无法确定目标 SVN URL，无法确认仓库合并状态');
    }
    return targetUrl;
  }

  Future<String> _verifyCommitRecordedMergeInfo(
    MergeJob job,
    int revision,
    String workingCopy,
  ) async {
    final targetUrl =
        await _resolveCommitVerificationTargetUrl(job, workingCopy);
    final merged = await _svnService.isRevisionMerged(
      sourceUrl: job.sourceUrl,
      revision: revision,
      target: targetUrl,
    );
    if (!merged) {
      throw StateError(
        '提交后未在仓库 mergeinfo 中检测到 r$revision，'
        '本次提交可能未真正成功，请检查 SVN 提交日志和服务端 hook 输出',
      );
    }
    return targetUrl;
  }

  Future<_CommitStepResult> _runCommitStep(MergeJob job, int revision) async {
    _appendLog('[INFO] 开始执行步骤: 提交');
    final workingCopy = _effectiveTargetWc(job);
    final message = _buildCommitMessage(job, revision);
    _appendLog('[INFO] 提交信息: $message');

    try {
      await _wcManager.commit(workingCopy, message);
      final verifiedTargetUrl =
          await _verifyCommitRecordedMergeInfo(job, revision, workingCopy);
      _appendLog('[INFO] 提交成功，仓库 mergeinfo 已确认 r$revision');
      return _CommitStepResult.completed(
        output: {
          'message': message,
          'revision': revision,
          'verifiedTargetUrl': verifiedTargetUrl,
        },
      );
    } catch (e) {
      final error = e.toString();
      final previousRetryCount =
          _runtimeVariables['commitRetryCount'] as int? ?? 0;
      final outcome = evaluateCommitOutcome(
        errorMessage: error,
        previousRetryCount: previousRetryCount,
        maxRetries: job.maxRetries,
      );

      switch (outcome.kind) {
        case CommitOutcomeKind.otherFailure:
          return _CommitStepResult.failed(error: error);

        case CommitOutcomeKind.exhaustedRetries:
          _runtimeVariables['commitRetryCount'] = outcome.nextRetryCount;
          final retryMessage = job.maxRetries > 0
              ? '工作副本过期，已达到最大重试次数 (${job.maxRetries})'
              : '工作副本过期，当前任务未启用重试';
          _appendLog('[ERROR] $retryMessage');
          return _CommitStepResult.failed(
            error: retryMessage,
            output: {
              'error': error,
              'retryCount': outcome.nextRetryCount - 1,
              'maxRetries': job.maxRetries,
            },
          );

        case CommitOutcomeKind.retryFromUpdate:
          _runtimeVariables['commitRetryCount'] = outcome.nextRetryCount;
          final retryMessage =
              '提交时检测到 out-of-date，准备进行第 ${outcome.nextRetryCount}/${job.maxRetries} 次重试';
          _appendLog('[WARN] $retryMessage');
          return _CommitStepResult.retryFromUpdate(
            error: retryMessage,
            output: {
              'error': error,
              'retryCount': outcome.nextRetryCount,
              'maxRetries': job.maxRetries,
            },
          );
      }
    }
  }

  String _buildCommitMessage(MergeJob job, int revision) =>
      buildCommitMessage(job, revision);

  bool _looksLikeConflict(String error) => isMergeConflictMessage(error);

  /// R136 async cancellation/stop signal 协议三档分类（MergeExecutionState 维度）
  ///
  /// 异步族第 5 轮（R119 fire-and-forget / R120 等待协议 / R121 资源释放 /
  /// R128 notify 触发 / 本轮 cancellation）。本应用所有可取消的长跑流程都用
  /// **协作式 (cooperative)** 取消——不调 `Process.kill`，不 `Completer.completeError`，
  /// 不 throw `CancellationException`，**单一信号通道** + **消费者主动轮询**。
  ///
  /// MergeExecutionState 的取消通道是 `_cancelRequestedJobId: int?`（line 569），
  /// 整个 lib 仅此一处可取消的状态字段；preload_service 用并行的 `_shouldStop:
  /// bool`，`StepOutput.cancelled` 是 runtime sentinel（R115 已锁外不持久化）。
  /// 这两条通道形态对偶但语义不同：
  /// - jobId-token：可标识"哪个 job 被取消"，写入即声明 intent、清零即声明终结。
  /// - bool flag：单 producer 单 consumer 的 preload 一次性流程，无需 id。
  ///
  /// **本 doc 锁住的是 jobId-token 协议的三档消费 + 四档不变量。**
  ///
  /// ## 3 档消费模式
  ///
  /// - **档 1 cooperative-poll cancel**（step boundary 轮询）：
  ///   `_runRevision` 在每个 step 循环头 (`for (int stepIndex = startIndex;
  ///   ...)` line 1231 的 1236) 调 `_isCancelRequestedFor(job.jobId)`，命中
  ///   立即 `return _RevisionRunResult.cancelled` 让上层 `_executeJob` 调
  ///   `_finalizeCancelledJob`。**特征**：在两次 await 之间（step 切换缝隙）
  ///   poll、不打断进行中的 SVN 命令、不依赖外部 signal。这是 step 内取消
  ///   的唯一锚点。
  ///
  /// - **档 2 finally-finalize cancel**（revision 完成后再轮询）：
  ///   `_executeJob` 在 revision 处理完成后（line 1161）轮询 token，命中后
  ///   分两种子档：
  ///   * **2a 还有后续 revision**（`i + 1 < job.revisions.length`）：调
  ///     `_finalizeCancelledJob` 走完整终止链。
  ///   * **2b 末位 revision**（无后续）：清零 token + 日志"忽略终止请求"
  ///     (line 1166)，不再终止——完整任务已合并完毕，没有"取消"语义可言。
  ///   **特征**：粒度比档 1 粗（必须等当前 revision 完整结束），但保证
  ///   "已合并的 revision 不会被回滚"——这是 R136 的最核心业务约束。
  ///
  /// - **档 3 paused-job 直接 finalize**（不经 token 通道）：
  ///   `cancelPausedJob` 在 `_status == ExecutorStatus.running` 时设 token
  ///   (line 997) 走档 2 路径；但当 `hasPausedJob == true` 时（任务已暂停、
  ///   不在跑），直接调 `_finalizeCancelledJob` (line 1015)——**不写 token**，
  ///   因为没有循环在轮询。这是"取消已暂停任务"的快路径。
  ///
  /// ## 4 档不变量
  ///
  /// - **L1 单一 channel**：所有可取消的 long-running flow 必须复用
  ///   `_cancelRequestedJobId`，不另起 Completer / Stream / CancellationToken。
  ///   理由：多通道会产生 race—两个 cancel 信号谁先到、谁的 finalize 先跑、
  ///   token 谁先清零都成 bug 源。
  ///
  /// - **L2 cooperative-only**：消费者必须在 await 缝隙主动 poll，**不允许**
  ///   通过抛异常或 kill 子进程来打断 SVN 命令。理由：SVN merge / commit
  ///   是非原子操作，强行打断留下半合并工作副本，无法 revert 干净。
  ///
  /// - **L3 token 单调**：token 写入路径只有 `cancelPausedJob:997`（user
  ///   intent），清零路径有且仅有 4 处（见 K 不变量）；从写入到清零之间
  ///   token 值**不变**——不允许"半路改成另一个 jobId"。理由：保证档 1/2
  ///   的 poll 语义稳定。
  ///
  /// - **L4 finalize 闭合**：档 1 命中必走 `_finalizeCancelledJob`（经
  ///   `_RevisionRunResult.cancelled` 传出 `_runRevision` 由 `_executeJob`
  ///   line 1174 接力）；档 2a 直接调 `_finalizeCancelledJob`；档 2b 跳过
  ///   finalize（合理，任务已完整完成）；档 3 直接调 `_finalizeCancelledJob`。
  ///   即"档 1 / 2a / 3 必到达 finalize、2b 跳过"是协议的形状。
  ///
  /// ## K 不变量：token reset 站点穷尽闭合
  ///
  /// `_cancelRequestedJobId` 清零有且仅有 **4** 处，缺一处就泄漏 stale token：
  ///
  /// 1. **null 初始化**（line 569 `int? _cancelRequestedJobId;`）—— 字段默
  ///    认 null，construction 即清零。
  /// 2. **`_executeJob` 末位忽略**（line 1166）—— 档 2b 路径，任务已完整跑完
  ///    最后一个 revision，token 失效。
  /// 3. **`_finalizeCancelledJob`**（line 1482）—— 档 1/2a/3 终止链统一清零，
  ///    保证 finalize 后"前一次 cancel intent"不会泄漏到 _startNextJob。
  /// 4. **`_clearExecutionState`**（line 1584）—— 与 `_status =
  ///    ExecutorStatus.idle` 同步清理 runtime state，防止 idle → running
  ///    切换时 stale token 立即触发 cancel。
  ///
  /// **未覆盖路径会导致的 bug**：若 finalize 不清零，`_startNextJob` 拿
  /// 下一任务、其 jobId 可能等于残留 token（罕见但可能、id 复用），新任务
  /// 在第一次 step boundary poll 立即 cancel——表现为"任务还没开始就被
  /// 终止"。所以 4 处 reset 是穷尽必要集。
  ///
  /// ## 形态对偶（preload_service `_shouldStop`）
  ///
  /// preload 用 bool 通道，3 档退化成 2 档：
  /// - 档 A 循环头 poll（`while (!_shouldStop)` line 576）
  /// - 档 B 循环结束后 finalize（line 641 `if (_shouldStop && status ==
  ///   loading)` 改 status 为 completed + reason userStopped）
  /// reset 站点 3 处：字段声明默认值 (line 497) / start 时 (line 521) /
  /// `reset()` (line 737)；写入站点 1 处：`stopPreload` (line 702)。token
  /// 不复用、单 channel、cooperative。
  ///
  /// 协议同律见 `test/async_cancellation_protocol_test.dart`。
  bool _isCancelRequestedFor(int jobId) => _cancelRequestedJobId == jobId;

  Future<void> _finalizeCancelledJob(
    int jobIndex,
    MergeJob job, {
    String? reason,
  }) async {
    final cancelReason =
        (reason != null && reason.trim().isNotEmpty) ? reason.trim() : '手动停止';

    _appendLog('[INFO] 正在终止任务 #${job.jobId}');

    try {
      _appendLog('[INFO] 正在还原工作副本...');
      await _wcManager.revert(
        _effectiveTargetWc(job),
        recursive: true,
        sourceUrl: job.sourceUrl,
        refreshMergeInfo: true,
      );
      _appendLog('[INFO] 工作副本已还原');
    } catch (e) {
      _appendLog('[WARN] 还原工作副本失败: $e');
    }

    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.failed,
      error: '用户终止: $cancelReason',
      pauseReason: '',
      resumeFromStepId: null,
    );

    _clearExecutionState();
    _status = ExecutorStatus.idle;
    _cancelRequestedJobId = null;
    await _storageService.saveQueue(_jobs);
    _logTemporarySparseWorkingCopyPreserved(_jobs[jobIndex]);
    _appendLog('[INFO] 任务 #${job.jobId} 已终止');
    notifyListeners();

    await _startNextJob();
  }

  StepSnapshot? _currentFailedSnapshot() {
    final stepId = _currentStepId;
    if (stepId == null) {
      return null;
    }

    final snapshot = _snapshots.get(stepId);
    if (snapshot == null) {
      return null;
    }

    return snapshot.status == StepExecutionStatus.failed ? snapshot : null;
  }

  String _resolveResumeStepId(StepSnapshot? failedSnapshot) =>
      resolveResumeStepId(failedSnapshot);

  /// 从当前 _snapshots 中读取 paused commit 步骤记录的上轮 retryCount。
  ///
  /// 实际逻辑全部在顶层纯函数 [extractPreviousRetryCountFromCommitSnapshot]
  /// 里，方便不构造 provider 直接单测。
  int _readPreviousCommitRetryCount() =>
      extractPreviousRetryCountFromCommitSnapshot(
          _snapshots.get(kCommitStepId));

  StepSnapshot _startSnapshot(
    MergeExecutionStepDefinition step,
    MergeJob job,
    int revision,
  ) {
    final workingCopy = _effectiveTargetWc(job);
    return StepSnapshot(
      stepId: step.id,
      stepTypeId: step.id,
      stepName: step.title,
      status: StepExecutionStatus.running,
      inputData: {
        'jobId': job.jobId,
        'sourceUrl': job.sourceUrl,
        'targetWc': job.targetWc,
        'workingCopy': workingCopy,
        'revision': revision,
      },
      config: {
        if (step.id == kValidateStepId)
          'scriptPath':
              normalizeMergeValidationScriptPath(job.mergeValidationScriptPath),
        if (step.id == kCommitStepId) 'maxRetries': job.maxRetries,
        if (step.id == kCommitStepId && job.commitMessageTemplate != null)
          'messageTemplate': job.commitMessageTemplate,
        if (step.id == kCommitStepId && job.commitSupplement != null)
          'commitSupplement': job.commitSupplement,
        if (job.useTemporarySparseWorkingCopy)
          'temporarySparseWorkingCopy': true,
      },
      startTime: DateTime.now(),
    );
  }

  StepSnapshot _completeSnapshot(
    StepSnapshot snapshot, {
    Map<String, dynamic>? output,
  }) {
    return snapshot.copyWith(
      status: StepExecutionStatus.completed,
      output: output == null ? null : StepOutput.success(data: output),
      endTime: DateTime.now(),
    );
  }

  StepSnapshot _failSnapshot(
    StepSnapshot snapshot, {
    required String error,
    Map<String, dynamic>? output,
  }) {
    return snapshot.copyWith(
      status: StepExecutionStatus.failed,
      output: output == null
          ? null
          : StepOutput.failure(data: output, message: error),
      error: error,
      endTime: DateTime.now(),
    );
  }

  void _setGlobalContext(MergeJob job) {
    final workingCopy = job.useTemporarySparseWorkingCopy &&
            (job.temporaryWorkingCopyPath ?? '').trim().isNotEmpty
        ? job.temporaryWorkingCopyPath!
        : job.targetWc;
    _currentContext = {
      'job': {
        'jobId': job.jobId,
        'sourceUrl': job.sourceUrl,
        'targetWc': job.targetWc,
        'workingCopy': workingCopy,
        'currentRevision': job.currentRevision,
        'revisions': job.revisions,
        'completedIndex': job.completedIndex,
      },
      'workDir': workingCopy,
    };
    _snapshots.setGlobalContext(_currentContext);
  }

  void _clearExecutionRuntime() {
    _snapshots.clear();
    _currentContext = const {};
    _currentStepId = null;
    _activeRevision = null;
    _runtimeVariables.clear();
  }

  void _clearExecutionState() {
    _clearExecutionRuntime();
    _status = ExecutorStatus.idle;
    _cancelRequestedJobId = null;
  }

  String? _normalizeStepId(String? stepId) => normalizeStepId(stepId);

  String _stepTitle(String stepId) {
    for (final step in steps) {
      if (step.id == stepId) {
        return step.title;
      }
    }
    return stepId;
  }

  void _appendLog(String message) {
    _log = appendExecutionLog(_log, message);
    AppLogger.merge.info(message);
    notifyListeners();
  }

  void clearLog() {
    _log = '';
    notifyListeners();
  }

  Map<int, bool> getMergedRevisions({
    String? sourceUrl,
    String? targetWc,
  }) {
    final result = <int, bool>{};

    for (final job in _jobs) {
      if (job.status != JobStatus.done) continue;
      if (sourceUrl != null && job.sourceUrl != sourceUrl) continue;
      if (targetWc != null && job.targetWc != targetWc) continue;

      for (final rev in job.revisions) {
        result[rev] = true;
      }
    }

    return result;
  }
}

enum _RevisionRunResult {
  completed,
  paused,
  cancelled,
}

enum _StepRunStatus {
  completed,
  retryFromUpdate,
  failed,
}

class _CommitStepResult {
  final _StepRunStatus status;
  final String? error;
  final Map<String, dynamic>? output;

  const _CommitStepResult._({
    required this.status,
    this.error,
    this.output,
  });

  factory _CommitStepResult.completed({Map<String, dynamic>? output}) {
    return _CommitStepResult._(
      status: _StepRunStatus.completed,
      output: output,
    );
  }

  factory _CommitStepResult.retryFromUpdate({
    required String error,
    Map<String, dynamic>? output,
  }) {
    return _CommitStepResult._(
      status: _StepRunStatus.retryFromUpdate,
      error: error,
      output: output,
    );
  }

  factory _CommitStepResult.failed({
    required String error,
    Map<String, dynamic>? output,
  }) {
    return _CommitStepResult._(
      status: _StepRunStatus.failed,
      error: error,
      output: output,
    );
  }
}
