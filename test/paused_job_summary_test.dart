/// `paused_job_summary.dart` 的纯函数单测——锁定四类信号在不同输入组合下的
/// 摘要结构。
///
/// 测试维度：
/// - pauseReason 为空 → fallback `'等待人工处理'`；
/// - completedIndex 越界 → 被夹紧到 `[0, total]`；
/// - failed snapshot 优先级（prepare → update → merge → commit）；
/// - commit retry 信息只在 commit step failed 且 output.data 含两个 int 时显示；
/// - resolveStepDisplayName 4 个 step + 未知 id 兜底。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/paused_job_summary.dart';
import 'package:svn_auto_merge/execution/step_output.dart';
import 'package:svn_auto_merge/execution/step_snapshot.dart';
import 'package:svn_auto_merge/execution/svn_failure_kind.dart';
import 'package:svn_auto_merge/models/merge_job.dart';

MergeJob _job({
  int jobId = 1,
  List<int> revisions = const [101, 102, 103],
  int completedIndex = 1,
  String pauseReason = '',
  int maxRetries = 3,
}) =>
    MergeJob(
      jobId: jobId,
      sourceUrl: 'svn://src',
      targetWc: '/tmp/wc',
      maxRetries: maxRetries,
      revisions: revisions,
      completedIndex: completedIndex,
      pauseReason: pauseReason,
    );

StepSnapshot _failedSnap({
  required String stepId,
  String? stepName,
  String? error,
  StepOutput? output,
}) =>
    StepSnapshot(
      stepId: stepId,
      stepTypeId: stepId,
      stepName: stepName,
      status: StepExecutionStatus.failed,
      inputData: const {},
      config: const {},
      output: output,
      error: error,
      startTime: DateTime(2026, 1, 1),
      endTime: DateTime(2026, 1, 1, 0, 0, 1),
    );

void main() {
  group('resolveStepDisplayName', () {
    test('4 个固定步骤映射到中文', () {
      expect(resolveStepDisplayName('prepare'), '准备');
      expect(resolveStepDisplayName('update'), '更新');
      expect(resolveStepDisplayName('merge'), '合并');
      expect(resolveStepDisplayName('commit'), '提交');
    });

    test('未知 id 原样返回（不抛、不空兜底）', () {
      expect(resolveStepDisplayName('unknown'), 'unknown');
      expect(resolveStepDisplayName(''), '');
    });
  });

  group('findFailedSnapshot 优先级', () {
    test('多个 fail 时按 prepare→update→merge→commit 取最早', () {
      final snaps = {
        'commit': _failedSnap(stepId: 'commit', error: 'commit fail'),
        'merge': _failedSnap(stepId: 'merge', error: 'merge fail'),
        'update': _failedSnap(stepId: 'update', error: 'update fail'),
      };
      expect(findFailedSnapshot(snaps)?.stepId, 'update');
    });

    test('全 completed → null', () {
      final snaps = {
        'merge': StepSnapshot(
          stepId: 'merge',
          stepTypeId: 'merge',
          status: StepExecutionStatus.completed,
          inputData: const {},
          config: const {},
          startTime: DateTime(2026),
        ),
      };
      expect(findFailedSnapshot(snaps), isNull);
    });

    test('空 map → null', () {
      expect(findFailedSnapshot(const {}), isNull);
    });
  });

  group('summarizePausedJob 基础聚合', () {
    test('空 pauseReason → 占位文案', () {
      final s = summarizePausedJob(job: _job(), snapshots: const {});
      expect(s.pauseReason, '等待人工处理');
    });

    test('非空 pauseReason 被 trim 后保留', () {
      final s = summarizePausedJob(
        job: _job(pauseReason: '  冲突  '),
        snapshots: const {},
      );
      expect(s.pauseReason, '冲突');
    });

    test('completedIndex 越界被夹紧到 [0, total]', () {
      final negative = summarizePausedJob(
        job: _job(completedIndex: -5, revisions: const [1, 2, 3]),
        snapshots: const {},
      );
      expect(negative.completedCount, 0);
      expect(negative.totalCount, 3);

      final overflow = summarizePausedJob(
        job: _job(completedIndex: 99, revisions: const [1, 2, 3]),
        snapshots: const {},
      );
      expect(overflow.completedCount, 3);
    });

    test('currentRevision 取自 job.currentRevision（completedIndex 处的元素）', () {
      final s = summarizePausedJob(
        job: _job(revisions: const [101, 102, 103], completedIndex: 1),
        snapshots: const {},
      );
      expect(s.currentRevision, 102);
    });

    test('completedIndex == revisions.length → currentRevision 为 null', () {
      final s = summarizePausedJob(
        job: _job(revisions: const [101], completedIndex: 1),
        snapshots: const {},
      );
      expect(s.currentRevision, isNull);
    });
  });

  group('summarizePausedJob 失败步骤信号', () {
    test('snapshot stepName 优先 → 显示名用 stepName', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'merge': _failedSnap(
            stepId: 'merge',
            stepName: '自定义合并名',
            error: '冲突 in foo.dart',
          ),
        },
      );
      expect(s.failedStepName, '自定义合并名');
      expect(s.failedStepError, '冲突 in foo.dart');
      expect(s.hasFailedStepInfo, isTrue);
    });

    test('snapshot stepName 缺失 → 用 resolveStepDisplayName 回填', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {'commit': _failedSnap(stepId: 'commit', error: 'oops')},
      );
      expect(s.failedStepName, '提交');
    });

    test('error 前后空白被 trim', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {'merge': _failedSnap(stepId: 'merge', error: '  msg\n  ')},
      );
      expect(s.failedStepError, 'msg');
    });

    test('error 为空字符串 → failedStepError = null', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {'merge': _failedSnap(stepId: 'merge', error: '   ')},
      );
      expect(s.failedStepError, isNull);
    });

    test('无任何 failed snapshot → 失败信号全 null', () {
      final s = summarizePausedJob(job: _job(), snapshots: const {});
      expect(s.failedStepName, isNull);
      expect(s.failedStepError, isNull);
      expect(s.hasFailedStepInfo, isFalse);
    });
  });

  group('summarizePausedJob commit retry 信号', () {
    test('commit 失败 + output.data 含 retryCount/maxRetries (int) → 两值显示', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'commit': _failedSnap(
            stepId: 'commit',
            error: 'oops',
            output: const StepOutput(
              port: 'failure',
              data: {'retryCount': 2, 'maxRetries': 3},
              isSuccess: false,
            ),
          ),
        },
      );
      expect(s.commitRetryCount, 2);
      expect(s.commitMaxRetries, 3);
      expect(s.hasCommitRetryInfo, isTrue);
    });

    test('retryCount = 0 → hasCommitRetryInfo = false（避免 0/3 噪音）', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'commit': _failedSnap(
            stepId: 'commit',
            output: const StepOutput(
              port: 'failure',
              data: {'retryCount': 0, 'maxRetries': 3},
              isSuccess: false,
            ),
          ),
        },
      );
      expect(s.commitRetryCount, 0);
      expect(s.hasCommitRetryInfo, isFalse);
    });

    test('output.data 缺失任一字段 → 两值都为 null', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'commit': _failedSnap(
            stepId: 'commit',
            output: const StepOutput(
              port: 'failure',
              data: {'retryCount': 2},
              isSuccess: false,
            ),
          ),
        },
      );
      expect(s.commitRetryCount, isNull);
      expect(s.commitMaxRetries, isNull);
    });

    test('字段类型非 int → 两值都为 null（防御 JSON 反序列化漂移）', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'commit': _failedSnap(
            stepId: 'commit',
            output: const StepOutput(
              port: 'failure',
              data: {'retryCount': '2', 'maxRetries': 3},
              isSuccess: false,
            ),
          ),
        },
      );
      expect(s.commitRetryCount, isNull);
    });

    test('commit snapshot 不是 failed → 不取 retry 信息', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'commit': StepSnapshot(
            stepId: 'commit',
            stepTypeId: 'commit',
            status: StepExecutionStatus.completed,
            inputData: const {},
            config: const {},
            output: const StepOutput(
              port: 'success',
              data: {'retryCount': 1, 'maxRetries': 3},
            ),
            startTime: DateTime(2026),
          ),
        },
      );
      expect(s.commitRetryCount, isNull);
    });
  });

  group('PausedJobSummary 渲染谓词', () {
    test('hasFailedStepInfo 仅 name / error 至少一个非空时 true', () {
      const a = PausedJobSummary(
        jobId: 1,
        pauseReason: 'r',
        currentRevision: null,
        completedCount: 0,
        totalCount: 0,
        failedStepName: '',
        failedStepError: '',
        commitRetryCount: null,
        commitMaxRetries: null,
      );
      expect(a.hasFailedStepInfo, isFalse);

      const b = PausedJobSummary(
        jobId: 1,
        pauseReason: 'r',
        currentRevision: null,
        completedCount: 0,
        totalCount: 0,
        failedStepName: '合并',
        failedStepError: null,
        commitRetryCount: null,
        commitMaxRetries: null,
      );
      expect(b.hasFailedStepInfo, isTrue);
    });
  });

  group('summarizePausedJob failureKind 推断', () {
    test('snapshot.error 含 out-of-date → outOfDate', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'commit': _failedSnap(
            stepId: 'commit',
            error: "svn: E160028: '/foo' is out of date",
          ),
        },
      );
      expect(s.failureKind, SvnFailureKind.outOfDate);
    });

    test('snapshot.error 含 tree conflict → treeConflict', () {
      final s = summarizePausedJob(
        job: _job(),
        snapshots: {
          'merge':
              _failedSnap(stepId: 'merge', error: 'tree conflict at /a/b'),
        },
      );
      expect(s.failureKind, SvnFailureKind.treeConflict);
    });

    test('无 snapshot 但 pauseReason 含网络关键词 → network（fallback 到 pauseReason）', () {
      final s = summarizePausedJob(
        job: _job(pauseReason: 'Connection refused'),
        snapshots: const {},
      );
      expect(s.failureKind, SvnFailureKind.network);
    });

    test('无 snapshot 且 pauseReason 空 → unknown', () {
      final s = summarizePausedJob(job: _job(), snapshots: const {});
      expect(s.failureKind, SvnFailureKind.unknown);
    });
  });
}
