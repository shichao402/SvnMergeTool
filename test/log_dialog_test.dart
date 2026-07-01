import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/screens/components/dialogs/log_dialog.dart';
import 'package:svn_auto_merge/utils/app_banner.dart';

void main() {
  group('formatLogDialogBodyText', () {
    test('日志非空 → 原日志（不修剪、不转义、不截断）', () {
      const log = '[INFO] step started\n[INFO] step done';
      expect(formatLogDialogBodyText(log), log);
    });

    test('空字符串 → "暂无日志"（占位符）', () {
      expect(formatLogDialogBodyText(''), '暂无日志');
    });

    test('单空格不被视为空 → 原样返回（不做 trim）', () {
      // 锁定"判定基准是 String.isEmpty 而非 isBlank"——避免误吞含空白的合法日志。
      expect(formatLogDialogBodyText(' '), ' ');
    });

    test('单换行不被视为空 → 原样返回', () {
      expect(formatLogDialogBodyText('\n'), '\n');
    });

    test('超长日志原样返回（不截断）', () {
      // 锁定"不截断"——SelectableText 自己做滚动，本函数不参与。
      final log = 'x' * 100000;
      expect(formatLogDialogBodyText(log), log);
    });
  });

  group('formatLogDialogClipboardText', () {
    test('日志非空 → 原日志（逐字副本，所见即所粘）', () {
      const log = '[INFO] step started\n[INFO] step done';
      expect(formatLogDialogClipboardText(log), log);
    });

    test('空字符串 → "暂无日志"（不写空串到剪贴板）', () {
      // 锁定"空日志走占位符"——避免用户点复制后剪贴板没变化、产生"复制没生效"的体验 bug。
      expect(formatLogDialogClipboardText(''), '暂无日志');
    });

    test('与 formatLogDialogBodyText 对空日志的输出字面相等（所见即所粘契约）', () {
      // 这是关键的"等价契约"——用户在对话框看到的占位符文字 == 复制粘贴出来的文字。
      // 任何分歧都会让用户怀疑"我到底复制了什么"。
      expect(formatLogDialogClipboardText(''), formatLogDialogBodyText(''));
    });

    test('与 formatLogDialogBodyText 对非空日志的输出字面相等', () {
      const log = '[ERROR] something wrong';
      expect(formatLogDialogClipboardText(log), formatLogDialogBodyText(log));
    });

    test('特殊字符（换行 / tab / Unicode）原样保留', () {
      const log = '行1\n行2\t制表\n中文 🎉';
      expect(formatLogDialogClipboardText(log), log);
    });
  });

  group('formatLogDialogHeaderText', () {
    test(r'日志非空 → "当前显示 $lineCount 行最近日志"', () {
      expect(
        formatLogDialogHeaderText(log: '[INFO] x', lineCount: 5),
        '当前显示 5 行最近日志',
      );
    });

    test('日志为空 → "暂无执行日志"（描述性散文）', () {
      expect(
        formatLogDialogHeaderText(log: '', lineCount: 0),
        '暂无执行日志',
      );
    });

    test('日志为空 + lineCount 非 0 → 仍走"暂无执行日志"分支（判定凭 log 不凭 lineCount）', () {
      // 锁定"判定基准是 log.isEmpty 而非 lineCount == 0"——
      // 防止有人误以为"行数 0 = 没日志"而切换判定逻辑。
      expect(
        formatLogDialogHeaderText(log: '', lineCount: 100),
        '暂无执行日志',
      );
    });

    test('日志非空 + lineCount == 0 → "当前显示 0 行最近日志"（不兜底切换占位符）', () {
      // 锁定"caller 传入不一致的 lineCount，本函数不做防御兜底"——
      // 上游 bug 应该暴露，不应该被本层静默掩盖。
      expect(
        formatLogDialogHeaderText(log: '   ', lineCount: 0),
        '当前显示 0 行最近日志',
      );
    });

    test('lineCount 不做千分位格式化（直接插值）', () {
      // 日志通常 600 行内，无需千分位；引入格式化反而让"600+"边界不可读。
      expect(
        formatLogDialogHeaderText(log: 'x', lineCount: 1234),
        '当前显示 1234 行最近日志',
      );
    });

    test('与 body 文案故意分歧：占位符 "暂无执行日志" ≠ "暂无日志"', () {
      // 头部是描述性散文（"为什么是空的"），正文是数据槽（"内容"）——职责不同，
      // 占位符故意不同。锁定这条分歧。
      expect(
        formatLogDialogHeaderText(log: '', lineCount: 0),
        isNot(equals(formatLogDialogBodyText(''))),
      );
      expect(formatLogDialogHeaderText(log: '', lineCount: 0), '暂无执行日志');
      expect(formatLogDialogBodyText(''), '暂无日志');
    });

    test('单空格 log 不被视为空 → 走"当前显示"分支', () {
      // 同 body：判定基准是 String.isEmpty 而非 isBlank。
      expect(
        formatLogDialogHeaderText(log: ' ', lineCount: 1),
        '当前显示 1 行最近日志',
      );
    });
  });

  group('三函数协同（对话框三槽位文案契约）', () {
    test('空日志：header / body / clipboard 三槽位的占位符', () {
      // 锁定整个对话框在"日志为空"时的三处文案：
      // - 头部: "暂无执行日志"（向用户解释）
      // - 正文: "暂无日志"（占位数据）
      // - 剪贴板: "暂无日志"（与正文一致，所见即所粘）
      expect(formatLogDialogHeaderText(log: '', lineCount: 0), '暂无执行日志');
      expect(formatLogDialogBodyText(''), '暂无日志');
      expect(formatLogDialogClipboardText(''), '暂无日志');
    });

    test('非空日志：三槽位文案的角色分工', () {
      // - 头部: 摘要（"当前显示 N 行..."）
      // - 正文: 原始日志
      // - 剪贴板: 原始日志（与正文一致）
      const log = '[INFO] line1\n[INFO] line2';
      expect(
        formatLogDialogHeaderText(log: log, lineCount: 2),
        '当前显示 2 行最近日志',
      );
      expect(formatLogDialogBodyText(log), log);
      expect(formatLogDialogClipboardText(log), log);
    });

    test('正文与剪贴板始终字面相等（核心"所见即所粘"等价）', () {
      // 不管 log 是什么，body == clipboard。这是用户体验的核心承诺。
      for (final log in [
        '',
        ' ',
        '\n',
        'normal log',
        'multi\nline\nlog',
        '中文 🎉',
        'x' * 1000,
      ]) {
        expect(
          formatLogDialogClipboardText(log),
          formatLogDialogBodyText(log),
          reason: 'log=${log.length > 20 ? "<${log.length} chars>" : log} 时两者应相等',
        );
      }
    });
  });

  group('filterLogLinesByQuery', () {
    test('空 query → 原 log 直出（不 split / 不重组）', () {
      const log = 'line1\nline2\nline3';
      expect(filterLogLinesByQuery(log, ''), log);
    });

    test('空 log + 空 query → 空串', () {
      expect(filterLogLinesByQuery('', ''), '');
    });

    test('空 log + 非空 query → 空串', () {
      expect(filterLogLinesByQuery('', 'foo'), '');
    });

    test('case-insensitive contains 匹配（小写 query 匹配大写行）', () {
      const log = '[INFO] ok\n[ERROR] failed\n[Warn] hmm';
      expect(filterLogLinesByQuery(log, 'error'), '[ERROR] failed');
    });

    test('大写 query 匹配小写行', () {
      const log = 'error here\nINFO ok';
      expect(filterLogLinesByQuery(log, 'ERROR'), 'error here');
    });

    test('多行匹配按原序保留', () {
      const log = '[INFO] a\n[ERROR] b\n[INFO] c\n[ERROR] d';
      expect(filterLogLinesByQuery(log, 'error'), '[ERROR] b\n[ERROR] d');
    });

    test('无匹配 → 空串', () {
      const log = 'apple\nbanana\ncherry';
      expect(filterLogLinesByQuery(log, 'durian'), '');
    });

    test('query 含前导空格不被 trim（精确子串匹配）', () {
      const log = 'no indent\n  indented';
      // 搜 "  indented"（含两个前导空格）只匹配带缩进的那行
      expect(filterLogLinesByQuery(log, '  indented'), '  indented');
    });

    test('中文 / Unicode 匹配', () {
      const log = '步骤 1 开始\n步骤 2 完成\n冲突: 中文.txt';
      expect(filterLogLinesByQuery(log, '冲突'), '冲突: 中文.txt');
    });

    test('空白行 / 含 tab 的行能被搜到', () {
      const log = '\tindented\nplain';
      expect(filterLogLinesByQuery(log, '\t'), '\tindented');
    });
  });

  group('formatLogDialogHeaderText 搜索分支', () {
    test('日志非空 + query 为 null → 走原 "当前显示 N 行最近日志" 分支（向后兼容）', () {
      expect(
        formatLogDialogHeaderText(log: 'x', lineCount: 5, query: null),
        '当前显示 5 行最近日志',
      );
    });

    test('日志非空 + query 为空字符串 → 退化到原分支', () {
      expect(
        formatLogDialogHeaderText(
            log: 'x', lineCount: 5, query: '', matchedCount: 5),
        '当前显示 5 行最近日志',
      );
    });

    test('日志非空 + query 非空 → "匹配 X / 共 Y 行（关键字: q）"', () {
      expect(
        formatLogDialogHeaderText(
            log: 'a\nb\nc', lineCount: 3, query: 'a', matchedCount: 1),
        '匹配 1 / 共 3 行（关键字: a）',
      );
    });

    test('日志非空 + query 非空 + 0 匹配 → "匹配 0 / 共 N 行"', () {
      expect(
        formatLogDialogHeaderText(
            log: 'a\nb\nc', lineCount: 3, query: 'zzz', matchedCount: 0),
        '匹配 0 / 共 3 行（关键字: zzz）',
      );
    });

    test('日志非空 + query 非空 + matchedCount null → 显示 0', () {
      // 防御：matchedCount 是可选，caller 漏传不应崩溃，按 0 展示。
      expect(
        formatLogDialogHeaderText(log: 'a', lineCount: 1, query: 'x'),
        '匹配 0 / 共 1 行（关键字: x）',
      );
    });

    test('日志为空 + query 非空 → 仍走"暂无执行日志"分支（log 优先）', () {
      // 锁定：判定凭 log，不凭 query——空日志 + 任意 query 都是"暂无执行日志"。
      expect(
        formatLogDialogHeaderText(
            log: '', lineCount: 0, query: 'foo', matchedCount: 0),
        '暂无执行日志',
      );
    });
  });

  group('LogDialog 关键字搜索 widget 行为', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: Builder(builder: (_) => child)),
        );

    Future<void> showLogDialog(
      WidgetTester tester, {
      required String log,
      required int lineCount,
    }) async {
      await tester.pumpWidget(
        wrap(Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => LogDialog.show(
                context: context,
                log: log,
                lineCount: lineCount,
                onClear: () {},
              ),
              child: const Text('open'),
            ),
          ),
        )),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('非空日志：搜索框可见 + 输入 query 后正文只剩匹配行', (tester) async {
      const log = '[INFO] alpha\n[ERROR] beta\n[INFO] gamma';
      await showLogDialog(tester, log: log, lineCount: 3);

      // 初始：搜索框可见，正文含全部三行
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(log), findsOneWidget);

      // 输入 query "ERROR"（实际匹配仅一行）
      await tester.enterText(find.byType(TextField), 'ERROR');
      await tester.pump();

      // 正文应只剩 [ERROR] beta，全文 log 应消失
      expect(find.text('[ERROR] beta'), findsOneWidget);
      expect(find.text(log), findsNothing);
      // header 应显示匹配数
      expect(find.text('匹配 1 / 共 3 行（关键字: ERROR）'), findsOneWidget);
    });

    testWidgets('非空日志：query 不匹配 → 正文落到占位符 "暂无日志"', (tester) async {
      const log = 'alpha\nbeta\ngamma';
      await showLogDialog(tester, log: log, lineCount: 3);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();

      expect(find.text('暂无日志'), findsOneWidget);
      expect(find.text('匹配 0 / 共 3 行（关键字: zzz）'), findsOneWidget);
    });

    testWidgets('空日志：不渲染搜索框（log.isEmpty 时无搜索意义）', (tester) async {
      await showLogDialog(tester, log: '', lineCount: 0);

      expect(find.byType(TextField), findsNothing);
      expect(find.text('暂无日志'), findsOneWidget);
      expect(find.text('暂无执行日志'), findsOneWidget);
    });

    testWidgets('复制按钮复制过滤后的内容（所见即所粘）', (tester) async {
      const log = '[INFO] a\n[ERROR] b\n[INFO] c';

      // mock 剪贴板
      String? clipboardWritten;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWritten =
                (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await showLogDialog(tester, log: log, lineCount: 3);

      // 输入 query 过滤
      await tester.enterText(find.byType(TextField), 'ERROR');
      await tester.pump();

      // 点击复制按钮
      await tester.tap(find.byTooltip('复制日志'));
      await tester.pump();

      expect(clipboardWritten, '[ERROR] b');

      // Overlay 顶部横幅应弹出
      expect(find.text('日志已复制到剪贴板'), findsOneWidget);
      await tester.pump(AppBanner.defaultDuration);

      // 还原
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
  });

  group('buildClearLogConfirmMessage（第三十六轮）', () {
    test('lineCount > 0 → "将清空当前 N 行日志，操作不可恢复。"', () {
      expect(
        buildClearLogConfirmMessage(lineCount: 5),
        '将清空当前 5 行日志，操作不可恢复。',
      );
    });

    test('lineCount = 1 → 单数 / 复数同款句式（不分语态）', () {
      expect(
        buildClearLogConfirmMessage(lineCount: 1),
        '将清空当前 1 行日志，操作不可恢复。',
      );
    });

    test('lineCount = 0 → "当前没有日志可清空。"占位文案（理论分支，UI 已 isEmpty 早退跳过 dialog）',
        () {
      expect(
        buildClearLogConfirmMessage(lineCount: 0),
        '当前没有日志可清空。',
      );
    });

    test('lineCount < 0 → 与 0 同款（防御越界 caller 传负数）', () {
      expect(
        buildClearLogConfirmMessage(lineCount: -3),
        '当前没有日志可清空。',
      );
    });

    test('文案末尾必含"操作不可恢复"（与第三十五轮 _clearPendingRevisions 文案家族同型）',
        () {
      // 锁破坏性操作 confirm 家族文案统一性——_clearPendingRevisions /
      // buildDeleteJobConfirmMessage / buildClearLogConfirmMessage 都以
      // "操作不可恢复" / "任务无法恢复" 结尾。
      final msg = buildClearLogConfirmMessage(lineCount: 999);
      expect(msg.endsWith('操作不可恢复。'), isTrue);
    });
  });

  group('LogDialog 清空按钮二次确认（第三十六轮）', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: Builder(builder: (_) => child)),
        );

    Future<void> openLogDialog(
      WidgetTester tester, {
      required String log,
      required int lineCount,
      required VoidCallback onClear,
    }) async {
      await tester.pumpWidget(
        wrap(Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => LogDialog.show(
                context: context,
                log: log,
                lineCount: lineCount,
                onClear: onClear,
              ),
              child: const Text('open'),
            ),
          ),
        )),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('非空日志 + 点清空 → 弹二次确认 dialog（不立刻清）', (tester) async {
      var cleared = 0;
      await openLogDialog(
        tester,
        log: 'a\nb\nc',
        lineCount: 3,
        onClear: () => cleared++,
      );

      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();

      // confirm dialog 已弹出（标题 + 文案 + 双按钮）
      expect(find.text('清空日志？'), findsOneWidget);
      expect(find.text('将清空当前 3 行日志，操作不可恢复。'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('清空'), findsWidgets); // tooltip + dialog button
      // 但 onClear 仍未触发
      expect(cleared, 0);
    });

    testWidgets('点取消 → 不调 onClear，原 LogDialog 仍可见', (tester) async {
      var cleared = 0;
      await openLogDialog(
        tester,
        log: 'a\nb\nc',
        lineCount: 3,
        onClear: () => cleared++,
      );

      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(cleared, 0);
      // 原 LogDialog 仍在（"操作日志"标题）
      expect(find.text('操作日志'), findsOneWidget);
    });

    testWidgets('点确认（清空按钮）→ 调 onClear + 关闭 LogDialog', (tester) async {
      var cleared = 0;
      await openLogDialog(
        tester,
        log: 'a\nb\nc',
        lineCount: 3,
        onClear: () => cleared++,
      );

      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();
      // 点 confirm dialog 内的"清空"TextButton（非 tooltip 的 IconButton）
      await tester.tap(find.widgetWithText(TextButton, '清空'));
      await tester.pumpAndSettle();

      expect(cleared, 1);
      // 原 LogDialog 也关闭
      expect(find.text('操作日志'), findsNothing);
    });

    testWidgets('空日志点清空 → 跳过 confirm dialog 直接关闭（不打扰用户）',
        (tester) async {
      var cleared = 0;
      await openLogDialog(
        tester,
        log: '',
        lineCount: 0,
        onClear: () => cleared++,
      );

      await tester.tap(find.byTooltip('清空'));
      await tester.pumpAndSettle();

      // confirm dialog 不应弹出
      expect(find.text('清空日志？'), findsNothing);
      // onClear 也不调（空日志清空是 no-op）
      expect(cleared, 0);
      // 原 LogDialog 已关闭
      expect(find.text('操作日志'), findsNothing);
    });
  });

  group('LogDialog 清空二次确认 doc-as-test（第三十六轮）', () {
    final src = File(
            'lib/screens/components/dialogs/log_dialog.dart')
        .readAsStringSync();

    test('helper buildClearLogConfirmMessage 存在且 @visibleForTesting', () {
      expect(
        src,
        contains(
            'String buildClearLogConfirmMessage({required int lineCount})'),
        reason: 'helper 签名锁',
      );
      // 顶层 helper 用 @visibleForTesting 暴露给测试
      final helperIndex =
          src.indexOf('String buildClearLogConfirmMessage');
      final preceding = src.substring(0, helperIndex);
      expect(preceding.contains('@visibleForTesting'), isTrue,
          reason: 'helper 必须 @visibleForTesting');
    });

    test('helper 正分支字面量锁', () {
      expect(
        src,
        contains("'将清空当前 \$lineCount 行日志，操作不可恢复。'"),
        reason: 'lineCount > 0 文案插值锁',
      );
      expect(
        src,
        contains("'当前没有日志可清空。'"),
        reason: 'lineCount <= 0 占位文案锁',
      );
    });

    test('_confirmClearLog 方法签名 + isEmpty 早退顺序', () {
      expect(
        src,
        contains('Future<void> _confirmClearLog(BuildContext context) async'),
        reason: '方法签名锁',
      );
      // isEmpty 早退必须在 showDialog 之前
      final emptyIdx = src.indexOf('if (widget.log.isEmpty)');
      final showIdx = src.indexOf('await showDialog<bool>');
      expect(emptyIdx, greaterThan(0));
      expect(showIdx, greaterThan(0));
      expect(emptyIdx < showIdx, isTrue,
          reason: 'isEmpty 早退必须先于 showDialog（空日志不弹 dialog 直接 pop）');
    });

    test('_confirmClearLog 调用 buildClearLogConfirmMessage 渲染文案 + 取消默认 false',
        () {
      expect(
        src,
        contains('buildClearLogConfirmMessage(lineCount: widget.lineCount)'),
        reason: 'AlertDialog content 必须复用 helper 而非 inline 字面量',
      );
      // 取消按钮 pop(false)
      expect(
        src,
        contains('Navigator.of(dialogContext).pop(false)'),
        reason: '取消按钮 pop(false)',
      );
      // 清空按钮 pop(true)
      expect(
        src,
        contains('Navigator.of(dialogContext).pop(true)'),
        reason: '清空按钮 pop(true)',
      );
      // 标题 / 取消 / 清空 三段字面量
      expect(src, contains("Text('清空日志？')"));
      expect(src, contains("Text('取消')"));
      expect(src, contains("Text('清空')"));
    });

    test('!confirmed 早退 + 跨 await context.mounted 守护先于 onClear', () {
      // !confirmed return 顺序锁
      final cancelIdx = src.indexOf('if (confirmed != true) return;');
      final mountedIdx = src.indexOf(
          'if (!context.mounted) return;', cancelIdx);
      final clearIdx = src.indexOf('widget.onClear();', cancelIdx);
      final popIdx = src.indexOf('Navigator.of(context).pop();', cancelIdx);

      expect(cancelIdx, greaterThan(0), reason: '!confirmed 早退守卫存在');
      expect(mountedIdx, greaterThan(cancelIdx),
          reason: 'context.mounted 守卫必须在 confirmed 检查之后');
      expect(clearIdx, greaterThan(mountedIdx),
          reason: 'widget.onClear() 必须在 mounted 守卫之后（R131 档 3 不变量 I1）');
      expect(popIdx, greaterThan(clearIdx),
          reason: 'Navigator.pop() 必须在 onClear 之后（用户先看到清空效果再关闭）');
    });

    test('清空 IconButton onPressed 已切到 _confirmClearLog（不再裸调 onClear）', () {
      expect(
        src,
        contains('onPressed: () => _confirmClearLog(context)'),
        reason: 'IconButton 必须走 _confirmClearLog，不能直接调 widget.onClear()',
      );
      // 反向锁：build() 内"清空" IconButton 区域不应再含 widget.onClear() 的裸调
      // （唯一 widget.onClear() 调用应仅在 _confirmClearLog 内）
      final occurrences = 'widget.onClear();'.allMatches(src).length;
      expect(occurrences, 1,
          reason: 'widget.onClear() 应仅在 _confirmClearLog 内出现一次');
    });
  });
}
