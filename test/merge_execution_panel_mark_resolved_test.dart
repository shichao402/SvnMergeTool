/// MergeExecutionPanel 中"标记为已解决"按钮的渲染与回调契约。
///
/// 锁四件事：
/// 1. `failureKind ∈ {textConflict, treeConflict}` + `onMarkResolved != null` →
///    主按钮渲染、点击触发回调（默认 [SvnResolveAccept.working]）；
/// 2. `failureKind` 是其他类（authFailed / outOfDate / locked / unknown）→ 按钮不渲染；
/// 3. `onMarkResolved == null` 即使条件满足也不渲染；
/// 4. `pausedJob == null` → 按钮不渲染（暂停摘要区整体不进入）。
///
/// 同时单测顶层 [shouldShowMarkResolvedButton] 谓词的真值表（5 种 SvnFailureKind）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/execution/svn_failure_kind.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/screens/components/merge_execution_panel.dart';
import 'package:svn_auto_merge/services/svn_service.dart';

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
  required void Function(SvnResolveAccept mode)? onMarkResolved,
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
        onMarkResolved: onMarkResolved,
      ),
    ),
  ));
}

void main() {
  group('shouldShowMarkResolvedButton 真值表 — 全部 8 种 SvnFailureKind', () {
    test('textConflict → true', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.textConflict), isTrue);
    });

    test('treeConflict → true', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.treeConflict), isTrue);
    });

    test('outOfDate → false（应该走"继续"重跑提交）', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.outOfDate), isFalse);
    });

    test('authFailed → false（与冲突无关）', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.authFailed), isFalse);
    });

    test('locked → false（应跑 svn cleanup 不是 resolve）', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.locked), isFalse);
    });

    test('workingCopyCorrupt → false（resolve 救不回损坏的 wc）', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.workingCopyCorrupt),
          isFalse);
    });

    test('notFound → false', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.notFound), isFalse);
    });

    test('network → false', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.network), isFalse);
    });

    test('unknown → false（不让用户瞎按 resolve 掩盖未识别问题）', () {
      expect(shouldShowMarkResolvedButton(SvnFailureKind.unknown), isFalse);
    });
  });

  group('MergeExecutionPanel 标记为已解决按钮', () {
    testWidgets('textConflict + 回调非空 → 主按钮渲染，点击触发回调（mode=working）', (tester) async {
      SvnResolveAccept? receivedMode;
      // pauseReason: '冲突' → classifySvnFailure → textConflict
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onMarkResolved: (mode) => receivedMode = mode,
      );

      final finder = find.widgetWithText(OutlinedButton, '标记为已解决');
      expect(finder, findsOneWidget);

      await tester.tap(finder);
      await tester.pump();
      expect(receivedMode, SvnResolveAccept.working,
          reason: '主按钮固定走 working 模式');
    });

    testWidgets('textConflict → 高级 PopupMenu "更多…" 按钮渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onMarkResolved: (_) {},
      );

      expect(find.text('更多…'), findsOneWidget,
          reason: '高级 accept 模式入口');
    });

    testWidgets('点击 "更多…" → 展开 3 项，选 mine-full 触发 mineFull mode', (tester) async {
      SvnResolveAccept? receivedMode;
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onMarkResolved: (mode) => receivedMode = mode,
      );

      await tester.tap(find.text('更多…'));
      await tester.pumpAndSettle();

      // 3 个 advanced 选项展开
      expect(find.text('--accept mine-full'), findsOneWidget);
      expect(find.text('--accept theirs-full'), findsOneWidget);
      expect(find.text('--accept base'), findsOneWidget);

      await tester.tap(find.text('--accept mine-full'));
      await tester.pumpAndSettle();
      expect(receivedMode, SvnResolveAccept.mineFull);
    });

    testWidgets('点击 "更多…" → 选 theirs-full 触发 theirsFull mode', (tester) async {
      SvnResolveAccept? receivedMode;
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onMarkResolved: (mode) => receivedMode = mode,
      );

      await tester.tap(find.text('更多…'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('--accept theirs-full'));
      await tester.pumpAndSettle();
      expect(receivedMode, SvnResolveAccept.theirsFull);
    });

    testWidgets('点击 "更多…" → 选 base 触发 base mode', (tester) async {
      SvnResolveAccept? receivedMode;
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onMarkResolved: (mode) => receivedMode = mode,
      );

      await tester.tap(find.text('更多…'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('--accept base'));
      await tester.pumpAndSettle();
      expect(receivedMode, SvnResolveAccept.base);
    });

    testWidgets('treeConflict → 主按钮渲染', (tester) async {
      // pauseReason: 'tree conflict ...' → treeConflict
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'tree conflict in foo.dart'),
        onMarkResolved: (_) {},
      );

      expect(find.widgetWithText(OutlinedButton, '标记为已解决'), findsOneWidget);
    });

    testWidgets('outOfDate → 主按钮 + "更多…" 都不渲染（即使提供了回调）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'out of date'),
        onMarkResolved: (_) {},
      );

      expect(find.widgetWithText(OutlinedButton, '标记为已解决'), findsNothing);
      expect(find.text('更多…'), findsNothing);
    });

    testWidgets('authFailed → 主按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'authentication failed'),
        onMarkResolved: (_) {},
      );

      expect(find.widgetWithText(OutlinedButton, '标记为已解决'), findsNothing);
    });

    testWidgets('textConflict 但回调为 null → 主按钮 + "更多…" 都不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onMarkResolved: null,
      );

      expect(find.widgetWithText(OutlinedButton, '标记为已解决'), findsNothing);
      expect(find.text('更多…'), findsNothing);
    });

    testWidgets('pausedJob 为 null → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: null,
        onMarkResolved: (_) {},
      );

      expect(find.widgetWithText(OutlinedButton, '标记为已解决'), findsNothing);
    });
  });
}
