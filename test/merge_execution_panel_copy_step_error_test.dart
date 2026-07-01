/// 步骤错误信息复制按钮契约。
///
/// 锁两件事：
/// 1. [formatStepErrorClipboardText] 真值表（占位符 / 直通 / Unicode 解码）；
/// 2. `selectedSnapshot.error != null` → IconButton(Icons.copy_all) 渲染，点击触发
///    Clipboard.setData + SnackBar `'步骤错误已复制到剪贴板'`。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/execution/executor_status.dart';
import 'package:svn_auto_merge/execution/step_snapshot.dart';
import 'package:svn_auto_merge/screens/components/merge_execution_panel.dart';
import 'package:svn_auto_merge/utils/app_banner.dart';

StepSnapshot _snapshotWith({String? error}) {
  return StepSnapshot(
    stepId: 's1',
    stepTypeId: 't',
    stepName: '步骤一',
    status: StepExecutionStatus.failed,
    inputData: const {},
    config: const {},
    error: error,
    startTime: DateTime.parse('2026-01-01T10:00:00Z'),
    endTime: DateTime.parse('2026-01-01T10:00:01Z'),
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required StepSnapshot? selectedSnapshot,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MergeExecutionPanel(
        status: ExecutorStatus.idle,
        pausedJob: null,
        onResume: () {},
        onSkip: () {},
        onCancel: () {},
        selectedSnapshot: selectedSnapshot,
        selectedStepId: selectedSnapshot?.stepId,
        snapshots: selectedSnapshot == null
            ? const {}
            : {selectedSnapshot.stepId: selectedSnapshot},
      ),
    ),
  ));
}

void main() {
  group('formatStepErrorClipboardText', () {
    test('null → 占位符 "暂无错误信息"', () {
      expect(formatStepErrorClipboardText(null), '暂无错误信息');
    });

    test('空串 → 占位符 "暂无错误信息"', () {
      expect(formatStepErrorClipboardText(''), '暂无错误信息');
    });

    test('普通文本 → 原文直通', () {
      expect(
        formatStepErrorClipboardText('svn: E155010: not under version control'),
        'svn: E155010: not under version control',
      );
    });

    test('包含 {U+xxxx} 转义 → 解码为字符（与面板显示字面一致）', () {
      // 0x4E2D = 中, 0x6587 = 文
      expect(
        formatStepErrorClipboardText('错误: {U+4E2D}{U+6587}冲突'),
        '错误: 中文冲突',
      );
    });
  });

  group('MergeExecutionPanel 步骤错误复制按钮', () {
    testWidgets('selectedSnapshot.error 非空 → 渲染 Icons.copy_all 按钮', (tester) async {
      await _pumpPanel(
        tester,
        selectedSnapshot: _snapshotWith(error: 'svn: oops'),
      );

      expect(find.byIcon(Icons.copy_all), findsOneWidget);
    });

    testWidgets('selectedSnapshot.error 为 null → 不渲染复制按钮', (tester) async {
      await _pumpPanel(
        tester,
        selectedSnapshot: _snapshotWith(error: null),
      );

      expect(find.byIcon(Icons.copy_all), findsNothing);
    });

    testWidgets('点击复制按钮 → 写剪贴板 + SnackBar 反馈', (tester) async {
      // 拦截 Clipboard 写入 channel，捕获写入的 text。
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map?;
            clipboardText = args?['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await _pumpPanel(
        tester,
        selectedSnapshot: _snapshotWith(error: '冲突: {U+4E2D}文'),
      );

      await tester.tap(find.byIcon(Icons.copy_all));
      await tester.pump(); // 启动 async 剪贴板写入
      await tester.pump(); // 完成写入并插入 Overlay
      await tester.pump(const Duration(milliseconds: 300)); // 入场动画

      expect(clipboardText, '冲突: 中文');
      expect(find.text('步骤错误已复制到剪贴板'), findsOneWidget);
      await tester.pump(AppBanner.defaultDuration);
    });
  });
}
