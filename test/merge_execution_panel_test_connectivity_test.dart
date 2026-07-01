/// MergeExecutionPanel 中"测试连通性"按钮的渲染与回调契约（network 暂停态专属）。
///
/// 锁四件事：
/// 1. `failureKind == network` + `onTestConnectivity != null` → 按钮渲染、点击触发回调；
/// 2. 其他 8 种 failureKind（textConflict / treeConflict / authFailed / locked
///    / notFound / outOfDate / workingCopyCorrupt / unknown）→ 按钮不渲染；
/// 3. `onTestConnectivity == null` 即使 network 也不渲染；
/// 4. `pausedJob == null` → 按钮不渲染（暂停摘要区整体不进入）。
///
/// 同时单测顶层 [shouldShowTestConnectivityButton] 谓词的真值表（全部 9 种 SvnFailureKind）。
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
  required VoidCallback? onTestConnectivity,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MergeExecutionPanel(
        status:
            pausedJob != null ? ExecutorStatus.paused : ExecutorStatus.idle,
        pausedJob: pausedJob,
        onResume: () {},
        onSkip: () {},
        onCancel: () {},
        onTestConnectivity: onTestConnectivity,
      ),
    ),
  ));
}

void main() {
  group('shouldShowTestConnectivityButton 真值表 — 全部 9 种 SvnFailureKind', () {
    test('network → true（唯一一个返回 true 的分类）', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.network),
        isTrue,
      );
    });

    test('textConflict → false', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.textConflict),
        isFalse,
      );
    });

    test('treeConflict → false', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.treeConflict),
        isFalse,
      );
    });

    test('authFailed → false（凭据问题，本按钮匿名探测会误导）', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.authFailed),
        isFalse,
      );
    });

    test('locked → false（互斥于 cleanup 按钮维度）', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.locked),
        isFalse,
      );
    });

    test('outOfDate → false（互斥于 adjustMaxRetries 按钮维度）', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.outOfDate),
        isFalse,
      );
    });

    test('notFound → false（URL 配置错误，连通性按钮无修复能力）', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.notFound),
        isFalse,
      );
    });

    test('workingCopyCorrupt → false', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.workingCopyCorrupt),
        isFalse,
      );
    });

    test('unknown → false（盲推"测试网络"会误导用户）', () {
      expect(
        shouldShowTestConnectivityButton(SvnFailureKind.unknown),
        isFalse,
      );
    });
  });

  group('MergeExecutionPanel 测试连通性 按钮', () {
    testWidgets('network + 回调非空 → 按钮渲染，点击触发回调', (tester) async {
      var called = 0;
      await _pumpPanel(
        tester,
        // pauseReason 含 "无法连接" 关键字 → classifySvnFailure → network
        pausedJob: _makePausedJob(pauseReason: '无法连接 SVN 服务器'),
        onTestConnectivity: () => called++,
      );

      final finder = find.widgetWithText(OutlinedButton, '测试连通性');
      expect(finder, findsOneWidget);

      await tester.tap(finder);
      await tester.pump();
      expect(called, 1);
    });

    testWidgets('textConflict → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '冲突'),
        onTestConnectivity: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '测试连通性'),
        findsNothing,
      );
    });

    testWidgets('outOfDate → 按钮不渲染（互斥于 adjustMaxRetries）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(
          pauseReason: 'svn: E160028 commit failed - out of date',
        ),
        onTestConnectivity: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '测试连通性'),
        findsNothing,
      );
    });

    testWidgets('locked → 按钮不渲染（互斥于 cleanup）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob:
            _makePausedJob(pauseReason: 'svn: E155004 path is locked'),
        onTestConnectivity: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '测试连通性'),
        findsNothing,
      );
    });

    testWidgets('authFailed → 按钮不渲染（避免匿名 probe 误导）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: 'authentication failed'),
        onTestConnectivity: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '测试连通性'),
        findsNothing,
      );
    });

    testWidgets('network 但回调为 null → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: _makePausedJob(pauseReason: '无法连接 SVN 服务器'),
        onTestConnectivity: null,
      );

      expect(
        find.widgetWithText(OutlinedButton, '测试连通性'),
        findsNothing,
      );
    });

    testWidgets('pausedJob 为 null → 按钮不渲染（整段摘要区不进入）', (tester) async {
      await _pumpPanel(
        tester,
        pausedJob: null,
        onTestConnectivity: () {},
      );

      expect(
        find.widgetWithText(OutlinedButton, '测试连通性'),
        findsNothing,
      );
    });
  });
}
