import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/svn_failure_kind.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/screens/components/job_queue_panel.dart';

MergeJob _job({
  int jobId = 1,
  String sourceUrl = 'svn://example/repo/trunk',
  String targetWc = '/tmp/wc',
  String? targetUrl,
  List<int> revisions = const [100, 101, 102],
  int completedIndex = 0,
  JobStatus status = JobStatus.pending,
  String error = '',
  String pauseReason = '',
}) {
  return MergeJob(
    jobId: jobId,
    sourceUrl: sourceUrl,
    targetWc: targetWc,
    targetUrl: targetUrl,
    maxRetries: 3,
    revisions: revisions,
    completedIndex: completedIndex,
    status: status,
    error: error,
    pauseReason: pauseReason,
  );
}

void main() {
  group('formatJobProgress', () {
    test('appends current revision when work remains', () {
      expect(
        formatJobProgress(_job(revisions: [100, 101, 102], completedIndex: 1)),
        '1/3，当前 r101',
      );
    });

    test('omits current revision text when all completed', () {
      expect(
        formatJobProgress(_job(revisions: [100, 101], completedIndex: 2)),
        '2/2',
      );
    });

    test('clamps completedIndex on overshoot', () {
      expect(
        formatJobProgress(_job(revisions: [100, 101], completedIndex: 3)),
        '2/2',
      );
    });

    test('handles empty revision list', () {
      expect(formatJobProgress(_job(revisions: [])), '0/0');
    });
  });

  group('statusLabel', () {
    test('returns "当前执行中" only when running AND isCurrent=true', () {
      expect(
        statusLabel(_job(status: JobStatus.running), isCurrent: true),
        '当前执行中',
      );
    });

    test('running but not current uses displayName', () {
      expect(
        statusLabel(_job(status: JobStatus.running), isCurrent: false),
        '执行中',
      );
    });

    test('isCurrent=true but not running uses displayName', () {
      // 例如暂停态卡片仍然恰好是 currentJob：不能误标“当前执行中”。
      expect(
        statusLabel(_job(status: JobStatus.paused), isCurrent: true),
        '已暂停',
      );
    });

    test('non-running statuses use displayName', () {
      expect(statusLabel(_job(status: JobStatus.pending)), '等待');
      expect(statusLabel(_job(status: JobStatus.paused)), '已暂停');
      expect(statusLabel(_job(status: JobStatus.done)), '完成');
      expect(statusLabel(_job(status: JobStatus.failed)), '失败');
    });
  });

  group('formatJobStatusLabelTooltip', () {
    test('isCurrent + running → "执行中 · 这是当前正在运行的任务。"', () {
      expect(
        formatJobStatusLabelTooltip(
          _job(status: JobStatus.running),
          isCurrent: true,
        ),
        '执行中 · 这是当前正在运行的任务。',
      );
    });

    test('isCurrent=false + running → ""（标题直出 displayName，无重写）', () {
      expect(
        formatJobStatusLabelTooltip(
          _job(status: JobStatus.running),
          isCurrent: false,
        ),
        '',
      );
    });

    test('isCurrent + 非 running → ""（无重写，标题直出 displayName）', () {
      for (final s in [
        JobStatus.pending,
        JobStatus.paused,
        JobStatus.done,
        JobStatus.failed,
      ]) {
        expect(
          formatJobStatusLabelTooltip(_job(status: s), isCurrent: true),
          '',
          reason: 'status=$s',
        );
      }
    });

    test('isCurrent=false + 任意 status → ""（穷举）', () {
      for (final s in JobStatus.values) {
        expect(
          formatJobStatusLabelTooltip(_job(status: s), isCurrent: false),
          '',
          reason: 'status=$s',
        );
      }
    });

    test('与 statusLabel "当前执行中" 重写档位严格对偶（双 helper 触发条件唯一）', () {
      // 唯一让 statusLabel 返回 "当前执行中" 的输入 ⇔ 唯一让 formatJobStatusLabelTooltip 返回非空的输入
      for (final s in JobStatus.values) {
        for (final c in [true, false]) {
          final label = statusLabel(_job(status: s), isCurrent: c);
          final tooltip =
              formatJobStatusLabelTooltip(_job(status: s), isCurrent: c);
          if (label == '当前执行中') {
            expect(tooltip, isNotEmpty, reason: 'status=$s isCurrent=$c');
          } else {
            expect(tooltip, isEmpty,
                reason: 'status=$s isCurrent=$c label=$label');
          }
        }
      }
    });
  });

  group('buildJobSubtitle', () {
    test('uses last segment of sourceUrl and targetUrl when available', () {
      expect(
        buildJobSubtitle(_job(
          sourceUrl: 'svn://example/repo/branches/release',
          targetWc: '/Users/dev/projects/app-wc',
          targetUrl: 'svn://example/repo/branches/main',
        )),
        'release -> main',
      );
    });

    test(
        'targetUrl wins over local folder name to avoid b1 -> b1 false display',
        () {
      expect(
        buildJobSubtitle(_job(
          sourceUrl: 'svn://example/repo/branches/b1',
          targetWc: '/Users/dev/work/b1',
          targetUrl: 'svn://example/repo/branches/b2',
        )),
        'b1 -> b2',
      );
    });

    test('old jobs without targetUrl fall back to targetWc last segment', () {
      // `lastOrNull` over non-empty parts → 应该忽略尾部空字符串
      expect(
        buildJobSubtitle(_job(
          sourceUrl: 'svn://example/repo/trunk',
          targetWc: '/Users/dev/projects/app-wc/',
        )),
        'trunk -> app-wc',
      );
    });

    test('falls back to original targetWc when no non-empty segment', () {
      // 全空：例如 "/" 切分后全是空串
      expect(
        buildJobSubtitle(_job(
          sourceUrl: 'svn://x/y',
          targetWc: '/',
        )),
        'y -> /',
      );
    });

    test('handles sourceUrl without slashes', () {
      expect(
        buildJobSubtitle(_job(
          sourceUrl: 'lone-name',
          targetWc: '/tmp/wc',
        )),
        'lone-name -> wc',
      );
    });
  });

  group('jobStatusColor', () {
    test('covers all JobStatus values', () {
      expect(jobStatusColor(JobStatus.pending), Colors.blueGrey);
      expect(jobStatusColor(JobStatus.running), Colors.blue);
      expect(jobStatusColor(JobStatus.paused), Colors.orange);
      expect(jobStatusColor(JobStatus.done), Colors.green);
      expect(jobStatusColor(JobStatus.failed), Colors.red);
    });

    test('R95 防漏配：JobStatus.values.length == 5（新增 enum 时强制 review）', () {
      // 与 executorStatusIsBusy / snapshotStatusText 等 group 的"防漏配"契约同款：
      // helper 的 exhaustive switch 在新增 enum 时会编译报错强迫加 case，但本断言锁住
      // 测试自身的"covers all"宣称——避免新增 enum 后测试通过却没人 review 颜色映射。
      expect(JobStatus.values.length, 5,
          reason: '当 JobStatus 新增枚举值时本测会红，强制 review jobStatusColor 的颜色映射');
    });
  });

  group('jobErrorMessageColor', () {
    test('failed → red.shade700', () {
      expect(jobErrorMessageColor(JobStatus.failed), Colors.red.shade700);
    });

    test('其它状态（实际只剩 paused 会带 error 文案）→ orange.shade700', () {
      // 锁住语义：只有 failed 显示红色，其它一律橙色——避免未来有人手抖加成 red
      // 让 paused（可恢复）看起来跟 failed（终结）一样严重。
      expect(jobErrorMessageColor(JobStatus.paused), Colors.orange.shade700);
      expect(jobErrorMessageColor(JobStatus.pending), Colors.orange.shade700);
      expect(jobErrorMessageColor(JobStatus.running), Colors.orange.shade700);
      expect(jobErrorMessageColor(JobStatus.done), Colors.orange.shade700);
    });

    test('R95 防漏配：JobStatus.values.length == 5（新增 enum 时强制 review）', () {
      // 新增 enum 时不仅要确认颜色，还要决定语义——是终结失败（红）还是可恢复（橙）。
      // 二元分类是本 helper 的核心契约，新值若错配会直接误导用户严重程度感知。
      expect(JobStatus.values.length, 5,
          reason:
              '当 JobStatus 新增枚举值时本测会红，强制 review jobErrorMessageColor 的红/橙二元分类');
    });
  });

  group('computeJobProgressRatio', () {
    test('空 revisions → 0.0（避免除零）', () {
      expect(computeJobProgressRatio(_job(revisions: [])), 0.0);
    });

    test('未完 → completed/total', () {
      expect(
        computeJobProgressRatio(
          _job(revisions: [100, 101, 102, 103], completedIndex: 1),
        ),
        0.25,
      );
    });

    test('全完 → 1.0', () {
      expect(
        computeJobProgressRatio(
          _job(revisions: [100, 101], completedIndex: 2),
        ),
        1.0,
      );
    });

    test('completedIndex 越界（>len）→ clamp 到 len，比例 = 1.0', () {
      expect(
        computeJobProgressRatio(
          _job(revisions: [100, 101], completedIndex: 5),
        ),
        1.0,
      );
    });

    test('completedIndex 负数 → clamp 到 0，比例 = 0.0', () {
      expect(
        computeJobProgressRatio(
          _job(revisions: [100, 101], completedIndex: -3),
        ),
        0.0,
      );
    });

    test('与 formatJobProgress 共享同一 clamp 约定（同一 job 给出一致的 N/M）', () {
      final job = _job(revisions: [100, 101, 102], completedIndex: 5);
      // formatJobProgress: '3/3'；computeJobProgressRatio: 3/3 = 1.0
      expect(formatJobProgress(job), '3/3');
      expect(computeJobProgressRatio(job), 1.0);
    });
  });

  group('partitionJobsForQueuePanel', () {
    test('空入参 → 三个空 list', () {
      final s = partitionJobsForQueuePanel([]);
      expect(s.queueJobs, isEmpty);
      expect(s.pendingJobs, isEmpty);
      expect(s.recentJobs, isEmpty);
    });

    test('全 active → queueJobs == 全部，recentJobs 空', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.pending),
        _job(jobId: 2, status: JobStatus.running),
        _job(jobId: 3, status: JobStatus.paused),
      ];
      final s = partitionJobsForQueuePanel(jobs);
      expect(s.queueJobs.map((j) => j.jobId).toList(), [1, 2, 3]);
      expect(s.pendingJobs.map((j) => j.jobId).toList(), [1]);
      expect(s.recentJobs, isEmpty);
    });

    test('全 finished → recentJobs 倒序，queueJobs/pending 都空', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.done),
        _job(jobId: 2, status: JobStatus.failed),
        _job(jobId: 3, status: JobStatus.done),
      ];
      final s = partitionJobsForQueuePanel(jobs);
      expect(s.queueJobs, isEmpty);
      expect(s.pendingJobs, isEmpty);
      // reversed → 后入先出
      expect(s.recentJobs.map((j) => j.jobId).toList(), [3, 2, 1]);
    });

    test('recentLimit 截断（默认 6）：只保留最近 N 条 finished', () {
      final jobs = List<MergeJob>.generate(
        10,
        (i) => _job(jobId: i + 1, status: JobStatus.done),
      );
      final s = partitionJobsForQueuePanel(jobs);
      expect(s.recentJobs.length, 6);
      // 最近优先：jobId 10..5
      expect(
        s.recentJobs.map((j) => j.jobId).toList(),
        [10, 9, 8, 7, 6, 5],
      );
    });

    test('recentLimit 自定义：可显式指定上限', () {
      final jobs = List<MergeJob>.generate(
        5,
        (i) => _job(jobId: i + 1, status: JobStatus.done),
      );
      final s = partitionJobsForQueuePanel(jobs, recentLimit: 2);
      expect(s.recentJobs.map((j) => j.jobId).toList(), [5, 4]);
    });

    test('recentLimit <= 0 → recentJobs 为空（不展示最近结果）', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.done),
        _job(jobId: 2, status: JobStatus.failed),
      ];
      expect(
        partitionJobsForQueuePanel(jobs, recentLimit: 0).recentJobs,
        isEmpty,
      );
      expect(
        partitionJobsForQueuePanel(jobs, recentLimit: -3).recentJobs,
        isEmpty,
      );
    });

    test('混合输入：分桶顺序保持 + finished 倒序 + pending 子集筛选', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.done),
        _job(jobId: 2, status: JobStatus.pending),
        _job(jobId: 3, status: JobStatus.failed),
        _job(jobId: 4, status: JobStatus.running),
        _job(jobId: 5, status: JobStatus.pending),
        _job(jobId: 6, status: JobStatus.done),
      ];
      final s = partitionJobsForQueuePanel(jobs);
      // queueJobs: pending/running/paused，按入参顺序
      expect(s.queueJobs.map((j) => j.jobId).toList(), [2, 4, 5]);
      // pendingJobs: 仅 pending
      expect(s.pendingJobs.map((j) => j.jobId).toList(), [2, 5]);
      // recentJobs: done/failed，倒序
      expect(s.recentJobs.map((j) => j.jobId).toList(), [6, 3, 1]);
    });

    test('不修改入参', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.done),
        _job(jobId: 2, status: JobStatus.pending),
      ];
      final snapshot = List<MergeJob>.from(jobs);
      partitionJobsForQueuePanel(jobs);
      expect(jobs.map((j) => j.jobId).toList(),
          snapshot.map((j) => j.jobId).toList());
    });

    test('kJobQueuePanelDefaultRecentLimit 与 widget 历史 magic number 一致', () {
      // widget 内联 take(6)，常量用来 lock 这个值（未来如果改成 8/10，应同步改 widget
      // 行为而不是只改一处）。
      expect(kJobQueuePanelDefaultRecentLimit, 6);
    });
  });

  group('formatJobOverviewCounts', () {
    test('正常态：半角斜杠 + 空格分隔', () {
      expect(formatJobOverviewCounts(3, 5), '3 队列中 / 5 最近结果');
    });

    test('双 0 → "0 队列中 / 0 最近结果"（不显示占位/隐藏）', () {
      expect(formatJobOverviewCounts(0, 0), '0 队列中 / 0 最近结果');
    });

    test('大数字也照常拼接，不做千分位 / 截断', () {
      expect(formatJobOverviewCounts(123456, 7890), '123456 队列中 / 7890 最近结果');
    });

    test('使用半角斜杠（防止误改成全角"／"或" - "等其他分隔符）', () {
      final result = formatJobOverviewCounts(1, 2);
      expect(result.contains(' / '), isTrue);
      expect(result.contains('／'), isFalse);
      expect(result.contains(' - '), isFalse);
    });
  });

  group('formatJobOverviewBreakdown', () {
    test('双空 → 空字符串（caller 用 isEmpty 判断不渲染 tooltip）', () {
      expect(
        formatJobOverviewBreakdown(queueJobs: const [], recentJobs: const []),
        '',
      );
    });

    test('队列段：按 pending/running/paused 顺序，零计数省略', () {
      final queueJobs = [
        _job(jobId: 1, status: JobStatus.paused),
        _job(jobId: 2, status: JobStatus.pending),
        _job(jobId: 3, status: JobStatus.pending),
      ];
      final s = formatJobOverviewBreakdown(
        queueJobs: queueJobs,
        recentJobs: const [],
      );
      // 顺序固定：pending 在前 / running 零 → 省略 / paused 在后
      expect(s, '队列中: 等待 2 / 已暂停 1');
    });

    test('最近段：按 done/failed 顺序，零计数省略', () {
      final recentJobs = [
        _job(jobId: 1, status: JobStatus.failed),
        _job(jobId: 2, status: JobStatus.failed),
        _job(jobId: 3, status: JobStatus.done),
      ];
      final s = formatJobOverviewBreakdown(
        queueJobs: const [],
        recentJobs: recentJobs,
      );
      expect(s, '最近结果: 完成 1 / 失败 2');
    });

    test('两段都有 → 用 "\\n" 分隔', () {
      final queueJobs = [_job(jobId: 1, status: JobStatus.running)];
      final recentJobs = [_job(jobId: 2, status: JobStatus.done)];
      final s = formatJobOverviewBreakdown(
        queueJobs: queueJobs,
        recentJobs: recentJobs,
      );
      expect(s, '队列中: 执行中 1\n最近结果: 完成 1');
    });

    test('空段省略：不出现 "队列中: " / "最近结果: " 这种 trailing 空尾', () {
      // 只有最近段
      final s1 = formatJobOverviewBreakdown(
        queueJobs: const [],
        recentJobs: [_job(jobId: 1, status: JobStatus.done)],
      );
      expect(s1, '最近结果: 完成 1');
      expect(s1.contains('队列中:'), isFalse);
      // 只有队列段
      final s2 = formatJobOverviewBreakdown(
        queueJobs: [_job(jobId: 1, status: JobStatus.pending)],
        recentJobs: const [],
      );
      expect(s2, '队列中: 等待 1');
      expect(s2.contains('最近结果:'), isFalse);
    });

    test('全 active 5 个 → 队列段 3 子项 / 最近段省略', () {
      final queueJobs = [
        _job(jobId: 1, status: JobStatus.pending),
        _job(jobId: 2, status: JobStatus.pending),
        _job(jobId: 3, status: JobStatus.running),
        _job(jobId: 4, status: JobStatus.paused),
        _job(jobId: 5, status: JobStatus.paused),
      ];
      final s = formatJobOverviewBreakdown(
        queueJobs: queueJobs,
        recentJobs: const [],
      );
      expect(s, '队列中: 等待 2 / 执行中 1 / 已暂停 2');
    });

    test('使用半角斜杠 + 空格分隔，与 formatJobOverviewCounts 同款', () {
      final queueJobs = [
        _job(jobId: 1, status: JobStatus.pending),
        _job(jobId: 2, status: JobStatus.running),
      ];
      final s = formatJobOverviewBreakdown(
        queueJobs: queueJobs,
        recentJobs: const [],
      );
      expect(s.contains(' / '), isTrue);
      expect(s.contains('／'), isFalse);
    });
  });

  group('formatJobRevisionList', () {
    test('正常态：每个 r 前缀 + ", " 分隔，整体前缀 "revision: "', () {
      expect(
          formatJobRevisionList([100, 101, 102]), 'revision: r100, r101, r102');
    });

    test('单条：仅一个 r 前缀，无逗号', () {
      expect(formatJobRevisionList([42]), 'revision: r42');
    });

    test('空 list → "revision: "（trailing 空，不附加占位）', () {
      // 原 inline 行为：widget 层用 maxLines + ellipsis 处理过宽，但空 list 在原代码里
      // 实际不会发生（caller 保证非空）；本条显式锁定降级行为，避免日后有人加上
      // "(无)" 占位破坏与已有 widget tree 的契约。
      expect(formatJobRevisionList(const []), 'revision: ');
    });

    test('保留 caller 顺序，不做排序 / 去重', () {
      expect(
        formatJobRevisionList([3, 1, 2, 1, 3]),
        'revision: r3, r1, r2, r1, r3',
      );
    });

    test('使用半角冒号 + 半角逗号（防止误改成全角"："或"，"）', () {
      final result = formatJobRevisionList([1, 2]);
      expect(result.startsWith('revision: '), isTrue);
      expect(result.contains('，'), isFalse);
      expect(result.contains('：'), isFalse);
    });

    // R92 等价锁定：`formatJobRevisionList` 内部 delegate 到 `formatRevisionListShort`
    //（merge_job.dart）—— `formatJobRevisionList(revs) == 'revision: ' + formatRevisionListShort(revs)`
    // 永远成立。在 5 个角点（空 / 单元素 / 多元素 / 重复 / 负数）上断言关系，
    // 防御未来"为优化把内联逻辑搬回来"的回退操作。
    test(
        'R92 等价：formatJobRevisionList = "revision: " + formatRevisionListShort',
        () {
      final cases = <List<int>>[
        const [],
        [42],
        [100, 101, 102],
        [3, 1, 2, 1, 3],
        [-1, -2],
      ];
      for (final revs in cases) {
        expect(
          formatJobRevisionList(revs),
          'revision: ${formatRevisionListShort(revs)}',
          reason: 'revs=$revs 时 outer 应等于 "revision: " + inner',
        );
      }
    });
  });

  group('JobCardActionSpec', () {
    test('值相等性（kind / icon / tooltip 全相同）', () {
      const a = JobCardActionSpec(
        kind: JobCardActionKind.requeue,
        icon: Icons.refresh,
        tooltip: '重新加入剩余 revision',
      );
      const b = JobCardActionSpec(
        kind: JobCardActionKind.requeue,
        icon: Icons.refresh,
        tooltip: '重新加入剩余 revision',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('kind 不同 → 不等', () {
      const a = JobCardActionSpec(
        kind: JobCardActionKind.requeue,
        icon: Icons.delete_outline,
        tooltip: 'X',
      );
      const b = JobCardActionSpec(
        kind: JobCardActionKind.delete,
        icon: Icons.delete_outline,
        tooltip: 'X',
      );
      expect(a == b, isFalse);
    });

    test('tooltip 不同 → 不等', () {
      const a = JobCardActionSpec(
        kind: JobCardActionKind.delete,
        icon: Icons.delete_outline,
        tooltip: '移除任务',
      );
      const b = JobCardActionSpec(
        kind: JobCardActionKind.delete,
        icon: Icons.delete_outline,
        tooltip: '删除记录',
      );
      expect(a == b, isFalse);
    });

    test('toString 含 kind 与 tooltip（便于日志排查）', () {
      const spec = JobCardActionSpec(
        kind: JobCardActionKind.delete,
        icon: Icons.delete_outline,
        tooltip: '移除任务',
      );
      final str = spec.toString();
      expect(str.contains('delete'), isTrue);
      expect(str.contains('移除任务'), isTrue);
    });
  });

  group('jobCardActionSpecs', () {
    test('failed + 仍有剩余 + 两个 callback 都有 → [requeue, delete]', () {
      final job = _job(status: JobStatus.failed, completedIndex: 1);
      // canRequeueRemaining = failed && remainingRevisions.isNotEmpty (2 remain)
      expect(job.canRequeueRemaining, isTrue, reason: 'fixture 前置条件');
      expect(job.canDelete, isTrue, reason: 'fixture 前置条件');
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: true,
      );
      expect(specs.map((s) => s.kind).toList(),
          [JobCardActionKind.requeue, JobCardActionKind.delete]);
    });

    test('顺序固定：requeue 在 delete 之前（积极操作优先）', () {
      // 显式以 reverse-order 命名表达，防止有人改成字母序时不察觉
      final job = _job(status: JobStatus.failed, completedIndex: 1);
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: true,
      );
      expect(specs.first.kind, JobCardActionKind.requeue);
      expect(specs.last.kind, JobCardActionKind.delete);
    });

    test('hasRequeueCallback==false → 即使 canRequeueRemaining 也不出现 requeue', () {
      final job = _job(status: JobStatus.failed, completedIndex: 1);
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: false,
        hasDeleteCallback: true,
      );
      expect(specs.map((s) => s.kind).toList(), [JobCardActionKind.delete]);
    });

    test('hasDeleteCallback==false → 即使 canDelete 也不出现 delete', () {
      final job = _job(status: JobStatus.failed, completedIndex: 1);
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: false,
      );
      expect(specs.map((s) => s.kind).toList(), [JobCardActionKind.requeue]);
    });

    test('running → 既不能 requeue（不是 failed）也不能 delete', () {
      final job = _job(status: JobStatus.running);
      expect(job.canRequeueRemaining, isFalse, reason: 'fixture 前置条件');
      expect(job.canDelete, isFalse, reason: 'fixture 前置条件');
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: true,
      );
      expect(specs, isEmpty);
    });

    test('paused → canDelete==false（避免删除正在等人处理的任务）', () {
      final job = _job(status: JobStatus.paused);
      expect(job.canDelete, isFalse, reason: 'fixture 前置条件');
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: true,
      );
      expect(specs, isEmpty);
    });

    test('pending → delete tooltip 为 "移除任务"（语义：还没开始，从队列拿掉）', () {
      final job = _job(status: JobStatus.pending);
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: true,
      );
      expect(specs.length, 1);
      expect(specs.first.kind, JobCardActionKind.delete);
      expect(specs.first.tooltip, '移除任务');
    });

    test('done → delete tooltip 为 "删除记录"（语义：已完成，清理历史）', () {
      final job = _job(status: JobStatus.done);
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: true,
      );
      expect(specs.length, 1);
      expect(specs.first.kind, JobCardActionKind.delete);
      expect(specs.first.tooltip, '删除记录');
    });

    test('failed + 全部 revision 已完成 → canRequeueRemaining==false', () {
      // 前置：completedIndex >= revisions.length 时 remainingRevisions 为空
      final job = _job(
        status: JobStatus.failed,
        revisions: [100],
        completedIndex: 1,
      );
      expect(job.canRequeueRemaining, isFalse, reason: 'fixture 前置条件');
      final specs = jobCardActionSpecs(
        job: job,
        hasRequeueCallback: true,
        hasDeleteCallback: true,
      );
      // failed 仍可 delete，故只剩 delete
      expect(specs.map((s) => s.kind).toList(), [JobCardActionKind.delete]);
      expect(specs.first.tooltip, '删除记录');
    });

    test('全部 JobStatus.values 真值表覆盖（防漏配 enum）', () {
      // 与 Round 56/57 同款"防漏配 enum"契约：未来若 JobStatus 新增枚举值，
      // 本测会因 length 不再 == 5 而红，强制 review jobCardActionSpecs 的覆盖。
      expect(
        JobStatus.values.length,
        5,
        reason: '当 JobStatus 新增枚举值时本测会红，强制 review jobCardActionSpecs',
      );
      // 用 fixture 默认 revisions/completedIndex（仍有剩余），逐个 status 算 spec：
      final specsByStatus = {
        for (final s in JobStatus.values)
          s: jobCardActionSpecs(
            job: _job(status: s),
            hasRequeueCallback: true,
            hasDeleteCallback: true,
          ).map((spec) => spec.kind).toList(),
      };
      expect(specsByStatus[JobStatus.pending], [JobCardActionKind.delete]);
      expect(specsByStatus[JobStatus.running], <JobCardActionKind>[]);
      expect(specsByStatus[JobStatus.paused], <JobCardActionKind>[]);
      expect(specsByStatus[JobStatus.done], [JobCardActionKind.delete]);
      // failed + 默认 fixture 仍有剩余 → requeue + delete
      expect(specsByStatus[JobStatus.failed],
          [JobCardActionKind.requeue, JobCardActionKind.delete]);
    });
  });

  group('JobCardActionSpec == / hashCode 对称性（R103）', () {
    const baseline = JobCardActionSpec(
      kind: JobCardActionKind.requeue,
      icon: Icons.replay,
      tooltip: 'TT',
    );

    test('全字段相同 → 相等 + hashCode 一致', () {
      const a = JobCardActionSpec(
        kind: JobCardActionKind.requeue,
        icon: Icons.replay,
        tooltip: 'TT',
      );
      expect(a, equals(baseline));
      expect(a.hashCode, baseline.hashCode);
    });

    test('任一字段不等 → != + Set 去重正确（3 字段对称性矩阵）', () {
      const diffKind = JobCardActionSpec(
        kind: JobCardActionKind.delete,
        icon: Icons.replay,
        tooltip: 'TT',
      );
      const diffIcon = JobCardActionSpec(
        kind: JobCardActionKind.requeue,
        icon: Icons.delete,
        tooltip: 'TT',
      );
      const diffTooltip = JobCardActionSpec(
        kind: JobCardActionKind.requeue,
        icon: Icons.replay,
        tooltip: 'TT2',
      );
      for (final v in [diffKind, diffIcon, diffTooltip]) {
        expect(v, isNot(equals(baseline)));
      }
      final s = <JobCardActionSpec>{baseline, diffKind, diffIcon, diffTooltip};
      expect(s.length, 4, reason: '3 字段对称性矩阵：每字段独立修改都应让 Set 多 1 元素');
    });

    test('R103 防漏配 .length guard：JobCardActionKind.values.length == 2', () {
      // 新增 kind 时强制 review 上面 3 字段对称性测试是否覆盖；
      // 目前 kind 是 enum，新值会改变 baseline 的 == 行为
      expect(JobCardActionKind.values.length, 2,
          reason: '新增 JobCardActionKind 时同步扩展上面对称性矩阵的 diffKind 候选');
    });
  });

  group('failureKindForJob', () {
    test('非 paused/failed 任务 → unknown（不参与分类）', () {
      // 与 _buildFailureKindChip 渲染契约对齐：pending/running/done 不应出现 chip。
      for (final s in [JobStatus.pending, JobStatus.running, JobStatus.done]) {
        expect(
          failureKindForJob(_job(
            status: s,
            error: 'svn: E170001: Authentication failed',
            pauseReason: 'Connection refused',
          )),
          SvnFailureKind.unknown,
          reason: 'status=$s 时即使 error/pauseReason 含分类关键词也应忽略',
        );
      }
    });

    test('paused 任务：error 优先于 pauseReason', () {
      // error 是步骤抛出的具体错误正文（信息更精确），优先级高于 pauseReason。
      expect(
        failureKindForJob(_job(
          status: JobStatus.paused,
          error: 'svn: E195020: Tree conflict in foo',
          pauseReason: 'Connection refused',
        )),
        SvnFailureKind.treeConflict,
      );
    });

    test('paused 任务：error 为空 → 用 pauseReason 兜底', () {
      // 中断恢复路径：error 字段可能为空，这时 pauseReason 是分类的唯一线索。
      expect(
        failureKindForJob(_job(
          status: JobStatus.paused,
          error: '',
          pauseReason: 'svn: E170001: Authentication failed',
        )),
        SvnFailureKind.authFailed,
      );
    });

    test('failed 任务：分类逻辑同 paused', () {
      expect(
        failureKindForJob(_job(
          status: JobStatus.failed,
          error: 'Connection refused: server',
        )),
        SvnFailureKind.network,
      );
    });

    test('paused/failed 但 error 与 pauseReason 都为空 → unknown', () {
      expect(
        failureKindForJob(_job(status: JobStatus.paused)),
        SvnFailureKind.unknown,
      );
      expect(
        failureKindForJob(_job(status: JobStatus.failed)),
        SvnFailureKind.unknown,
      );
    });
  });

  group('visibleFailureKindForJob', () {
    test('unknown → null（caller 用 null 判断不渲染 chip）', () {
      expect(visibleFailureKindForJob(_job(status: JobStatus.pending)), isNull);
      expect(visibleFailureKindForJob(_job(status: JobStatus.paused)), isNull,
          reason: '空 error/pauseReason → unknown → null');
    });

    test('已识别分类 → 直接返回 kind', () {
      expect(
        visibleFailureKindForJob(_job(
          status: JobStatus.failed,
          error: 'svn: E160028: Out of date',
        )),
        SvnFailureKind.outOfDate,
      );
    });

    test('R95 防漏配：JobStatus.values.length == 5（新增 enum 时强制 review）', () {
      // 新增 JobStatus 时必须决定它是否参与 failureKind 分类——
      // running 中也可能短暂含 SVN 失败，但当前契约是只有 paused/failed 才有意义。
      expect(JobStatus.values.length, 5,
          reason: '新增 JobStatus 时 review failureKindForJob 的状态白名单');
    });
  });

  group('bucketFailureKinds', () {
    test('空 jobs → 空 map', () {
      expect(bucketFailureKinds(const []), isEmpty);
    });

    test('仅 pending/running/done → 空 map（不参与分类）', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.pending, error: 'svn: E170001'),
        _job(jobId: 2, status: JobStatus.running, error: 'Connection refused'),
        _job(jobId: 3, status: JobStatus.done, error: 'svn: E195020'),
      ];
      expect(bucketFailureKinds(jobs), isEmpty);
    });

    test('paused/failed 但 unknown → 排除', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.paused),
        _job(jobId: 2, status: JobStatus.failed, error: '   '),
      ];
      expect(bucketFailureKinds(jobs), isEmpty);
    });

    test('混合：仅 paused + failed 的已识别分类计数', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'svn: E170001 auth'),
        _job(jobId: 2, status: JobStatus.paused, error: 'svn: E170001'),
        _job(
          jobId: 3,
          status: JobStatus.failed,
          error: 'Connection refused: server',
        ),
        _job(jobId: 4, status: JobStatus.done, error: 'svn: E170001'),
        _job(jobId: 5, status: JobStatus.pending),
      ];
      final m = bucketFailureKinds(jobs);
      expect(m[SvnFailureKind.authFailed], 2);
      expect(m[SvnFailureKind.network], 1);
      expect(m.length, 2);
    });

    test('不修改入参', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'svn: E170001'),
      ];
      final ids = jobs.map((j) => j.jobId).toList();
      bucketFailureKinds(jobs);
      expect(jobs.map((j) => j.jobId).toList(), ids);
    });
  });

  group('orderedFailureKindBuckets', () {
    test('空 jobs → 空列表', () {
      expect(orderedFailureKindBuckets(const []), isEmpty);
    });

    test('severity 降序：severe 在前（即使 count 更少）', () {
      // authFailed = severe；treeConflict = normal
      // 让 normal 的 count 更高，验证 severity 优先于 count
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'tree conflict'),
        _job(jobId: 2, status: JobStatus.failed, error: 'tree conflict'),
        _job(jobId: 3, status: JobStatus.failed, error: 'svn: E170001'),
      ];
      final ordered = orderedFailureKindBuckets(jobs);
      expect(ordered.first.key, SvnFailureKind.authFailed,
          reason: 'severe 永远在 normal 之前');
      expect(ordered.first.value, 1);
      expect(ordered.last.key, SvnFailureKind.treeConflict);
      expect(ordered.last.value, 2);
    });

    test('同 severity 内：count 降序', () {
      // network + authFailed 都是 severe；let authFailed=3, network=1
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'svn: E170001'),
        _job(jobId: 2, status: JobStatus.failed, error: 'svn: E170001'),
        _job(jobId: 3, status: JobStatus.failed, error: 'svn: E170001'),
        _job(jobId: 4, status: JobStatus.failed, error: 'Connection refused'),
      ];
      final ordered = orderedFailureKindBuckets(jobs);
      expect(ordered.map((e) => e.key).toList(),
          [SvnFailureKind.authFailed, SvnFailureKind.network]);
      expect(ordered.map((e) => e.value).toList(), [3, 1]);
    });

    test('同 severity + 同 count → 按 enum 声明序', () {
      // treeConflict (index 0) 与 textConflict (index 1) 都 normal、count 相同
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'tree conflict'),
        _job(jobId: 2, status: JobStatus.failed, error: 'text conflict'),
      ];
      final ordered = orderedFailureKindBuckets(jobs);
      expect(ordered.map((e) => e.key).toList(),
          [SvnFailureKind.treeConflict, SvnFailureKind.textConflict],
          reason: 'enum 声明序：treeConflict (0) < textConflict (1)');
    });

    test('排序稳定：多次调用结果一致', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.paused, error: 'svn: E170001'),
        _job(jobId: 2, status: JobStatus.failed, error: 'tree conflict'),
        _job(jobId: 3, status: JobStatus.failed, error: 'Connection refused'),
        _job(jobId: 4, status: JobStatus.paused, error: 'svn: E155004 locked'),
      ];
      final a = orderedFailureKindBuckets(jobs).map((e) => e.key).toList();
      final b = orderedFailureKindBuckets(jobs).map((e) => e.key).toList();
      expect(a, b);
    });
  });

  group('formatFailureBucketTooltip', () {
    // Step 18：header bucket chip 的 hover tooltip 要在 hint 之外把"这个 ×N 计数
    // 命中的所有 jobIds"还原出来。聚合数字 → 元素列表的 dual-encode（与 Step 12
    // 进度行三段拆分同源）。

    test('单个 jobId 命中也输出"包含任务: #N"', () {
      final jobs = [
        _job(jobId: 7, status: JobStatus.failed, error: 'svn: E170001'),
      ];
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.authFailed, jobs),
        '$hint\n包含任务: #7',
      );
    });

    test('多个 jobId 命中：jobIds 用 ", " 分隔，保持入参顺序', () {
      final jobs = [
        _job(jobId: 11, status: JobStatus.failed, error: 'svn: E170001'),
        _job(
            jobId: 3, status: JobStatus.paused, error: 'authentication failed'),
        _job(jobId: 99, status: JobStatus.failed, error: 'svn: E170001'),
      ];
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.authFailed, jobs),
        '$hint\n包含任务: #11, #3, #99',
        reason: 'jobIds 顺序与入参 jobs 相对顺序一致，不排序',
      );
    });

    test('过滤命中：只列出 visibleFailureKindForJob == kind 的任务', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'svn: E170001'),
        _job(jobId: 2, status: JobStatus.failed, error: 'tree conflict'),
        _job(jobId: 3, status: JobStatus.failed, error: 'Connection refused'),
        _job(jobId: 4, status: JobStatus.failed, error: 'svn: E170001'),
      ];
      final authHint = presentationFor(SvnFailureKind.authFailed).hint;
      final treeHint = presentationFor(SvnFailureKind.treeConflict).hint;
      final netHint = presentationFor(SvnFailureKind.network).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.authFailed, jobs),
        '$authHint\n包含任务: #1, #4',
      );
      expect(
        formatFailureBucketTooltip(SvnFailureKind.treeConflict, jobs),
        '$treeHint\n包含任务: #2',
      );
      expect(
        formatFailureBucketTooltip(SvnFailureKind.network, jobs),
        '$netHint\n包含任务: #3',
      );
    });

    test('jobs 中无任何任务命中 kind → 仅返回 hint', () {
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'tree conflict'),
      ];
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.authFailed, jobs),
        hint,
        reason: '无命中时仅返回 hint，避免 "<hint>\\n包含任务: " 尾巴空白',
      );
    });

    test('jobs 为空 → 仅返回 hint', () {
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.authFailed, const []),
        hint,
      );
    });

    test('paused/failed 之外的状态不参与命中（与 visibleFailureKindForJob 对齐）', () {
      // running 状态即便 error 非空也不归类（pending/running/done 没有失败上下文）
      final jobs = [
        _job(jobId: 1, status: JobStatus.running, error: 'svn: E170001'),
        _job(jobId: 2, status: JobStatus.done, error: 'svn: E170001'),
        _job(jobId: 3, status: JobStatus.failed, error: 'svn: E170001'),
      ];
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.authFailed, jobs),
        '$hint\n包含任务: #3',
      );
    });

    test('paused 也参与命中（与 failureKindForJob 状态白名单对齐）', () {
      final jobs = [
        _job(jobId: 5, status: JobStatus.paused, error: 'svn: E170001'),
        _job(
            jobId: 6,
            status: JobStatus.paused,
            pauseReason: 'authentication failed'),
      ];
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.authFailed, jobs),
        '$hint\n包含任务: #5, #6',
      );
    });

    test(
        'SvnFailureKind.unknown：与 visibleFailureKindForJob 同源——unknown 被滤掉，仅返回 hint',
        () {
      // 此 helper 用 visibleFailureKindForJob 过滤（unknown → null），所以
      // 即便强行用 unknown 调用，命中列表也始终为空，仅返回 hint。
      // caller（顶部 bucket chip）只会对 orderedFailureKindBuckets 已经排除
      // unknown 后的 kinds 调用，所以这条路径在 production 不会被命中——
      // 此测验证"防御性输入下行为安全（不抛、不夹假命中）"。
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed),
        _job(jobId: 2, status: JobStatus.failed, error: 'svn: E170001'),
      ];
      final hint = presentationFor(SvnFailureKind.unknown).hint;
      expect(
        formatFailureBucketTooltip(SvnFailureKind.unknown, jobs),
        hint,
        reason:
            'visibleFailureKindForJob 把 unknown 映成 null，本 helper 不会命中任何 jobId',
      );
    });
  });

  group('formatFailureKindChipTooltip（Step 25 - 第二十一层 hover）', () {
    // 第二轮回访 job_queue_panel.dart 维度。per-card failureKind chip 自 R159 起一直只展示
    // hint；当 job.error.isEmpty && job.pauseReason.isNotEmpty 时（典型 paused 任务），
    // 用户没有任何路径能看到触发分类的 pauseReason 正文——仅 hint 是泛化建议。
    // 本 helper 在该档位 dual-encode pauseReason；error 非空时仅 hint（dedup with
    // formatJobErrorTooltip 已经在错误行 hover 还原 error 正文）。

    test('error 非空 → 仅 hint（dedup with formatJobErrorTooltip）', () {
      final job = _job(
        jobId: 1,
        status: JobStatus.failed,
        error: 'svn: E170001 Authentication failed',
      );
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureKindChipTooltip(job, SvnFailureKind.authFailed),
        hint,
        reason: 'error 非空时错误行 + formatJobErrorTooltip 已 dual-encode error 正文，'
            'chip tooltip 不重复——仅 hint',
      );
    });

    test('error 非空 + pauseReason 也非空 → 仍仅 hint（error 优先级更高）', () {
      // 即便 pauseReason 也非空，只要 error 非空，错误行就会渲染并 dual-encode error；
      // chip tooltip 仍走 hint-only 分支不重复。
      final job = _job(
        jobId: 1,
        status: JobStatus.failed,
        error: 'svn: E170001',
        pauseReason: 'previous pause reason text',
      );
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureKindChipTooltip(job, SvnFailureKind.authFailed),
        hint,
      );
    });

    test('error 为空 + pauseReason 非空 → "hint\\n暂停原因: <reason>"（核心档位）', () {
      // 典型 paused 任务：error 为空，pauseReason 携带触发分类的文本。
      // chip tooltip 是 widget 树里唯一能展示 pauseReason 的载体。
      final job = _job(
        jobId: 1,
        status: JobStatus.paused,
        pauseReason: 'svn: E170001 Authentication failed against repo',
      );
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      expect(
        formatFailureKindChipTooltip(job, SvnFailureKind.authFailed),
        '$hint\n暂停原因: svn: E170001 Authentication failed against repo',
      );
    });

    test('error 与 pauseReason 都为空 → 仅 hint（兜底）', () {
      // 理论上 chip 不应在此档位渲染（visibleFailureKindForJob → null），
      // 但 helper 不依赖该不变量，独立兜底返回 hint。
      final job = _job(jobId: 1, status: JobStatus.failed);
      final hint = presentationFor(SvnFailureKind.unknown).hint;
      expect(
        formatFailureKindChipTooltip(job, SvnFailureKind.unknown),
        hint,
      );
    });

    test('多行 pauseReason 原样保留（不 trim 末尾换行）', () {
      // pauseReason 来自 MergeJob.pauseReason，已经是 trim 后的字符串
      // （normalizePauseReason 已 trim），但内部多行换行会保留——chip tooltip 不再 trim。
      final job = _job(
        jobId: 2,
        status: JobStatus.paused,
        pauseReason: 'line1\nline2',
      );
      final hint = presentationFor(SvnFailureKind.network).hint;
      expect(
        formatFailureKindChipTooltip(job, SvnFailureKind.network),
        '$hint\n暂停原因: line1\nline2',
      );
    });

    testWidgets(
        'per-card chip widget 在 paused + 仅 pauseReason 档位 hover 显示完整 tooltip',
        (tester) async {
      // 集成测试：widget 树里 chip 的 Tooltip.message 必须等于 helper 输出
      final job = _job(
        jobId: 7,
        status: JobStatus.paused,
        error: '',
        pauseReason: 'svn: E155004 working copy is locked',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: [job])),
        ),
      );
      final hint = presentationFor(SvnFailureKind.locked).hint;
      final expected = '$hint\n暂停原因: svn: E155004 working copy is locked';
      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(
        messages.contains(expected),
        isTrue,
        reason:
            'per-card chip Tooltip.message 应包含 pauseReason 段，messages=$messages',
      );
    });

    testWidgets(
        'per-card chip widget 在 failed + error 档位 hover 仅显示 hint（dedup）',
        (tester) async {
      // 与 'failureKind chip 的 Tooltip hover' group 的 'per-card chip 包 Tooltip(message=hint)'
      // 测试形成对偶：error 非空时 chip 维持纯 hint，不会被 Step 25 改坏（防回归）。
      final job = _job(
        jobId: 1,
        status: JobStatus.failed,
        error: 'svn: E170001 Authentication failed',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: [job])),
        ),
      );
      final hint = presentationFor(SvnFailureKind.authFailed).hint;
      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      // chip Tooltip == hint
      expect(messages.contains(hint), isTrue);
      // 不应有任何 message 含 "暂停原因:" 字样
      expect(
        messages.any((m) => m != null && m.contains('暂停原因:')),
        isFalse,
        reason: 'error 非空时 chip tooltip 不应附 pauseReason 段',
      );
    });
  });

  group('failureKind chip 的 Tooltip hover', () {
    // Step 7：两类 chip（per-card + header bucket）都包了一层 Tooltip(message: hint)，
    // 让用户 hover 时不展开详情就能看到 presentationFor(kind).hint 的操作建议。
    // hint 文本由 svn_failure_kind.dart 决定，这里只验证「Tooltip 存在 + message 与 hint 严格相等」契约。

    Future<void> pumpPanel(WidgetTester tester, List<MergeJob> jobs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: jobs)),
        ),
      );
    }

    testWidgets('per-card chip 包 Tooltip(message=hint)', (tester) async {
      final job = _job(
        jobId: 1,
        status: JobStatus.failed,
        error: 'svn: E170001 Authentication failed',
      );
      await pumpPanel(tester, [job]);

      final expectedHint = presentationFor(SvnFailureKind.authFailed).hint;
      // 卡片 chip 用 label 作为 Text；查找 chip 上方的 Tooltip
      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .where((t) => t.message == expectedHint)
          .toList();
      expect(tooltips.isNotEmpty, isTrue,
          reason: '期望至少一个 Tooltip.message == 认证失败 hint');
    });

    testWidgets('header bucket chip 包 Tooltip(message=hint + 包含任务)',
        (tester) async {
      // Step 18：header bucket chip 的 hover tooltip 在 hint 之外附 jobIds
      // 列表（`'<hint>\n包含任务: #N, #M'`）。per-card chip 仍只用单段 hint。
      final jobs = [
        _job(jobId: 1, status: JobStatus.failed, error: 'svn: E170001'),
        _job(jobId: 2, status: JobStatus.failed, error: 'svn: E170001'),
        _job(jobId: 3, status: JobStatus.failed, error: 'tree conflict'),
      ];
      await pumpPanel(tester, jobs);

      final authHint = presentationFor(SvnFailureKind.authFailed).hint;
      final treeHint = presentationFor(SvnFailureKind.treeConflict).hint;
      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      // header bucket chip：hint + 包含任务
      expect(messages, contains('$authHint\n包含任务: #1, #2'));
      expect(messages, contains('$treeHint\n包含任务: #3'));
      // per-card chip：仍是单段 hint
      expect(messages, contains(authHint));
      expect(messages, contains(treeHint));
    });

    testWidgets('unknown 不渲染 chip → 不应该出现 unknown.hint 的 Tooltip',
        (tester) async {
      // 空 error/pauseReason → unknown → 不渲染 chip。Tooltip 列表里应找不到 unknown 的 hint。
      final jobs = [_job(jobId: 1, status: JobStatus.failed)];
      await pumpPanel(tester, jobs);

      final unknownHint = presentationFor(SvnFailureKind.unknown).hint;
      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(messages.contains(unknownHint), isFalse,
          reason: 'unknown 不应出现在任何 chip 的 Tooltip 里');
    });
  });

  group('header 顶部计数 hover tooltip 拆分', () {
    Future<void> pumpPanel(WidgetTester tester, List<MergeJob> jobs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: jobs)),
        ),
      );
    }

    testWidgets('混合状态 → header 计数包 Tooltip(message=breakdown)', (tester) async {
      final jobs = [
        _job(jobId: 1, status: JobStatus.pending),
        _job(jobId: 2, status: JobStatus.running),
        _job(jobId: 3, status: JobStatus.paused),
        _job(jobId: 4, status: JobStatus.done),
        _job(jobId: 5, status: JobStatus.failed),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(
        messages,
        contains('队列中: 等待 1 / 执行中 1 / 已暂停 1\n最近结果: 完成 1 / 失败 1'),
      );
    });

    testWidgets('空 jobs → 不应出现 header 拆分 tooltip', (tester) async {
      await pumpPanel(tester, const []);
      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(messages.any((m) => m != null && m.contains('队列中:')), isFalse);
      expect(messages.any((m) => m != null && m.contains('最近结果:')), isFalse);
    });
  });

  group('formatJobSubtitleTooltip', () {
    test(
        'new job with targetUrl → tooltip includes source, target URL and target WC',
        () {
      final job = _job(
        sourceUrl: 'svn://example/repo/branches/feature-x',
        targetWc: '/Users/dev/wc/projectA',
        targetUrl: 'svn://example/repo/branches/main',
      );
      expect(
        formatJobSubtitleTooltip(job),
        '源: svn://example/repo/branches/feature-x\n'
        '目标: svn://example/repo/branches/main\n'
        '目标工作副本: /Users/dev/wc/projectA',
      );
    });

    test(
        'old job without targetUrl and short form equals full values → returns empty',
        () {
      final job = _job(sourceUrl: 'feature-x', targetWc: 'projectA');
      expect(formatJobSubtitleTooltip(job), '');
    });

    test('仅 sourceUrl 含 / → 仍渲染 tooltip（非双方都等价时不视为冗余）', () {
      final job = _job(
        sourceUrl: 'svn://example/repo/trunk',
        targetWc: 'projectA',
      );
      expect(
        formatJobSubtitleTooltip(job),
        '源: svn://example/repo/trunk\n目标工作副本: projectA',
      );
    });

    test('targetWc 末尾带 / → 末段为空但完整字符串 != 末段 → 仍渲染 tooltip', () {
      final job = _job(
        sourceUrl: 'svn://example/repo/trunk',
        targetWc: '/tmp/wc/',
      );
      // sourceShort='trunk' != sourceUrl ⇒ 不进入"双方等价"分支
      expect(
        formatJobSubtitleTooltip(job),
        '源: svn://example/repo/trunk\n目标工作副本: /tmp/wc/',
      );
    });

    test('忠实展示原字符串 — 不 trim、不解码、不剥 query', () {
      final job = _job(
        sourceUrl: '  svn://example/repo/trunk?revision=100  ',
        targetWc: '/tmp/wc',
      );
      expect(
        formatJobSubtitleTooltip(job),
        '源:   svn://example/repo/trunk?revision=100  \n目标工作副本: /tmp/wc',
      );
    });
  });

  group('副标题 hover tooltip 渲染', () {
    Future<void> pumpPanel(WidgetTester tester, List<MergeJob> jobs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: jobs)),
        ),
      );
    }

    testWidgets('卡片副标题（短形态 != 完整路径）→ 包 Tooltip(message=展开路径)', (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'svn://example/repo/branches/feature-x',
          targetWc: '/Users/dev/wc/projectA',
          targetUrl: 'svn://example/repo/branches/main',
          status: JobStatus.pending,
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(
        messages,
        contains(
          '源: svn://example/repo/branches/feature-x\n'
          '目标: svn://example/repo/branches/main\n'
          '目标工作副本: /Users/dev/wc/projectA',
        ),
      );
    });

    testWidgets('短形态等价完整路径 → 不渲染副标题 tooltip', (tester) async {
      final jobs = [
        _job(jobId: 1, sourceUrl: 'feature-x', targetWc: 'projectA'),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      // 副标题 tooltip 的特征 "源:" 不应出现
      expect(messages.any((m) => m != null && m.startsWith('源:')), isFalse);
    });
  });

  group('formatJobRevisionTooltip', () {
    test('typical 列表 → 双行 "共 N 个 revision\\nr1, r2, ..."', () {
      expect(
        formatJobRevisionTooltip([100, 101, 102]),
        '共 3 个 revision\nr100, r101, r102',
      );
    });

    test('单 revision → 仍渲染（提供总数 additive 信息）', () {
      expect(
        formatJobRevisionTooltip([42]),
        '共 1 个 revision\nr42',
      );
    });

    test('空 list → 返回空字符串', () {
      expect(formatJobRevisionTooltip(const []), '');
    });

    test('保持 formatRevisionListShort 的顺序契约 — 不排序、不去重', () {
      expect(
        formatJobRevisionTooltip([102, 100, 100, 101]),
        '共 4 个 revision\nr102, r100, r100, r101',
      );
    });
  });

  group('revision 列表 hover tooltip 渲染', () {
    Future<void> pumpPanel(WidgetTester tester, List<MergeJob> jobs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: jobs)),
        ),
      );
    }

    testWidgets('非空 revisions → 包 Tooltip(message="共 N ...\\nr1, ...")',
        (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          revisions: const [100, 101, 102],
          status: JobStatus.pending,
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(
        messages,
        contains('共 3 个 revision\nr100, r101, r102'),
      );
    });

    testWidgets('空 revisions → 不渲染 revision tooltip', (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          revisions: const [],
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(
        messages.any((m) => m != null && m.startsWith('共 ')),
        isFalse,
      );
    });
  });

  group('formatJobErrorTooltip', () {
    test('failed + 非空 error → "失败: <error>"', () {
      final job =
          _job(status: JobStatus.failed, error: 'svn: E170001 auth failed');
      expect(
        formatJobErrorTooltip(job),
        '失败: svn: E170001 auth failed',
      );
    });

    test('paused + 非空 error → "已暂停: <error>"', () {
      final job = _job(status: JobStatus.paused, error: 'working copy locked');
      expect(formatJobErrorTooltip(job), '已暂停: working copy locked');
    });

    test('error 为空 → 返回空字符串（与 caller 的 if 守卫双保险）', () {
      final job = _job(status: JobStatus.failed, error: '');
      expect(formatJobErrorTooltip(job), '');
    });

    test('多行 stderr → 原样保留换行（不 trim/不裁剪）', () {
      final job = _job(
        status: JobStatus.failed,
        error: 'svn: E155004\nworking copy locked\nrun cleanup',
      );
      expect(
        formatJobErrorTooltip(job),
        '失败: svn: E155004\nworking copy locked\nrun cleanup',
      );
    });
  });

  group('error 行 hover tooltip 渲染', () {
    Future<void> pumpPanel(WidgetTester tester, List<MergeJob> jobs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: jobs)),
        ),
      );
    }

    testWidgets('failed + 非空 error → 包 Tooltip(message="失败: <error>")',
        (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          status: JobStatus.failed,
          error: 'svn: E170001 auth failed',
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(messages, contains('失败: svn: E170001 auth failed'));
    });

    testWidgets('error 为空 → 不渲染 error 行 tooltip', (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          status: JobStatus.pending,
          error: '',
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      // error 行 tooltip 的特征 "失败:" / "已暂停:" 都不应出现
      expect(messages.any((m) => m != null && m.startsWith('失败: ')), isFalse);
      expect(messages.any((m) => m != null && m.startsWith('已暂停: ')), isFalse);
    });
  });

  group('formatJobProgressTooltip', () {
    test('completedIndex 介于中间 → 三段全输出', () {
      final job = _job(
        revisions: [100, 101, 102, 103],
        completedIndex: 2,
      );
      expect(
        formatJobProgressTooltip(job),
        '已完成: r100, r101\n当前: r102\n剩余: r103',
      );
    });

    test('completedIndex == 0 → 仅"当前 + 剩余"两段（无已完成）', () {
      final job = _job(
        revisions: [100, 101, 102],
        completedIndex: 0,
      );
      expect(
        formatJobProgressTooltip(job),
        '当前: r100\n剩余: r101, r102',
      );
    });

    test('completedIndex == length（全部完成）→ 仅"已完成"一段', () {
      final job = _job(
        revisions: [100, 101, 102],
        completedIndex: 3,
      );
      expect(
        formatJobProgressTooltip(job),
        '已完成: r100, r101, r102',
      );
    });

    test('completedIndex == length-1 → 仅"已完成 + 当前"两段（无剩余）', () {
      final job = _job(
        revisions: [100, 101, 102],
        completedIndex: 2,
      );
      expect(
        formatJobProgressTooltip(job),
        '已完成: r100, r101\n当前: r102',
      );
    });

    test('revisions 为空 → 三段全空 → 返回 ""', () {
      final job = _job(
        revisions: const [],
        completedIndex: 0,
      );
      expect(formatJobProgressTooltip(job), '');
    });

    test('revisions 含重复值 → 不按值过滤、按 index 切分', () {
      // [100, 100, 101] + completedIndex=1 → 已完成=[100] / 当前=100 / 剩余=[101]。
      // 关键：不能因为"剩余去当前"按值过滤把第二个 100 误删——按 index 切分保证。
      final job = _job(
        revisions: [100, 100, 101],
        completedIndex: 1,
      );
      expect(
        formatJobProgressTooltip(job),
        '已完成: r100\n当前: r100\n剩余: r101',
      );
    });
  });

  group('进度行 hover tooltip 渲染', () {
    Future<void> pumpPanel(WidgetTester tester, List<MergeJob> jobs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: jobs)),
        ),
      );
    }

    testWidgets(
        'completedIndex 中间 → Tooltip(message="已完成 ...\\n当前 ...\\n剩余 ...")',
        (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          revisions: [100, 101, 102, 103],
          completedIndex: 2,
          status: JobStatus.paused,
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(messages, contains('已完成: r100, r101\n当前: r102\n剩余: r103'));
    });

    testWidgets('revisions 为空 → 进度行不渲染 tooltip', (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          revisions: const [],
          completedIndex: 0,
          status: JobStatus.pending,
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      // 进度行 tooltip 的特征前缀都不应出现
      expect(messages.any((m) => m != null && m.startsWith('已完成: ')), isFalse);
      expect(messages.any((m) => m != null && m.startsWith('当前: ')), isFalse);
      expect(messages.any((m) => m != null && m.startsWith('剩余: ')), isFalse);
    });
  });

  group('formatJobProgressBarTooltip', () {
    test('未完 25% → "25% 完成（1/4 个 revision）"', () {
      final job = _job(
        revisions: [100, 101, 102, 103],
        completedIndex: 1,
      );
      expect(formatJobProgressBarTooltip(job), '25% 完成（1/4 个 revision）');
    });

    test('刚开始 0% → "0% 完成（0/3 个 revision）"', () {
      final job = _job(revisions: [100, 101, 102], completedIndex: 0);
      expect(formatJobProgressBarTooltip(job), '0% 完成（0/3 个 revision）');
    });

    test('全完 100% → "100% 完成（3/3 个 revision）"', () {
      final job = _job(revisions: [100, 101, 102], completedIndex: 3);
      expect(formatJobProgressBarTooltip(job), '100% 完成（3/3 个 revision）');
    });

    test('非整除 → 四舍五入到整数百分比（1/3 ≈ 33%）', () {
      final job = _job(revisions: [100, 101, 102], completedIndex: 1);
      // 1/3 = 0.333... → round → 33
      expect(formatJobProgressBarTooltip(job), '33% 完成（1/3 个 revision）');
    });

    test('非整除 → 四舍五入到整数百分比（2/3 ≈ 67%，验证 .5 进位方向）', () {
      final job = _job(revisions: [100, 101, 102], completedIndex: 2);
      // 2/3 = 0.666... → round → 67
      expect(formatJobProgressBarTooltip(job), '67% 完成（2/3 个 revision）');
    });

    test(
        'completedIndex 越界（>len）→ clamp 到 len，与 computeJobProgressRatio 共享 clamp',
        () {
      final job = _job(revisions: [100, 101], completedIndex: 5);
      // clamp → completed=2, ratio=1.0, percent=100
      expect(formatJobProgressBarTooltip(job), '100% 完成（2/2 个 revision）');
    });

    test('completedIndex 负数 → clamp 到 0', () {
      final job = _job(revisions: [100, 101], completedIndex: -3);
      expect(formatJobProgressBarTooltip(job), '0% 完成（0/2 个 revision）');
    });

    test('revisions 为空 → 返回 ""（避免误导的 "0% 完成（0/0 个 revision）"）', () {
      final job = _job(revisions: const [], completedIndex: 0);
      expect(formatJobProgressBarTooltip(job), '');
    });

    test('与 formatJobProgress / computeJobProgressRatio 同源 clamp（同一 job 数字一致）',
        () {
      // 三个 helper 共享 clampedCompletedRevisionCount，越界时表现一致：
      // - formatJobProgress: '3/3'
      // - computeJobProgressRatio: 1.0
      // - formatJobProgressBarTooltip: '100% 完成（3/3 个 revision）'
      final job = _job(revisions: [100, 101, 102], completedIndex: 7);
      expect(formatJobProgress(job), '3/3');
      expect(computeJobProgressRatio(job), 1.0);
      expect(formatJobProgressBarTooltip(job), '100% 完成（3/3 个 revision）');
    });
  });

  group('进度条 hover tooltip 渲染', () {
    Future<void> pumpPanel(WidgetTester tester, List<MergeJob> jobs) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JobQueuePanel(jobs: jobs)),
        ),
      );
    }

    testWidgets('非空 revisions → 进度条本身被 Tooltip 包裹（message=百分比）',
        (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          revisions: [100, 101, 102, 103],
          completedIndex: 1,
          status: JobStatus.running,
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(messages, contains('25% 完成（1/4 个 revision）'));
    });

    testWidgets('revisions 为空 → 进度条不被 Tooltip 包裹（无百分比 tooltip）',
        (tester) async {
      final jobs = [
        _job(
          jobId: 1,
          sourceUrl: 'feature-x',
          targetWc: 'projectA',
          revisions: const [],
          completedIndex: 0,
          status: JobStatus.pending,
        ),
      ];
      await pumpPanel(tester, jobs);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      // 百分比 tooltip 的特征后缀不应出现
      expect(
        messages.any((m) => m != null && m.endsWith('个 revision）')),
        isFalse,
      );
    });
  });
}
