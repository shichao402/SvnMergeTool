/// MergeExecutionPanel 中"打开冲突文件"按钮的渲染与回调契约。
///
/// 锁四件事：
/// 1. `failureKind == textConflict` + `onOpenConflictFile != null` →
///    按钮渲染、点击触发回调；
/// 2. `failureKind == treeConflict` → 按钮**不**渲染——treeConflict 没有单一文本
///    文件可开（与 [shouldShowMarkResolvedButton] 的差异点：标记为已解决两种都显示，
///    打开冲突文件**仅** textConflict）；
/// 3. 其他 failureKind（authFailed / outOfDate / locked / unknown / ...）→ 按钮不渲染；
/// 4. `onOpenConflictFile == null` 即使 textConflict 也不渲染；
/// 5. `pausedJob == null` → 按钮不渲染（暂停摘要区整体不进入）。
///
/// 同时单测顶层 [shouldShowOpenConflictFileButton] 谓词的真值表（全部 9 种 SvnFailureKind）。
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
  required VoidCallback? onOpenConflictFile,
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
        onOpenConflictFile: onOpenConflictFile,
      ),
    ),
  ));
}

void main() {
  group('shouldShowOpenConflictFileButton 真值表 — 全部 9 种 SvnFailureKind', () {
    test('textConflict → true（唯一一个返回 true 的分类）', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.textConflict),
        isTrue,
      );
    });

    test('treeConflict → false（与 shouldShowMarkResolvedButton 的关键差异点）', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.treeConflict),
        isFalse,
      );
    });

    test('outOfDate → false', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.outOfDate),
        isFalse,
      );
    });

    test('authFailed → false', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.authFailed),
        isFalse,
      );
    });

    test('locked → false', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.locked),
        isFalse,
      );
    });

    test('workingCopyCorrupt → false', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.workingCopyCorrupt),
        isFalse,
      );
    });

    test('notFound → false', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.notFound),
        isFalse,
      );
    });

    test('network → false', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.network),
        isFalse,
      );
    });

    test('unknown → false', () {
      expect(
        shouldShowOpenConflictFileButton(SvnFailureKind.unknown),
        isFalse,
      );
    });
  });

  group('MergeExecutionPanel 打开冲突文件按钮', () {
    testWidgets('textConflict + 回调非空 → 按钮渲染，点击触发回调', (tester) async {
      var called = 0;
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onOpenConflictFile: () => called++,
      );

      final finder = find.widgetWithText(OutlinedButton, '打开冲突文件');
      expect(finder, findsOneWidget);

      await tester.tap(finder);
      await tester.pump();
      expect(called, 1);
    });

    testWidgets('treeConflict → 按钮不渲染（与"标记为已解决"差异点）', (tester) async {
      // 关键差异：treeConflict 时"标记为已解决"按钮显示但"打开冲突文件"不显示
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'tree conflict in foo.dart'),
        onOpenConflictFile: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '打开冲突文件'), findsNothing);
    });

    testWidgets('outOfDate → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'out of date'),
        onOpenConflictFile: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '打开冲突文件'), findsNothing);
    });

    testWidgets('authFailed → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'authentication failed'),
        onOpenConflictFile: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '打开冲突文件'), findsNothing);
    });

    testWidgets('textConflict 但回调为 null → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onOpenConflictFile: null,
      );

      expect(find.widgetWithText(OutlinedButton, '打开冲突文件'), findsNothing);
    });

    testWidgets('pausedJob 为 null → 按钮不渲染（整段摘要区不进入）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: null,
        onOpenConflictFile: () {},
      );

      expect(find.widgetWithText(OutlinedButton, '打开冲突文件'), findsNothing);
    });
  });
}
