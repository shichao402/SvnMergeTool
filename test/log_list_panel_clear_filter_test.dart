/// `hasActiveLogTextFilter` 顶层谓词的真值表 + log_list_panel
/// "清空筛选"按钮的渲染与回调契约。
///
/// 锁三件事：
/// 1. 谓词 8 路径（3 个布尔 ∈ {空, 非空} ⇒ 2³ = 8）真值表 — 当前 lib 不再
///    用此谓词驱动 UI（因为这会逼出 controller.addListener，违反 R130 档 4
///    lib 0 处 addListener 不变量），但保留谓词作为可被未来非 UI 调用方
///    （日志导出过滤摘要 / debug snapshot）共用的稳定语义；
/// 2. UI 当 onClearFilter 为 null → 按钮不渲染（用于禁用整个能力）；
/// 3. UI 当 onClearFilter 非 null → 按钮始终 enabled（除非 isLoading），
///    点击触发回调。空文本时点击等价"应用空过滤"，无副作用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/screens/components/log_list_panel.dart';
import 'package:svn_auto_merge/services/log_filter_service.dart';

Future<void> _pumpPanel(
  WidgetTester tester, {
  required VoidCallback? onClearFilter,
  bool isLoading = false,
}) async {
  final authorController = TextEditingController();
  final titleController = TextEditingController();
  final messageController = TextEditingController();
  addTearDown(authorController.dispose);
  addTearDown(titleController.dispose);
  addTearDown(messageController.dispose);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LogListPanel(
        entries: const [],
        selectedRevisions: const {},
        pendingRevisions: const {},
        mergedRevisions: const {},
        isLoading: isLoading,
        authorController: authorController,
        titleController: titleController,
        messageController: messageController,
        stopOnCopy: false,
        onStopOnCopyChanged: (_) {},
        onApplyFilter: () {},
        onClearFilter: onClearFilter,
        canSyncLatest: false,
        onSyncLatest: () {},
        canLoadMore: false,
        onLoadMore: () {},
        canStopPreload: false,
        onStopPreload: () {},
        canExportCsv: false,
        onExportCsv: () {},
        cachedCount: 0,
        latestCachedRevision: null,
        earliestCachedRevision: null,
        branchPoint: null,
        preloadStatusText: null,
        boundaryText: null,
        currentPage: 0,
        totalPages: 1,
        hasMore: false,
        onPageChanged: (_) {},
        selectableEntryCount: 0,
        onSelectAllSelectable: () {},
        onClearSelection: () {},
        onSelectionChanged: (_, __) {},
      ),
    ),
  ));
}

void main() {
  group('hasActiveLogTextFilter 真值表', () {
    test('全部为空 → false', () {
      expect(
        hasActiveLogTextFilter(author: '', title: '', message: ''),
        isFalse,
      );
    });

    test('全部 null → false', () {
      expect(hasActiveLogTextFilter(), isFalse);
    });

    test('纯空白字符 → true（与 isStringFilterEmpty 同口径，不 trim）', () {
      // isStringFilterEmpty 只判 null / isEmpty，不 trim：
      // 用户键入 '   ' 是 3 个真实字符，下游 LogFilter.isEmpty 也会视为非空。
      // 这里跟齐底层口径，避免 UI 谓词与过滤实际行为不一致。
      expect(
        hasActiveLogTextFilter(author: '   ', title: '', message: ''),
        isTrue,
      );
    });

    test('仅 author 非空 → true', () {
      expect(
        hasActiveLogTextFilter(author: 'alice', title: '', message: ''),
        isTrue,
      );
    });

    test('仅 title 非空 → true', () {
      expect(
        hasActiveLogTextFilter(author: '', title: 'bug', message: ''),
        isTrue,
      );
    });

    test('仅 message 非空 → true', () {
      expect(
        hasActiveLogTextFilter(author: '', title: '', message: 'fix'),
        isTrue,
      );
    });

    test('author + title 非空 → true', () {
      expect(
        hasActiveLogTextFilter(author: 'a', title: 'b', message: ''),
        isTrue,
      );
    });

    test('author + message 非空 → true', () {
      expect(
        hasActiveLogTextFilter(author: 'a', title: '', message: 'm'),
        isTrue,
      );
    });

    test('title + message 非空 → true', () {
      expect(
        hasActiveLogTextFilter(author: '', title: 't', message: 'm'),
        isTrue,
      );
    });

    test('三者都非空 → true', () {
      expect(
        hasActiveLogTextFilter(author: 'a', title: 't', message: 'm'),
        isTrue,
      );
    });

    test('内容含前后空白但非纯空白 → true（与 isStringFilterEmpty 同口径）', () {
      expect(
        hasActiveLogTextFilter(author: '  alice  '),
        isTrue,
      );
    });
  });

  group('LogListPanel 清空筛选按钮', () {
    testWidgets('onClearFilter 非空 + 非 loading → 按钮渲染 enabled，点击触发',
        (tester) async {
      var called = 0;
      await _pumpPanel(
        tester,
        onClearFilter: () => called++,
      );

      final finder = find.widgetWithText(OutlinedButton, '清空筛选');
      expect(finder, findsOneWidget);

      final button = tester.widget<OutlinedButton>(finder);
      expect(button.onPressed, isNotNull);

      await tester.tap(finder);
      await tester.pump();
      expect(called, 1);
    });

    testWidgets('onClearFilter 非空 + isLoading == true → 按钮渲染但 disabled',
        (tester) async {
      await _pumpPanel(
        tester,
        onClearFilter: () {},
        isLoading: true,
      );

      final finder = find.widgetWithText(OutlinedButton, '清空筛选');
      expect(finder, findsOneWidget);

      final button = tester.widget<OutlinedButton>(finder);
      expect(button.onPressed, isNull);
    });

    testWidgets('onClearFilter == null → 按钮不渲染', (tester) async {
      await _pumpPanel(
        tester,
        onClearFilter: null,
      );

      expect(find.widgetWithText(OutlinedButton, '清空筛选'), findsNothing);
    });
  });
}
