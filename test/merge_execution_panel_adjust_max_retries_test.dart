/// MergeExecutionPanel 中"调整重试次数"按钮的渲染与回调契约。
///
/// 锁四件事：
/// 1. `failureKind == outOfDate` + `onAdjustMaxRetries != null` → 按钮渲染、点击触发回调；
/// 2. 其他 8 种 failureKind（textConflict / treeConflict / authFailed / locked
///    / notFound / network / workingCopyCorrupt / unknown）→ 按钮不渲染；
/// 3. `onAdjustMaxRetries == null` 即使 outOfDate 也不渲染；
/// 4. `pausedJob == null` → 按钮不渲染（暂停摘要区整体不进入）。
///
/// 同时单测顶层 [shouldShowAdjustMaxRetriesButton] 谓词的真值表（全部 9 种 SvnFailureKind）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/execution/svn_failure_kind.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/screens/components/merge_execution_panel.dart';

MergeJob _makePausedJob({required String pauseReason}) {
  return MergeJob(
    jobId: 1,
    sourceUrl: 'svn://repo/branches/feature',
    targetWc: '/Users/dev/wc/trunk',
    maxRetries: 3,
    revisions: const [100, 101],
    status: JobStatus.paused,
    pauseReason: pauseReason,
    completedIndex: 0,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required MergeJob? pausedJob,
  required VoidCallback? onAdjustMaxRetries,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MergeExecutionPanel(
        status: pausedJob != null
            ? ExecutorStatus.paused
            : ExecutorStatus.idle,
        pausedJob: pausedJob,
        onResume: () {},
        onSkip: () {},
        onCancel: () {},
        onAdjustMaxRetries: onAdjustMaxRetries,
      ),
    ),
  ));
}

void main() {
  group('shouldShowAdjustMaxRetriesButton 真值表 — 全部 9 种 SvnFailureKind', () {
    test('outOfDate → true（唯一一个返回 true 的分类）', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.outOfDate),
        isTrue,
      );
    });

    test('textConflict → false', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.textConflict),
        isFalse,
      );
    });

    test('treeConflict → false', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.treeConflict),
        isFalse,
      );
    });

    test('authFailed → false', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.authFailed),
        isFalse,
      );
    });

    test('locked → false（与 shouldShowCleanupButton 互斥维度）', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.locked),
        isFalse,
      );
    });

    test('workingCopyCorrupt → false', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.workingCopyCorrupt),
        isFalse,
      );
    });

    test('notFound → false', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.notFound),
        isFalse,
      );
    });

    test('network → false', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.network),
        isFalse,
      );
    });

    test('unknown → false', () {
      expect(
        shouldShowAdjustMaxRetriesButton(SvnFailureKind.unknown),
        isFalse,
      );
    });
  });

  group('MergeExecutionPanel 调整重试次数 按钮', () {
    testWidgets('outOfDate + 回调非空 → 按钮渲染，点击触发回调', (tester) async {
      var called = 0;
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(
          pauseReason: 'svn: E160028 commit failed - out of date',
        ),
        onAdjustMaxRetries: () => called++,
      );

      final finder = find.widgetWithText(OutlinedButton, '调整重试次数');
      expect(finder, findsOneWidget);

      await tester.tap(finder);
      await tester.pump();
      expect(called, 1);
    });

    testWidgets('textConflict → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onAdjustMaxRetries: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '调整重试次数'),
        findsNothing,
      );
    });

    testWidgets('locked → 按钮不渲染（互斥于 cleanup 按钮）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'svn: E155004 path is locked'),
        onAdjustMaxRetries: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '调整重试次数'),
        findsNothing,
      );
    });

    testWidgets('authFailed → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'authentication failed'),
        onAdjustMaxRetries: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '调整重试次数'),
        findsNothing,
      );
    });

    testWidgets('outOfDate 但回调为 null → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(
          pauseReason: 'svn: E160028 commit failed - out of date',
        ),
        onAdjustMaxRetries: null,
      );

      expect(
        find.widgetWithText(OutlinedButton, '调整重试次数'),
        findsNothing,
      );
    });

    testWidgets('pausedJob 为 null → 按钮不渲染（整段摘要区不进入）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: null,
        onAdjustMaxRetries: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '调整重试次数'),
        findsNothing,
      );
    });
  });
}
