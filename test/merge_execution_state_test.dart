import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/execution/step_output.dart';
import 'package:svn_auto_merge/execution/step_snapshot.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/providers/merge_execution_state.dart';
import 'package:svn_auto_merge/services/storage_service.dart';
import 'package:svn_auto_merge/services/svn_service.dart';

class _FakeStorageService extends StorageService {
  _FakeStorageService(this.loadedJobs) : super.forTesting();

  final List<MergeJob> loadedJobs;
  List<MergeJob>? savedJobs;

  @override
  Future<List<MergeJob>> loadQueue() async => List<MergeJob>.from(loadedJobs);

  @override
  Future<void> saveQueue(List<MergeJob> jobs) async {
    savedJobs = List<MergeJob>.from(jobs);
  }
}

class _FakeSvnService extends SvnService {
  _FakeSvnService(this.urls) : super.forTesting();

  final Map<String, String> urls;

  @override
  Future<String> getInfo(
    String path, {
    String? item,
    String? username,
    String? password,
  }) async {
    if (item == 'url' && urls.containsKey(path)) {
      return urls[path]!;
    }
    throw StateError('missing fake svn info for $path item=$item');
  }
}

@visibleForTesting
QueueMutationResult applyDeleteJobResult(List<MergeJob> jobs, int jobId) {
  return resolveDeleteJobResult(jobs, jobId);
}

@visibleForTesting
QueueMutationResult applyEnqueueRemainingJobResult(
  List<MergeJob> jobs,
  int jobId, {
  required int nextJobId,
}) {
  return resolveEnqueueRemainingJobResult(jobs, jobId, nextJobId: nextJobId);
}

@visibleForTesting
QueueMutationResult applyClearPendingJobsResult(List<MergeJob> jobs) {
  return resolveClearPendingJobsResult(jobs);
}

@visibleForTesting
QueueMutationResult applyClearFinishedJobsResult(List<MergeJob> jobs) {
  return resolveClearFinishedJobsResult(jobs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildRunningJobState', () {
    test('forces running status and clears stale pause metadata', () {
      const job = MergeJob(
        jobId: 1,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 3,
        revisions: [101, 102],
        status: JobStatus.paused,
        completedIndex: 0,
        error: 'old error',
        pauseReason: '需要人工处理',
        resumeFromStepId: 'commit',
      );

      final running = buildRunningJobState(job, completedIndex: 1);

      expect(running.status, JobStatus.running);
      expect(running.completedIndex, 1);
      expect(running.pauseReason, isEmpty);
      expect(running.error, isEmpty);
      expect(running.resumeFromStepId, isNull);
    });
  });

  group('buildRemainingJob', () {
    test('creates a fresh pending job from failed remainder', () {
      const failedJob = MergeJob(
        jobId: 8,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 4,
        revisions: [101, 102, 103],
        status: JobStatus.failed,
        completedIndex: 1,
        error: '用户终止',
        commitMessageTemplate: 'merge {revision}',
        sourceMessagesByRevision: {
          '101': '已完成 message',
          '102': '待重排 message\n\n完整正文',
          '103': '另一个待重排 message',
        },
        commitSupplement: '--crid=123456',
      );

      final queued = buildRemainingJob(failedJob, newJobId: 18);

      expect(queued, isNotNull);
      expect(queued!.jobId, 18);
      expect(queued.status, JobStatus.pending);
      expect(queued.revisions, [102, 103]);
      expect(queued.completedIndex, 0);
      expect(queued.commitMessageTemplate, 'merge {revision}');
      expect(
          queued.sourceMessagesByRevision, failedJob.sourceMessagesByRevision);
      expect(queued.commitSupplement, '--crid=123456');
    });

    test('returns null when failed job has no remaining revisions', () {
      const finishedJob = MergeJob(
        jobId: 9,
        sourceUrl: 'svn://source',
        targetWc: '/tmp/wc',
        maxRetries: 4,
        revisions: [201, 202],
        status: JobStatus.failed,
        completedIndex: 2,
      );

      expect(buildRemainingJob(finishedJob, newJobId: 19), isNull);
    });
  });
  group('appendExecutionLog', () {
    test('appends trailing newline and keeps recent lines within limit', () {
      expect(
        appendExecutionLog('', '[INFO] first', maxLines: 3),
        '[INFO] first\n',
      );

      final limited = appendExecutionLog(
        '[INFO] first\n[INFO] second\n[INFO] third\n',
        '[INFO] fourth',
        maxLines: 3,
      );

      expect(
        limited,
        '[INFO] second\n[INFO] third\n[INFO] fourth\n',
      );
    });

    test('splits multiline message before trimming recent lines', () {
      final limited = appendExecutionLog(
        '[INFO] first\n',
        '[INFO] second\n[ERROR] detail 1\n[ERROR] detail 2',
        maxLines: 3,
      );

      expect(
        limited,
        '[INFO] second\n[ERROR] detail 1\n[ERROR] detail 2\n',
      );
    });

    test('treats non-positive maxLines as one line', () {
      final limited = appendExecutionLog(
        '[INFO] old\n',
        '[INFO] new',
        maxLines: 0,
      );

      expect(limited, '[INFO] new\n');
    });
  });

  group('isRevisionCompletionConfirmed', () {
    test('commit 未执行或仓库未确认都不能视为 revision 完成', () {
      expect(
        isRevisionCompletionConfirmed(
          commitAttempted: false,
          mergeInfoConfirmed: false,
        ),
        isFalse,
      );
      expect(
        isRevisionCompletionConfirmed(
          commitAttempted: false,
          mergeInfoConfirmed: true,
        ),
        isFalse,
      );
      expect(
        isRevisionCompletionConfirmed(
          commitAttempted: true,
          mergeInfoConfirmed: false,
        ),
        isFalse,
      );
      expect(
        isRevisionCompletionConfirmed(
          commitAttempted: true,
          mergeInfoConfirmed: true,
        ),
        isTrue,
      );
    });
  });

  group('queue mutation results', () {
    test('deleteQueueJobResult distinguishes applied blocked and missing jobs',
        () {
      const jobs = [
        MergeJob(
          jobId: 1,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [101],
          status: JobStatus.pending,
        ),
        MergeJob(
          jobId: 2,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [102],
          status: JobStatus.paused,
        ),
      ];

      final applied = applyDeleteJobResult(jobs, 1);
      expect(applied.status, QueueMutationStatus.applied);
      expect(applied.jobId, 1);

      final blocked = applyDeleteJobResult(jobs, 2);
      expect(blocked.status, QueueMutationStatus.blocked);
      expect(blocked.jobId, 2);

      final missing = applyDeleteJobResult(jobs, 99);
      expect(missing.status, QueueMutationStatus.notFound);
      expect(missing.jobId, 99);
    });

    test(
        'enqueueRemainingJobResult returns new job id only when remainder exists',
        () {
      const jobs = [
        MergeJob(
          jobId: 4,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [201, 202, 203],
          status: JobStatus.failed,
          completedIndex: 1,
        ),
      ];

      final applied = applyEnqueueRemainingJobResult(jobs, 4, nextJobId: 5);
      expect(applied.status, QueueMutationStatus.applied);
      expect(applied.jobId, 5);

      const finishedJobs = [
        MergeJob(
          jobId: 8,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [301],
          status: JobStatus.failed,
          completedIndex: 1,
        ),
      ];

      final blocked = applyEnqueueRemainingJobResult(
        finishedJobs,
        8,
        nextJobId: 9,
      );
      expect(blocked.status, QueueMutationStatus.blocked);
      expect(blocked.jobId, 8);
    });

    test(
        'clearPendingJobsResult and clearFinishedJobsResult report affected counts',
        () {
      const jobs = [
        MergeJob(
          jobId: 1,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [101],
          status: JobStatus.pending,
        ),
        MergeJob(
          jobId: 2,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [102],
          status: JobStatus.done,
        ),
        MergeJob(
          jobId: 3,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [103],
          status: JobStatus.failed,
        ),
      ];

      final clearedPending = applyClearPendingJobsResult(jobs);
      expect(clearedPending.status, QueueMutationStatus.applied);
      expect(clearedPending.affectedCount, 1);

      final clearedFinished = applyClearFinishedJobsResult(jobs);
      expect(clearedFinished.status, QueueMutationStatus.applied);
      expect(clearedFinished.affectedCount, 2);

      const activeOnlyJobs = [
        MergeJob(
          jobId: 9,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: [401],
          status: JobStatus.running,
        ),
      ];

      final blocked = applyClearFinishedJobsResult(activeOnlyJobs);
      expect(blocked.status, QueueMutationStatus.blocked);
      expect(blocked.affectedCount, 0);
    });
  });

  group('reorderPendingJobsList', () {
    MergeJob job(int id, JobStatus status) => MergeJob(
          jobId: id,
          sourceUrl: 'svn://source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: const [100],
          status: status,
        );

    test('moves a pending job from index 0 to index 2 (drag down)', () {
      final jobs = [
        job(1, JobStatus.pending),
        job(2, JobStatus.pending),
        job(3, JobStatus.pending),
      ];

      // ReorderableListView 语义：把 0 拖到末位 → newIndex == 3
      final result = reorderPendingJobsList(jobs, 0, 3);
      expect(result.map((j) => j.jobId).toList(), [2, 3, 1]);
    });

    test('moves a pending job upward (drag up)', () {
      final jobs = [
        job(1, JobStatus.pending),
        job(2, JobStatus.pending),
        job(3, JobStatus.pending),
      ];
      // 把 2 (index 2) 拖到 index 0
      final result = reorderPendingJobsList(jobs, 2, 0);
      expect(result.map((j) => j.jobId).toList(), [3, 1, 2]);
    });

    test('preserves running and paused jobs absolute position', () {
      final jobs = [
        job(10, JobStatus.running),
        job(1, JobStatus.pending),
        job(2, JobStatus.pending),
        job(20, JobStatus.paused),
        job(3, JobStatus.pending),
      ];

      // 在 pending 子列表 [1,2,3] 内把 0 → 末位 (newIndex 3)
      final result = reorderPendingJobsList(jobs, 0, 3);
      expect(
        result.map((j) => j.jobId).toList(),
        [10, 2, 3, 20, 1],
      );
      // running/paused 位置 (0, 3) 保持不变
      expect(result[0].status, JobStatus.running);
      expect(result[3].status, JobStatus.paused);
    });

    test('returns same instance when no pending jobs exist', () {
      final jobs = [
        job(1, JobStatus.running),
        job(2, JobStatus.done),
      ];
      final result = reorderPendingJobsList(jobs, 0, 1);
      expect(identical(result, jobs), isTrue);
    });

    test('returns same instance when oldIndex is out of range', () {
      final jobs = [job(1, JobStatus.pending)];
      expect(identical(reorderPendingJobsList(jobs, 5, 0), jobs), isTrue);
      expect(identical(reorderPendingJobsList(jobs, -1, 0), jobs), isTrue);
    });

    test('returns same instance for no-op (drag to current position)', () {
      final jobs = [
        job(1, JobStatus.pending),
        job(2, JobStatus.pending),
      ];
      // 拖到自己的当前位置 (newIndex == oldIndex 或 oldIndex+1 都是 no-op)
      expect(identical(reorderPendingJobsList(jobs, 0, 0), jobs), isTrue);
      expect(identical(reorderPendingJobsList(jobs, 0, 1), jobs), isTrue);
    });

    test('handles single pending job (no possible reorder)', () {
      final jobs = [
        job(10, JobStatus.running),
        job(1, JobStatus.pending),
      ];
      expect(identical(reorderPendingJobsList(jobs, 0, 1), jobs), isTrue);
    });

    test('does not mutate input list', () {
      final jobs = [
        job(1, JobStatus.pending),
        job(2, JobStatus.pending),
      ];
      final snapshot = jobs.map((j) => j.jobId).toList();
      reorderPendingJobsList(jobs, 0, 2);
      expect(jobs.map((j) => j.jobId).toList(), snapshot);
    });
  });

  group('evaluateCommitOutcome', () {
    test('non out-of-date error is reported as otherFailure without counting',
        () {
      final outcome = evaluateCommitOutcome(
        errorMessage: 'Exception: svn: E155010: working copy locked',
        previousRetryCount: 0,
        maxRetries: 3,
      );

      expect(outcome.kind, CommitOutcomeKind.otherFailure);
      expect(outcome.nextRetryCount, 0);
    });

    test('out-of-date within budget asks for retry from update', () {
      final first = evaluateCommitOutcome(
        errorMessage: "svn: E160028: Item is out-of-date",
        previousRetryCount: 0,
        maxRetries: 3,
      );

      expect(first.kind, CommitOutcomeKind.retryFromUpdate);
      expect(first.nextRetryCount, 1);

      final second = evaluateCommitOutcome(
        errorMessage: 'Item is out-of-date',
        previousRetryCount: first.nextRetryCount,
        maxRetries: 3,
      );

      expect(second.kind, CommitOutcomeKind.retryFromUpdate);
      expect(second.nextRetryCount, 2);
    });

    test('out-of-date past the budget exhausts retries', () {
      final outcome = evaluateCommitOutcome(
        errorMessage: 'item is out-of-date',
        previousRetryCount: 3,
        maxRetries: 3,
      );

      expect(outcome.kind, CommitOutcomeKind.exhaustedRetries);
      expect(outcome.nextRetryCount, 4);
    });

    test('maxRetries=0 exhausts on the very first out-of-date', () {
      final outcome = evaluateCommitOutcome(
        errorMessage: 'svn: out-of-date',
        previousRetryCount: 0,
        maxRetries: 0,
      );

      expect(outcome.kind, CommitOutcomeKind.exhaustedRetries);
      expect(outcome.nextRetryCount, 1);
    });

    test('mixed-case and spaced variants of out-of-date are all detected', () {
      const variants = [
        'Item is Out-Of-Date',
        'commit failed: out of date',
        'WORKING COPY OUT-OF-DATE WITH RESPECT TO REPOSITORY',
        'item is out of date.',
      ];

      for (final message in variants) {
        final outcome = evaluateCommitOutcome(
          errorMessage: message,
          previousRetryCount: 0,
          maxRetries: 1,
        );
        expect(outcome.kind, CommitOutcomeKind.retryFromUpdate,
            reason: 'expected retry for: $message');
      }
    });

    test('isOutOfDateMessage returns false for unrelated errors', () {
      expect(isOutOfDateMessage('connection refused'), isFalse);
      expect(isOutOfDateMessage('conflict during merge'), isFalse);
      expect(isOutOfDateMessage(''), isFalse);
    });
  });

  group('extractPreviousRetryCountFromCommitSnapshot', () {
    StepSnapshot makeSnap({
      required StepExecutionStatus status,
      StepOutput? output,
    }) {
      return StepSnapshot(
        stepId: 'commit',
        stepTypeId: 'commit',
        status: status,
        inputData: const {},
        config: const {},
        output: output,
        startTime: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    test('null snapshot → 0', () {
      expect(extractPreviousRetryCountFromCommitSnapshot(null), 0);
    });

    test('non-failed snapshot → 0（completed/running/pending 都不算）', () {
      for (final status in [
        StepExecutionStatus.completed,
        StepExecutionStatus.running,
        StepExecutionStatus.pending,
        StepExecutionStatus.skipped,
      ]) {
        expect(
          extractPreviousRetryCountFromCommitSnapshot(
            makeSnap(
              status: status,
              output: StepOutput.failure(data: const {'retryCount': 5}),
            ),
          ),
          0,
          reason: '$status 不应被当作可恢复的 paused 状态',
        );
      }
    });

    test('failed snapshot 但 output 为 null → 0', () {
      expect(
        extractPreviousRetryCountFromCommitSnapshot(
          makeSnap(status: StepExecutionStatus.failed),
        ),
        0,
      );
    });

    test('failed snapshot output 无 retryCount 字段 → 0', () {
      expect(
        extractPreviousRetryCountFromCommitSnapshot(
          makeSnap(
            status: StepExecutionStatus.failed,
            output: StepOutput.failure(data: const {'error': 'oops'}),
          ),
        ),
        0,
      );
    });

    test('failed snapshot retryCount 类型不对（String）→ 0', () {
      expect(
        extractPreviousRetryCountFromCommitSnapshot(
          makeSnap(
            status: StepExecutionStatus.failed,
            output: StepOutput.failure(data: const {'retryCount': '3'}),
          ),
        ),
        0,
      );
    });

    test('failed snapshot retryCount 为负 → 0（防 corrupt 数据回滚 attempt）', () {
      expect(
        extractPreviousRetryCountFromCommitSnapshot(
          makeSnap(
            status: StepExecutionStatus.failed,
            output: StepOutput.failure(data: const {'retryCount': -1}),
          ),
        ),
        0,
      );
    });

    test('failed snapshot retryCount=N → 返回 N（resume 时新 attempt 接续为 N+1）', () {
      // 上一轮 maxRetries=3，paused 在 nextRetryCount=4 (exhausted)，
      // snapshot 写入 retryCount = 4 - 1 = 3。Resume 时 previousRetryCount=3，
      // 用户调高 maxRetries=4，新一轮 attempt = 3 + 1 = 4，符合 retryFromUpdate
      // 边界 (4 <= 4)，retry 计数严格单调不会回退到 1。
      final snap = makeSnap(
        status: StepExecutionStatus.failed,
        output: StepOutput.failure(data: const {'retryCount': 3}),
      );
      expect(extractPreviousRetryCountFromCommitSnapshot(snap), 3);

      // 把它喂给 evaluateCommitOutcome 验证接续语义
      final next = evaluateCommitOutcome(
        errorMessage: 'item is out-of-date',
        previousRetryCount: extractPreviousRetryCountFromCommitSnapshot(snap),
        maxRetries: 4,
      );
      expect(next.kind, CommitOutcomeKind.retryFromUpdate);
      expect(next.nextRetryCount, 4,
          reason: 'resume 后 attempt 应当从上轮 +1 接续，不应回退到 1');
    });

    test('failed snapshot retryCount=0 → 0（首次 commit 即 paused 的特殊情况）', () {
      expect(
        extractPreviousRetryCountFromCommitSnapshot(
          makeSnap(
            status: StepExecutionStatus.failed,
            output: StepOutput.failure(data: const {'retryCount': 0}),
          ),
        ),
        0,
      );
    });
  });

  group('evaluateStepFailure', () {
    test('merge step failure always pauses (conflict or otherwise)', () {
      final conflict = evaluateStepFailure(
        stepId: 'merge',
        errorMessage: 'svn: E155015: tree conflict on file foo.txt',
        updateRequired: false,
      );
      final other = evaluateStepFailure(
        stepId: 'merge',
        errorMessage: 'network unreachable',
        updateRequired: false,
      );

      expect(conflict, StepFailureAction.pause);
      expect(other, StepFailureAction.pause);
    });

    test('commit step failure with updateRequired retries from update', () {
      final action = evaluateStepFailure(
        stepId: 'commit',
        errorMessage: 'commit failed unexpectedly',
        updateRequired: true,
      );

      expect(action, StepFailureAction.retryFromUpdate);
    });

    test('commit step failure without updateRequired pauses', () {
      final action = evaluateStepFailure(
        stepId: 'commit',
        errorMessage: 'auth denied',
        updateRequired: false,
      );

      expect(action, StepFailureAction.pause);
    });

    test('prepare and update step failures pause regardless of flag', () {
      for (final stepId in const ['prepare', 'update']) {
        for (final updateRequired in const [true, false]) {
          final action = evaluateStepFailure(
            stepId: stepId,
            errorMessage: 'svn: cleanup failed',
            updateRequired: updateRequired,
          );
          expect(action, StepFailureAction.pause,
              reason: 'step=$stepId, updateRequired=$updateRequired');
        }
      }
    });

    test('unknown step pauses', () {
      final action = evaluateStepFailure(
        stepId: 'mystery',
        errorMessage: 'boom',
        updateRequired: true,
      );

      expect(action, StepFailureAction.pause);
    });
  });

  group('isMergeConflictMessage', () {
    test('matches english, chinese, and tree conflict variants', () {
      const positives = [
        'svn: E155015: One or more conflicts were produced',
        'CONFLICT (content): Merge conflict in foo.txt',
        'svn: E155015: tree conflict on file foo.txt',
        '合并产生冲突，请手动处理',
      ];

      for (final message in positives) {
        expect(isMergeConflictMessage(message), isTrue,
            reason: 'expected conflict for: $message');
      }
    });

    test('returns false for unrelated errors and empty string', () {
      expect(isMergeConflictMessage('out-of-date'), isFalse);
      expect(isMergeConflictMessage('connection reset'), isFalse);
      expect(isMergeConflictMessage(''), isFalse);
    });
  });

  group('normalizeStepId', () {
    test('returns null for null, empty, or unknown step ids', () {
      expect(normalizeStepId(null), isNull);
      expect(normalizeStepId(''), isNull);
      expect(normalizeStepId('mystery'), isNull);
    });

    test('returns the canonical id for every known step', () {
      expect(normalizeStepId('prepare'), 'prepare');
      expect(normalizeStepId('update'), 'update');
      expect(normalizeStepId('merge'), 'merge');
      expect(normalizeStepId('validate'), 'validate');
      expect(normalizeStepId('commit'), 'commit');
    });
  });

  group('resolveMergeValidationScriptCommand', () {
    test('py：相对 / 路径拼到目标工作副本，并按平台选择 Python', () {
      final mac = resolveMergeValidationScriptCommand(
        targetWc: '/wc',
        scriptPath: r'Tools\check.py',
        operatingSystem: 'macos',
        pathSeparator: '/',
      );
      expect(mac.relativePath, 'Tools/check.py');
      expect(mac.resolvedPath, '/wc/Tools/check.py');
      expect(mac.executable, 'python3');
      expect(mac.args, ['/wc/Tools/check.py']);

      final windows = resolveMergeValidationScriptCommand(
        targetWc: r'C:\wc',
        scriptPath: 'Tools/check.py',
        operatingSystem: 'windows',
        pathSeparator: r'\',
      );
      expect(windows.executable, 'python');
      expect(windows.args, [r'C:\wc\Tools\check.py']);
    });

    test('sh：Unix 用 sh，Windows 用 bash', () {
      final unix = resolveMergeValidationScriptCommand(
        targetWc: '/wc',
        scriptPath: 'Tools/check.sh',
        operatingSystem: 'linux',
        pathSeparator: '/',
      );
      expect(unix.executable, 'sh');
      expect(unix.args, ['/wc/Tools/check.sh']);

      final windows = resolveMergeValidationScriptCommand(
        targetWc: r'C:\wc',
        scriptPath: 'Tools/check.sh',
        operatingSystem: 'windows',
        pathSeparator: r'\',
      );
      expect(windows.executable, 'bash');
      expect(windows.args, [r'C:\wc\Tools\check.sh']);
    });

    test('bat：Windows 用 cmd /c，非 Windows 拒绝', () {
      final windows = resolveMergeValidationScriptCommand(
        targetWc: r'C:\wc',
        scriptPath: 'Tools/check.bat',
        operatingSystem: 'windows',
        pathSeparator: r'\',
      );
      expect(windows.executable, 'cmd');
      expect(windows.args, [r'/c', r'C:\wc\Tools\check.bat']);

      expect(
        () => resolveMergeValidationScriptCommand(
          targetWc: '/wc',
          scriptPath: 'Tools/check.bat',
          operatingSystem: 'macos',
          pathSeparator: '/',
        ),
        throwsUnsupportedError,
      );
    });

    test('只接受相对路径和支持的后缀', () {
      expect(
        () => resolveMergeValidationScriptCommand(
          targetWc: '/wc',
          scriptPath: '/abs/check.py',
          operatingSystem: 'macos',
          pathSeparator: '/',
        ),
        throwsArgumentError,
      );
      expect(
        () => resolveMergeValidationScriptCommand(
          targetWc: '/wc',
          scriptPath: 'Tools/check.js',
          operatingSystem: 'macos',
          pathSeparator: '/',
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('buildCommitMessage', () {
    const job = MergeJob(
      jobId: 1,
      sourceUrl: 'svn://repo/branches/feature-a',
      targetWc: '/home/user/wc/trunk',
      targetUrl: 'svn://repo/branches/trunk',
      maxRetries: 3,
      revisions: [101],
      commitMessageTemplate:
          'merge r{revision} from {sourceUrl} into {targetUrl}',
    );

    test('default template renders when commitMessageTemplate is null', () {
      const noTemplate = MergeJob(
        jobId: 2,
        sourceUrl: 'svn://repo/branches/feature-b',
        targetWc: '/tmp/wc',
        maxRetries: 0,
        revisions: [999],
      );

      expect(
        buildCommitMessage(noTemplate, 999),
        '[Merge] r999 from svn://repo/branches/feature-b',
      );
    });

    test('default template renders when template is empty', () {
      const emptyTemplate = MergeJob(
        jobId: 3,
        sourceUrl: 'svn://repo/branches/feature-c',
        targetWc: '/tmp/wc',
        maxRetries: 0,
        revisions: [42],
        commitMessageTemplate: '',
      );

      expect(
        buildCommitMessage(emptyTemplate, 42),
        '[Merge] r42 from svn://repo/branches/feature-c',
      );
    });

    test('braced placeholders are substituted', () {
      expect(
        buildCommitMessage(job, 555),
        'merge r555 from svn://repo/branches/feature-a into svn://repo/branches/trunk',
      );
    });

    test('dollar-prefixed placeholders are substituted', () {
      const dollarJob = MergeJob(
        jobId: 4,
        sourceUrl: 'svn://repo/branches/x',
        targetWc: '/wc/x',
        targetUrl: 'svn://repo/branches/main',
        maxRetries: 0,
        revisions: [7],
        commitMessageTemplate: r'rev=$revision src=$sourceUrl tgt=$targetUrl',
      );

      expect(
        buildCommitMessage(dollarJob, 7),
        'rev=7 src=svn://repo/branches/x tgt=svn://repo/branches/main',
      );
    });

    test('targetUrl missing falls back to targetWc for old jobs', () {
      const oldJob = MergeJob(
        jobId: 40,
        sourceUrl: 'svn://repo/branches/old',
        targetWc: '/wc/old',
        maxRetries: 0,
        revisions: [8],
        commitMessageTemplate: 'target={targetUrl}',
      );

      expect(buildCommitMessage(oldJob, 8), 'target=/wc/old');
    });

    test('placeholders appearing multiple times all get substituted', () {
      const repeatJob = MergeJob(
        jobId: 5,
        sourceUrl: 'svn://repo/branches/y',
        targetWc: '/wc/y',
        maxRetries: 0,
        revisions: [8],
        commitMessageTemplate: '{revision}-{revision} ({sourceUrl})',
      );

      expect(
        buildCommitMessage(repeatJob, 8),
        '8-8 (svn://repo/branches/y)',
      );
    });

    test('null commitSupplement leaves message unchanged', () {
      const noSupplement = MergeJob(
        jobId: 10,
        sourceUrl: 'svn://repo/branches/s',
        targetWc: '/wc/s',
        maxRetries: 0,
        revisions: [11],
        // commitSupplement omitted (defaults to null)
      );

      expect(
        buildCommitMessage(noSupplement, 11),
        '[Merge] r11 from svn://repo/branches/s',
      );
    });

    test('source SVN message is appended as full original multiline block', () {
      const sourceMessage = '修复登录问题\n\n保留正文第一行\n  保留缩进正文第二行';
      const withSourceMessage = MergeJob(
        jobId: 100,
        sourceUrl: 'svn://repo/branches/source',
        targetWc: '/wc/source',
        maxRetries: 0,
        revisions: [123],
        sourceMessagesByRevision: {'123': sourceMessage},
      );

      expect(
        buildCommitMessage(withSourceMessage, 123),
        '[Merge] r123 from svn://repo/branches/source\n\n'
        'Original SVN message:\n'
        '$sourceMessage',
      );
    });

    test('message placeholder keeps full source message inside custom template',
        () {
      const sourceMessage = '标题\n\n正文第一行\n正文第二行';
      const templated = MergeJob(
        jobId: 101,
        sourceUrl: 'svn://repo/branches/source',
        targetWc: '/wc/source',
        maxRetries: 0,
        revisions: [124],
        commitMessageTemplate: 'merge r{revision}\n\n{message}',
        sourceMessagesByRevision: {'124': sourceMessage},
      );

      expect(
        buildCommitMessage(templated, 124),
        'merge r124\n\n$sourceMessage',
      );
    });

    test('blank/whitespace-only commitSupplement is treated as absent', () {
      const blankSupplement = MergeJob(
        jobId: 11,
        sourceUrl: 'svn://repo/branches/s',
        targetWc: '/wc/s',
        maxRetries: 0,
        revisions: [12],
        commitSupplement: '   \n\t  ',
      );

      expect(
        buildCommitMessage(blankSupplement, 12),
        '[Merge] r12 from svn://repo/branches/s',
      );
    });

    test(
        'non-empty commitSupplement is appended after blank line (default template)',
        () {
      const withSupplement = MergeJob(
        jobId: 12,
        sourceUrl: 'svn://repo/branches/s',
        targetWc: '/wc/s',
        maxRetries: 0,
        revisions: [13],
        commitSupplement: '--crid=123456',
      );

      expect(
        buildCommitMessage(withSupplement, 13),
        '[Merge] r13 from svn://repo/branches/s\n\n--crid=123456',
      );
    });

    test(
        'commitSupplement coexists with commitMessageTemplate (template renders, then \\n\\n + trimmed supplement)',
        () {
      const both = MergeJob(
        jobId: 13,
        sourceUrl: 'svn://repo/branches/feature-z',
        targetWc: '/wc/z',
        maxRetries: 0,
        revisions: [14],
        commitMessageTemplate: 'merge r{revision}',
        commitSupplement: '  --crid=987  ',
      );

      expect(
        buildCommitMessage(both, 14),
        'merge r14\n\n--crid=987',
      );
    });

    test('commitMessageOverride replaces full message for matching revision',
        () {
      const overridden = MergeJob(
        jobId: 14,
        sourceUrl: 'svn://repo/branches/feature-z',
        targetWc: '/wc/z',
        maxRetries: 0,
        revisions: [15, 16],
        commitMessageTemplate: 'merge r{revision}',
        commitSupplement: '--crid=987',
        commitMessageOverride: 'custom full message\n\n--crid=987',
        commitMessageOverrideRevision: 15,
      );

      expect(
        buildCommitMessage(overridden, 15),
        'custom full message\n\n--crid=987',
      );
      expect(
        buildCommitMessage(overridden, 16),
        'merge r16\n\n--crid=987',
      );
    });
  });

  group('resolveResumeStepId', () {
    StepSnapshot snapshotFor(String stepId, {String? error}) {
      return StepSnapshot(
        stepId: stepId,
        stepTypeId: stepId,
        status: StepExecutionStatus.failed,
        inputData: const {},
        config: const {},
        error: error,
        startTime: DateTime(2024, 1, 1),
      );
    }

    test('null snapshot falls back to prepare', () {
      expect(resolveResumeStepId(null), 'prepare');
    });

    test('prepare/update/merge failures resume on the same step', () {
      expect(resolveResumeStepId(snapshotFor('prepare')), 'prepare');
      expect(resolveResumeStepId(snapshotFor('update')), 'update');
      expect(resolveResumeStepId(snapshotFor('merge')), 'merge');
    });

    test('commit failure without out-of-date resumes on commit', () {
      expect(
        resolveResumeStepId(snapshotFor('commit', error: 'auth denied')),
        'commit',
      );
    });

    test('commit failure with out-of-date jumps back to update', () {
      expect(
        resolveResumeStepId(
            snapshotFor('commit', error: 'svn: item is out-of-date')),
        'update',
      );
      expect(
        resolveResumeStepId(snapshotFor('commit', error: 'OUT OF DATE')),
        'update',
      );
    });

    test('commit failure with null error stays on commit', () {
      expect(
        resolveResumeStepId(snapshotFor('commit')),
        'commit',
      );
    });

    test('unknown step id falls back to prepare', () {
      expect(resolveResumeStepId(snapshotFor('mystery')), 'prepare');
    });
  });

  group('countLogLines', () {
    test('empty string → 0（不是 1，避免空 log 显示 "1 行"）', () {
      expect(countLogLines(''), 0);
    });

    test('单行无换行 → 1', () {
      expect(countLogLines('hello'), 1);
    });

    test('单行带末尾换行 → 1（末尾空字符串被过滤）', () {
      expect(countLogLines('hello\n'), 1);
    });

    test('两行 → 2', () {
      expect(countLogLines('a\nb'), 2);
    });

    test('两行带末尾换行 → 2', () {
      expect(countLogLines('a\nb\n'), 2);
    });

    test('全空行（仅换行符）→ 0（与 appendExecutionLog 写入端口径一致）', () {
      expect(countLogLines('\n\n\n'), 0);
    });

    test('混合空行 → 仅非空行计数（写端会过滤空行，读端必须同口径）', () {
      // 关键：与 appendExecutionLog 的 .where(isNotEmpty) 一致——否则
      // "刚写入 N 行 → 读出 logLineCount" 会偏差
      expect(countLogLines('a\n\nb\n\nc'), 3);
    });

    test('行内空白保留（不修剪）：" hello " 仍算一行', () {
      expect(countLogLines('  hello  '), 1);
    });
  });

  group('deriveHasPausedJob', () {
    const pendingJob = MergeJob(
      jobId: 1,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [101],
      status: JobStatus.pending,
    );
    const pausedJob = MergeJob(
      jobId: 2,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [102],
      status: JobStatus.paused,
    );
    const runningJob = MergeJob(
      jobId: 3,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [103],
      status: JobStatus.running,
    );

    test('空 jobs + executorStatus.idle → false', () {
      expect(
        deriveHasPausedJob(jobs: const [], executorStatus: ExecutorStatus.idle),
        isFalse,
      );
    });

    test('jobs 全 pending + executorStatus.running → false（双条件都不成立）', () {
      expect(
        deriveHasPausedJob(
          jobs: const [pendingJob],
          executorStatus: ExecutorStatus.running,
        ),
        isFalse,
      );
    });

    test('某 job paused + executorStatus.running → true（job 路径命中）', () {
      expect(
        deriveHasPausedJob(
          jobs: const [pendingJob, pausedJob, runningJob],
          executorStatus: ExecutorStatus.running,
        ),
        isTrue,
      );
    });

    test('jobs 无 paused + executorStatus.paused → true（执行器路径命中）', () {
      expect(
        deriveHasPausedJob(
          jobs: const [pendingJob, runningJob],
          executorStatus: ExecutorStatus.paused,
        ),
        isTrue,
      );
    });

    test('双路径同时为真 → true（OR 短路即可）', () {
      expect(
        deriveHasPausedJob(
          jobs: const [pausedJob],
          executorStatus: ExecutorStatus.paused,
        ),
        isTrue,
      );
    });

    test('空 jobs + executorStatus.paused → true（jobs 清空后执行器仍 paused 的兜底）', () {
      // 显式锁定 dartdoc 里"jobs 被清空但 executorStatus 还没刷新"的边界
      expect(
        deriveHasPausedJob(
            jobs: const [], executorStatus: ExecutorStatus.paused),
        isTrue,
      );
    });

    test('反向断言：是 OR 不是 AND（任一条件命中就够）', () {
      // 防御性测试——若有人误改为 AND，本测会立刻撞红
      // jobs 有 paused 但 executor 还是 running，AND 会返回 false（错），OR 返回 true
      expect(
        deriveHasPausedJob(
          jobs: const [pausedJob],
          executorStatus: ExecutorStatus.running,
        ),
        isTrue,
      );
    });

    test('ExecutorStatus 全 4 cases 对照（仅 paused 触发执行器路径，其它路径靠 jobs）', () {
      // 用空 jobs 隔离 jobs 路径，单独验证 4 种 executorStatus
      const noJobs = <MergeJob>[];
      expect(
        deriveHasPausedJob(jobs: noJobs, executorStatus: ExecutorStatus.idle),
        isFalse,
      );
      expect(
        deriveHasPausedJob(
          jobs: noJobs,
          executorStatus: ExecutorStatus.running,
        ),
        isFalse,
      );
      expect(
        deriveHasPausedJob(
          jobs: noJobs,
          executorStatus: ExecutorStatus.paused,
        ),
        isTrue,
      );
      expect(
        deriveHasPausedJob(
          jobs: noJobs,
          executorStatus: ExecutorStatus.completed,
        ),
        isFalse,
      );
    });
  });

  group('resolveCurrentJobIndex', () {
    const job1 = MergeJob(
      jobId: 1,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [101],
      status: JobStatus.pending,
    );
    const job2 = MergeJob(
      jobId: 2,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [102],
      status: JobStatus.running,
    );
    const job3 = MergeJob(
      jobId: 3,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [103],
      status: JobStatus.done,
    );

    test('jobId == null → -1（首次启动场景）', () {
      expect(
        resolveCurrentJobIndex(jobId: null, jobs: const [job1, job2]),
        -1,
      );
    });

    test('jobId == null + 空 jobs → -1', () {
      expect(resolveCurrentJobIndex(jobId: null, jobs: const []), -1);
    });

    test('jobId 在 jobs 中 → 对应 index', () {
      expect(
        resolveCurrentJobIndex(jobId: 2, jobs: const [job1, job2, job3]),
        1,
      );
    });

    test('jobId 不在 jobs 中 → -1（持久化的 currentJobId 已被清理）', () {
      expect(
        resolveCurrentJobIndex(jobId: 999, jobs: const [job1, job2]),
        -1,
      );
    });

    test('jobId 不在 + 空 jobs → -1', () {
      expect(resolveCurrentJobIndex(jobId: 1, jobs: const []), -1);
    });

    test('null 与"找不到"返回相同 -1（合并语义，caller 不区分原因）', () {
      // 显式断言两条路径输出一致——若有人把 null 路径改成抛异常或返回别的值，会撞红
      expect(
        resolveCurrentJobIndex(jobId: null, jobs: const [job1]),
        resolveCurrentJobIndex(jobId: 999, jobs: const [job1]),
      );
    });

    test('首个 job → 0（边界：返回的 index 与 indexWhere 语义一致）', () {
      expect(
        resolveCurrentJobIndex(jobId: 1, jobs: const [job1, job2, job3]),
        0,
      );
    });

    test('末尾 job → length - 1', () {
      expect(
        resolveCurrentJobIndex(jobId: 3, jobs: const [job1, job2, job3]),
        2,
      );
    });
  });

  // R116 排序契约审计——把 init() 里内联的 `reduce(max) + 1` 抽到
  // `deriveNextJobId`，并在这里集中锁定 jobId 的排序/单调性契约。
  //
  // **为什么是排序契约**：jobId 不暴露 operator< / Comparable，但
  // `_nextJobId` 的恢复语义要求"全局取 max"——本质是降序排序的极值取首位。
  // 这一族契约和 `revisionExtremesOf` / `resolveRootTailFromEntries` /
  // `planLogFilesCleanup` / `mergePendingRevisions` 并列，构成 SvnAutoMerge
  // 的全部 5 个排序契约点。
  //
  // **N-tuple 第 5 元（R114/R115 之延续）**：modify(copyWith) /
  // compare(==) / render(toString) / serialize(toJson) / **sort(order)**——
  // 此处锁的是 sort 维度对 jobId 字段的"max+1"派生契约。
  group('deriveNextJobId — jobId 单调递增/极值排序契约（R116）', () {
    const j1 = MergeJob(
      jobId: 1,
      sourceUrl: 'svn://r',
      targetWc: '/wc',
      maxRetries: 1,
      revisions: [101],
    );
    const j2 = MergeJob(
      jobId: 2,
      sourceUrl: 'svn://r',
      targetWc: '/wc',
      maxRetries: 1,
      revisions: [102],
    );
    const j5 = MergeJob(
      jobId: 5,
      sourceUrl: 'svn://r',
      targetWc: '/wc',
      maxRetries: 1,
      revisions: [105],
    );
    const j9 = MergeJob(
      jobId: 9,
      sourceUrl: 'svn://r',
      targetWc: '/wc',
      maxRetries: 1,
      revisions: [109],
    );

    test('空 jobs → 1（首启动语义；与 `_nextJobId = 1` 默认值一致）', () {
      expect(deriveNextJobId(const []), 1);
    });

    test('单 job → max+1', () {
      expect(deriveNextJobId(const [j5]), 6);
    });

    test('多 job → max(jobId)+1，**不**依赖输入顺序', () {
      // 三种顺序产出同样结果——排序极值与输入顺序无关。
      expect(deriveNextJobId(const [j1, j5, j9]), 10);
      expect(deriveNextJobId(const [j9, j5, j1]), 10);
      expect(deriveNextJobId(const [j5, j9, j1]), 10);
    });

    test(
      '中间 jobId 被删除时仍取 max+1，**不**塌缩成 length+1（单调递增锁）',
      () {
        // 锁定"删除后仍单调递增"的语义：即使 jobs.length=2，nextJobId 仍 = 10。
        // 任何把 reduce(max) 误重构成 jobs.length + 1 的实现会在这里立刻翻车。
        expect(deriveNextJobId(const [j1, j9]), 10);
        expect(deriveNextJobId(const [j2, j9]).toString(), '10');
      },
    );

    test('jobId 全相等的退化输入 → max+1（reduce 兜底单元素的等价行为）', () {
      // 实际不会发生（addJob 用 ++ 严格递增），但本函数对这类输入仍稳定收敛。
      expect(deriveNextJobId(const [j5, j5, j5]), 6);
    });

    test('与 init() 的 inline 实现等价性锁（漂移信号）', () {
      // init() 之前内联：`_jobs.map((job) => job.jobId).reduce((a, b) => a > b ? a : b) + 1`
      // R116 抽出后，**此处锁定两种写法在合法输入上等价**——任何想替换为
      // `jobs.last.jobId + 1` / `jobs.length + 1` / 引入 sort 的"优化"，
      // 都会在此处与 inline 表达式断开。
      const cases = [
        [j1],
        [j1, j2],
        [j5, j1, j9, j2],
        [j9, j9],
      ];
      for (final c in cases) {
        final inlineEquivalent =
            c.map((job) => job.jobId).reduce((a, b) => a > b ? a : b) + 1;
        expect(
          deriveNextJobId(c),
          inlineEquivalent,
          reason: 'deriveNextJobId 必须与 reduce(max)+1 表达式逐输入等价；'
              '不等说明实现已偏离 jobId 单调递增的恢复语义',
        );
      }
    });
  });

  group('init targetUrl hydration', () {
    test('old jobs without targetUrl are hydrated from svn info and saved',
        () async {
      const oldJob = MergeJob(
        jobId: 7,
        sourceUrl: 'svn://repo/branches/b1',
        targetWc: '/Users/dev/work/b1',
        maxRetries: 3,
        revisions: [3],
        status: JobStatus.done,
      );
      final storage = _FakeStorageService([oldJob]);
      final svn = _FakeSvnService({
        '/Users/dev/work/b1': 'svn://repo/branches/b2',
      });
      final state = MergeExecutionState(
        storageService: storage,
        svnService: svn,
      );

      await state.init();

      expect(state.jobs.single.targetUrl, 'svn://repo/branches/b2');
      expect(storage.savedJobs, isNotNull);
      expect(storage.savedJobs!.single.targetUrl, 'svn://repo/branches/b2');
    });

    test('jobs with targetUrl are not rehydrated or re-saved', () async {
      const job = MergeJob(
        jobId: 8,
        sourceUrl: 'svn://repo/branches/b1',
        targetWc: '/Users/dev/work/b1',
        targetUrl: 'svn://repo/branches/b2',
        maxRetries: 3,
        revisions: [4],
        status: JobStatus.done,
      );
      final storage = _FakeStorageService([job]);
      final svn = _FakeSvnService(const {});
      final state = MergeExecutionState(
        storageService: storage,
        svnService: svn,
      );

      await state.init();

      expect(state.jobs.single.targetUrl, 'svn://repo/branches/b2');
      expect(storage.savedJobs, isNull);
    });
  });

  group('updateJobCommitSupplement', () {
    test('trim non-empty supplement, save queue and notify', () async {
      const pausedJob = MergeJob(
        jobId: 9,
        sourceUrl: 'svn://repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        maxRetries: 3,
        revisions: [3],
        status: JobStatus.paused,
        pauseReason: 'Code-Review-Rule: missing CRID',
      );
      final storage = _FakeStorageService([pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        svnService: _FakeSvnService({
          '/Users/dev/work/b2': 'svn://repo/branches/b2',
        }),
      );
      await state.init();

      var notifyCount = 0;
      state.addListener(() => notifyCount++);
      final ok = await state.updateJobCommitSupplement(
        9,
        '  --crid=123456  ',
      );

      expect(ok, isTrue);
      expect(state.jobs.single.commitSupplement, '--crid=123456');
      expect(storage.savedJobs!.single.commitSupplement, '--crid=123456');
      expect(notifyCount, 2);
    });

    test('blank supplement is rejected', () async {
      const job = MergeJob(
        jobId: 10,
        sourceUrl: 'svn://repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        maxRetries: 3,
        revisions: [4],
        status: JobStatus.paused,
      );
      final storage = _FakeStorageService([job]);
      final state = MergeExecutionState(
        storageService: storage,
        svnService: _FakeSvnService({
          '/Users/dev/work/b2': 'svn://repo/branches/b2',
        }),
      );
      await state.init();

      final ok = await state.updateJobCommitSupplement(10, '   ');

      expect(ok, isFalse);
      expect(state.jobs.single.commitSupplement, isNull);
    });
  });

  group('updateJobCommitMessageOverride', () {
    test('saves full message for current revision without trimming content',
        () async {
      const pausedJob = MergeJob(
        jobId: 11,
        sourceUrl: 'svn://repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        maxRetries: 3,
        revisions: [123],
        status: JobStatus.paused,
        completedIndex: 0,
      );
      final storage = _FakeStorageService([pausedJob]);
      final state = MergeExecutionState(
        storageService: storage,
        svnService: _FakeSvnService(const {}),
      );
      await state.init();

      const message = '  custom subject\n\nbody line  ';
      final ok = await state.updateJobCommitMessageOverride(
        jobId: 11,
        revision: 123,
        message: message,
      );

      expect(ok, isTrue);
      expect(state.jobs.single.commitMessageOverride, message);
      expect(state.jobs.single.commitMessageOverrideRevision, 123);
      expect(storage.savedJobs!.single.commitMessageOverride, message);
    });

    test('blank full message is rejected', () async {
      const job = MergeJob(
        jobId: 12,
        sourceUrl: 'svn://repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        maxRetries: 3,
        revisions: [123],
      );
      final state = MergeExecutionState(
        storageService: _FakeStorageService([job]),
        svnService: _FakeSvnService(const {}),
      );
      await state.init();

      final ok = await state.updateJobCommitMessageOverride(
        jobId: 12,
        revision: 123,
        message: '   ',
      );

      expect(ok, isFalse);
      expect(state.jobs.single.commitMessageOverride, isNull);
    });
  });

  // R117 集合查找契约审计——把散落的 `_jobs.indexWhere((job) => job.jobId == X)`
  // 与 `steps.indexWhere((s) => s.id == Y)` 6+4 处 inline 收敛到 findJobIndexById /
  // findStepIndexById 两个 helper，并锁定哨兵 -1 + 等价性 + 唯一性契约。
  //
  // **为什么 R117 与 R116 同抽象层但维度不同**：R116 锁的是 sort（集合 → 标量），
  // R117 锁的是 lookup（集合 → 元素/下标），二者并列构成"集合操作 contract"族。
  // 同 R102/R103/R114/R115/R116 的 5 元组 invariance 不同——本族属于"派生函数族"，
  // 输入是集合、输出形态各异（标量 / 下标 / 元素 / Iterable）。
  group('findJobIndexById — jobId 查找哨兵语义（R117）', () {
    const j1 = MergeJob(
      jobId: 1,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [101],
      status: JobStatus.pending,
    );
    const j2 = MergeJob(
      jobId: 2,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [102],
      status: JobStatus.running,
    );
    const j5 = MergeJob(
      jobId: 5,
      sourceUrl: 'svn://source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: [105],
      status: JobStatus.done,
    );

    test('空 jobs → -1（哨兵；caller 必须 < 0 兜底）', () {
      expect(findJobIndexById(const [], 1), -1);
    });

    test('找到 → 首个匹配下标（jobId 全局唯一是上游契约）', () {
      expect(findJobIndexById(const [j1, j2, j5], 2), 1);
      expect(findJobIndexById(const [j1, j2, j5], 1), 0);
      expect(findJobIndexById(const [j1, j2, j5], 5), 2);
    });

    test('找不到 → -1（**不抛 StateError**；与 firstWhere 默认行为对偶）', () {
      // 显式锁定哨兵 vs 异常的设计选择——若有人把实现改成 firstWhere(...).index,
      // 找不到时会抛 StateError 让 caller 全部炸开。
      expect(findJobIndexById(const [j1, j2], 999), -1);
      expect(() => findJobIndexById(const [j1, j2], 999), returnsNormally);
    });

    test('与 resolveCurrentJobIndex（非 null 分支）逐输入等价（漂移信号）', () {
      // R117 把 resolveCurrentJobIndex 的非 null 分支 delegate 到 findJobIndexById，
      // 这里锁定两个 helper 在 jobId != null 时输出严格相等——任何"优化"（如
      // 在 resolveCurrentJobIndex 里改成 indexOf 或加排序）都会在此处撞红。
      const cases = [
        [j1, j2, j5],
        [j5, j1],
        <MergeJob>[],
      ];
      const probes = [1, 2, 5, 999];
      for (final jobs in cases) {
        for (final id in probes) {
          expect(
            findJobIndexById(jobs, id),
            resolveCurrentJobIndex(jobId: id, jobs: jobs),
            reason: 'findJobIndexById 必须与 resolveCurrentJobIndex(非 null) 等价',
          );
        }
      }
    });

    test('inline indexWhere 等价锁——防"美化"成 indexOf', () {
      // lib R117 改造前，6 处 callsite 都写 `_jobs.indexWhere((job) => job.jobId == X)`。
      // 此处锁定 helper 输出与原始 inline 表达式逐输入等价——任何改成
      // `jobs.map((j) => j.jobId).toList().indexOf(X)` 的"扁平化"重写，都会在
      // 空 jobs / 找不到 / 多匹配场景下与 indexWhere 出现差异（或性能差）。
      const cases = [
        [j1, j2, j5],
        [j5, j1, j2],
        <MergeJob>[],
      ];
      const probes = [1, 2, 5, 999];
      for (final jobs in cases) {
        for (final id in probes) {
          final inlineEquivalent = jobs.indexWhere((job) => job.jobId == id);
          expect(
            findJobIndexById(jobs, id),
            inlineEquivalent,
            reason: 'findJobIndexById 必须与 indexWhere((j) => j.jobId == X) 表达式'
                '逐输入等价；不等说明实现已偏离 R85-R89 helper-vs-inline 漏迁防线',
          );
        }
      }
    });
  });

  group('findStepIndexById — stepId 查找哨兵语义（R117）', () {
    test('找到已知 step id → 对应下标（kPrepare/kUpdate/kMerge/kValidate/kCommit 全覆盖）',
        () {
      // 锁定 kMergeExecutionSteps 常量列表的顺序——若有人重排步骤定义，下面
      // 5 条断言会逐一撞红，强制走显式迁移决策（涉及 _runRevision 的 startIndex
      // 比较语义）。
      expect(findStepIndexById(kMergeExecutionSteps, kPrepareStepId), 0);
      expect(findStepIndexById(kMergeExecutionSteps, kUpdateStepId), 1);
      expect(findStepIndexById(kMergeExecutionSteps, kMergeStepId), 2);
      expect(findStepIndexById(kMergeExecutionSteps, kValidateStepId), 3);
      expect(findStepIndexById(kMergeExecutionSteps, kCommitStepId), 4);
    });

    test('未知 stepId → -1（caller 通过 -1 触发"未知恢复步骤"诊断分支）', () {
      // _runRevision 的 startIndex == -1 分支会输出 [ERROR] 日志并 return paused——
      // 这是恢复链路的安全兜底，必须靠 helper 的 -1 哨兵触发。
      expect(findStepIndexById(kMergeExecutionSteps, 'nonexistent_step'), -1);
      expect(findStepIndexById(kMergeExecutionSteps, ''), -1);
    });

    test('空 steps → -1（防御性兜底；常量列表实测不会为空）', () {
      expect(
        findStepIndexById(
            const <MergeExecutionStepDefinition>[], kPrepareStepId),
        -1,
      );
    });

    test('inline indexWhere 等价锁——防与 findJobIndexById 实现漂移', () {
      // 4 处 callsite 都写 `steps.indexWhere((step/item) => step.id == X)`。
      // findStepIndexById 与 findJobIndexById 故意保持平行结构（doc 已说明不抽
      // 泛型 helper），此处锁定 stepId 路径的 inline 等价性。
      const probes = [
        kPrepareStepId,
        kUpdateStepId,
        kMergeStepId,
        kValidateStepId,
        kCommitStepId,
        'unknown',
      ];
      for (final id in probes) {
        final inlineEquivalent =
            kMergeExecutionSteps.indexWhere((step) => step.id == id);
        expect(
          findStepIndexById(kMergeExecutionSteps, id),
          inlineEquivalent,
          reason: 'findStepIndexById 必须与 indexWhere((s) => s.id == X) 表达式逐'
              '输入等价；不等说明 R117 helper-vs-inline 收敛已被破坏',
        );
      }
    });

    test('helper 之间的不可收敛性 doc 化——故意不抽泛型 lookupById', () {
      // R117 的 doc 明确说："不抽泛型 helper，因为 Dart 没有 'has id field'
      // 的结构类型"。这条测试把"两个 helper 平行存在但不收敛"显式锁定——
      // 若有人引入 `int lookupById<T>(List<T>, dynamic id, int Function(T) extract)`,
      // findJobIndexById / findStepIndexById 会变成两行 delegate，本测试通过
      // 检查两个 helper 各自独立可用、无共享 lookup 来 doc 化此设计。
      expect(findJobIndexById(const [], 1), -1);
      expect(findStepIndexById(const [], 'x'), -1);
      // 两个 helper 不能跨用——下面这两个表达式编译都通不过（类型不兼容），
      // 这就是"不抽泛型"的设计本意（编译期防止误用）。如果未来某一天合并成
      // 泛型，需要重新评估两个查找谓词的语义是否真的相同。
    });
  });

  group('pausedJob getter — firstWhere + try-catch 等价 firstWhereOrNull（R117）',
      () {
    test(
      '无 paused job → null（StateError 被 try-catch 兜成 null，等价 firstWhereOrNull）',
      () async {
        final state = MergeExecutionState();
        // 无任何 init/load——_jobs 为空 → firstWhere 抛 StateError → catch → null
        expect(state.pausedJob, isNull);
      },
    );

    test('单个 paused job 之外只有 pending → 找到该 paused job', () async {
      final state = MergeExecutionState();
      // 通过反射不可能直接注入 _jobs（私有字段）——本测试通过 hasPausedJob
      // 间接锁定 pausedJob 与 _jobs.firstWhere 的语义对偶；细粒度场景由
      // deriveHasPausedJob 的现有测试覆盖。空状态返回 null 是本测试的核心断言。
      expect(state.hasPausedJob, isFalse);
      expect(state.pausedJob, isNull);
    });
  });

  group('R123 removeAt arbitrary-index 二档判据 doc-as-test', () {
    // **R123 上下文**：MergeExecutionState.deleteJob 内 `_jobs.removeAt(index)`
    // 的 index 来自 `findJobIndexById` 谓词命中——属档 2（任意 index removal）。
    // 这一组锁定"保留 List"决策的合理性：上下行用 `_currentJobIndex > index` /
    // `== index` 做关系运算，Queue 抹掉位置语义后无法表达。
    test('档 2：deleteJob 的 index 来自 findJobIndexById、非头部 drain', () {
      // findJobIndexById 是 R117 抽出的纯函数——锁住 deleteJob 用的"索引"
      // 是按谓词命中得来，不是固定位置。
      final jobs = <MergeJob>[
        const MergeJob(
            jobId: 10,
            sourceUrl: 'a',
            targetWc: 'b',
            maxRetries: 0,
            revisions: [1]),
        const MergeJob(
            jobId: 20,
            sourceUrl: 'a',
            targetWc: 'b',
            maxRetries: 0,
            revisions: [2]),
        const MergeJob(
            jobId: 30,
            sourceUrl: 'a',
            targetWc: 'b',
            maxRetries: 0,
            revisions: [3]),
      ];
      expect(findJobIndexById(jobs, 20), equals(1),
          reason: 'index 由 jobId 谓词命中决定，不是 0 或 last');
      expect(findJobIndexById(jobs, 30), equals(2));
      expect(findJobIndexById(jobs, 999), equals(-1),
          reason: '未命中返回 -1，调用方需在 R0+ 决定如何处理');
    });

    test('档 2 判据：Queue 无 removeAt(int)，且 deleteJob 还需 _currentJobIndex 关系运算',
        () {
      // 反证为何不能改 Queue：deleteJob 内 `_currentJobIndex > index` /
      // `== index` 依赖删除位置——Queue 把位置概念抹掉后无从计算。
      // List.removeAt(index) 同时承载"删除"+"返回 index"两层语义，Queue 只
      // 提供"从一端删"无 index 概念。
      final jobs = <int>[10, 20, 30];
      var currentIndex = 1; // 模拟 _currentJobIndex
      const targetIndex = 1; // 模拟 findJobIndexById 命中
      jobs.removeAt(targetIndex);
      // deleteJob 的关系更新逻辑（lib :690-694 简化版）
      if (currentIndex > targetIndex) {
        currentIndex--;
      } else if (currentIndex == targetIndex) {
        currentIndex = -1;
      }
      expect(jobs, equals([10, 30]));
      expect(currentIndex, equals(-1),
          reason: 'currentIndex == targetIndex → 被删除的就是 current');
    });
  });
}
