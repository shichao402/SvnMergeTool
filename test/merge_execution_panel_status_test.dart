import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/execution/svn_failure_kind.dart';
import 'package:svn_auto_merge/execution/step_output.dart';
import 'package:svn_auto_merge/execution/step_snapshot.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/screens/components/merge_execution_panel.dart';

void main() {
  group('snapshotStatusText', () {
    test('covers all StepExecutionStatus values', () {
      expect(snapshotStatusText(StepExecutionStatus.pending), '待执行');
      expect(snapshotStatusText(StepExecutionStatus.running), '执行中');
      expect(snapshotStatusText(StepExecutionStatus.completed), '已完成');
      expect(snapshotStatusText(StepExecutionStatus.failed), '失败');
      expect(snapshotStatusText(StepExecutionStatus.skipped), '已跳过');
    });

    test('R95 防漏配：StepExecutionStatus.values.length == 5（新增 enum 时强制 review）',
        () {
      // 与 executorStatusIsBusy group 的"全部 .values 真值表覆盖"同款防漏配契约：
      // helper 自身的 exhaustive switch 在新增 enum 时会编译报错强迫加 case，但这里
      // 锁住"测试本身的覆盖宣称"——`covers all` 这条 doc 不会因 enum 扩展而自动失效。
      // 任何一个 helper（Text/Color/Icon）都需要决定新值的展示文案/颜色/图标，本断言
      // 让"测试通过 = 已 review 过新 enum 的展示策略"成立。
      expect(StepExecutionStatus.values.length, 5,
          reason:
              '当 StepExecutionStatus 新增枚举值时本测会红，强制 review snapshotStatusText 的展示文案');
    });
  });

  group('snapshotStatusColor', () {
    test('covers all StepExecutionStatus values', () {
      expect(snapshotStatusColor(StepExecutionStatus.pending), Colors.grey);
      expect(snapshotStatusColor(StepExecutionStatus.running), Colors.blue);
      expect(snapshotStatusColor(StepExecutionStatus.completed), Colors.green);
      expect(snapshotStatusColor(StepExecutionStatus.failed), Colors.red);
      expect(snapshotStatusColor(StepExecutionStatus.skipped), Colors.orange);
    });

    test('R95 防漏配：StepExecutionStatus.values.length == 5（新增 enum 时强制 review）',
        () {
      expect(StepExecutionStatus.values.length, 5,
          reason:
              '当 StepExecutionStatus 新增枚举值时本测会红，强制 review snapshotStatusColor 的颜色映射');
    });
  });

  group('executorStatusTitle', () {
    test('covers all ExecutorStatus values', () {
      expect(executorStatusTitle(ExecutorStatus.idle), '等待执行');
      expect(executorStatusTitle(ExecutorStatus.running), '执行中');
      expect(executorStatusTitle(ExecutorStatus.paused), '已暂停');
      expect(executorStatusTitle(ExecutorStatus.completed), '执行完成');
    });

    test('R95 防漏配：ExecutorStatus.values.length == 4（新增 enum 时强制 review）', () {
      expect(ExecutorStatus.values.length, 4,
          reason:
              '当 ExecutorStatus 新增枚举值时本测会红，强制 review executorStatusTitle 的标题文案');
    });
  });

  group('executorStatusIcon', () {
    test('covers all ExecutorStatus values', () {
      expect(executorStatusIcon(ExecutorStatus.idle), Icons.schedule);
      expect(executorStatusIcon(ExecutorStatus.running), Icons.play_circle);
      expect(executorStatusIcon(ExecutorStatus.paused), Icons.pause_circle);
      expect(executorStatusIcon(ExecutorStatus.completed), Icons.check_circle);
    });

    test('R95 防漏配：ExecutorStatus.values.length == 4（新增 enum 时强制 review）', () {
      expect(ExecutorStatus.values.length, 4,
          reason:
              '当 ExecutorStatus 新增枚举值时本测会红，强制 review executorStatusIcon 的图标映射');
    });
  });

  group('executorStatusIsBusy', () {
    test('running → true（唯一 busy 态）', () {
      expect(executorStatusIsBusy(ExecutorStatus.running), isTrue);
    });

    test('idle → false（无任务在跑，无须 spinner）', () {
      expect(executorStatusIsBusy(ExecutorStatus.idle), isFalse);
    });

    test('paused → false（暂停态，静态图标即可表达）', () {
      expect(executorStatusIsBusy(ExecutorStatus.paused), isFalse);
    });

    test('completed → false（已完成，静态打勾即可）', () {
      expect(executorStatusIsBusy(ExecutorStatus.completed), isFalse);
    });

    test('全部 ExecutorStatus.values 真值表覆盖（防止新增 enum 时漏配）', () {
      // 与 shouldShowTerminateHint 同款"防漏配"契约：未来若 enum 新增第 5 态，
      // 本测会因没断言新值而强制提醒补 case 决策。
      final busyStates =
          ExecutorStatus.values.where(executorStatusIsBusy).toSet();
      expect(busyStates, {ExecutorStatus.running});
      expect(
        ExecutorStatus.values.length,
        4,
        reason: '当 ExecutorStatus 新增枚举值时本测会红，强制 review executorStatusIsBusy',
      );
    });

    test('与 shouldShowTerminateHint 在 running 态同真，但前缀/语义刻意不同（防误合并）', () {
      // 两个 helper 当前在 4 个 status 上的真值完全相同，但用途不同：
      // - executorStatusIsBusy: 决定 header 图标 vs spinner
      // - shouldShowTerminateHint: 决定底部是否显示"延迟生效"提示
      // 单测显式锁住"真值相同"是巧合，不可借此合并——一旦其中一方契约变化（比如
      // paused 也要 spinner），合并版会同时影响另一边的提示文案。
      for (final s in ExecutorStatus.values) {
        expect(
          executorStatusIsBusy(s),
          equals(shouldShowTerminateHint(s)),
          reason: 'status=$s 当前真值应一致（巧合而非语义等价）',
        );
      }
    });
  });

  group('executorStatusColor', () {
    test('covers all ExecutorStatus values', () {
      expect(executorStatusColor(ExecutorStatus.idle), Colors.grey);
      expect(executorStatusColor(ExecutorStatus.running), Colors.blue);
      expect(executorStatusColor(ExecutorStatus.paused), Colors.orange);
      expect(executorStatusColor(ExecutorStatus.completed), Colors.green);
    });

    test('R95 防漏配：ExecutorStatus.values.length == 4（新增 enum 时强制 review）', () {
      expect(ExecutorStatus.values.length, 4,
          reason:
              '当 ExecutorStatus 新增枚举值时本测会红，强制 review executorStatusColor 的颜色映射');
    });
  });

  group('shouldShowEditCommitSupplementButton', () {
    test('missingCrid → true', () {
      expect(
        shouldShowEditCommitSupplementButton(SvnFailureKind.missingCrid),
        isTrue,
      );
    });

    test('non missingCrid kinds → false', () {
      for (final kind in SvnFailureKind.values) {
        if (kind == SvnFailureKind.missingCrid) continue;
        expect(
          shouldShowEditCommitSupplementButton(kind),
          isFalse,
          reason: 'kind=$kind',
        );
      }
    });
  });

  group('shouldShowCreateCodeReviewButton', () {
    test('missingCrid → true', () {
      expect(
        shouldShowCreateCodeReviewButton(SvnFailureKind.missingCrid),
        isTrue,
      );
    });

    test('non missingCrid kinds → false', () {
      for (final kind in SvnFailureKind.values) {
        if (kind == SvnFailureKind.missingCrid) continue;
        expect(
          shouldShowCreateCodeReviewButton(kind),
          isFalse,
          reason: 'kind=$kind',
        );
      }
    });
  });

  group('shouldShowResumeCommitButton', () {
    test('missingCrid with commit supplement → true', () {
      expect(
        shouldShowResumeCommitButton(
          SvnFailureKind.missingCrid,
          '--crid=123456',
          7,
          null,
          null,
        ),
        isTrue,
      );
    });

    test('missingCrid without commit supplement → false', () {
      expect(
        shouldShowResumeCommitButton(
          SvnFailureKind.missingCrid,
          null,
          7,
          null,
          null,
        ),
        isFalse,
      );
      expect(
        shouldShowResumeCommitButton(
          SvnFailureKind.missingCrid,
          '   ',
          7,
          null,
          null,
        ),
        isFalse,
      );
    });

    test('unknown with current revision message override → true', () {
      expect(
        shouldShowResumeCommitButton(
          SvnFailureKind.unknown,
          null,
          7,
          'manual message',
          7,
        ),
        isTrue,
      );
    });

    test('missingCrid with current revision message override → true', () {
      expect(
        shouldShowResumeCommitButton(
          SvnFailureKind.missingCrid,
          null,
          7,
          '[Merge] r7 from svn://repo\n\n--crid=9',
          7,
        ),
        isTrue,
      );
    });

    test('non missingCrid kinds → false', () {
      for (final kind in SvnFailureKind.values) {
        if (kind == SvnFailureKind.missingCrid ||
            kind == SvnFailureKind.unknown) {
          continue;
        }
        expect(
          shouldShowResumeCommitButton(kind, '--crid=123456', 7, null, null),
          isFalse,
          reason: 'kind=$kind',
        );
      }
    });
  });

  group('shouldShowEditCommitMessageButton', () {
    test('unknown commit failure → true', () {
      expect(
        shouldShowEditCommitMessageButton(
          failureKind: SvnFailureKind.unknown,
          failedStepName: '提交',
          resumeFromStepId: 'commit',
        ),
        isTrue,
      );
    });

    test('unknown non-commit failure → false', () {
      expect(
        shouldShowEditCommitMessageButton(
          failureKind: SvnFailureKind.unknown,
          failedStepName: '合并',
          resumeFromStepId: 'merge',
        ),
        isFalse,
      );
    });

    test('known commit failure → false', () {
      expect(
        shouldShowEditCommitMessageButton(
          failureKind: SvnFailureKind.missingCrid,
          failedStepName: '提交',
          resumeFromStepId: 'commit',
        ),
        isFalse,
      );
    });
  });

  group('MergeExecutionPanel CRID resume action', () {
    testWidgets('CRID 回填后在暂停摘要区显示继续提交', (tester) async {
      var resumed = false;
      final now = DateTime(2026, 6, 4);
      final job = MergeJob(
        jobId: 1,
        sourceUrl: 'svn://example/repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        maxRetries: 3,
        revisions: const [7],
        status: JobStatus.paused,
        pauseReason: 'Code-Review-Rule: missing CRID',
        commitSupplement: '--crid=123456',
        resumeFromStepId: 'commit',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MergeExecutionPanel(
              status: ExecutorStatus.paused,
              pausedJob: job,
              onResume: () {
                resumed = true;
              },
              onSkip: () {},
              onCancel: () {},
              snapshots: {
                'commit': StepSnapshot(
                  stepId: 'commit',
                  stepTypeId: 'commit',
                  stepName: '提交',
                  status: StepExecutionStatus.failed,
                  inputData: const {},
                  config: const {},
                  output: StepOutput.failure(),
                  error: 'Code-Review-Rule: missing CRID',
                  startTime: now,
                  endTime: now,
                ),
              },
            ),
          ),
        ),
      );

      final continueCommit = find.text('继续提交');
      expect(continueCommit, findsOneWidget);
      await tester.tap(continueCommit);
      expect(resumed, isTrue);
    });
  });

  group('MergeExecutionPanel edit commit message action', () {
    testWidgets('未知提交失败时显示修改提交 Message', (tester) async {
      final now = DateTime(2026, 6, 4);
      var editCalled = false;
      final job = MergeJob(
        jobId: 2,
        sourceUrl: 'svn://example/repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        maxRetries: 3,
        revisions: const [9],
        status: JobStatus.paused,
        pauseReason: 'message format invalid',
        resumeFromStepId: 'commit',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MergeExecutionPanel(
              status: ExecutorStatus.paused,
              pausedJob: job,
              onResume: () {},
              onSkip: () {},
              onCancel: () {},
              onEditCommitMessage: () {
                editCalled = true;
              },
              snapshots: {
                'commit': StepSnapshot(
                  stepId: 'commit',
                  stepTypeId: 'commit',
                  stepName: '提交',
                  status: StepExecutionStatus.failed,
                  inputData: const {},
                  config: const {},
                  output: StepOutput.failure(),
                  error: 'message format invalid',
                  startTime: now,
                  endTime: now,
                ),
              },
            ),
          ),
        ),
      );

      final editButton = find.text('修改提交 Message');
      expect(editButton, findsOneWidget);
      await tester.tap(editButton);
      expect(editCalled, isTrue);
    });
  });

  group('executorStatusMessage', () {
    test('covers all ExecutorStatus values', () {
      expect(executorStatusMessage(ExecutorStatus.idle), '等待开始');
      expect(executorStatusMessage(ExecutorStatus.running), '正在执行...');
      expect(executorStatusMessage(ExecutorStatus.paused), '等待人工处理');
      expect(executorStatusMessage(ExecutorStatus.completed), '执行完成');
    });

    test('R95 防漏配：ExecutorStatus.values.length == 4（新增 enum 时强制 review）', () {
      expect(ExecutorStatus.values.length, 4,
          reason:
              '当 ExecutorStatus 新增枚举值时本测会红，强制 review executorStatusMessage 的状态消息');
    });
  });

  group('decodeUnicodeEscapes', () {
    test('returns input unchanged when no escapes present', () {
      expect(decodeUnicodeEscapes('hello world'), 'hello world');
      expect(decodeUnicodeEscapes(''), '');
    });

    test('decodes a single {U+xxxx} escape', () {
      // U+4F60 -> 你
      expect(decodeUnicodeEscapes('hello {U+4F60}'), 'hello 你');
    });

    test('decodes multiple escapes in one string', () {
      // U+4F60 -> 你, U+597D -> 好
      expect(decodeUnicodeEscapes('{U+4F60}{U+597D}!'), '你好!');
    });

    test('accepts both upper and lower case hex', () {
      expect(decodeUnicodeEscapes('{U+4f60}'), '你');
      expect(decodeUnicodeEscapes('{U+4F60}'), '你');
    });

    test('decodes 6-digit code points', () {
      // U+1F600 -> 😀
      expect(decodeUnicodeEscapes('{U+1F600}'), '😀');
    });

    test('leaves malformed escapes untouched', () {
      // 3-digit hex below the 4..6 range should not match.
      expect(decodeUnicodeEscapes('{U+ABC}'), '{U+ABC}');
      // Missing U+ prefix should not match.
      expect(decodeUnicodeEscapes('{4F60}'), '{4F60}');
    });
  });

  group('formatRevisionProgress', () {
    MergeJob job({
      required List<int> revisions,
      int completedIndex = 0,
    }) =>
        MergeJob(
          jobId: 1,
          sourceUrl: 'svn://example/source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: revisions,
          completedIndex: completedIndex,
        );

    test('shows progress and current revision when work remains', () {
      expect(
        formatRevisionProgress(
            job(revisions: [100, 101, 102], completedIndex: 1)),
        '1/3，当前 r101',
      );
    });

    test('omits current revision text when all revisions are completed', () {
      expect(
        formatRevisionProgress(job(revisions: [100, 101], completedIndex: 2)),
        '2/2',
      );
    });

    test('clamps completedIndex to revisions.length on overshoot', () {
      // completedIndex > revisions.length must not produce e.g. "3/2".
      expect(
        formatRevisionProgress(job(revisions: [100, 101], completedIndex: 3)),
        '2/2',
      );
    });

    test('handles empty revision list without crashing', () {
      expect(formatRevisionProgress(job(revisions: [])), '0/0');
    });

    test('starts at 0 with the first revision marked current', () {
      expect(
        formatRevisionProgress(job(revisions: [100, 101], completedIndex: 0)),
        '0/2，当前 r100',
      );
    });
  });

  group('formatJsonForDisplay', () {
    test('returns {} for an empty map (no surrounding whitespace)', () {
      expect(formatJsonForDisplay({}), '{}');
    });

    test('formats with two-space indentation', () {
      final out = formatJsonForDisplay({'a': 1, 'b': 'x'});
      expect(out, '{\n  "a": 1,\n  "b": "x"\n}');
    });

    test('decodes embedded {U+xxxx} escapes inside string values', () {
      // The Map value already contains the literal `{U+xxxx}` marker;
      // formatJsonForDisplay must restore it to the original character.
      final out = formatJsonForDisplay({'name': '{U+4F60}{U+597D}'});
      expect(out, '{\n  "name": "你好"\n}');
    });
  });

  group('snapshotStatusIcon', () {
    test('covers all StepExecutionStatus values', () {
      expect(snapshotStatusIcon(StepExecutionStatus.pending), Icons.schedule);
      expect(
          snapshotStatusIcon(StepExecutionStatus.running), Icons.play_circle);
      expect(snapshotStatusIcon(StepExecutionStatus.completed),
          Icons.check_circle);
      expect(snapshotStatusIcon(StepExecutionStatus.failed), Icons.error);
      expect(snapshotStatusIcon(StepExecutionStatus.skipped), Icons.skip_next);
    });

    test('R95 防漏配：StepExecutionStatus.values.length == 5（新增 enum 时强制 review）',
        () {
      expect(StepExecutionStatus.values.length, 5,
          reason:
              '当 StepExecutionStatus 新增枚举值时本测会红，强制 review snapshotStatusIcon 的图标映射');
    });
  });

  // R90: `formatStepClockTime` 已被删除（与 `formatStepTime` 是逐字相同 duplicate），
  // 6 个原测试用例已迁到 `step_execution_view_test.dart::formatStepTime` group。

  group('computeJobProgressFraction', () {
    MergeJob job({
      required List<int> revisions,
      int completedIndex = 0,
    }) =>
        MergeJob(
          jobId: 1,
          sourceUrl: 'svn://example/source',
          targetWc: '/tmp/wc',
          maxRetries: 3,
          revisions: revisions,
          completedIndex: completedIndex,
        );

    test('空 revisions → 0.0（避免除零）', () {
      expect(computeJobProgressFraction(job(revisions: [])), 0.0);
    });

    test('未开始（completedIndex=0）→ 0.0', () {
      expect(
        computeJobProgressFraction(
            job(revisions: [1, 2, 3], completedIndex: 0)),
        0.0,
      );
    });

    test('部分完成 → 正确的比例', () {
      expect(
        computeJobProgressFraction(
            job(revisions: [1, 2, 3, 4], completedIndex: 1)),
        0.25,
      );
      expect(
        computeJobProgressFraction(
            job(revisions: [1, 2, 3, 4], completedIndex: 2)),
        0.5,
      );
    });

    test('全部完成 → 1.0', () {
      expect(
        computeJobProgressFraction(job(revisions: [1, 2], completedIndex: 2)),
        1.0,
      );
    });

    test('completedIndex 越界（> length）→ clamp 到 length，结果为 1.0', () {
      // 防御性：上游不该传越界值，但传入也不应炸（或返回 > 1.0）
      expect(
        computeJobProgressFraction(job(revisions: [1, 2], completedIndex: 5)),
        1.0,
      );
    });

    test('completedIndex 负数 → clamp 到 0，结果为 0.0', () {
      expect(
        computeJobProgressFraction(job(revisions: [1, 2], completedIndex: -3)),
        0.0,
      );
    });

    test('返回值始终在 [0.0, 1.0] 区间内', () {
      // 极端组合
      for (final ci in [-100, -1, 0, 1, 2, 5, 100]) {
        final frac = computeJobProgressFraction(
            job(revisions: [1, 2], completedIndex: ci));
        expect(frac, greaterThanOrEqualTo(0.0));
        expect(frac, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('isStepSnapshotDetailEmpty', () {
    StepSnapshot snap({
      Map<String, dynamic> inputData = const {},
      Map<String, dynamic> config = const {},
      StepOutput? output,
      String? error,
      StepExecutionStatus status = StepExecutionStatus.pending,
    }) {
      return StepSnapshot(
        stepId: 's1',
        stepTypeId: 'svnUpdate',
        status: status,
        inputData: inputData,
        config: config,
        output: output,
        error: error,
        startTime: DateTime(2026, 5, 27, 10),
      );
    }

    test('四字段全空 → true', () {
      expect(isStepSnapshotDetailEmpty(snap()), isTrue);
    });

    test('inputData 非空 → false', () {
      expect(isStepSnapshotDetailEmpty(snap(inputData: {'a': 1})), isFalse);
    });

    test('config 非空 → false', () {
      expect(isStepSnapshotDetailEmpty(snap(config: {'a': 1})), isFalse);
    });

    test('output 非空 → false（即便 data 为空 map）', () {
      // 锁住"output != null 即非空"——空 data 的 StepOutput 也算有详情，
      // caller 仍会渲染 output port 卡片
      expect(
        isStepSnapshotDetailEmpty(snap(output: const StepOutput(port: 'ok'))),
        isFalse,
      );
    });

    test('error 非空（即便是空字符串）→ false', () {
      // 锁住"error != null 即非空"——caller 检查的是 != null 而非 isNotEmpty，
      // 因此空字符串 error 也算有详情
      expect(isStepSnapshotDetailEmpty(snap(error: '')), isFalse);
    });

    test('元信息字段（status / startTime / endTime）不影响判定', () {
      // 同样的"四字段空"，不管 status 是 pending / completed / failed
      // 都返回 true——元信息由 _buildSnapshotInfoCard 处理，跟"详情空不空"是两回事
      for (final status in StepExecutionStatus.values) {
        expect(
          isStepSnapshotDetailEmpty(snap(status: status)),
          isTrue,
          reason: 'status=$status 元信息不应影响详情空判定',
        );
      }
    });
  });

  group('describeEmptySnapshotPlaceholder', () {
    test('pending → "该步骤尚未执行"', () {
      expect(
        describeEmptySnapshotPlaceholder(StepExecutionStatus.pending),
        '该步骤尚未执行',
      );
    });

    test('非 pending 状态全部 → "该步骤没有详细数据"', () {
      // 显式遍历，防止未来加新枚举值时漏处理（会直接落入"没有详细数据"分支）。
      // 这是有意的默认——pending 是唯一"还没轮到"语义，其他都是"执行了但本步本来无详情"。
      for (final status in StepExecutionStatus.values) {
        if (status == StepExecutionStatus.pending) continue;
        expect(
          describeEmptySnapshotPlaceholder(status),
          '该步骤没有详细数据',
          reason: 'status=$status 应落入非 pending 文案',
        );
      }
    });
  });

  group('resolveSelectedStepHeaderLabels', () {
    StepSnapshot snap({String? stepName, String stepTypeId = 'svnUpdate'}) {
      return StepSnapshot(
        stepId: 's1',
        stepTypeId: stepTypeId,
        stepName: stepName,
        status: StepExecutionStatus.pending,
        inputData: const {},
        config: const {},
        startTime: DateTime(2026, 5, 27, 10),
      );
    }

    test('snapshot == null → 主副标题都落到 selectedStepId', () {
      final labels = resolveSelectedStepHeaderLabels(
        snapshot: null,
        selectedStepId: 'step-x',
      );
      expect(labels.displayName, 'step-x');
      expect(labels.typeId, 'step-x');
    });

    test('stepName 优先用于 displayName，typeId 永远用 stepTypeId', () {
      final labels = resolveSelectedStepHeaderLabels(
        snapshot: snap(stepName: '更新工作副本', stepTypeId: 'svnUpdate'),
        selectedStepId: 'step-x',
      );
      expect(labels.displayName, '更新工作副本');
      expect(labels.typeId, 'svnUpdate');
    });

    test('stepName == null → displayName 退到 stepTypeId', () {
      final labels = resolveSelectedStepHeaderLabels(
        snapshot: snap(stepName: null, stepTypeId: 'svnUpdate'),
        selectedStepId: 'step-x',
      );
      expect(labels.displayName, 'svnUpdate');
      expect(labels.typeId, 'svnUpdate');
    });

    test('优先级：stepName 非空时不应被 stepTypeId 覆盖（防回归）', () {
      // 显式锁住"stepName 优先于 stepTypeId"——重构者很容易把 ?? 顺序反掉
      final labels = resolveSelectedStepHeaderLabels(
        snapshot: snap(stepName: 'A', stepTypeId: 'B'),
        selectedStepId: 'C',
      );
      expect(labels.displayName, 'A');
    });

    test('selectedStepId 是最后兜底，永远不会用到 displayName 当 snapshot 提供了 stepTypeId',
        () {
      final labels = resolveSelectedStepHeaderLabels(
        snapshot: snap(stepName: null, stepTypeId: 'svnUpdate'),
        selectedStepId: 'WONT_USE',
      );
      expect(labels.displayName, isNot('WONT_USE'));
    });
  });

  group('describeCurrentRevisionLine', () {
    test('null → 已完成文案（不带 r 前缀）', () {
      expect(describeCurrentRevisionLine(null), '当前 revision 已完成');
    });

    test('正数 → 当前: rN', () {
      expect(describeCurrentRevisionLine(12345), '当前: r12345');
    });

    test('0 也照常拼接（不做合法性校验）', () {
      expect(describeCurrentRevisionLine(0), '当前: r0');
    });

    test('负数也照常拼接（不做合法性校验，由上游保证）', () {
      expect(describeCurrentRevisionLine(-1), '当前: r-1');
    });

    test('使用半角冒号 + 空格（与现有 UI 文案风格一致）', () {
      // 锁定字面格式，防止有人误改成全角"："或去掉空格
      final result = describeCurrentRevisionLine(42);
      expect(result.contains(': r'), isTrue);
      expect(result.contains('：'), isFalse);
    });

    test('null 与非 null 文案前缀完全分裂（不共享前缀，防误合并）', () {
      // 防止"形似但语义相反的函数"误合并：null 走"已完成"语义、非 null 走"当前"语义，
      // 文案前缀完全分裂，不应被合并成 `'当前: ${currentRevision ?? "已完成"}'` 这种瑞士军刀。
      expect(
        describeCurrentRevisionLine(null).startsWith('当前:'),
        isFalse,
      );
      expect(
        describeCurrentRevisionLine(1).startsWith('当前:'),
        isTrue,
      );
    });
  });

  group('formatSkipButtonLabel', () {
    test('正数 → 跳过 rN', () {
      expect(formatSkipButtonLabel(123), '跳过 r123');
    });

    test('0 → 跳过 r0（不做合法性校验）', () {
      expect(formatSkipButtonLabel(0), '跳过 r0');
    });

    test('与 describeCurrentRevisionLine 前缀刻意不同（动作 vs 状态）', () {
      // 跳过按钮 label 是"动作"前缀，进度行文案是"状态"前缀；
      // 两个函数都接 currentRevision 但语义不同，不应被合并。
      expect(formatSkipButtonLabel(42).startsWith('跳过 r'), isTrue);
      expect(describeCurrentRevisionLine(42).startsWith('当前: r'), isTrue);
    });

    test('使用半角空格分隔（与"当前: rN"一致风格）', () {
      expect(formatSkipButtonLabel(7).contains(' r'), isTrue);
    });
  });

  group('shouldShowSkipButton', () {
    // 通过 (revisions, completedIndex) 派生 currentRevision，
    // 不直接构造 currentRevision——getter 派生关系是模型契约，由前置 expect 锁定。
    MergeJob makeJob({
      required List<int> revisions,
      required int completedIndex,
    }) =>
        MergeJob(
          jobId: 1,
          sourceUrl: '',
          targetWc: '',
          maxRetries: 0,
          revisions: revisions,
          completedIndex: completedIndex,
        );

    test('null pausedJob → false', () {
      expect(shouldShowSkipButton(null), isFalse);
    });

    test('pausedJob 非 null 但 currentRevision 为 null（任务全做完）→ false', () {
      // revisions=[100], completedIndex=1 → currentRevision==null
      final job = makeJob(revisions: [100], completedIndex: 1);
      expect(job.currentRevision, isNull, reason: 'fixture 前置条件');
      expect(shouldShowSkipButton(job), isFalse);
    });

    test('pausedJob 非 null 且 currentRevision 非 null → true', () {
      final job = makeJob(revisions: [100, 101], completedIndex: 0);
      expect(job.currentRevision, 100, reason: 'fixture 前置条件');
      expect(shouldShowSkipButton(job), isTrue);
    });

    test('空 revisions 列表 → currentRevision==null → false', () {
      final job = makeJob(revisions: const [], completedIndex: 0);
      expect(job.currentRevision, isNull, reason: 'fixture 前置条件');
      expect(shouldShowSkipButton(job), isFalse);
    });

    test('completedIndex 超出 revisions.length（异常但仍降级）→ false', () {
      // currentRevision getter 在 completedIndex >= length 时返回 null
      final job = makeJob(revisions: [100], completedIndex: 5);
      expect(job.currentRevision, isNull, reason: 'fixture 前置条件');
      expect(shouldShowSkipButton(job), isFalse);
    });
  });

  group('shouldShowTerminateHint', () {
    test('running → true（按下终止后命令延迟生效，需要解释）', () {
      expect(shouldShowTerminateHint(ExecutorStatus.running), isTrue);
    });

    test('paused → false（暂停态终止立即生效）', () {
      expect(shouldShowTerminateHint(ExecutorStatus.paused), isFalse);
    });

    test('idle → false（无任务在跑，提示无意义）', () {
      expect(shouldShowTerminateHint(ExecutorStatus.idle), isFalse);
    });

    test('completed → false（已完成，提示无意义）', () {
      expect(shouldShowTerminateHint(ExecutorStatus.completed), isFalse);
    });

    test('全部 ExecutorStatus.values 真值表覆盖（防止新增 enum 时漏配）', () {
      // 与设计模式 #11 同款"防漏配"契约：未来若 enum 新增第 5 态，本测会因
      // 没有断言新值而强制提醒补 case 决策。
      final trueStates =
          ExecutorStatus.values.where(shouldShowTerminateHint).toSet();
      expect(trueStates, {ExecutorStatus.running});
      expect(
        ExecutorStatus.values.length,
        4,
        reason: '当 ExecutorStatus 新增枚举值时本测会红，强制 review shouldShowTerminateHint',
      );
    });
  });

  group('SnapshotDetailSectionFlags', () {
    test('值相等性：6 个 bool 字段全相同 → 相等', () {
      const a = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: false,
        showConfig: true,
        showOutput: false,
        showError: true,
        showEmptyPlaceholder: false,
      );
      const b = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: false,
        showConfig: true,
        showOutput: false,
        showError: true,
        showEmptyPlaceholder: false,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('任一字段不同 → 不等（防止字段漏列入 ==）', () {
      // 6 个字段挨个翻转一次，确保每个字段都被 == 检查到
      const base = SnapshotDetailSectionFlags(
        showGlobalContext: false,
        showInputData: false,
        showConfig: false,
        showOutput: false,
        showError: false,
        showEmptyPlaceholder: false,
      );
      const flipGlobal = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: false,
        showConfig: false,
        showOutput: false,
        showError: false,
        showEmptyPlaceholder: false,
      );
      const flipInput = SnapshotDetailSectionFlags(
        showGlobalContext: false,
        showInputData: true,
        showConfig: false,
        showOutput: false,
        showError: false,
        showEmptyPlaceholder: false,
      );
      const flipConfig = SnapshotDetailSectionFlags(
        showGlobalContext: false,
        showInputData: false,
        showConfig: true,
        showOutput: false,
        showError: false,
        showEmptyPlaceholder: false,
      );
      const flipOutput = SnapshotDetailSectionFlags(
        showGlobalContext: false,
        showInputData: false,
        showConfig: false,
        showOutput: true,
        showError: false,
        showEmptyPlaceholder: false,
      );
      const flipError = SnapshotDetailSectionFlags(
        showGlobalContext: false,
        showInputData: false,
        showConfig: false,
        showOutput: false,
        showError: true,
        showEmptyPlaceholder: false,
      );
      const flipPlaceholder = SnapshotDetailSectionFlags(
        showGlobalContext: false,
        showInputData: false,
        showConfig: false,
        showOutput: false,
        showError: false,
        showEmptyPlaceholder: true,
      );
      expect(base, isNot(equals(flipGlobal)));
      expect(base, isNot(equals(flipInput)));
      expect(base, isNot(equals(flipConfig)));
      expect(base, isNot(equals(flipOutput)));
      expect(base, isNot(equals(flipError)));
      expect(base, isNot(equals(flipPlaceholder)));
    });

    test('toString 含全部 6 个字段（便于排查 detail section 回归）', () {
      const flags = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: false,
        showConfig: true,
        showOutput: false,
        showError: true,
        showEmptyPlaceholder: false,
      );
      final str = flags.toString();
      expect(str, contains('showGlobalContext: true'));
      expect(str, contains('showInputData: false'));
      expect(str, contains('showConfig: true'));
      expect(str, contains('showOutput: false'));
      expect(str, contains('showError: true'));
      expect(str, contains('showEmptyPlaceholder: false'));
    });
  });

  group('resolveSnapshotDetailSections', () {
    StepSnapshot snap({
      Map<String, dynamic> inputData = const {},
      Map<String, dynamic> config = const {},
      StepOutput? output,
      String? error,
      StepExecutionStatus status = StepExecutionStatus.pending,
    }) {
      return StepSnapshot(
        stepId: 's1',
        stepTypeId: 'svnUpdate',
        status: status,
        inputData: inputData,
        config: config,
        output: output,
        error: error,
        startTime: DateTime(2026, 5, 27, 10),
      );
    }

    test('全空 snapshot + 空 globalContext → placeholder=true，其余全 false', () {
      final flags = resolveSnapshotDetailSections(
        snapshot: snap(),
        globalContext: const {},
      );
      expect(flags.showGlobalContext, isFalse);
      expect(flags.showInputData, isFalse);
      expect(flags.showConfig, isFalse);
      expect(flags.showOutput, isFalse);
      expect(flags.showError, isFalse);
      expect(flags.showEmptyPlaceholder, isTrue);
    });

    test('inputData 非空 → showInputData=true，placeholder=false', () {
      final flags = resolveSnapshotDetailSections(
        snapshot: snap(inputData: {'k': 'v'}),
        globalContext: const {},
      );
      expect(flags.showInputData, isTrue);
      expect(flags.showEmptyPlaceholder, isFalse);
      // 其他三个详情字段仍为 false
      expect(flags.showConfig, isFalse);
      expect(flags.showOutput, isFalse);
      expect(flags.showError, isFalse);
    });

    test('config 非空 → showConfig=true，placeholder=false', () {
      final flags = resolveSnapshotDetailSections(
        snapshot: snap(config: {'k': 'v'}),
        globalContext: const {},
      );
      expect(flags.showConfig, isTrue);
      expect(flags.showEmptyPlaceholder, isFalse);
    });

    test('output 非空 → showOutput=true，placeholder=false', () {
      final flags = resolveSnapshotDetailSections(
        snapshot: snap(output: const StepOutput(port: 'ok')),
        globalContext: const {},
      );
      expect(flags.showOutput, isTrue);
      expect(flags.showEmptyPlaceholder, isFalse);
    });

    test('error 非 null（即便空字符串）→ showError=true，placeholder=false', () {
      // 与 isStepSnapshotDetailEmpty 的契约保持一致：error != null 即"有详情"
      final flags = resolveSnapshotDetailSections(
        snapshot: snap(error: ''),
        globalContext: const {},
      );
      expect(flags.showError, isTrue);
      expect(flags.showEmptyPlaceholder, isFalse);
    });

    test(
        '核心契约：globalContext 非空 但 snapshot 4 字段全空 → showGlobalContext=true && placeholder=true',
        () {
      // 这是 globalContext 与"详情空"判定独立性最关键的真值——
      // 用户视角："步骤本身没有详细数据，但全局上下文存在"是合法状态，
      // placeholder 文案"该步骤没有详细数据"指的是步骤的 4 个字段，与 globalContext 无关。
      // 若有人误把 globalContext 也算进 isStepSnapshotDetailEmpty，
      // showEmptyPlaceholder 会变成 false，本测会立即撞红。
      final flags = resolveSnapshotDetailSections(
        snapshot: snap(),
        globalContext: const {'job.branch': 'release/v1'},
      );
      expect(flags.showGlobalContext, isTrue);
      expect(flags.showEmptyPlaceholder, isTrue);
      // snapshot 4 字段仍 false
      expect(flags.showInputData, isFalse);
      expect(flags.showConfig, isFalse);
      expect(flags.showOutput, isFalse);
      expect(flags.showError, isFalse);
    });

    test('反向断言：globalContext 切换不影响其他 5 个 flag（独立维度——globalContext 在它自己的轨道上）',
        () {
      // 构造同一份 snapshot，仅改 globalContext，断言 5 个 snapshot-derived flag 完全相同。
      // 防止有人误把 globalContext 牵进 snapshot 的判定逻辑（如把它合并到 inputData）。
      final s = snap(
        inputData: {'a': 1},
        config: {'b': 2},
        output: const StepOutput(port: 'p', data: {'r': 1}),
        error: 'oops',
      );
      final empty = resolveSnapshotDetailSections(
        snapshot: s,
        globalContext: const {},
      );
      final filled = resolveSnapshotDetailSections(
        snapshot: s,
        globalContext: const {'job.x': 1},
      );
      // showGlobalContext 不同
      expect(empty.showGlobalContext, isFalse);
      expect(filled.showGlobalContext, isTrue);
      // 其他 5 个 flag 必须完全相同
      expect(empty.showInputData, equals(filled.showInputData));
      expect(empty.showConfig, equals(filled.showConfig));
      expect(empty.showOutput, equals(filled.showOutput));
      expect(empty.showError, equals(filled.showError));
      expect(empty.showEmptyPlaceholder, equals(filled.showEmptyPlaceholder));
    });

    test('反向断言：snapshot 切换不影响 showGlobalContext（双向锁定独立性）', () {
      // 对称同款：固定 globalContext，对比 snapshot 的不同填充——showGlobalContext 必须不变。
      // 这条与上一条成对，**双向锁定 globalContext 与 snapshot 互不影响**——
      // 单向反向只锁一半，两条加起来才证明真独立性（设计模式 #17 双维度独立）。
      const ctx = {'job.branch': 'main'};
      final emptySnap = resolveSnapshotDetailSections(
        snapshot: snap(),
        globalContext: ctx,
      );
      final fullSnap = resolveSnapshotDetailSections(
        snapshot: snap(
          inputData: {'a': 1},
          config: {'b': 2},
          output: const StepOutput(port: 'p'),
          error: 'e',
        ),
        globalContext: ctx,
      );
      // showGlobalContext 必须相同（=true）
      expect(emptySnap.showGlobalContext, isTrue);
      expect(fullSnap.showGlobalContext, isTrue);
      // 其他 5 个 flag 必须不同（snapshot 维度变了）
      expect(emptySnap.showInputData, isNot(equals(fullSnap.showInputData)));
      expect(emptySnap.showConfig, isNot(equals(fullSnap.showConfig)));
      expect(emptySnap.showOutput, isNot(equals(fullSnap.showOutput)));
      expect(emptySnap.showError, isNot(equals(fullSnap.showError)));
      expect(
        emptySnap.showEmptyPlaceholder,
        isNot(equals(fullSnap.showEmptyPlaceholder)),
      );
    });

    test('placeholder 与 isStepSnapshotDetailEmpty 等价（4 字段联动锁定）', () {
      // 直接断言 showEmptyPlaceholder 的真值与 isStepSnapshotDetailEmpty 严格一致——
      // 两个函数共享逻辑（resolveSnapshotDetailSections 内部调用 isStepSnapshotDetailEmpty），
      // 此测防止有人在 resolveSnapshotDetailSections 里误写自己的判定（如漏掉 error 字段）。
      final cases = [
        snap(),
        snap(inputData: {'a': 1}),
        snap(config: {'a': 1}),
        snap(output: const StepOutput(port: 'p')),
        snap(error: 'e'),
        snap(inputData: {'a': 1}, error: 'e'),
      ];
      for (final s in cases) {
        final flags = resolveSnapshotDetailSections(
          snapshot: s,
          globalContext: const {},
        );
        expect(
          flags.showEmptyPlaceholder,
          equals(isStepSnapshotDetailEmpty(s)),
          reason: 'snapshot=$s',
        );
      }
    });

    test(
        'showOutput 检查 != null 而非 data.isEmpty（与 isStepSnapshotDetailEmpty 同款契约）',
        () {
      // 细节锁定：output 是 nullable 类型，"null vs 非 null" 是渲染分支的边界，
      // 而 output.data 是否为空（即 StepOutput(port: 'p', data: {}) 的情况）
      // 不影响 showOutput——与 widget 树原行为 `if (snapshot.output != null) ...[` 严格一致。
      final flags = resolveSnapshotDetailSections(
        snapshot: snap(output: const StepOutput(port: 'p')), // data 默认空
        globalContext: const {},
      );
      expect(flags.showOutput, isTrue);
      // 同时 placeholder=false（output 非 null 算"有详情"）
      expect(flags.showEmptyPlaceholder, isFalse);
    });
  });

  group('SnapshotDetailSectionFlags == / hashCode 对称性（R103）', () {
    const baseline = SnapshotDetailSectionFlags(
      showGlobalContext: true,
      showInputData: true,
      showConfig: true,
      showOutput: true,
      showError: true,
      showEmptyPlaceholder: true,
    );

    test('全字段相同 → 相等 + hashCode 一致', () {
      const a = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: true,
        showConfig: true,
        showOutput: true,
        showError: true,
        showEmptyPlaceholder: true,
      );
      expect(a, equals(baseline));
      expect(a.hashCode, baseline.hashCode);
    });

    test('任一字段不等 → != + Set 去重正确（6 字段对称性矩阵）', () {
      const diffGlobal = SnapshotDetailSectionFlags(
        showGlobalContext: false,
        showInputData: true,
        showConfig: true,
        showOutput: true,
        showError: true,
        showEmptyPlaceholder: true,
      );
      const diffInput = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: false,
        showConfig: true,
        showOutput: true,
        showError: true,
        showEmptyPlaceholder: true,
      );
      const diffConfig = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: true,
        showConfig: false,
        showOutput: true,
        showError: true,
        showEmptyPlaceholder: true,
      );
      const diffOutput = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: true,
        showConfig: true,
        showOutput: false,
        showError: true,
        showEmptyPlaceholder: true,
      );
      const diffError = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: true,
        showConfig: true,
        showOutput: true,
        showError: false,
        showEmptyPlaceholder: true,
      );
      const diffPlaceholder = SnapshotDetailSectionFlags(
        showGlobalContext: true,
        showInputData: true,
        showConfig: true,
        showOutput: true,
        showError: true,
        showEmptyPlaceholder: false,
      );
      for (final v in [
        diffGlobal,
        diffInput,
        diffConfig,
        diffOutput,
        diffError,
        diffPlaceholder,
      ]) {
        expect(v, isNot(equals(baseline)));
      }
      final s = <SnapshotDetailSectionFlags>{
        baseline,
        diffGlobal,
        diffInput,
        diffConfig,
        diffOutput,
        diffError,
        diffPlaceholder,
      };
      expect(s.length, 7, reason: '6 字段对称性矩阵：每字段独立修改都应让 Set 多 1 元素');
    });
  });
}
