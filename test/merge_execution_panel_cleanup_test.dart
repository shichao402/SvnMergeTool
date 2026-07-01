/// MergeExecutionPanel 中"执行 cleanup"按钮的渲染与回调契约。
///
/// 锁四件事：
/// 1. `failureKind == locked` + `onCleanup != null` → 按钮渲染、点击触发回调；
/// 2. 其他 8 种 failureKind（textConflict / treeConflict / outOfDate / authFailed
///    / notFound / network / workingCopyCorrupt / unknown）→ 按钮不渲染；
/// 3. `onCleanup == null` 即使 locked 也不渲染；
/// 4. `pausedJob == null` → 按钮不渲染（暂停摘要区整体不进入）。
///
/// 同时单测顶层 [shouldShowCleanupButton] 谓词的真值表（全部 9 种 SvnFailureKind）。
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
  required VoidCallback? onCleanup,
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
        onCleanup: onCleanup,
      ),
    ),
  ));
}

void main() {
  group('shouldShowCleanupButton 真值表 — 全部 9 种 SvnFailureKind', () {
    test('locked → true（唯一一个返回 true 的分类）', () {
      expect(shouldShowCleanupButton(SvnFailureKind.locked), isTrue);
    });

    test('textConflict → false', () {
      expect(shouldShowCleanupButton(SvnFailureKind.textConflict), isFalse);
    });

    test('treeConflict → false', () {
      expect(shouldShowCleanupButton(SvnFailureKind.treeConflict), isFalse);
    });

    test('outOfDate → false', () {
      expect(shouldShowCleanupButton(SvnFailureKind.outOfDate), isFalse);
    });

    test('authFailed → false', () {
      expect(shouldShowCleanupButton(SvnFailureKind.authFailed), isFalse);
    });

    test('workingCopyCorrupt → false（虽相关，但需 re-checkout 而非 cleanup）', () {
      expect(
        shouldShowCleanupButton(SvnFailureKind.workingCopyCorrupt),
        isFalse,
      );
    });

    test('notFound → false', () {
      expect(shouldShowCleanupButton(SvnFailureKind.notFound), isFalse);
    });

    test('network → false', () {
      expect(shouldShowCleanupButton(SvnFailureKind.network), isFalse);
    });

    test('unknown → false', () {
      expect(shouldShowCleanupButton(SvnFailureKind.unknown), isFalse);
    });
  });

  group('MergeExecutionPanel 执行 cleanup 按钮', () {
    testWidgets('locked + 回调非空 → 按钮渲染，点击触发回调', (tester) async {
      var called = 0;
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'svn: E155004 path is locked'),
        onCleanup: () => called++,
      );

      final finder = find.widgetWithText(OutlinedButton, '执行 cleanup');
      expect(finder, findsOneWidget);

      await tester.tap(finder);
      await tester.pump();
      expect(called, 1);
    });

    testWidgets('textConflict → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onCleanup: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '执行 cleanup'), findsNothing);
    });

    testWidgets('treeConflict → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'tree conflict in foo.dart'),
        onCleanup: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '执行 cleanup'), findsNothing);
    });

    testWidgets('authFailed → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'authentication failed'),
        onCleanup: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '执行 cleanup'), findsNothing);
    });

    testWidgets('locked 但回调为 null → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'svn: E155004 path is locked'),
        onCleanup: null,
      );

      expect(find.widgetWithText(OutlinedButton, '执行 cleanup'), findsNothing);
    });

    testWidgets('pausedJob 为 null → 按钮不渲染（整段摘要区不进入）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: null,
        onCleanup: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '执行 cleanup'), findsNothing);
    });
  });
}
