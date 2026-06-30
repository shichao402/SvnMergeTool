import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/log_entry.dart';
import 'package:svn_auto_merge/providers/app_state.dart' show isUsableSourceUrl;
import 'package:svn_auto_merge/screens/components/log_list_panel.dart';
import 'package:svn_auto_merge/services/log_cache_service.dart'
    show isUsableSqlStringFilter;
import 'package:svn_auto_merge/services/log_filter_service.dart'
    show isUsableWorkingDirectory;
import 'package:svn_auto_merge/services/log_sync_service.dart'
    show planSyncFromHead, truncateEntriesAtRevision;
import 'package:svn_auto_merge/services/svn_service.dart'
    show isUsableSvnCredential;

LogEntry _titledEntry(int rev, String title) => LogEntry(
      revision: rev,
      author: 'svn',
      date: '2026-06-04T10:00:00Z',
      title: title,
      message: title,
    );

class _RestartHeadSyncHarness extends StatefulWidget {
  const _RestartHeadSyncHarness();

  @override
  State<_RestartHeadSyncHarness> createState() =>
      _RestartHeadSyncHarnessState();
}

class _RestartHeadSyncHarnessState extends State<_RestartHeadSyncHarness> {
  final _authorController = TextEditingController();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  var _entries = <LogEntry>[
    _titledEntry(1000, 'cached boundary r1000'),
    _titledEntry(999, 'cached old r999'),
  ];
  var _isLoading = false;
  var _cachedCount = 4000;
  int? _latestCachedRevision = 1000;
  final _earliestCachedRevision = 1;

  @override
  void dispose() {
    _authorController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _syncLatestFromUi() async {
    setState(() => _isLoading = true);
    await Future<void>.delayed(Duration.zero);

    final plan = planSyncFromHead(
      headRevision: 1003,
      cachedStartRevision: _latestCachedRevision,
      limit: 50,
    );
    var fetched = <LogEntry>[
      _titledEntry(1003, 'new svn commit r1003'),
      _titledEntry(1002, 'new svn commit r1002'),
      _titledEntry(1001, 'new svn commit r1001'),
      _titledEntry(1000, 'cached boundary r1000 refreshed'),
    ];
    fetched = truncateEntriesAtRevision(fetched, plan.truncateAtRevision!);
    final fetchedRevisions = fetched.map((e) => e.revision).toSet();

    setState(() {
      _entries = [
        ...fetched,
        ..._entries.where((e) => !fetchedRevisions.contains(e.revision)),
      ];
      _cachedCount += 3;
      _latestCachedRevision = 1003;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 800,
          child: LogListPanel(
            entries: _entries,
            selectedRevisions: const {},
            pendingRevisions: const {},
            mergedRevisions: const {},
            isLoading: _isLoading,
            authorController: _authorController,
            titleController: _titleController,
            messageController: _messageController,
            stopOnCopy: false,
            onStopOnCopyChanged: (_) {},
            onApplyFilter: () {},
            onClearFilter: () {},
            onRefresh: () {},
            canSyncLatest: true,
            onSyncLatest: () {
              _syncLatestFromUi();
            },
            canLoadMore: true,
            onLoadMore: () {},
            canStopPreload: false,
            onStopPreload: () {},
            canExportCsv: true,
            onExportCsv: () {},
            cachedCount: _cachedCount,
            latestCachedRevision: _latestCachedRevision,
            earliestCachedRevision: _earliestCachedRevision,
            branchPoint: null,
            preloadStatusText: null,
            boundaryText: null,
            currentPage: 0,
            totalPages: 1,
            hasMore: false,
            onPageChanged: (_) {},
            selectableEntryCount: _entries.length,
            onSelectAllSelectable: () {},
            onClearSelection: () {},
            onSelectionChanged: (_, __) {},
          ),
        ),
      ),
    );
  }
}

void main() {
  group('canSelectLogEntry', () {
    test('returns true only when none of the disable flags is set', () {
      expect(
        canSelectLogEntry(isMerged: false, isPending: false, isLoading: false),
        isTrue,
      );
    });

    test('returns false when isMerged', () {
      expect(
        canSelectLogEntry(isMerged: true, isPending: false, isLoading: false),
        isFalse,
      );
    });

    test('returns false when isPending', () {
      expect(
        canSelectLogEntry(isMerged: false, isPending: true, isLoading: false),
        isFalse,
      );
    });

    test('returns false when isLoading', () {
      expect(
        canSelectLogEntry(isMerged: false, isPending: false, isLoading: true),
        isFalse,
      );
    });

    test('returns false when multiple disable flags overlap', () {
      expect(
        canSelectLogEntry(isMerged: true, isPending: true, isLoading: true),
        isFalse,
      );
    });
  });

  group('logEntryTileColor', () {
    test('selected wins over every other state', () {
      // 即使同时是 pending / merged / 偶数行，被选中就显示蓝色。
      expect(
        logEntryTileColor(
          isSelected: true,
          isPending: true,
          isMerged: true,
          index: 0,
        ),
        Colors.blue.shade50,
      );
    });

    test('pending beats merged and zebra', () {
      expect(
        logEntryTileColor(
          isSelected: false,
          isPending: true,
          isMerged: true,
          index: 0,
        ),
        Colors.green.shade100,
      );
    });

    test('merged beats zebra', () {
      expect(
        logEntryTileColor(
          isSelected: false,
          isPending: false,
          isMerged: true,
          index: 0,
        ),
        Colors.grey.shade200,
      );
    });

    test('even index gets zebra grey50 when no other flag is set', () {
      expect(
        logEntryTileColor(
          isSelected: false,
          isPending: false,
          isMerged: false,
          index: 2,
        ),
        Colors.grey.shade50,
      );
    });

    test('odd index gets null background by default', () {
      expect(
        logEntryTileColor(
          isSelected: false,
          isPending: false,
          isMerged: false,
          index: 1,
        ),
        isNull,
      );
    });
  });

  group('pagination predicates', () {
    test(
        'canGoFirstPage / canGoPrevPage are true when not at first and not loading',
        () {
      expect(canGoFirstPage(currentPage: 1, isLoading: false), isTrue);
      expect(canGoPrevPage(currentPage: 1, isLoading: false), isTrue);
    });

    test('canGoFirstPage / canGoPrevPage are false at page 0', () {
      expect(canGoFirstPage(currentPage: 0, isLoading: false), isFalse);
      expect(canGoPrevPage(currentPage: 0, isLoading: false), isFalse);
    });

    test('canGoFirstPage / canGoPrevPage are false while loading', () {
      expect(canGoFirstPage(currentPage: 5, isLoading: true), isFalse);
      expect(canGoPrevPage(currentPage: 5, isLoading: true), isFalse);
    });

    // R91 等价锁定：`canGoFirstPage` 是 `canGoPrevPage` 的语义别名（delegate）。
    // 在 6 角点（page 0/1/边界 + loading true/false）上断言两者输出永远相同。
    test('R91 等价：canGoFirstPage 永远 == canGoPrevPage', () {
      final cases = <({int page, bool loading})>[
        (page: 0, loading: false),
        (page: 0, loading: true),
        (page: 1, loading: false),
        (page: 1, loading: true),
        (page: 99, loading: false),
        (page: 99, loading: true),
      ];
      for (final c in cases) {
        expect(
          canGoFirstPage(currentPage: c.page, isLoading: c.loading),
          canGoPrevPage(currentPage: c.page, isLoading: c.loading),
          reason: 'page=${c.page} loading=${c.loading} 时两者应等价',
        );
      }
    });

    test('canGoNextPage requires hasMore and not loading', () {
      expect(canGoNextPage(hasMore: true, isLoading: false), isTrue);
      expect(canGoNextPage(hasMore: false, isLoading: false), isFalse);
      expect(canGoNextPage(hasMore: true, isLoading: true), isFalse);
    });

    test('canGoLastPage needs totalPages > 0 and current < last', () {
      expect(
        canGoLastPage(currentPage: 0, totalPages: 3, isLoading: false),
        isTrue,
      );
      // 已在末页
      expect(
        canGoLastPage(currentPage: 2, totalPages: 3, isLoading: false),
        isFalse,
      );
      // 总页数未知
      expect(
        canGoLastPage(currentPage: 0, totalPages: 0, isLoading: false),
        isFalse,
      );
      // 加载中
      expect(
        canGoLastPage(currentPage: 0, totalPages: 3, isLoading: true),
        isFalse,
      );
    });
  });

  group('formatPageLabel', () {
    test('uses 1-based current page', () {
      expect(formatPageLabel(currentPage: 0, totalPages: 5), '1 / 5');
      expect(formatPageLabel(currentPage: 4, totalPages: 5), '5 / 5');
    });

    test('shows ? when totalPages is unknown (<= 0)', () {
      expect(formatPageLabel(currentPage: 0, totalPages: 0), '1 / ?');
      expect(formatPageLabel(currentPage: 3, totalPages: -1), '4 / ?');
    });
  });

  group('chipSpecsForLogSummary', () {
    // 默认色（与 _StatusChip 默认一致）
    const defaultBg = Color(0xFFF3F4F6);
    const defaultFg = Color(0xFF4B5563);
    // 分支点配色
    const branchBg = Color(0xFFE8F4FD);
    const branchFg = Color(0xFF0F5A94);
    // 预加载配色
    const preloadBg = Color(0xFFEEF4FF);
    const preloadFg = Color(0xFF335C99);
    // 边界配色
    const boundaryBg = Color(0xFFFFF4E5);
    const boundaryFg = Color(0xFF9A5D00);

    List<LogSummaryChipSpec> call({
      int cachedCount = 0,
      int? latestCachedRevision,
      int? earliestCachedRevision,
      int? branchPoint,
      String? preloadStatusText,
      String? boundaryText,
    }) =>
        chipSpecsForLogSummary(
          cachedCount: cachedCount,
          latestCachedRevision: latestCachedRevision,
          earliestCachedRevision: earliestCachedRevision,
          branchPoint: branchPoint,
          preloadStatusText: preloadStatusText,
          boundaryText: boundaryText,
        );

    test('cachedCount = 0 → "未缓存日志"，仅 1 条', () {
      final specs = call();
      expect(specs.length, 1);
      expect(specs.first.label, '未缓存日志');
      expect(specs.first.backgroundColor.toARGB32(), defaultBg.toARGB32());
      expect(specs.first.textColor.toARGB32(), defaultFg.toARGB32());
    });

    test('cachedCount > 0 → "缓存 N 条"', () {
      final specs = call(cachedCount: 42);
      expect(specs.first.label, '缓存 42 条');
    });

    test('区间 chip 仅当两端 revision 都给时出现', () {
      // 只给 latest → 不出现
      expect(
        call(cachedCount: 5, latestCachedRevision: 100)
            .where((s) => s.label.startsWith('区间')),
        isEmpty,
      );
      // 只给 earliest → 不出现
      expect(
        call(cachedCount: 5, earliestCachedRevision: 50)
            .where((s) => s.label.startsWith('区间')),
        isEmpty,
      );
      // 都给 → 出现一条 "区间 r{latest} -> r{earliest}"
      final specs = call(
        cachedCount: 5,
        latestCachedRevision: 100,
        earliestCachedRevision: 50,
      );
      final range = specs.firstWhere((s) => s.label.startsWith('区间'));
      expect(range.label, '区间 r100 -> r50');
      // 区间用默认色
      expect(range.backgroundColor.toARGB32(), defaultBg.toARGB32());
      expect(range.textColor.toARGB32(), defaultFg.toARGB32());
    });

    test('branchPoint 非 null → "分支点 rX" + 蓝色对', () {
      final specs = call(branchPoint: 88);
      final branch = specs.firstWhere((s) => s.label.startsWith('分支点'));
      expect(branch.label, '分支点 r88');
      expect(branch.backgroundColor.toARGB32(), branchBg.toARGB32());
      expect(branch.textColor.toARGB32(), branchFg.toARGB32());
    });

    test('branchPoint = null → 不出现分支点 chip', () {
      expect(
        call().where((s) => s.label.startsWith('分支点')),
        isEmpty,
      );
    });

    test('preloadStatusText null/空串 → 不出现；非空 → 蓝色对', () {
      expect(
        call(preloadStatusText: null).where((s) => s.label == 'foo'),
        isEmpty,
      );
      expect(
        call(preloadStatusText: '').length,
        1, // 仅缓存 chip
      );
      final specs = call(preloadStatusText: '正在预加载...');
      final preload = specs.firstWhere((s) => s.label == '正在预加载...');
      expect(preload.backgroundColor.toARGB32(), preloadBg.toARGB32());
      expect(preload.textColor.toARGB32(), preloadFg.toARGB32());
    });

    test('boundaryText null/空串 → 不出现；非空 → 橙色对', () {
      expect(
        call(boundaryText: '').length,
        1,
      );
      final specs = call(boundaryText: '已到达仓库起点');
      final boundary = specs.firstWhere((s) => s.label == '已到达仓库起点');
      expect(boundary.backgroundColor.toARGB32(), boundaryBg.toARGB32());
      expect(boundary.textColor.toARGB32(), boundaryFg.toARGB32());
    });

    test('五项都给齐 → 5 chip 顺序固定（缓存→区间→分支点→preload→boundary）', () {
      final specs = call(
        cachedCount: 10,
        latestCachedRevision: 200,
        earliestCachedRevision: 100,
        branchPoint: 90,
        preloadStatusText: '预加载中',
        boundaryText: '到底了',
      );
      expect(specs.map((s) => s.label).toList(), [
        '缓存 10 条',
        '区间 r200 -> r100',
        '分支点 r90',
        '预加载中',
        '到底了',
      ]);
    });

    test('只给缓存 + boundary → 跳过中间几条，顺序仍正确', () {
      final specs = call(
        cachedCount: 3,
        boundaryText: '到底了',
      );
      expect(specs.map((s) => s.label).toList(), ['缓存 3 条', '到底了']);
    });

    // ---- Step 27 - 第二十三层 hover：tooltip 字段联动断言 ----

    test('Step 27：缓存 chip tooltip = tooltipForCacheChip(cachedCount)', () {
      final empty = call().first;
      expect(empty.tooltip, tooltipForCacheChip(0));
      final filled = call(cachedCount: 7).first;
      expect(filled.tooltip, tooltipForCacheChip(7));
    });

    test('Step 27：区间 chip tooltip = tooltipForRangeChip(latest, earliest)', () {
      final specs = call(
        cachedCount: 5,
        latestCachedRevision: 100,
        earliestCachedRevision: 50,
      );
      final range = specs.firstWhere((s) => s.label.startsWith('区间'));
      expect(
        range.tooltip,
        tooltipForRangeChip(
          latestCachedRevision: 100,
          earliestCachedRevision: 50,
        ),
      );
    });

    test('Step 27：分支点 chip tooltip = tooltipForBranchPointChip(branchPoint)',
        () {
      final specs = call(branchPoint: 88);
      final branch = specs.firstWhere((s) => s.label.startsWith('分支点'));
      expect(branch.tooltip, tooltipForBranchPointChip(88));
    });

    test('Step 27：preload chip tooltip == null（label 已自描述，去重契约）', () {
      final specs = call(preloadStatusText: '正在预加载...');
      final preload = specs.firstWhere((s) => s.label == '正在预加载...');
      expect(preload.tooltip, isNull,
          reason: 'preload label 已是完整文案，再加 tooltip 会重复噪音');
    });

    test('Step 27：boundary chip tooltip == null（label 已自描述，去重契约）', () {
      final specs = call(boundaryText: '已到达仓库起点');
      final boundary = specs.firstWhere((s) => s.label == '已到达仓库起点');
      expect(boundary.tooltip, isNull,
          reason: 'boundary label 已是完整文案，再加 tooltip 会重复噪音');
    });
  });

  group('tooltipForCacheChip（Step 27 - 第二十三层 hover）', () {
    test('cachedCount = 0 → "未缓存" + 同步入口提示', () {
      final t = tooltipForCacheChip(0);
      expect(t, contains('未缓存'));
      expect(t, contains('SVN'));
    });

    test('cachedCount > 0 → 含具体数字 + "本地" 关键字', () {
      final t = tooltipForCacheChip(42);
      expect(t, contains('42'));
      expect(t, contains('本地'));
      expect(t, contains('缓存'));
    });

    test('cachedCount 边界过渡：0 与 1 文案明显不同', () {
      expect(tooltipForCacheChip(0), isNot(equals(tooltipForCacheChip(1))));
    });
  });

  group('tooltipForRangeChip（Step 27 - 第二十三层 hover）', () {
    test('包含 latest / earliest 数字 + 自然语言"最新/最早"', () {
      final t = tooltipForRangeChip(
        latestCachedRevision: 200,
        earliestCachedRevision: 100,
      );
      expect(t, contains('200'));
      expect(t, contains('100'));
      expect(t, contains('最新'));
      expect(t, contains('最早'));
      // 提示用户向下翻页的入口
      expect(t, contains('加载更多'));
    });

    test('latest == earliest（单点缓存）→ 同样合法返回', () {
      final t = tooltipForRangeChip(
        latestCachedRevision: 50,
        earliestCachedRevision: 50,
      );
      expect(t, contains('50'));
    });
  });

  group('tooltipForBranchPointChip（Step 27 - 第二十三层 hover）', () {
    test('包含 branchPoint 数字 + "父分支" / "无法合并" 关键字', () {
      final t = tooltipForBranchPointChip(88);
      expect(t, contains('88'));
      expect(t, contains('父分支'));
      expect(t, contains('无法合并'));
    });

    test('不同 branchPoint 数字 → tooltip 不同（防止常量化）', () {
      expect(
        tooltipForBranchPointChip(10),
        isNot(equals(tooltipForBranchPointChip(20))),
      );
    });
  });

  group('LogSummaryChipSpec', () {
    test('默认色 == _StatusChip 默认值', () {
      const spec = LogSummaryChipSpec(label: 'x');
      expect(
          spec.backgroundColor.toARGB32(), const Color(0xFFF3F4F6).toARGB32());
      expect(spec.textColor.toARGB32(), const Color(0xFF4B5563).toARGB32());
    });

    test('值相等性（label + 两色）', () {
      const a = LogSummaryChipSpec(label: 'x');
      const b = LogSummaryChipSpec(label: 'x');
      const c = LogSummaryChipSpec(label: 'y');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('LogStatusTagSpec', () {
    test('值相等性（label + 背景色 + tooltip，按 toARGB32 比较）', () {
      final a = LogStatusTagSpec(
        label: '已合并',
        backgroundColor: Colors.grey.shade400,
        tooltip: 'tip',
      );
      final b = LogStatusTagSpec(
        label: '已合并',
        backgroundColor: Colors.grey.shade400,
        tooltip: 'tip',
      );
      const c = LogStatusTagSpec(
        label: '待合并',
        backgroundColor: Colors.green,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('label 不同 → 不等', () {
      final a = LogStatusTagSpec(
        label: '已合并',
        backgroundColor: Colors.grey.shade400,
      );
      final b = LogStatusTagSpec(
        label: '其它',
        backgroundColor: Colors.grey.shade400,
      );
      expect(a, isNot(equals(b)));
    });

    test('tooltip 不同 → 不等（Step 28 字段进入 == 矩阵）', () {
      final a = LogStatusTagSpec(
        label: '已合并',
        backgroundColor: Colors.grey.shade400,
        tooltip: 'A',
      );
      final b = LogStatusTagSpec(
        label: '已合并',
        backgroundColor: Colors.grey.shade400,
        tooltip: 'B',
      );
      final c = LogStatusTagSpec(
        label: '已合并',
        backgroundColor: Colors.grey.shade400,
      );
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
    });

    test('toString 包含 label / ARGB hex / tooltip（便于日志排查）', () {
      final spec = LogStatusTagSpec(
        label: '已合并',
        backgroundColor: Colors.grey.shade400,
        tooltip: 'hint',
      );
      expect(spec.toString(), contains('已合并'));
      expect(
        spec.toString(),
        contains(Colors.grey.shade400.toARGB32().toRadixString(16)),
      );
      expect(spec.toString(), contains('hint'));
    });
  });

  group('statusTagSpecsForLogEntry', () {
    test('都为 false → 空列表', () {
      expect(
        statusTagSpecsForLogEntry(isMerged: false, isPending: false),
        isEmpty,
      );
    });

    test('isMerged 单独 true → 仅[已合并]', () {
      final tags = statusTagSpecsForLogEntry(isMerged: true, isPending: false);
      expect(tags.length, 1);
      expect(tags[0].label, '已合并');
      expect(
        tags[0].backgroundColor.toARGB32(),
        Colors.grey.shade400.toARGB32(),
      );
    });

    test('isPending 单独 true → 仅[待合并]', () {
      final tags = statusTagSpecsForLogEntry(isMerged: false, isPending: true);
      expect(tags.length, 1);
      expect(tags[0].label, '待合并');
      expect(tags[0].backgroundColor.toARGB32(), Colors.green.toARGB32());
    });

    test('两 flag 同时 true → [已合并, 待合并]（独立维度，两个都渲染）', () {
      // 设计契约：'已合并 + pending 中再次出现' 是合法少见状态——同时显示两个 tag
      // 反而更利于用户察觉，不做"已合并就吃掉 pending tag"的偷换。
      final tags = statusTagSpecsForLogEntry(isMerged: true, isPending: true);
      expect(tags.length, 2);
      expect(tags[0].label, '已合并');
      expect(tags[1].label, '待合并');
    });

    test('顺序固定：已合并 → 待合并（与原 inline `if/if` 顺序一致）', () {
      // _LogEntryTile.build 原 inline 行 630-631 顺序就是 merged 先、pending 后。
      // 上层 spread 后按列表顺序追加 widget——顺序变更就是视觉变更，必须锁定。
      final tags = statusTagSpecsForLogEntry(isMerged: true, isPending: true);
      final labels = tags.map((s) => s.label).toList();
      expect(labels, ['已合并', '待合并']);
    });

    test('返回的列表是新实例（每次调用独立，不共享底层）', () {
      final a = statusTagSpecsForLogEntry(isMerged: true, isPending: false);
      final b = statusTagSpecsForLogEntry(isMerged: true, isPending: false);
      expect(identical(a, b), isFalse);
      expect(a, equals(b)); // 内容仍相等
    });

    test('配色字面量锁定（grey.shade400 / green）', () {
      // 即使 Material 内部表示变化，`toARGB32` 也按 RGBA 字节比较——这是与 widget 历史值
      // 的契约边界；色值漂移会被这条测试显眼抓到。
      final tags = statusTagSpecsForLogEntry(isMerged: true, isPending: true);
      expect(
        tags[0].backgroundColor.toARGB32(),
        Colors.grey.shade400.toARGB32(),
      );
      expect(tags[1].backgroundColor.toARGB32(), Colors.green.toARGB32());
    });

    test('Step 28：每个 tag 都带非空 tooltip 且与 helper 一致', () {
      final tags = statusTagSpecsForLogEntry(isMerged: true, isPending: true);
      // 已合并 → tooltipForMergedTag()
      expect(tags[0].tooltip, isNotNull);
      expect(tags[0].tooltip, tooltipForMergedTag());
      // 待合并 → tooltipForPendingTag()
      expect(tags[1].tooltip, isNotNull);
      expect(tags[1].tooltip, tooltipForPendingTag());
    });

    test('Step 28：两 helper 文案不同（语义正交，不互相 dedup）', () {
      // 已合并（mergeinfo 维度）vs 待合并（pending 队列维度）是两个独立语义维度，
      // tooltip 文案必须可区分——否则 hover 等价于无信息量的悬浮气泡。
      expect(tooltipForMergedTag(), isNot(equals(tooltipForPendingTag())));
    });
  });

  group('tooltipForMergedTag（Step 28）', () {
    test('返回非空文案', () {
      expect(tooltipForMergedTag(), isNotEmpty);
    });

    test('文案明确出现"已合并"与 mergeinfo 语义关键字', () {
      // 用户在 hover 时要立刻判断"这个'已合并'指的是哪种已合并"，doc-comment 说明是
      // mergeinfo 维度——单测把这个语义关键字锁死，避免文案漂移成"已存在"等近义词。
      final tip = tooltipForMergedTag();
      expect(tip, contains('已合并'));
      expect(tip, contains('mergeinfo'));
    });
  });

  group('tooltipForPendingTag（Step 28）', () {
    test('返回非空文案', () {
      expect(tooltipForPendingTag(), isNotEmpty);
    });

    test('文案明确出现"待合并"与"队列"关键字', () {
      // 与"待勾选"等近义词区分——单测锁定本 tooltip 是"已加入合并队列"语义，
      // 不是"用户尚未选择"语义。
      final tip = tooltipForPendingTag();
      expect(tip, contains('待合并'));
      expect(tip, contains('队列'));
    });
  });

  group('formatLogEntryDate', () {
    test('SVN 实际日期串 → 取前 19 字符（精确到秒）', () {
      expect(
        formatLogEntryDate('2024-01-01 10:00:00 +0800 (Mon, 01 Jan 2024)'),
        '2024-01-01 10:00:00',
      );
    });

    test('恰好 19 字符 → 整段返回（边界）', () {
      expect(formatLogEntryDate('2024-01-01 10:00:00'), '2024-01-01 10:00:00');
    });

    test('只有日期 → 整段返回（短于秒级格式）', () {
      expect(formatLogEntryDate('2024-01-01'), '2024-01-01');
    });

    test('短于 19 字符 → 整段返回，不抛 RangeError（降级 fallback）', () {
      // String.substring(0, 19) 在长度 < 19 时会抛 RangeError；本函数显眼地"原样返回"，
      // 让上游格式异常作为可见信号出现而非崩溃整列表。
      expect(formatLogEntryDate('2024'), '2024');
      expect(formatLogEntryDate('x'), 'x');
    });

    test('空字符串 → 空字符串', () {
      expect(formatLogEntryDate(''), '');
    });

    test('不做 trim：前后空白保留进展示', () {
      // 前后空白是上游格式异常的信号，本函数不替上游"修正"——保留作为显眼缺陷。
      expect(formatLogEntryDate('   2024-01-0'), '   2024-01-0');
      expect(formatLogEntryDate('2024-01-01   '), '2024-01-01   ');
    });

    test('不做日期合法性校验：非 ISO 长串照样截前 19', () {
      // 职责单一——只裁切，"是不是合法日期"由上游 SVN 客户端保证。
      expect(formatLogEntryDate('XX-YY-ZZabc...extra-tail'),
          'XX-YY-ZZabc...extra');
    });

    test('多字节字符按 Dart String 的 UTF-16 code unit 计长', () {
      // Dart String.length / substring 是按 UTF-16 code unit；中文字符占 1 code unit。
      // 这条测试锁定行为，避免日后用 runes 改写时静默漂移。
      expect(formatLogEntryDate('中文中文中文中文中文extra'), '中文中文中文中文中文extra');
      expect(formatLogEntryDate('中文中文中文中文中文extra-tail'), '中文中文中文中文中文extra');
    });
  });

  group('formatLogEntryMessageForList', () {
    LogEntry buildEntry(String message) => LogEntry(
          revision: 100,
          author: 'alice',
          date: '2026-05-30 10:00:00',
          title: message.split('\n').first,
          message: message,
        );

    test('单行 message 原样展示', () {
      expect(formatLogEntryMessageForList(buildEntry('修复登录闪退')), '修复登录闪退');
    });

    test('多行 message 仅在列表展示层把换行替换为空格', () {
      final entry = buildEntry('标题行\n\n正文第一行\n正文第二行');
      expect(
        formatLogEntryMessageForList(entry),
        '标题行 正文第一行 正文第二行',
      );
      expect(entry.message, '标题行\n\n正文第一行\n正文第二行');
    });

    test('CRLF message 展示时同样压成单个空格', () {
      expect(
        formatLogEntryMessageForList(buildEntry('title\r\nbody')),
        'title body',
      );
    });
  });

  group('isUsableChipLabel', () {
    // 真值表 4 角点
    test('null → false（chip 列表中不渲染该项——视觉上消失，不占布局）', () {
      // 关键：若 null 走 true 路径，会构造 `LogSummaryChipSpec(label: null!)`
      // 直接 NPE。本谓词的第一职责是阻止 NPE。
      expect(isUsableChipLabel(null), isFalse);
    });

    test('空串 → false（清空后的 preloadStatusText/boundaryText 不应渲染色块）', () {
      // 关键：若空串走 true 路径，UI 会出现一个**没有文字但仍占空间的色块**，
      // 破坏汇总条的视觉秩序——空串视作"未启用 chip"
      expect(isUsableChipLabel(''), isFalse);
    });

    test('单字符 → true（最小可用 label——锁定 isNotEmpty 而非 length > N）', () {
      expect(isUsableChipLabel('a'), isTrue);
    });

    test('正常 chip 文本 → true', () {
      expect(isUsableChipLabel('预加载中'), isTrue);
      expect(isUsableChipLabel('已到达边界'), isTrue);
    });

    // 反向断言：&& 不能误改成 ||
    test('null + 空 都 false 锁定 && 而非 ||（防 OR 误改让空串/null 变 true 触发 NPE）', () {
      // 如果谓词被误改成 `label == null || label.isNotEmpty`，
      // null 输入会走 OR 短路成 true，让 caller 走 `label!` 路径触发 NPE
      expect(isUsableChipLabel(null), isFalse);
      expect(isUsableChipLabel(''), isFalse);
    });

    // 不做 trim 边界锁定（与 R81 isUsableSqlStringFilter 一致）
    test('单空格 → true（不做 trim——caller 责任）', () {
      // 单空格虽然视觉退化为色块，但仍是有意义的"用户已传入"信号
      // 调用方负责 UI 层去白
      expect(isUsableChipLabel(' '), isTrue);
    });

    // 端到端 callsite 反向断言（R80/R81 模式延续）：与 chipSpecsForLogSummary 联动
    test('谓词 false 时 chipSpecsForLogSummary 不渲染 preload/boundary chip', () {
      // null + null：缓存 chip 始终在；preload/boundary chip 都不在
      final cNull = chipSpecsForLogSummary(
        cachedCount: 0,
        latestCachedRevision: null,
        earliestCachedRevision: null,
        branchPoint: null,
        preloadStatusText: null,
        boundaryText: null,
      );
      // 只有 1 个缓存 chip，没有 preload/boundary
      expect(cNull, hasLength(1));
      expect(cNull.map((s) => s.label), ['未缓存日志']);

      // 空串 + 空串
      final cEmpty = chipSpecsForLogSummary(
        cachedCount: 0,
        latestCachedRevision: null,
        earliestCachedRevision: null,
        branchPoint: null,
        preloadStatusText: '',
        boundaryText: '',
      );
      expect(cEmpty, hasLength(1));
      expect(cEmpty.map((s) => s.label), ['未缓存日志']);

      // 谓词 true 时必渲染
      final cFull = chipSpecsForLogSummary(
        cachedCount: 0,
        latestCachedRevision: null,
        earliestCachedRevision: null,
        branchPoint: null,
        preloadStatusText: '预加载中',
        boundaryText: '已到达边界',
      );
      expect(cFull.map((s) => s.label), ['未缓存日志', '预加载中', '已到达边界']);
    });

    // #9 形似但语义不同——五谓词等价性反向断言矩阵
    // （R79 双谓词 → R80 三谓词 → R81 四谓词 → R83 五谓词）
    test(
        '与 SourceUrl / Credential / WorkingDirectory / SqlStringFilter 输出等价但语境不同',
        () {
      // 五者实现完全相同（`!= null && isNotEmpty`），但 callsite 语境分别是：
      // - isUsableChipLabel：是否值得在 UI chip 列表中渲染一项
      // - isUsableSourceUrl：是否值得调 refreshLogEntries
      // - isUsableSvnCredential：是否值得加到 svn CLI args 的 --username/--password
      // - isUsableWorkingDirectory：是否值得用作 SVN 缓存键
      // - isUsableSqlStringFilter：是否值得拼到 SQL WHERE 字符串过滤段
      //
      // 跨模块复用单一通名 helper 会让 callsite 失去语义自描述能力。
      // 本测试在 4 角点上同时调五者断言**输出等价**——证明实现等价但
      // **不能合并**。这是 R79-R83 累积 5 轮的"DRY 反例"证据：从双谓词
      // 起步，每轮加一个谓词，模式从"个例"升级为"项目惯例"。
      for (final input in <String?>[null, '', ' ', 'x']) {
        expect(
          isUsableChipLabel(input),
          isUsableSourceUrl(input),
          reason: 'input=$input: ChipLabel vs SourceUrl 输出应等价',
        );
        expect(
          isUsableChipLabel(input),
          isUsableSvnCredential(input),
          reason: 'input=$input: ChipLabel vs SvnCredential 输出应等价',
        );
        expect(
          isUsableChipLabel(input),
          isUsableWorkingDirectory(input),
          reason: 'input=$input: ChipLabel vs WorkingDirectory 输出应等价',
        );
        expect(
          isUsableChipLabel(input),
          isUsableSqlStringFilter(input),
          reason: 'input=$input: ChipLabel vs SqlStringFilter 输出应等价',
        );
      }
    });
  });

  group('LogSummaryChipSpec == / hashCode 对称性（R103）', () {
    const baseline = LogSummaryChipSpec(
      label: 'L',
      backgroundColor: Color(0xFFAA0000),
      textColor: Color(0xFF00BB00),
    );

    test('全字段相同 → 相等 + hashCode 一致', () {
      const a = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
        textColor: Color(0xFF00BB00),
      );
      expect(a, equals(baseline));
      expect(a.hashCode, baseline.hashCode);
    });

    test('任一字段不等 → != + Set 去重正确（3 字段对称性矩阵）', () {
      const diffLabel = LogSummaryChipSpec(
        label: 'L2',
        backgroundColor: Color(0xFFAA0000),
        textColor: Color(0xFF00BB00),
      );
      const diffBg = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFBB0000),
        textColor: Color(0xFF00BB00),
      );
      const diffFg = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
        textColor: Color(0xFF00CC00),
      );
      for (final v in [diffLabel, diffBg, diffFg]) {
        expect(v, isNot(equals(baseline)));
      }
      final s = <LogSummaryChipSpec>{baseline, diffLabel, diffBg, diffFg};
      expect(s.length, 4);
    });

    test('Color 字段使用 toARGB32() 比较——同 ARGB 不同实例视为相等', () {
      // 锁定"toARGB32 比较"契约：lib 用 toARGB32() 而非引用比较是有意的，
      // 防御未来误改成 `other.backgroundColor == backgroundColor`（在 Color 上是引用比较）
      const a = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAABBCC),
        textColor: Color(0xFFDDEEFF),
      );
      const b = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAABBCC),
        textColor: Color(0xFFDDEEFF),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('Step 27：tooltip 字段进入 == / hashCode 对称性矩阵', () {
      // 同 label/bg/fg、不同 tooltip → 不等
      const noTip = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
        textColor: Color(0xFF00BB00),
      );
      const withTipA = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
        textColor: Color(0xFF00BB00),
        tooltip: 'tip A',
      );
      const withTipB = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
        textColor: Color(0xFF00BB00),
        tooltip: 'tip B',
      );
      expect(noTip, isNot(equals(withTipA)));
      expect(withTipA, isNot(equals(withTipB)));

      // tooltip 都是 null → 仍相等（默认值兼容）
      const sameNull = LogSummaryChipSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
        textColor: Color(0xFF00BB00),
      );
      expect(noTip, equals(sameNull));
      expect(noTip.hashCode, sameNull.hashCode);

      // 4 个变体放进 Set 应去重为 3（noTip == sameNull）
      // 使用 List 构造避免 set literal 触发 equal_elements_in_set 静态检查
      final s = <LogSummaryChipSpec>{
        ...[noTip, sameNull, withTipA, withTipB],
      };
      expect(s.length, 3);
    });
  });

  group('LogStatusTagSpec == / hashCode 对称性（R103 + Step 28）', () {
    const baseline = LogStatusTagSpec(
      label: 'L',
      backgroundColor: Color(0xFFAA0000),
    );

    test('全字段相同 → 相等 + hashCode 一致', () {
      const a = LogStatusTagSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
      );
      expect(a, equals(baseline));
      expect(a.hashCode, baseline.hashCode);
    });

    test('任一字段不等 → != + Set 去重正确（3 字段对称性矩阵：label / bg / tooltip）', () {
      const diffLabel = LogStatusTagSpec(
        label: 'L2',
        backgroundColor: Color(0xFFAA0000),
      );
      const diffBg = LogStatusTagSpec(
        label: 'L',
        backgroundColor: Color(0xFFBB0000),
      );
      const diffTooltip = LogStatusTagSpec(
        label: 'L',
        backgroundColor: Color(0xFFAA0000),
        tooltip: 'tip',
      );
      for (final v in [diffLabel, diffBg, diffTooltip]) {
        expect(v, isNot(equals(baseline)));
      }
      // 4 个变体放进 Set 应去重为 4（互不相等）
      // 使用 List 构造避免 set literal 触发 equal_elements_in_set 静态检查
      final s = <LogStatusTagSpec>{
        ...[baseline, diffLabel, diffBg, diffTooltip],
      };
      expect(s.length, 4);
    });
  });

  group('formatLogEntryTitleTooltip（Step 19）', () {
    LogEntry buildEntry({required String message}) => LogEntry(
          revision: 100,
          author: 'alice',
          date: '2026-05-30',
          // title 是 message 第一行的派生量；测试里手工对齐 title 与 message.split('\n').first
          // 不影响 helper（helper 只看 message），但保持模型一致避免测试本身误导。
          title: message.split('\n').first,
          message: message,
        );

    test('多行 message → 返回完整 message（不 trim、不截断、不附加前缀）', () {
      final e =
          buildEntry(message: '修复登录闪退\n\n详情：在 onTap 里加了 mounted check\n并补了单测');
      expect(
        formatLogEntryTitleTooltip(e),
        '修复登录闪退\n\n详情：在 onTap 里加了 mounted check\n并补了单测',
      );
    });

    test('单行 message（无 \\n）→ 返回 \'\'（与 title 字面相等，列表已完整渲染，dedup）', () {
      final e = buildEntry(message: '修复登录闪退');
      expect(formatLogEntryTitleTooltip(e), '');
    });

    test('空 message 防御性 → \'\'（caller 不渲染 Tooltip）', () {
      final e = buildEntry(message: '');
      expect(formatLogEntryTitleTooltip(e), '');
    });

    test('仅一个换行 → 返回完整 message（含 trailing 换行后的空段也保留）', () {
      // 用户极端情况：message = "abc\n"——也算"多行"信号丢失
      // （title="abc"，第二行的""丢失），helper 仍返回完整原文
      final e = buildEntry(message: 'abc\n');
      expect(formatLogEntryTitleTooltip(e), 'abc\n');
    });

    test('多行 message 含末尾空白行 → 不 trim，原样返回', () {
      // 与 extractMessageFirstLine 不 trim 的契约同源：trim/不 trim 由调用方决定，
      // helper 只做"截断还原"单一职责
      final e = buildEntry(message: 'first line\nsecond line\n   ');
      expect(formatLogEntryTitleTooltip(e), 'first line\nsecond line\n   ');
    });

    test('CRLF 风格（\\r\\n）→ 因含 \\n 走多行分支', () {
      // helper 用 contains('\n') 判定，CRLF 也命中（\r 在前、\n 在后）
      final e = buildEntry(message: 'title line\r\nbody');
      expect(formatLogEntryTitleTooltip(e), 'title line\r\nbody');
    });
  });

  group('formatLogEntryDateTooltip（Step 20）', () {
    test('SVN 实际 timestamp（>19 字符）→ 返回完整 date 字符串（含时区+星期）', () {
      const date = '2024-01-15 10:30:45 +0800 (Mon, 15 Jan 2024)';
      expect(formatLogEntryDateTooltip(date), date);
    });

    test('短串（<19 字符）→ 空字符串（formatLogEntryDate 已原样渲染，dedup）', () {
      expect(formatLogEntryDateTooltip('2024'), '');
      expect(formatLogEntryDateTooltip('x'), '');
      expect(formatLogEntryDateTooltip(''), '');
    });

    test('恰好 19 字符 → 空字符串（formatLogEntryDate 已完整渲染，dedup）', () {
      // 边界：长度 == 19 时 formatLogEntryDate 走 substring(0, 19) 分支但等价于原样
      expect(formatLogEntryDateTooltip('2024-01-01 10:30:45'), '');
    });

    test('长度 20 → 返回完整 date（最小截断量）', () {
      // 边界：长度 20 时 formatLogEntryDate 截掉了 1 个字符 → tooltip 必须显示完整
      expect(formatLogEntryDateTooltip('2024-01-01 10:30:45x'),
          '2024-01-01 10:30:45x');
    });

    test('不做 trim：前后空白原样保留进 tooltip', () {
      const date = '   2024-01-15 10:30:45 +0800';
      expect(formatLogEntryDateTooltip(date), date);
      const date2 = '2024-01-15 10:30:45 +0800   ';
      expect(formatLogEntryDateTooltip(date2), date2);
    });

    test('不做 ISO 校验：非 ISO 长串照样原样返回', () {
      const date = 'XX-YY-ZZabc...extra';
      expect(formatLogEntryDateTooltip(date), date);
    });

    test('多字节字符按 Dart String UTF-16 code unit 计长（与 formatLogEntryDate 同律）', () {
      // 中文每字符 1 code unit；长度 <= 19 → 不截 → tooltip ''
      expect(formatLogEntryDateTooltip('中文中文中文中文中文'), '');
      expect(formatLogEntryDateTooltip('中文中文中文中文中文extra'), '');
      // 超过 19 code units → 截 → tooltip 完整
      expect(
        formatLogEntryDateTooltip('中文中文中文中文中文extra-tail'),
        '中文中文中文中文中文extra-tail',
      );
    });
  });

  group('UI 自动化：重启后通过"同步最新"补 SVN 新日志', () {
    testWidgets('已有缓存区间时，点击同步最新后新增 revision 出现在日志列表', (tester) async {
      await tester.pumpWidget(const _RestartHeadSyncHarness());

      expect(find.text('r1000'), findsOneWidget);
      expect(find.text('cached boundary r1000'), findsOneWidget);
      expect(find.text('r1003'), findsNothing);
      expect(find.text('new svn commit r1003'), findsNothing);

      await tester.tap(find.text('同步最新'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();
      expect(find.text('r1003'), findsOneWidget);
      expect(find.text('r1002'), findsOneWidget);
      expect(find.text('r1001'), findsOneWidget);
      expect(find.text('new svn commit r1003'), findsOneWidget);

      // r1000 是缓存头部边界：同步时必须带回来用于区间连续合并，
      // 但 UI 列表中仍应只有一行，不应出现重复边界记录。
      expect(find.text('r1000'), findsOneWidget);
      expect(find.text('cached boundary r1000 refreshed'), findsOneWidget);
      expect(find.text('缓存 4003 条'), findsOneWidget);
    });
  });

  group('LogListPanel 停止预加载按钮', () {
    LogListPanel buildPanel({
      required bool canStopPreload,
      required VoidCallback onStopPreload,
    }) {
      return LogListPanel(
        entries: const [],
        selectedRevisions: const {},
        pendingRevisions: const {},
        mergedRevisions: const {},
        isLoading: false,
        authorController: TextEditingController(),
        titleController: TextEditingController(),
        messageController: TextEditingController(),
        stopOnCopy: false,
        onStopOnCopyChanged: (_) {},
        onApplyFilter: () {},
        onRefresh: () {},
        canSyncLatest: true,
        onSyncLatest: () {},
        canLoadMore: true,
        onLoadMore: () {},
        canStopPreload: canStopPreload,
        onStopPreload: onStopPreload,
        canExportCsv: false,
        onExportCsv: () {},
        cachedCount: 0,
        latestCachedRevision: null,
        earliestCachedRevision: null,
        branchPoint: null,
        preloadStatusText: null,
        boundaryText: null,
        currentPage: 1,
        totalPages: 1,
        hasMore: false,
        onPageChanged: (_) {},
        selectableEntryCount: 0,
        onSelectAllSelectable: () {},
        onClearSelection: () {},
        onSelectionChanged: (_, __) {},
      );
    }

    Finder findStopButton() => find.widgetWithText(OutlinedButton, '停止预加载');

    testWidgets('canStopPreload=false → 按钮 disabled，点击不触发回调', (tester) async {
      var called = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildPanel(
              canStopPreload: false,
              onStopPreload: () => called++,
            ),
          ),
        ),
      );

      final button = findStopButton();
      expect(button, findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(called, 0);
    });

    testWidgets('canStopPreload=true → 按钮 enabled，点击触发回调', (tester) async {
      var called = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: buildPanel(
              canStopPreload: true,
              onStopPreload: () => called++,
            ),
          ),
        ),
      );

      final button = findStopButton();
      expect(button, findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pump();
      expect(called, 1);
    });
  });

  group('过滤按钮 loading 状态指示器（doc-as-test）', () {
    // 用户场景：用户输入过滤条件点"过滤"，按钮 disabled 但**无任何视觉反馈**——
    // 当数据库扫描 + 过滤耗时较长时用户无法判断进度，可能反复点击。
    // 同面板"同步最新"按钮在 isLoading 时已展示 16x16 CircularProgressIndicator，
    // "过滤"按钮必须复用同款进度指示器消除体验断裂。
    final src =
        File('lib/screens/components/log_list_panel.dart').readAsStringSync();

    test('过滤按钮升级为 ElevatedButton.icon（不再是裸 ElevatedButton）', () {
      // 锁住 icon 入口必须存在
      final filterStart = src.indexOf('// 过滤按钮');
      expect(filterStart, greaterThan(0), reason: '过滤按钮注释锚点必须保留');
      final body = src.substring(filterStart, filterStart + 800);
      expect(
        body.contains('ElevatedButton.icon('),
        isTrue,
        reason: '过滤按钮必须升级为 ElevatedButton.icon 以承载 loading 进度图标',
      );
      expect(
        body.contains('ElevatedButton(\n                onPressed:'),
        isFalse,
        reason: '裸 ElevatedButton 路径必须被替换',
      );
    });

    test('isLoading 时图标走 CircularProgressIndicator(strokeWidth: 2)', () {
      final filterStart = src.indexOf('// 过滤按钮');
      final body = src.substring(filterStart, filterStart + 800);
      expect(
        body.contains('isLoading\n                    ? const SizedBox('),
        isTrue,
        reason: 'isLoading 三元判断必须存在',
      );
      expect(
        body.contains('child: CircularProgressIndicator(strokeWidth: 2),'),
        isTrue,
        reason: '复用与"同步最新"同款 CircularProgressIndicator(strokeWidth: 2)',
      );
      expect(
        body.contains('width: 16,\n                        height: 16,'),
        isTrue,
        reason: '复用同款 16x16 容器尺寸',
      );
    });

    test('非 loading 时图标走 Icons.filter_alt', () {
      final filterStart = src.indexOf('// 过滤按钮');
      final body = src.substring(filterStart, filterStart + 800);
      expect(
        body.contains(": const Icon(Icons.filter_alt, size: 16),"),
        isTrue,
        reason: '非 loading 时图标必须用 filter_alt 与"清空筛选"的 filter_alt_off 形成对照',
      );
    });

    test('label 文案保持"过滤"不变', () {
      final filterStart = src.indexOf('// 过滤按钮');
      final body = src.substring(filterStart, filterStart + 800);
      expect(
        body.contains("label: const Text('过滤'),"),
        isTrue,
        reason: '按钮文案保持"过滤"，不改成"过滤中..."等动态文案（避免按钮宽度抖动）',
      );
    });

    test('disabled 接线保持 isLoading ? null : onApplyFilter', () {
      final filterStart = src.indexOf('// 过滤按钮');
      final body = src.substring(filterStart, filterStart + 800);
      expect(
        body.contains('onPressed: isLoading ? null : onApplyFilter,'),
        isTrue,
        reason: 'disabled 三元接线不变，loading 期间禁止重复点击',
      );
    });
  });

  group('加载更多按钮 loading 状态指示器（doc-as-test，第四十轮）', () {
    // 用户场景：用户在日志列表点"加载更多"（触发 svn log 远程拉更旧 revision），
    // 慢网络下 0.5-2s 期间按钮 disabled 但 icon 始终是 Icons.unfold_more 不变，
    // 与同 panel 内"过滤"（第二十二轮已加 spinner）/ "同步最新"（已有 spinner）
    // 不对称——用户感知不到按钮在工作，反复点击或误以为按钮坏了。
    // 第四十轮把 icon 三元化为 isLoading ? CircularProgressIndicator(16x16,
    // strokeWidth: 2) : Icons.unfold_more，三按钮 spinner 同款规格对称闭合。
    final src =
        File('lib/screens/components/log_list_panel.dart').readAsStringSync();

    String loadMoreBlock() {
      final labelPos = src.indexOf("label: const Text('加载更多'),");
      expect(labelPos, greaterThan(0), reason: '加载更多 label 锚点必须存在');
      // 向上找最近的 OutlinedButton.icon( 起始位置
      final start = src.lastIndexOf('OutlinedButton.icon(', labelPos);
      expect(start, greaterThan(0),
          reason: '加载更多按钮 OutlinedButton.icon 起点必须存在');
      // 向下取到 label 行结束（含 trailing ),）
      return src.substring(start, labelPos + 60);
    }

    test('加载更多按钮 isLoading 时 icon 走 CircularProgressIndicator(strokeWidth: 2)',
        () {
      final body = loadMoreBlock();
      expect(
        body.contains('isLoading\n                    ? const SizedBox('),
        isTrue,
        reason: 'icon 三元化必须基于 isLoading 切换，与"过滤"/"同步最新"同款',
      );
      expect(
        body.contains('child: CircularProgressIndicator(strokeWidth: 2),'),
        isTrue,
        reason: '复用与"过滤"/"同步最新"同款 CircularProgressIndicator(strokeWidth: 2)',
      );
      expect(
        body.contains('width: 16,\n                        height: 16,'),
        isTrue,
        reason: '复用同款 16x16 容器尺寸（避免按钮高度跳动）',
      );
    });

    test('加载更多按钮非 loading 时 icon 仍走 Icons.unfold_more', () {
      final body = loadMoreBlock();
      expect(
        body.contains(': const Icon(Icons.unfold_more, size: 16),'),
        isTrue,
        reason: '非 loading 时图标必须保持 unfold_more（语义不变）',
      );
    });

    test('加载更多按钮 label 保持"加载更多"不变（避免宽度抖动）', () {
      final body = loadMoreBlock();
      expect(
        body.contains("label: const Text('加载更多'),"),
        isTrue,
        reason: '按钮文案不改成"加载中..."，避免 loading/idle 切换时按钮宽度跳动',
      );
    });

    test('加载更多按钮 disabled 接线保持 canLoadMore && !isLoading ? onLoadMore : null',
        () {
      final body = loadMoreBlock();
      expect(
        body.contains(
            'onPressed: canLoadMore && !isLoading ? onLoadMore : null,'),
        isTrue,
        reason: 'disabled 三元接线不变，loading 期间禁止重复点击',
      );
    });

    test('三按钮 spinner 同款 contract — 加载更多 / 过滤 / 同步最新 同步规格对称', () {
      // 三按钮均必须出现 16x16 SizedBox + CircularProgressIndicator(strokeWidth: 2)。
      // 加载更多：第四十轮新增；过滤：第二十二轮；同步最新：长期已有。
      final spinnerCount =
          'CircularProgressIndicator(strokeWidth: 2),'.allMatches(src).length;
      expect(
        spinnerCount >= 3,
        isTrue,
        reason: '三按钮（过滤 / 同步最新 / 加载更多）必须均出现同款 spinner，至少 3 处字面量',
      );
    });
  });
}
