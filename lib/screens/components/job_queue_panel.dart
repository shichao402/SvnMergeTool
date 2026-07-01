/// 任务队列概览面板
library;

import 'package:flutter/material.dart';

import '../../execution/svn_failure_kind.dart';
import '../../models/merge_job.dart';

/// 把 [MergeJob] 渲染成 `N/M[，当前 rX]` 风格的进度短语。
///
/// 与 [MergeExecutionPanel] 共用同一约定：completedIndex 会 clamp 到合法区间，
/// 没有当前 revision 时不附加“当前 rX”。
@visibleForTesting
String formatJobProgress(MergeJob job) {
  final completed = clampedCompletedRevisionCount(job);
  final currentRevision = job.currentRevision;
  final currentText = currentRevision == null ? '' : '，当前 r$currentRevision';
  return '$completed/${job.revisions.length}$currentText';
}

/// 任务卡片标题文案。
///
/// - 任务正处于运行中且就是当前正在执行的任务 → 显示 `当前执行中`。
/// - 其它情况一律走 `JobStatus.displayName`。
@visibleForTesting
String statusLabel(MergeJob job, {bool isCurrent = false}) {
  if (isCurrent && job.status == JobStatus.running) {
    return '当前执行中';
  }
  return job.status.displayName;
}

/// 任务卡片标题 hover tooltip。
///
/// **进度披露第十二层（Step 5→...→14→15→16）**：[statusLabel] 在 `isCurrent + running`
/// 档位**主动把 `JobStatus.running.displayName="执行中"` 重写为 "当前执行中"**——
/// 用户在标题处看到的是"当前执行中"四字，原始 status displayName "执行中"以及
/// "这是当前正在跑的（不是排队中的其它 running 历史/兜底数据）"两条信息合并成一个
/// 字符串。本 tooltip 还原"`<JobStatus.displayName>` ・ 这是当前正在运行的任务"两段
/// dual-encode，让用户 hover 即可看到底层 status 名 + 当前指示器双信号。
///
/// 触发条件与 [statusLabel] 重写档位严格对偶（`isCurrent && status == running`）；
/// 其它档位标题与底层 displayName 直接一致 → 返回 `''`，由 caller `isEmpty` 检查决定
/// 是否包 [Tooltip]，与 Step 8/9/10/11/12/13/14/15 的 empty-string 契约同源。
///
/// **为什么 fallback 档位（非 running 但 isCurrent，或 running 但非 current）不补 tooltip**：
/// - `isCurrent && !running`（如 `paused/failed/done`）：标题直出 `JobStatus.displayName`，
///   无重写、无信号丢失 → dedup 约束（"helper 已渲染等价信息 → tooltip 不重复"）。
/// - `!isCurrent && running`（队列中其它 running 任务，理论上不可达——单任务串行执行模型
///   下只会有一个 running——但保留 fallback 路径不抛异常）：标题直出 "执行中"，原始
///   displayName 已可见，无 added value。
///
/// **为什么不展开 jobId / pauseReason / completedIndex 进度细节**：那些信息已分别落在
/// `#${jobId}` chip、error 行（Step 11 已 hover）、进度行（Step 12 已 hover）；本 tooltip
/// 聚焦"标题字符串重写"这一**单点**信号丢失（与 Step 15 stepStatusTooltip 单点聚焦同源决策）。
///
/// **与 Step 15 `stepStatusTooltip` 同型对偶**：双 helper 都只在"label 主动重写"档位触发，
/// 触发条件与 label 重写档位严格双向等价（单测以矩阵双向等价锁定）；两 helper 维度正交
/// （任务卡 vs 步骤卡），不强行抽公共 helper——重写规则不同（任务用 `isCurrent + running`，
/// 步骤用 `failed + paused + isCurrent`），强行抽参数化 helper 反而稀释语义。
@visibleForTesting
String formatJobStatusLabelTooltip(MergeJob job, {bool isCurrent = false}) {
  if (!isCurrent) return '';
  if (job.status != JobStatus.running) return '';
  return '${job.status.displayName} · 这是当前正在运行的任务。';
}

/// 任务卡片的副标题：`<sourceUrl 最后一段> -> <targetUrl 最后一段>`。
///
/// 旧任务没有 targetUrl 时，回退到 targetWc 的末尾 path segment。
@visibleForTesting
String buildJobSubtitle(MergeJob job) {
  final sourceName = extractSourceDisplayName(job.sourceUrl);
  final targetUrl = job.targetUrl;
  final targetName = targetUrl != null && targetUrl.isNotEmpty
      ? extractSourceDisplayName(targetUrl)
      : job.targetWc.split('/').where((part) => part.isNotEmpty).lastOrNull ??
          job.targetWc;
  return '$sourceName -> $targetName';
}

/// 任务卡片的强调色。
@visibleForTesting
Color jobStatusColor(JobStatus status) {
  switch (status) {
    case JobStatus.pending:
      return Colors.blueGrey;
    case JobStatus.running:
      return Colors.blue;
    case JobStatus.paused:
      return Colors.orange;
    case JobStatus.done:
      return Colors.green;
    case JobStatus.failed:
      return Colors.red;
  }
}

/// 任务卡片"错误信息行"的文字颜色。
///
/// `JobStatus.failed` 用红色（最终失败），其它（实际只剩 `paused` 会带 error 文案）
/// 用橙色——和卡片状态色对齐：失败=红，暂停=橙。
@visibleForTesting
Color jobErrorMessageColor(JobStatus status) {
  return status == JobStatus.failed
      ? Colors.red.shade700
      : Colors.orange.shade700;
}

/// 任务进度比例（0.0 ~ 1.0），用于驱动 `LinearProgressIndicator`。
///
/// 与 [formatJobProgress] 共用 clamp 约定：
/// - `revisions` 为空 → 返回 0.0（避免除零）
/// - `completedIndex` 越界（负数 / > len）→ clamp 到 [0, len]，再除以 len
@visibleForTesting
double computeJobProgressRatio(MergeJob job) {
  final total = job.revisions.length;
  if (total == 0) {
    return 0.0;
  }
  final completed = clampedCompletedRevisionCount(job);
  return completed / total;
}

/// `JobQueuePanel.build()` 的"任务分桶"结果。
///
/// 把 `_buildHeader` 用到的两个计数（队列长度 / 最近结果长度）和 `ListView`
/// 用到的三个 list 一次算清，避免 widget 内部反复 `where`/`reversed`/`take`。
@visibleForTesting
class JobQueuePanelSnapshot {
  /// 当前队列任务（pending / running / paused）。
  final List<MergeJob> queueJobs;

  /// 队列中的待执行任务（pending）。`actionLabel = "清空待执行"` 是否显示由它驱动。
  final List<MergeJob> pendingJobs;

  /// 最近完成或失败的任务，按"最近优先"排列，最多 [JobQueuePanelSnapshot.recentLimit]。
  final List<MergeJob> recentJobs;

  const JobQueuePanelSnapshot({
    required this.queueJobs,
    required this.pendingJobs,
    required this.recentJobs,
  });
}

/// 默认"最近结果"条数上限，与 `JobQueuePanel.build()` 内联取值保持一致。
const int kJobQueuePanelDefaultRecentLimit = 6;

/// 把 `jobs` 切分成"队列中 / 待执行 / 最近结果"三段。
///
/// - `queueJobs`：保持入参 `jobs` 中的相对顺序，过滤 `isActive`（pending/running/paused）。
/// - `pendingJobs`：在 `queueJobs` 基础上再过滤 `pending`。
/// - `recentJobs`：从 `jobs` 倒序取前 [recentLimit] 条 `isFinished`（done/failed）。
///
/// **不修改入参**，三个返回 list 都是新分配。`recentLimit <= 0` 视为"不展示最近"，
/// 返回空 list（与 widget 现状的 magic number `take(6)` 等价；现在通过参数显式化）。
@visibleForTesting
JobQueuePanelSnapshot partitionJobsForQueuePanel(
  List<MergeJob> jobs, {
  int recentLimit = kJobQueuePanelDefaultRecentLimit,
}) {
  final queueJobs = jobs.where((job) => job.status.isActive).toList();
  final pendingJobs =
      queueJobs.where((job) => job.status == JobStatus.pending).toList();
  final recentJobs = recentLimit <= 0
      ? <MergeJob>[]
      : jobs.reversed
          .where((job) => job.status.isFinished)
          .take(recentLimit)
          .toList();
  return JobQueuePanelSnapshot(
    queueJobs: queueJobs,
    pendingJobs: pendingJobs,
    recentJobs: recentJobs,
  );
}

/// 任务概览面板顶部"X 队列中 / Y 最近结果"计数文案。
///
/// **契约**：用半角斜杠 + 空格分隔（`'$queueCount 队列中 / $recentCount 最近结果'`）。
/// 0 / 负数照常拼接，不做合法性校验——caller 已经从 `partitionJobsForQueuePanel` 拿到的是
/// list 长度，永远是非负整数；本函数把"格式串"这一层契约从 widget 树拎出来锁死，
/// 未来若改成"X 个队列任务 · Y 条最近结果"风格时，单测会立刻红强制 review。
@visibleForTesting
String formatJobOverviewCounts(int queueCount, int recentCount) {
  return '$queueCount 队列中 / $recentCount 最近结果';
}

/// 顶部计数 chip 的 hover tooltip 文案：把 [partitionJobsForQueuePanel] 的两段
/// 切片再下钻到 `JobStatus`，让用户 hover 时看到"队列中 = 等待 N + 执行中 N + 已暂停 N"
/// 与"最近结果 = 完成 N + 失败 N"的拆分。
///
/// **契约**：
/// - 两行：第 1 行队列段，第 2 行最近段；空段省略（避免 "队列中: " 这种 trailing 空尾）；
/// - 单行内用 `' / '`（半角斜杠 + 空格）分隔，与 [formatJobOverviewCounts] 同款分隔符；
/// - 同行内子项格式 `"${displayName} ${count}"`（与 chip strip 用的 `"${label} ×${count}"`
///   故意不同——chip 空间紧用 ×N 显示乘法感，tooltip 行宽充裕用空格分隔更易读）；
/// - 子项顺序固定：队列段按 enum 声明序 pending → running → paused，最近段按 done → failed；
///   零计数子项省略（如全无 paused 时不显示 "已暂停 0"，避免噪音）；
/// - 全空（`queueJobs.isEmpty && recentJobs.isEmpty`）→ 返回空字符串，caller 用空判断不渲染 tooltip。
@visibleForTesting
String formatJobOverviewBreakdown({
  required List<MergeJob> queueJobs,
  required List<MergeJob> recentJobs,
}) {
  String renderSegment(
      String label, List<JobStatus> order, List<MergeJob> jobs) {
    if (jobs.isEmpty) return '';
    final counts = <JobStatus, int>{};
    for (final job in jobs) {
      counts[job.status] = (counts[job.status] ?? 0) + 1;
    }
    final parts = <String>[];
    for (final s in order) {
      final c = counts[s] ?? 0;
      if (c == 0) continue;
      parts.add('${s.displayName} $c');
    }
    if (parts.isEmpty) return '';
    return '$label: ${parts.join(' / ')}';
  }

  final queueLine = renderSegment(
    '队列中',
    const [JobStatus.pending, JobStatus.running, JobStatus.paused],
    queueJobs,
  );
  final recentLine = renderSegment(
    '最近结果',
    const [JobStatus.done, JobStatus.failed],
    recentJobs,
  );
  return [queueLine, recentLine].where((line) => line.isNotEmpty).join('\n');
}

/// 任务卡片副标题的 hover tooltip 文案：展示完整 `sourceUrl`、目标 URL 与 `targetWc`，
/// 让用户不展开详情就能看到完整路径。
///
/// **契约**：
/// - 两行：`'源: <sourceUrl>\n目标: <targetWc>'`，第 1 行源 URL，第 2 行目标 WC；
/// - 当 [buildJobSubtitle] 的短形态已经"完整等价于" `'sourceUrl -> targetWc'` 时（即
///   sourceUrl 与 targetWc 各自都不含 `/` 或恰好等于末段），短形态本身已经是完整信息，
///   tooltip 重复 → 返回空字符串，caller 用 `isEmpty` 判断不渲染 tooltip（对齐 Step 8
///   [formatJobOverviewBreakdown] 的"双空 → ''" 契约）；
/// - 不做 trim、不做 URL 解码、不剥 query string：忠实展示原始字符串，与
///   [extractWcDisplayName] / [extractSourceDisplayName] 的"上游负责规范化"思路一致。
///
/// **为什么不直接显示完整 sourceUrl**：副标题在卡片头部空间紧；完整 SVN URL 常常是
///   `svn://server/repo/path/branches/feature-2026-q2-xxxx` 形态，会挤掉状态/操作按钮。
///   末段+hover 是最低成本的桥梁——延续 Step 5→6→7→8 的"progressive disclosure"轨迹。
@visibleForTesting
String formatJobSubtitleTooltip(MergeJob job) {
  final sourceShort = extractSourceDisplayName(job.sourceUrl);
  final targetForDisplay = job.targetUrl ?? job.targetWc;
  final targetShort = job.targetUrl != null && job.targetUrl!.isNotEmpty
      ? extractSourceDisplayName(job.targetUrl!)
      : job.targetWc.split('/').where((part) => part.isNotEmpty).lastOrNull ??
          job.targetWc;
  // 双方都已经是完整信息（短形态 == 完整字符串）→ tooltip 重复，返回空。
  if (sourceShort == job.sourceUrl && targetShort == targetForDisplay) {
    return '';
  }
  final lines = <String>[
    '源: ${job.sourceUrl}',
    if (job.targetUrl != null && job.targetUrl!.isNotEmpty)
      '目标: ${job.targetUrl}',
    '目标工作副本: ${job.targetWc}',
  ];
  return lines.join('\n');
}

/// 任务卡片中部 revision 列表的 hover tooltip 文案：展示总数 + 完整列表，
/// 让用户在 inline `maxLines:2 + ellipsis` 截断时不点开详情就能看到全部 revision。
///
/// **契约**：
/// - 两行：`'共 N 个 revision\nr1, r2, ...'`，第 1 行总数（用户最关心的"有多少"），
///   第 2 行完整列表（具体哪些）；
/// - 列表段 **delegate 到 [formatRevisionListShort]**——与 [formatJobRevisionList] 同款"列表
///   渲染唯一逻辑源"约束，分隔符 / 前缀 / 顺序由 [formatRevisionListShort] 决定，本函数
///   不再 join 一次；
/// - 空 list → 返回空字符串，caller 用 `isEmpty` 判断不渲染 tooltip（对齐 Step 8/9 的
///   "无附加信息 → ''" 契约）；
/// - **不做"是否截断"判断**：widget 树的 `maxLines:2 + ellipsis` 是否实际生效取决于运行时
///   宽度，纯函数无法获取；只要列表非空就附加 tooltip——单 revision 的场景里 tooltip 仍然
///   提供"共 1 个 revision"的总数信息，对用户是 additive 不冗余。
///
/// **为什么先放总数**：用户 hover 时第一眼看 N，能立刻判断"被截掉了多少"——单纯展开
///   完整列表反而要数一遍。延续 Step 5→6→7→8→9 的 progressive disclosure 轨迹。
@visibleForTesting
String formatJobRevisionTooltip(List<int> revisions) {
  if (revisions.isEmpty) return '';
  return '共 ${revisions.length} 个 revision\n${formatRevisionListShort(revisions)}';
}

/// 任务卡片进度行的 hover tooltip 文案：把 `job.completedRevisions` /
/// `job.currentRevision` / `job.remainingRevisions` 三段 dual-encode 成
/// `'已完成: r1, r2\n当前: r3\n剩余: r4, r5'`——inline 进度文案 `'进度 N/M，当前 rX'`
/// 只给出聚合数字 + 当前 revision，hover 时把"具体哪些 revision 已完成 / 还在排队"
/// 浮出来，延续 Step 5→6→7→8→9→10→11 的"hover progressive disclosure"轨迹。
///
/// **契约**：
/// - 三段顺序固定 `已完成 → 当前 → 剩余`（与时间轴 / `revisions[]` 索引方向一致）；
/// - 列表段（已完成 / 剩余）**delegate 到 [formatRevisionListShort]**——与
///   [formatJobRevisionTooltip] / [formatJobRevisionList] 同款"列表渲染唯一逻辑源"；
/// - 空段省略：`completedRevisions.isEmpty` → 不输出"已完成"行；`currentRevision == null`
///   → 不输出"当前"行；`remainingRevisions.isEmpty` → 不输出"剩余"行；
/// - 三段全空（`revisions.isEmpty` 且 `currentRevision == null`）→ 返回 `''`，caller 用
///   `isEmpty` 判断不渲染 tooltip（与 Step 8/9/10/11 的"无附加信息 → ''" 契约对齐）；
/// - 单段非空时（如只有"剩余"一段）仍渲染 tooltip——hover 提供"具体是哪几条"
///   是 additive 信息，inline 进度行只能给 `'0/3，当前 r100'` 这种聚合形态；
/// - **不复用 [formatJobProgress] 的 inline 形态**：本 helper 是"列表展开"维度，与
///   inline 的"聚合数字"维度正交——dual-encode 不是同维度复刻；
/// - **不展开 `currentRevision` 进度细节**（如已用时长 / 当前步骤名）：当前 schema 没有
///   `startedAt` / 当前步骤字段，强行展示需扩 MergeJob schema（重大决策延后）。
///
/// **为什么三段而非两段**：用户 hover 进度行的核心问题是"卡在哪条 / 还有几条 /
///   走过哪几条"——三个时间维度（过去/现在/未来）各自独立信息密度高，合并成两段
///   （如已完成 + 待办）会失去"当前正在跑的就是 rX"这个最关键的眼下信息。
@visibleForTesting
String formatJobProgressTooltip(MergeJob job) {
  final lines = <String>[];
  final completed = job.completedRevisions;
  if (completed.isNotEmpty) {
    lines.add('已完成: ${formatRevisionListShort(completed)}');
  }
  final current = job.currentRevision;
  if (current != null) {
    lines.add('当前: r$current');
  }
  // [job.remainingRevisions] 包含 currentRevision（当 completedIndex < length 时
  // 是 sublist(completedIndex)），但本 tooltip 已单独列了"当前"行——
  // 用 sublist(completedIndex+1) 切出"未来 only"，避免按值 filter 在重复 revision
  // 列表（如 [100, 100, 101]）下误删第二个 100。
  final futureStart = job.completedIndex + 1;
  final future = futureStart >= job.revisions.length
      ? const <int>[]
      : job.revisions.sublist(futureStart);
  if (future.isNotEmpty) {
    lines.add('剩余: ${formatRevisionListShort(future)}');
  }
  return lines.join('\n');
}

/// 任务卡片进度条 [LinearProgressIndicator] 的 hover tooltip 文案：把视觉填充比例
/// 还原为**整数百分比 + 分子分母**，让用户 hover 即可读到"50% 完成（2/4 个 revision）"
/// 这种数字 anchor。
///
/// **进度披露第十三层（Step 5→...→16→17）**：进度条本身只用**视觉填充比例**编码进度
/// （`LinearProgressIndicator(value: ratio)`），无任何数字 anchored 在条本身上；
/// 下方文字标签 `'进度 N/M，当前 rX'`（[formatJobProgress]）走分数形态。**百分比形态**
/// 是与"分数/三段 list"正交的第三种数字维度——人类对"50%"的距离感比 "2/4" 直觉更强
/// （特别是 N、M 不是常见整除时如 "3/7"），但精度不如分数（10/100 vs 1/10 显示完全相同）。
/// 进度条 hover 不应抢下方文字标签的"分数 + 当前 revision"信号——本 tooltip 聚焦
/// 进度条**本身**缺失的"数字"维度。
///
/// **契约**：
/// - `revisions.isEmpty` → 返回 `''`，caller 用 `isEmpty` 判断不渲染 tooltip。
///   原因：空列表场景下 [computeJobProgressRatio] 返回 `0.0`，但 "0% 完成（0/0 个 revision）"
///   是误导信号——分母 0 不是真"0%"，而是"无任务可言"。直接 dedup。
/// - 其它情况返回 `'<percent>% 完成（<completed>/<total> 个 revision）'`，例如
///   `'40% 完成（2/5 个 revision）'`、`'100% 完成（3/3 个 revision）'`、`'0% 完成（0/3 个 revision）'`。
/// - 百分比 = `(ratio * 100).round()`——四舍五入到整数。**不取小数位**：进度条视觉精度
///   就是肉眼级的，附加小数位反而误导（"33.3%"显得有 0.1% 精度但条本身误差更大）。
/// - 分子 = [clampedCompletedRevisionCount]——与 [formatJobProgress] / [computeJobProgressRatio]
///   同款 clamp 约定（completedIndex 越界 → clamp 到 [0, len]）。
///
/// **为什么不复用 [formatJobProgress]**：[formatJobProgress] 是 `'N/M[，当前 rX]'` 形态，
/// 携带 currentRevision 段 — 与进度条 tooltip 的"百分比"职责正交。进度条 hover 用百分比
/// 不附 currentRevision（那一段是 [formatJobProgressTooltip] / 下方文字标签的职责）。
///
/// **为什么 ratio == 0 / ratio == 1.0 仍渲染**：肉眼判断"接近 0%"vs"刚好 0%"或"接近 100%"
/// vs"刚好 100%"很难——hover 时给出精确数字 anchored 是 additive 信息，不冗余。
@visibleForTesting
String formatJobProgressBarTooltip(MergeJob job) {
  final total = job.revisions.length;
  if (total == 0) return '';
  final completed = clampedCompletedRevisionCount(job);
  final percent = (computeJobProgressRatio(job) * 100).round();
  return '$percent% 完成（$completed/$total 个 revision）';
}

/// 任务卡片底部错误信息行的 hover tooltip 文案：把 `job.error` 加上 status 标签前缀，
/// 让用户在 inline `maxLines:2 + ellipsis` 截断时不点开详情就能看到完整 stderr，并且
/// 通过文字（而非仅靠 [jobErrorMessageColor] 红/橙色）显式知道是 `失败` 还是 `已暂停`。
///
/// **契约**：
/// - 输入 `job.error` 非空 → 返回 `'<status.displayName>: <error>'`，例如 `'失败: svn ...'`、
///   `'已暂停: working copy locked'`；status 标签 delegate 到 [JobStatusExtension.displayName]
///   ("等待"/"执行中"/"已暂停"/"完成"/"失败")，与 [statusLabel] 同源；
/// - 输入 `job.error` 为空 → 返回空字符串。caller 已经用 `if (job.error.isNotEmpty)` 包整段
///   错误行，本 helper 的"空 → ''" 是双保险，与 Step 8/9/10 的"无附加信息 → ''" 契约对齐；
/// - **不做"是否截断"判断**：与 [formatJobRevisionTooltip] 同源——widget 树的
///   `maxLines:2 + ellipsis` 是否实际生效取决于运行时宽度，纯函数无法获取；只要 error 非空就附加
///   tooltip——短单行错误场景下 tooltip 加了 status 前缀仍是 additive 信息，不冗余。
///
/// **为什么加 status 标签**：inline 错误行已经用 [jobErrorMessageColor] 红/橙色携带了 status
///   信号（红=失败，橙=暂停），但颜色对色觉障碍 / 高对比度模式不友好；hover tooltip 用文字
///   `'失败: ...'` / `'已暂停: ...'` 把信号文本化，作为颜色的可访问性兜底。同时延续 Step 9
///   `'源: <sourceUrl>\n目标: <targetWc>'` 的"标签 + 内容" 双段式样。
///
/// **为什么不展开 `pauseReason`**：`_buildJobCard` 当前只渲染 `job.error` 这一行；
///   `pauseReason` 在详情面板（[MergeExecutionPanel]）单独展示，本 helper 与 inline 同源——
///   若未来 `_buildJobCard` 既显示 error 又显示 pauseReason，本 helper 需同步扩展。
@visibleForTesting
String formatJobErrorTooltip(MergeJob job) {
  if (job.error.isEmpty) return '';
  return '${job.status.displayName}: ${job.error}';
}

/// 任务卡片中部"revision: r1, r2, r3"的列表文案。
///
/// **契约**：
/// - 整体前缀 `'revision: '`（半角冒号 + 空格）。`revision` 不带复数 `s`，与原 inline 一致；
/// - 列表渲染段（`r1, r2, r3` 形态）**delegate 到 [formatRevisionListShort]**——
///   `formatRevisionListShort` 是项目内"revision 列表渲染"的**唯一逻辑源**，本函数
///   只负责加 `'revision: '` 标签前缀。每个 revision `r` 前缀、半角逗号 + 空格
///   分隔、空列表 / 单元素 / 负数 / 排序行为都由 [formatRevisionListShort] 决定。
/// - 空 list → `'revision: '`（trailing 空，不附加 "（无）" / "暂无" 等占位）——保持原 inline 行为，
///   widget 层用 `maxLines: 2 + ellipsis` 处理过宽，**但空 list 在原代码里实际不会发生**
///   （MergeJob 的 revisions 由 caller 保证非空）；这条单测显式锁定降级行为。
///
/// **R92 收敛历史**：原 body 内联了 `revisions.map((rev) => 'r$rev').join(', ')`，
/// 与 `lib/models/merge_job.dart::formatRevisionListShort` 实现完全一致——属于
/// "outer 标签 helper + inner 列表 helper 各写一份内层逻辑"的 duplicate。
/// R92 改为 delegate：`formatRevisionListShort` 唯一负责列表渲染，本 helper
/// 只 prepend `'revision: '`。
@visibleForTesting
String formatJobRevisionList(List<int> revisions) {
  return 'revision: ${formatRevisionListShort(revisions)}';
}

/// 任务卡片右侧操作按钮的种类标签——用于 [JobCardActionSpec.kind] 区分。
///
/// **当前两种**：`requeue`（重新加入剩余 revision）/ `delete`（移除 / 删除）。未来若新增第三种
/// （如 `cancel` 取消任务），加 enum 值 + spec builder 配套即可，单测覆盖率断言会立刻提醒补 case。
enum JobCardActionKind { requeue, delete }

/// 任务卡片右侧操作按钮的渲染规格——把"显示哪些按钮 + 各自 tooltip / icon"
/// 从 widget 树里拎出来，与 `LogStatusTagSpec` / `SvnOperationMenuItemSpec` 同风格。
class JobCardActionSpec {
  final JobCardActionKind kind;
  final IconData icon;
  final String tooltip;

  const JobCardActionSpec({
    required this.kind,
    required this.icon,
    required this.tooltip,
  });

  @override
  bool operator ==(Object other) {
    if (other is! JobCardActionSpec) return false;
    return other.kind == kind && other.icon == icon && other.tooltip == tooltip;
  }

  @override
  int get hashCode => Object.hash(kind, icon, tooltip);

  @override
  String toString() => 'JobCardActionSpec($kind, ${icon.codePoint}, $tooltip)';
}

/// 计算任务卡片要渲染的右侧操作按钮列表（顺序固定 `[requeue, delete]`）。
///
/// **契约**：
/// - `requeue` 仅当 `job.canRequeueRemaining == true` 且 `hasRequeueCallback == true` 时出现
///   （`canRequeueRemaining` 已经合并了"`status == failed`"和"`remainingRevisions.isNotEmpty`"，
///   是 `MergeJob` 的派生 getter，本函数信任它）；
/// - `delete` 仅当 `job.canDelete == true` 且 `hasDeleteCallback == true` 时出现；
/// - **delete 的 tooltip 切换**：`pending` → `'移除任务'`（强调"还没开始执行，从队列里拿掉"），
///   其它状态 → `'删除记录'`（强调"已经执行完，清理历史"）。这是有意的语义区分，单测显式锁定。
/// - **顺序固定** `[requeue, delete]`：与原 widget 树渲染顺序一致；`requeue` 在前是因为它属于
///   "积极操作"（recover 失败任务），优先级高于 `delete`（清理）。
/// - **接 `bool hasXxxCallback` 而不是 `VoidCallback?`**：与 Round 56 `shouldShowSvnOperationMenu`
///   同款思路，保持函数纯净不依赖 closure 类型，单测无需构造 fake callback。
@visibleForTesting
List<JobCardActionSpec> jobCardActionSpecs({
  required MergeJob job,
  required bool hasRequeueCallback,
  required bool hasDeleteCallback,
}) {
  final specs = <JobCardActionSpec>[];
  if (job.canRequeueRemaining && hasRequeueCallback) {
    specs.add(
      const JobCardActionSpec(
        kind: JobCardActionKind.requeue,
        icon: Icons.refresh,
        tooltip: '重新加入剩余 revision',
      ),
    );
  }
  if (job.canDelete && hasDeleteCallback) {
    specs.add(
      JobCardActionSpec(
        kind: JobCardActionKind.delete,
        icon: Icons.delete_outline,
        tooltip: job.status == JobStatus.pending ? '移除任务' : '删除记录',
      ),
    );
  }
  return specs;
}

/// 计算任务卡片是否应该渲染 [SvnFailureKind] 分类 chip。
///
/// **契约**：仅 `paused` / `failed` 任务参与分类——pending/running/done 没有失败上下文。
/// 分类源优先级：`job.error` > `job.pauseReason`（与 [summarizePausedJob] 对齐：
/// `error` 是步骤抛出的具体错误正文，`pauseReason` 是恢复/中断时的兜底文案）。
/// 若两者都为空 → 返回 [SvnFailureKind.unknown]，caller 用 `unknown` 来判断"不渲染 chip"。
///
/// **为什么 paused 也分类**：paused 的根因经常就是 SVN 失败被框架捕获后挂起；
/// 队列面板能直接告诉用户「这一条卡在认证失败 vs 网络异常」，不必点开详情。
///
/// **为什么 failed 也分类**：failed 任务在「最近结果」段展示——分类标签让用户看
/// 一眼就能区分历史失败原因，决定是否要 requeue。
SvnFailureKind failureKindForJob(MergeJob job) {
  if (job.status != JobStatus.paused && job.status != JobStatus.failed) {
    return SvnFailureKind.unknown;
  }
  final source = job.error.isNotEmpty ? job.error : job.pauseReason;
  return classifySvnFailure(source);
}

/// 任务卡片头部 chip 的渲染规格——只对 [SvnFailureKind.unknown] 之外的分类显示。
///
/// **契约**：仅 paused / failed 任务参与分类（见 [failureKindForJob]）；其它状态、
/// 或分类为 unknown 时本函数返回 null，caller 用 `null` 判断不渲染。
@visibleForTesting
SvnFailureKind? visibleFailureKindForJob(MergeJob job) {
  final kind = failureKindForJob(job);
  return kind == SvnFailureKind.unknown ? null : kind;
}

/// 队列面板顶部「分桶摘要」的累计：把入参 jobs 中所有 paused/failed 任务的
/// [SvnFailureKind] 按种类计数。
///
/// **契约**：
/// - 只统计 paused / failed 状态——pending/running/done 没有失败上下文，复用
///   [failureKindForJob] 的状态白名单约束；
/// - 排除 [SvnFailureKind.unknown]——它代表"没有有效错误正文"或"未识别"，
///   渲染到 chip strip 反而干扰用户视线（与 [visibleFailureKindForJob] 的 null
///   契约对齐：unknown 永远不展示）；
/// - 返回新分配的 `Map`，**不修改入参**；
/// - 入参为空 / 全部 unknown / 无 paused-or-failed → 返回空 map（caller 用 isEmpty 判断不渲染）。
///
/// 这是 R159 的 visual extension：每条 paused/failed 卡片已经各自展示了 chip，
/// 顶部摘要把它们 N → 1 聚合，让用户**不展开列表**就能看到分布
/// （"认证失败 ×2 / 网络异常 ×1"）。
@visibleForTesting
Map<SvnFailureKind, int> bucketFailureKinds(List<MergeJob> jobs) {
  final counts = <SvnFailureKind, int>{};
  for (final job in jobs) {
    final kind = visibleFailureKindForJob(job);
    if (kind == null) continue;
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return counts;
}

/// 把 [bucketFailureKinds] 的 map 转成 chip strip 的渲染顺序。
///
/// **排序契约**（与 R116 的 N-tuple 排序契约同款，稳定排序）：
/// 1. **severity 降序**（severe 在前）—— 让"红色严重项"先映入眼帘；
/// 2. **count 降序** —— 同 severity 内多发项靠前；
/// 3. **enum 声明序升序**（即 [SvnFailureKind.values] 索引）—— 让相同 severity + 相同 count
///    时仍有稳定顺序，单测可断言不会因哈希顺序抖动。
///
/// 输出是 `MapEntry` 列表（保留 kind→count 关联），caller 直接 map 到 widget。
@visibleForTesting
List<MapEntry<SvnFailureKind, int>> orderedFailureKindBuckets(
  List<MergeJob> jobs,
) {
  final buckets = bucketFailureKinds(jobs);
  final entries = buckets.entries.toList();
  entries.sort((a, b) {
    final sa = presentationFor(a.key).severity;
    final sb = presentationFor(b.key).severity;
    if (sa != sb) {
      // severe 在前
      return sa == SvnFailureSeverity.severe ? -1 : 1;
    }
    if (a.value != b.value) {
      return b.value.compareTo(a.value); // count 降序
    }
    return SvnFailureKind.values
        .indexOf(a.key)
        .compareTo(SvnFailureKind.values.indexOf(b.key));
  });
  return entries;
}

/// 任务卡片头部 **per-card failureKind chip** 的 hover tooltip 文案。
///
/// **进度披露第二十一层（Step 5→...→24→25）/ 第二轮回访 job_queue_panel.dart**：
/// 卡片头部的 failureKind chip 自 R159 以来一直只展示 `presentationFor(kind).hint`
/// （泛化操作建议），但 [failureKindForJob] 的分类逻辑实际是 `job.error > job.pauseReason`
/// fallback——当 `job.error.isEmpty && job.pauseReason.isNotEmpty` 时，分类源是 pauseReason，
/// 但 [_buildJobCard] 底部"错误行"在 `job.error.isEmpty` 档位**完全不渲染**
/// （line `if (job.error.isNotEmpty)` 守卫），用户**没有任何路径**能看到触发该分类的
/// pauseReason 正文——只能看到泛化 hint。本 helper 在该档位 dual-encode pauseReason。
///
/// **契约**：
/// - `job.error.isNotEmpty` → 仅返回 `hint`。错误正文已经在底部错误行 + [formatJobErrorTooltip]
///   hover 还原（带 status 前缀），chip tooltip 不重复（与 Step 11/15/16/17/24 同源 dedup 约束）；
/// - `job.error.isEmpty && job.pauseReason.isNotEmpty` → 返回 `'$hint\n暂停原因: $pauseReason'`，
///   把 chip 分类的**实际触发文本**浮出来——pauseReason 在 widget 树里没有任何 inline / hover
///   出口（与 [formatJobErrorTooltip] 的注释 "若未来 _buildJobCard 既显示 error 又显示 pauseReason,
///   本 helper 需同步扩展" 形成对偶——本轮就是补这个缺口，但不是在 error helper 里补，而是
///   在 chip helper 里补——chip 是 paused 任务**唯一**额外渲染的元素，是最自然的载体）；
/// - `job.error.isEmpty && job.pauseReason.isEmpty` → 仅返回 `hint`。理论上 chip 不应在此档位
///   渲染（[failureKindForJob] 在两源都空时返回 unknown，[visibleFailureKindForJob] → null →
///   widget 不渲染 chip），但 helper 不依赖该不变量，独立兜底。
///
/// **为什么用 `'暂停原因: '` 标签而非 `'失败: '`**：触发档位仅在 paused 状态（failed 状态
/// 必有 error 正文，会走 hint-only 分支）。标签与 [JobStatusExtension.displayName] paused
/// 档位 "已暂停" 语义对齐，与 [formatJobErrorTooltip] 的 `'失败: ...'` / `'已暂停: ...'`
/// 双段式样保持一致风格。
///
/// **为什么不展开 jobId / progress 等**：chip 的语义焦点是"分类 + 触发文本"；jobId 已在头部
/// `#${jobId}` chip 渲染，progress 已在进度行 dual-encode（[formatJobProgressTooltip]）；
/// 强行扩展会稀释 chip tooltip 的语义焦点。
@visibleForTesting
String formatFailureKindChipTooltip(MergeJob job, SvnFailureKind kind) {
  final hint = presentationFor(kind).hint;
  if (job.error.isNotEmpty) return hint;
  if (job.pauseReason.isEmpty) return hint;
  return '$hint\n暂停原因: ${job.pauseReason}';
}

/// 队列面板顶部 failureKind **bucket chip** 的 hover tooltip 文案。
///
/// 在 Step 5→...→17 progressive disclosure via hover 轨迹延续上加第十四层 ——
/// 顶部分桶 chip 的 inline 形态是 `'<label> ×<count>'`（如 `"认证失败 ×2"`），
/// 把 N 个 paused/failed 任务**聚合**成一个 chip：用户能看到分类与计数，
/// 但**具体哪些 jobIds 命中这个分类**完全不可见——用户必须展开下方任务列表
/// 一个一个比对每张卡片的 failureKind chip 才能逆推。本 tooltip 还原成
/// 两段：第一段沿用 [presentationFor]`(kind).hint` 的操作建议，第二段附
/// `'包含任务: #N, #M'` 把这个桶的 jobIds 列出来。
///
/// **契约**：
/// - 入参 [jobs] 是面板顶部传给 `_buildHeader` 的全量任务列表（与
///   [orderedFailureKindBuckets] 同源）；本 helper 内部用同款过滤
///   ([visibleFailureKindForJob]) 摘出命中 [kind] 的任务，**保持 jobs 入参的相对顺序**——
///   用户在面板里看到的列表顺序 == tooltip 里 jobIds 的顺序，便于按编号定位。
/// - jobIds 用 `'#'` 前缀（与 [_buildJobCard] 头部 `#${jobId}` chip 同款渲染），
///   `, `（半角逗号 + 空格）分隔，与 [formatRevisionListShort] 同源风格；
///   不去重不排序，与原始过滤顺序一致。
/// - 即便 jobIds 单条命中也输出"包含任务: #N"——单条时 hover 仍能"指针 → 卡片 #"
///   的映射比"靠肉眼遍历列表"快。
/// - **不展开 error 正文**：每张卡片的 failureKind chip 已经挂着同款 hint，
///   error 正文也已在 [formatJobErrorTooltip] 通过任务卡片底部的 error 行 hover
///   还原；本 tooltip 聚焦 bucket chip **本身**缺失的"哪些任务命中这一类"维度，
///   不抢卡片级 helper 已 dual-encode 的信号（与 Step 11/15/16/17 同源 dedup 约束）。
/// - jobIds 段为空（理论上 [orderedFailureKindBuckets] 不会给出 count==0 的桶，
///   但本 helper 不依赖这个不变量，独立判定）→ 仅返回 hint，避免 `'<hint>\n包含任务: '`
///   尾巴空白。
@visibleForTesting
String formatFailureBucketTooltip(SvnFailureKind kind, List<MergeJob> jobs) {
  final hint = presentationFor(kind).hint;
  final ids = <int>[];
  for (final job in jobs) {
    if (visibleFailureKindForJob(job) == kind) {
      ids.add(job.jobId);
    }
  }
  if (ids.isEmpty) return hint;
  final idList = ids.map((id) => '#$id').join(', ');
  return '$hint\n包含任务: $idList';
}

class JobQueuePanel extends StatelessWidget {
  final List<MergeJob> jobs;
  final int? currentJobId;
  final Future<void> Function(int jobId)? onDeleteJob;
  final Future<void> Function(int jobId)? onRequeueRemainingJob;
  final Future<void> Function()? onClearPendingJobs;
  final Future<void> Function()? onClearFinishedJobs;

  /// 拖拽 reorder pending 子列表的回调。索引语义为 pending 子列表内位置
  /// （与 [ReorderableListView.onReorder] 同款约定，未减 1）。null 时禁用拖拽。
  final Future<void> Function(int oldPendingIndex, int newPendingIndex)?
      onReorderPendingJobs;

  const JobQueuePanel({
    super.key,
    required this.jobs,
    this.currentJobId,
    this.onDeleteJob,
    this.onRequeueRemainingJob,
    this.onClearPendingJobs,
    this.onClearFinishedJobs,
    this.onReorderPendingJobs,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = partitionJobsForQueuePanel(jobs);
    final queueJobs = snapshot.queueJobs;
    final pendingJobs = snapshot.pendingJobs;
    final recentJobs = snapshot.recentJobs;
    final failureBuckets = orderedFailureKindBuckets(jobs);

    // 把 queueJobs 拆成"非 pending（running/paused）"和"pending"——前者保持静态
    // 顺序，后者走 ReorderableListView 支持拖拽。
    final nonPendingQueue =
        queueJobs.where((job) => job.status != JobStatus.pending).toList();
    final canReorder = onReorderPendingJobs != null && pendingJobs.length > 1;

    return Container(
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        border: Border(left: BorderSide(color: Colors.blueGrey.shade200)),
      ),
      child: Column(
        children: [
          _buildHeader(
            queueJobs.length,
            recentJobs.length,
            failureBuckets,
            queueJobs,
            recentJobs,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildSectionTitle(
                  '执行队列',
                  Icons.playlist_play,
                  actionLabel: pendingJobs.isEmpty ? null : '清空待执行',
                  onAction: pendingJobs.isEmpty || onClearPendingJobs == null
                      ? null
                      : () {
                          onClearPendingJobs!();
                        },
                ),
                const SizedBox(height: 8),
                if (queueJobs.isEmpty)
                  _buildEmptyCard('当前没有队列任务')
                else ...[
                  // 先渲染 running/paused（不可拖拽）
                  ...nonPendingQueue.map(
                    (job) => _buildJobCard(
                      job,
                      isCurrent: job.jobId == currentJobId,
                    ),
                  ),
                  // pending 子列表：拖拽支持
                  if (pendingJobs.isNotEmpty)
                    canReorder
                        ? ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: true,
                            itemCount: pendingJobs.length,
                            onReorder: (oldIndex, newIndex) {
                              onReorderPendingJobs!(oldIndex, newIndex);
                            },
                            itemBuilder: (context, index) {
                              final job = pendingJobs[index];
                              return KeyedSubtree(
                                key: ValueKey('pending-job-${job.jobId}'),
                                child: _buildJobCard(
                                  job,
                                  isCurrent: job.jobId == currentJobId,
                                ),
                              );
                            },
                          )
                        : Column(
                            children: pendingJobs
                                .map((job) => _buildJobCard(
                                      job,
                                      isCurrent: job.jobId == currentJobId,
                                    ))
                                .toList(),
                          ),
                ],
                const SizedBox(height: 16),
                _buildSectionTitle(
                  '最近结果',
                  Icons.history,
                  actionLabel: recentJobs.isEmpty ? null : '清空',
                  onAction: recentJobs.isEmpty || onClearFinishedJobs == null
                      ? null
                      : () {
                          onClearFinishedJobs!();
                        },
                ),
                const SizedBox(height: 8),
                if (recentJobs.isEmpty)
                  _buildEmptyCard('暂无完成或失败记录')
                else
                  ...recentJobs.map((job) => _buildJobCard(job)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    int queueCount,
    int recentCount,
    List<MapEntry<SvnFailureKind, int>> failureBuckets,
    List<MergeJob> queueJobs,
    List<MergeJob> recentJobs,
  ) {
    final breakdown = formatJobOverviewBreakdown(
      queueJobs: queueJobs,
      recentJobs: recentJobs,
    );
    final countsText = Text(
      formatJobOverviewCounts(queueCount, recentCount),
      style: TextStyle(
        fontSize: 11,
        color: Colors.blueGrey.shade700,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.blueGrey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt, color: Colors.blueGrey),
              const SizedBox(width: 8),
              const Text(
                '任务概览',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (breakdown.isEmpty)
                countsText
              else
                Tooltip(message: breakdown, child: countsText),
            ],
          ),
          if (failureBuckets.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in failureBuckets)
                  _buildFailureKindBucketChip(entry.key, entry.value),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 队列面板顶部分桶 chip：与卡片头部 [_buildFailureKindChip] 同款配色（severe=红，
  /// normal=橙），但文字改为 `"${label} ×${count}"`，让用户在不展开列表时一眼看到
  /// "认证失败 ×2 / 网络异常 ×1" 的整体分布。复用 list-tier 紧凑尺寸（fontSize=10）。
  ///
  /// **hover tooltip**：与 [_buildFailureKindChip] 同款 `hint` 之外，
  /// 通过 [formatFailureBucketTooltip] 附加 `'包含任务: #N, #M'` 把命中
  /// 这一桶的所有 jobIds 列出——把"聚合 ×N 计数"还原为"具体哪些任务命中"。
  /// 第十四层 progressive disclosure via hover；与 Step 12 进度行三段拆分同源
  /// （N → 元素列表的 dual-encode）。
  Widget _buildFailureKindBucketChip(SvnFailureKind kind, int count) {
    final p = presentationFor(kind);
    final isSevere = p.severity == SvnFailureSeverity.severe;
    final bg = isSevere ? Colors.red.shade100 : Colors.orange.shade100;
    final fg = isSevere ? Colors.red.shade800 : Colors.orange.shade800;
    return Tooltip(
      message: formatFailureBucketTooltip(kind, jobs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${p.label} ×$count',
          style: TextStyle(
            fontSize: 10,
            color: fg,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
    IconData icon, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey.shade700),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.blueGrey.shade800,
          ),
        ),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel),
          ),
      ],
    );
  }

  Widget _buildEmptyCard(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.blueGrey.shade500,
        ),
      ),
    );
  }

  Widget _buildJobCard(MergeJob job, {bool isCurrent = false}) {
    final accentColor = jobStatusColor(job.status);
    final progress = computeJobProgressRatio(job);
    final progressText = formatJobProgress(job);
    final subtitle = buildJobSubtitle(job);
    final subtitleTooltip = formatJobSubtitleTooltip(job);
    final revisionTooltip = formatJobRevisionTooltip(job.revisions);
    final progressTooltip = formatJobProgressTooltip(job);
    final progressBarTooltip = formatJobProgressBarTooltip(job);
    final statusLabelTooltip =
        formatJobStatusLabelTooltip(job, isCurrent: isCurrent);
    final failureKind = visibleFailureKindForJob(job);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? accentColor : Colors.blueGrey.shade100,
          width: isCurrent ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '#${job.jobId}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: statusLabelTooltip.isEmpty
                    ? Text(
                        statusLabel(job, isCurrent: isCurrent),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Tooltip(
                        message: statusLabelTooltip,
                        child: Text(
                          statusLabel(job, isCurrent: isCurrent),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
              if (failureKind != null) ...[
                _buildFailureKindChip(job, failureKind),
                const SizedBox(width: 4),
              ],
              ...jobCardActionSpecs(
                job: job,
                hasRequeueCallback: onRequeueRemainingJob != null,
                hasDeleteCallback: onDeleteJob != null,
              ).map(
                (spec) => IconButton(
                  tooltip: spec.tooltip,
                  onPressed: () {
                    switch (spec.kind) {
                      case JobCardActionKind.requeue:
                        onRequeueRemainingJob!(job.jobId);
                      case JobCardActionKind.delete:
                        onDeleteJob!(job.jobId);
                    }
                  },
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: Icon(spec.icon),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (subtitleTooltip.isEmpty)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade700,
              ),
            )
          else
            Tooltip(
              message: subtitleTooltip,
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey.shade700,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (revisionTooltip.isEmpty)
            Text(
              formatJobRevisionList(job.revisions),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Colors.blueGrey.shade500,
              ),
            )
          else
            Tooltip(
              message: revisionTooltip,
              child: Text(
                formatJobRevisionList(job.revisions),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.blueGrey.shade500,
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (progressBarTooltip.isEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.blueGrey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            )
          else
            Tooltip(
              message: progressBarTooltip,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.blueGrey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ),
          const SizedBox(height: 6),
          if (progressTooltip.isEmpty)
            Text(
              '进度 $progressText',
              style: TextStyle(
                fontSize: 11,
                color: Colors.blueGrey.shade500,
              ),
            )
          else
            Tooltip(
              message: progressTooltip,
              child: Text(
                '进度 $progressText',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.blueGrey.shade500,
                ),
              ),
            ),
          if (job.error.isNotEmpty) ...[
            const SizedBox(height: 6),
            Tooltip(
              message: formatJobErrorTooltip(job),
              child: Text(
                job.error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: jobErrorMessageColor(job.status),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 与 `MergeExecutionPanel._buildFailureKindChip` 同款样式：severe=红、normal=橙；
  /// 在队列面板里压扁尺寸（fontSize=10、padding 更紧）以适配卡片头部紧凑空间。
  ///
  /// **hover tooltip**：通过 [formatFailureKindChipTooltip] 把 hint 与触发分类的
  /// pauseReason 正文 dual-encode——详情面板能看到分类的「建议」全文，但队列卡片
  /// 空间紧只能放短 label，更关键的是 paused 任务（job.error 为空时）的 pauseReason
  /// 在 widget 树里没有任何 inline / hover 出口，本 chip tooltip 是它唯一的展示载体。
  /// 第二十一层 progressive disclosure via hover；与 Step 24 同源延续 dedup 思路
  /// （error 非空时仅 hint，避免与 [formatJobErrorTooltip] 重复）。
  Widget _buildFailureKindChip(MergeJob job, SvnFailureKind kind) {
    final p = presentationFor(kind);
    final isSevere = p.severity == SvnFailureSeverity.severe;
    final bg = isSevere ? Colors.red.shade100 : Colors.orange.shade100;
    final fg = isSevere ? Colors.red.shade800 : Colors.orange.shade800;
    return Tooltip(
      message: formatFailureKindChipTooltip(job, kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          p.label,
          style: TextStyle(
            fontSize: 10,
            color: fg,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
