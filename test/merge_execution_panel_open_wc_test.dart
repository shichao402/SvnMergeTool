/// MergeExecutionPanel 中"打开工作副本目录"按钮的渲染与回调契约。
///
/// 锁三件事：
/// 1. `pausedJob != null` + `onOpenWorkingCopy != null` → 按钮渲染、点击触发回调；
/// 2. `pausedJob != null` 但 `onOpenWorkingCopy == null` → 按钮不渲染；
/// 3. `pausedJob == null` → 按钮不渲染（整个 `_buildPausedSummarySection` 不进入）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/screens/components/merge_execution_panel.dart';

MergeJob _makePausedJob() {
  return MergeJob(
    jobId: 1,
    sourceUrl: 'svn://repo/branches/feature',
    targetWc: '/Users/dev/wc/trunk',
    maxRetries: 3,
    revisions: const [100, 101],
    status: JobStatus.paused,
    pauseReason: '冲突',
    completedIndex: 0,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required MergeJob? pausedJob,
  required VoidCallback? onOpenWorkingCopy,
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
        onOpenWorkingCopy: onOpenWorkingCopy,
      ),
    ),
  ));
}

void main() {
  group('MergeExecutionPanel 打开工作副本目录按钮', () {
    testWidgets('pausedJob 非空 + 回调非空 → 按钮渲染，点击触发回调', (tester) async {
      var called = 0;
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(),
        onOpenWorkingCopy: () => called++,
      );

      final finder = find.widgetWithText(OutlinedButton, '打开工作副本目录');
      expect(finder, findsOneWidget);

      await tester.tap(finder);
      await tester.pump();
      expect(called, 1);
    });

    testWidgets('pausedJob 非空但回调为 null → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(),
        onOpenWorkingCopy: null,
      );

      expect(
        find.widgetWithText(OutlinedButton, '打开工作副本目录'),
        findsNothing,
      );
    });

    testWidgets('pausedJob 为 null → 按钮不渲染（整个暂停摘要区不出现）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: null,
        onOpenWorkingCopy: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '打开工作副本目录'),
        findsNothing,
      );
    });
  });
}
