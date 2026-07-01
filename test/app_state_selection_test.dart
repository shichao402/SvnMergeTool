import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:svn_auto_merge/models/log_entry.dart';
import 'package:svn_auto_merge/providers/app_state.dart';
import 'package:svn_auto_merge/screens/components/config_bar.dart';
import 'package:svn_auto_merge/screens/main_screen_v3.dart';
import 'package:svn_auto_merge/services/logger_service.dart';
import 'package:svn_auto_merge/services/mergeinfo_cache_service.dart';
import 'package:svn_auto_merge/services/storage_service.dart';
import 'package:svn_auto_merge/services/log_filter_service.dart'
    show LogFilter, isUsableWorkingDirectory;
import 'package:svn_auto_merge/services/working_copy_manager.dart';

class _NoopMergeInfoCacheService extends MergeInfoCacheService {
  _NoopMergeInfoCacheService() : super.forTesting();

  @override
  Future<void> init() async {}
}

class _RecordingMergeInfoCacheService extends MergeInfoCacheService {
  _RecordingMergeInfoCacheService() : super.forTesting();

  Set<int> nextRevisions = const <int>{};
  final List<String> refreshSourceUrls = [];
  final List<String> refreshTargetWcs = [];
  final Map<String, Set<int>> _memory = {};

  @override
  Future<Set<int>> getMergedRevisions(
    String sourceUrl,
    String targetWc, {
    bool forceRefresh = false,
    bool fullRefresh = false,
  }) async {
    refreshSourceUrls.add(sourceUrl);
    refreshTargetWcs.add(targetWc);
    final revisions = Set<int>.from(nextRevisions);
    _memory[buildMergeInfoCacheKey(sourceUrl, targetWc)] = revisions;
    return revisions;
  }

  @override
  bool isRevisionMergedSync(String sourceUrl, String targetWc, int revision) {
    return _memory[buildMergeInfoCacheKey(sourceUrl, targetWc)]
            ?.contains(revision) ??
        false;
  }

  @override
  Set<int> getMergedRevisionsSync(String sourceUrl, String targetWc) {
    return _memory[buildMergeInfoCacheKey(sourceUrl, targetWc)] ??
        const <int>{};
  }
}

class _FakeStorageService extends StorageService {
  _FakeStorageService() : super.forTesting();

  List<String> sourceUrlHistory = [];
  List<String> switchBranchHistory = [];
  List<String> targetWcHistory = [];
  List<String> targetUrlHistory = [];
  String? lastSourceUrl;
  String? lastTargetWc;
  String? lastTargetUrl;
  bool useTemporarySparseWorkingCopy = false;

  Completer<void>? lastTargetUrlReadGate;
  Completer<void>? lastTargetUrlReadStarted;
  String? staleLastTargetUrl;

  @override
  Future<List<String>> getSourceUrlHistory() async => sourceUrlHistory;

  @override
  Future<void> addSourceUrlToHistory(String url) async {
    sourceUrlHistory = promoteToMruFront(sourceUrlHistory, url, maxLength: 20);
  }

  @override
  Future<List<String>> getSwitchBranchHistory() async => switchBranchHistory;

  @override
  Future<void> addSwitchBranchToHistory(String url) async {
    switchBranchHistory =
        promoteToMruFront(switchBranchHistory, url, maxLength: 20);
  }

  @override
  Future<List<String>> getTargetWcHistory() async => targetWcHistory;

  @override
  Future<void> addTargetWcToHistory(String wc) async {
    targetWcHistory = promoteToMruFront(targetWcHistory, wc, maxLength: 20);
  }

  @override
  Future<List<String>> getTargetUrlHistory() async => targetUrlHistory;

  @override
  Future<void> addTargetUrlToHistory(String url) async {
    targetUrlHistory = promoteToMruFront(targetUrlHistory, url, maxLength: 20);
  }

  @override
  Future<String?> getLastSourceUrl() async => lastSourceUrl;

  @override
  Future<void> saveLastSourceUrl(String url) async {
    lastSourceUrl = url;
  }

  @override
  Future<String?> getLastTargetWc() async => lastTargetWc;

  @override
  Future<void> saveLastTargetWc(String wc) async {
    lastTargetWc = wc;
  }

  @override
  Future<String?> getLastTargetUrl() async {
    final gate = lastTargetUrlReadGate;
    if (gate != null) {
      final started = lastTargetUrlReadStarted;
      if (started != null && !started.isCompleted) {
        started.complete();
      }
      await gate.future;
      lastTargetUrlReadGate = null;
      return staleLastTargetUrl;
    }
    return lastTargetUrl;
  }

  @override
  Future<void> saveLastTargetUrl(String url) async {
    lastTargetUrl = url;
  }

  @override
  Future<bool> getUseTemporarySparseWorkingCopy() async =>
      useTemporarySparseWorkingCopy;

  @override
  Future<void> saveUseTemporarySparseWorkingCopy(bool value) async {
    useTemporarySparseWorkingCopy = value;
  }
}

void main() {
  setUpAll(() {
    logger.enabled = false;
  });

  group('target URL state separation', () {
    test('设置目标 URL 不改变源 URL 或 switch 分支历史', () async {
      final storage = _FakeStorageService();
      final state = AppState(
        storageService: storage,
        mergeInfoService: _NoopMergeInfoCacheService(),
      );

      await state.saveSourceUrlToHistory('svn://repo/branches/source');
      await state.saveTargetUrlToHistory('svn://repo/branches/target');

      expect(state.lastSourceUrl, 'svn://repo/branches/source');
      expect(state.lastTargetUrl, 'svn://repo/branches/target');
      expect(state.sourceUrlHistory, ['svn://repo/branches/source']);
      expect(state.targetUrlHistory, ['svn://repo/branches/target']);
      expect(state.switchBranchHistory, isEmpty);
    });

    test('设置源 URL 不改变目标 URL', () async {
      final storage = _FakeStorageService();
      final state = AppState(
        storageService: storage,
        mergeInfoService: _NoopMergeInfoCacheService(),
      );

      await state.saveTargetUrlToHistory('svn://repo/branches/target');
      await state.saveSourceUrlToHistory('svn://repo/branches/source');

      expect(state.lastSourceUrl, 'svn://repo/branches/source');
      expect(state.lastTargetUrl, 'svn://repo/branches/target');
      expect(state.targetUrlHistory, ['svn://repo/branches/target']);
    });

    testWidgets('第一次设置目标 URL 后 UI 立即显示目标 URL', (tester) async {
      final storage = _FakeStorageService();
      final state = AppState(
        storageService: storage,
        mergeInfoService: _NoopMergeInfoCacheService(),
      );
      await state.setUseTemporarySparseWorkingCopy(true);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer<AppState>(
                builder: (context, appState, _) => ConfigBar(
                  sourceUrl: appState.lastSourceUrl ?? '',
                  targetConfig: appState.targetConfig,
                  onSourceTap: () {},
                  onTargetTap: () {},
                  onSettingsTap: () {},
                  onTemporarySparseWorkingCopyChanged:
                      appState.setUseTemporarySparseWorkingCopy,
                ),
              ),
            ),
          ),
        ),
      );

      await state.saveTargetUrlToHistory('svn://repo/branches/target');
      await tester.pump();

      expect(find.text('branches/target'), findsOneWidget);
      expect(find.textContaining('目标 URL'), findsOneWidget);
    });

    test('preference 异步加载不会覆盖用户刚设置的目标 URL', () async {
      final storage = _FakeStorageService()
        ..targetUrlHistory = ['svn://repo/branches/old-history']
        ..staleLastTargetUrl = 'svn://repo/branches/old-target'
        ..lastTargetUrlReadGate = Completer<void>()
        ..lastTargetUrlReadStarted = Completer<void>();
      final state = AppState(
        storageService: storage,
        mergeInfoService: _NoopMergeInfoCacheService(),
      );

      final initFuture = state.init();
      await storage.lastTargetUrlReadStarted!.future;

      await state.saveTargetUrlToHistory('svn://repo/branches/new-target');
      storage.lastTargetUrlReadGate!.complete();
      await initFuture;

      expect(state.lastTargetUrl, 'svn://repo/branches/new-target');
      expect(state.targetUrlHistory.first, 'svn://repo/branches/new-target');
    });

    test('切换临时精简工作副本模式不会把目标 URL 写入源 URL', () async {
      final storage = _FakeStorageService();
      final state = AppState(
        storageService: storage,
        mergeInfoService: _NoopMergeInfoCacheService(),
      );

      await state.saveSourceUrlToHistory('svn://repo/branches/source');
      await state.saveTargetUrlToHistory('svn://repo/branches/target');
      await state.setUseTemporarySparseWorkingCopy(true);
      await state.setUseTemporarySparseWorkingCopy(false);

      expect(state.lastSourceUrl, 'svn://repo/branches/source');
      expect(state.sourceUrlHistory, ['svn://repo/branches/source']);
      expect(state.lastTargetUrl, 'svn://repo/branches/target');
      expect(storage.lastSourceUrl, 'svn://repo/branches/source');
    });
  });

  group('resolveMergeInfoSelection', () {
    test('prefers explicit source and target values', () {
      final selection = resolveMergeInfoSelection(
        currentSourceUrl: 'svn://old-source',
        currentTargetWc: '/tmp/old-wc',
        sourceUrl: '  svn://new-source  ',
        targetWc: '  /tmp/new-wc  ',
      );

      expect(selection, isNotNull);
      expect(selection!.sourceUrl, 'svn://new-source');
      expect(selection.targetWc, '/tmp/new-wc');
    });

    test('falls back to current selection when explicit values are absent', () {
      final selection = resolveMergeInfoSelection(
        currentSourceUrl: 'svn://source',
        currentTargetWc: '/tmp/wc',
      );

      expect(selection, isNotNull);
      expect(selection!.sourceUrl, 'svn://source');
      expect(selection.targetWc, '/tmp/wc');
    });

    test('returns null when source or target is missing', () {
      expect(
        resolveMergeInfoSelection(
          currentSourceUrl: 'svn://source',
          currentTargetWc: null,
        ),
        isNull,
      );
      expect(
        resolveMergeInfoSelection(
          currentSourceUrl: null,
          currentTargetWc: '/tmp/wc',
        ),
        isNull,
      );
    });
  });

  group('temporary target mergeinfo flow', () {
    LogEntry entry(int revision) => LogEntry(
          revision: revision,
          author: 'tester',
          date: '2026-06-30',
          title: 'r$revision',
          message: '',
        );

    test('临时目标 SVN URL 作为 mergeinfo key 加载并驱动 log 已合并标记', () async {
      const sourceUrl = 'svn://repo/branches/source';
      const targetUrl = 'svn://repo/branches/target';
      final mergeInfo = _RecordingMergeInfoCacheService()
        ..nextRevisions = {101, 103};
      final state = AppState(
        storageService: _FakeStorageService(),
        mergeInfoService: mergeInfo,
      );

      await state.loadMergeInfo(
        sourceUrl: sourceUrl,
        targetWc: targetUrl,
        forceRefresh: true,
      );

      expect(mergeInfo.refreshSourceUrls, [sourceUrl]);
      expect(mergeInfo.refreshTargetWcs, [targetUrl]);
      expect(
        state.getMergedRevisionsSync(
          sourceUrl: sourceUrl,
          targetWc: targetUrl,
        ),
        {101, 103},
      );

      final merged = computeMergedRevisions(
        entries: [entry(100), entry(101), entry(102), entry(103)],
        isMerged: (revision) => state.isRevisionMergedSync(
          revision,
          sourceUrl: sourceUrl,
          targetWc: targetUrl,
        ),
      );

      expect(merged, {101, 103});
    });
  });

  group('pending source helpers', () {
    test('hasPendingSourceMismatch only flags non-empty mismatched source', () {
      expect(
        hasPendingSourceMismatch(
          pendingRevisions: const [1001],
          currentSourceUrl: 'svn://repo/branches/release',
          pendingSourceUrl: 'svn://repo/branches/release',
        ),
        isFalse,
      );

      expect(
        hasPendingSourceMismatch(
          pendingRevisions: const [1001],
          currentSourceUrl: 'svn://repo/branches/release',
          pendingSourceUrl: 'svn://repo/trunk',
        ),
        isTrue,
      );

      expect(
        hasPendingSourceMismatch(
          pendingRevisions: const [],
          currentSourceUrl: 'svn://repo/branches/release',
          pendingSourceUrl: 'svn://repo/trunk',
        ),
        isFalse,
      );
    });

    test('summarizeSourceUrl keeps the trailing branch segments', () {
      expect(
        summarizeSourceUrl(
          'https://svn.example.com/repos/app/branches/release',
        ),
        'branches/release',
      );
      expect(summarizeSourceUrl('trunk'), 'trunk');
    });

    test('summarizeSourceUrl trims whitespace inside each segment', () {
      // Round 15 修：尾随空白不再保留到 UI 文案。
      expect(
        summarizeSourceUrl('svn://example.com/proj/branches/v2  '),
        'branches/v2',
      );
      expect(
        summarizeSourceUrl('  svn://example.com/proj/branches/v2  '),
        'branches/v2',
      );
      // 段内空白：单独的 segment 被 trim
      expect(
        summarizeSourceUrl('svn://example.com/proj/branches/  v2'),
        'branches/v2',
      );
      // Tab 也算空白
      expect(
        summarizeSourceUrl('svn://example.com/proj/branches/\tv2\t'),
        'branches/v2',
      );
    });

    test('summarizeSourceUrl 全空白段算空段（不会出现 "branches/" 这种残段）', () {
      // segments = ['svn:', 'example.com', 'proj', 'branches', 'v2'] 之后
      // 中间夹一个 '   ' 段会被 trim 成 '' 然后过滤掉。
      expect(
        summarizeSourceUrl('svn://example.com/proj/branches/   /v2'),
        'branches/v2',
      );
    });

    test('summarizeSourceUrl 单段输入做 trim（length<2 fallback 已存在）', () {
      expect(summarizeSourceUrl('  trunk  '), 'trunk');
    });

    test(
        'shouldClearSelectedRevisionsOnSourceChange only clears when source really changes',
        () {
      expect(
        shouldClearSelectedRevisionsOnSourceChange(
          selectedRevisions: const {1001, 1002},
          previousSourceUrl: 'svn://repo/branches/release',
          currentSourceUrl: 'svn://repo/branches/release',
        ),
        isFalse,
      );

      expect(
        shouldClearSelectedRevisionsOnSourceChange(
          selectedRevisions: const {1001, 1002},
          previousSourceUrl: 'svn://repo/branches/release',
          currentSourceUrl: 'svn://repo/trunk',
        ),
        isTrue,
      );

      expect(
        shouldClearSelectedRevisionsOnSourceChange(
          selectedRevisions: const <int>{},
          previousSourceUrl: 'svn://repo/branches/release',
          currentSourceUrl: 'svn://repo/trunk',
        ),
        isFalse,
      );
    });
  });

  group('buildPendingSourceWarning', () {
    test('returns null when there are no pending revisions', () {
      expect(
        buildPendingSourceWarning(
          pendingRevisions: const [],
          currentSourceUrl: 'svn://repo/branches/release',
          pendingSourceUrl: 'svn://repo/trunk',
        ),
        isNull,
      );
    });

    test('returns null when current and pending sources match', () {
      expect(
        buildPendingSourceWarning(
          pendingRevisions: const [1001],
          currentSourceUrl: 'svn://repo/branches/release',
          pendingSourceUrl: 'svn://repo/branches/release',
        ),
        isNull,
      );
    });

    test('returns null when pendingSourceUrl is null or blank', () {
      expect(
        buildPendingSourceWarning(
          pendingRevisions: const [1001],
          currentSourceUrl: 'svn://repo/branches/release',
          pendingSourceUrl: null,
        ),
        isNull,
      );
      expect(
        buildPendingSourceWarning(
          pendingRevisions: const [1001],
          currentSourceUrl: 'svn://repo/branches/release',
          pendingSourceUrl: '   ',
        ),
        isNull,
      );
    });

    test('returns null when currentSourceUrl is blank', () {
      // hasPendingSourceMismatch 已经会因为 currentSourceUrl 空而返回 false。
      expect(
        buildPendingSourceWarning(
          pendingRevisions: const [1001],
          currentSourceUrl: '',
          pendingSourceUrl: 'svn://repo/trunk',
        ),
        isNull,
      );
    });

    test('on mismatch returns formatted warning with summarized urls', () {
      final warning = buildPendingSourceWarning(
        pendingRevisions: const [1001],
        currentSourceUrl: 'https://svn.example.com/repos/app/branches/release',
        pendingSourceUrl: 'https://svn.example.com/repos/app/trunk',
      );

      expect(
        warning,
        '待合并列表来自 app/trunk，当前日志来自 branches/release',
      );
    });
  });

  group('describeLockOperation', () {
    test('returns fallback text when lockInfo is null', () {
      expect(describeLockOperation(null), '当前操作');
    });

    test('uses description when present', () {
      final lock = WcLockInfo(
        workingCopy: '/tmp/wc',
        operationType: WcOperationType.merge,
        startTime: DateTime(2024, 1, 1),
        description: '正在合并 r12345',
      );

      expect(describeLockOperation(lock), '正在合并 r12345');
    });

    test('falls back to operationType.label when description is null', () {
      final lock = WcLockInfo(
        workingCopy: '/tmp/wc',
        operationType: WcOperationType.cleanup,
        startTime: DateTime(2024, 1, 1),
      );

      expect(describeLockOperation(lock), '清理');
    });

    test('treats explicitly null description as null (not empty string)', () {
      final lock = WcLockInfo(
        workingCopy: '/tmp/wc',
        operationType: WcOperationType.update,
        startTime: DateTime(2024, 1, 1),
        description: null,
      );

      expect(describeLockOperation(lock), '更新');
    });
  });

  group('mergePendingRevisions', () {
    test('两个空 list → 空 list', () {
      expect(mergePendingRevisions(const [], const []), <int>[]);
    });

    test('existing 为空 → 返回 incoming 的升序去重副本', () {
      // 注意原实现是 add then sort()，所以即使 incoming 已升序也会重排
      expect(mergePendingRevisions(const [], const [3, 1, 2, 1]), [1, 2, 3]);
    });

    test('incoming 为空 → 返回 existing 的升序副本（不影响入参）', () {
      final existing = [5, 2, 8];
      final result = mergePendingRevisions(existing, const []);
      expect(result, [2, 5, 8]);
      // 入参未被修改
      expect(existing, [5, 2, 8]);
    });

    test('合并去重 + 升序', () {
      expect(
        mergePendingRevisions(const [1, 5, 9], const [3, 5, 7, 9]),
        [1, 3, 5, 7, 9],
      );
    });

    test('incoming 内部含重复也只算一次', () {
      expect(
        mergePendingRevisions(const [10], const [20, 20, 20, 5, 5]),
        [5, 10, 20],
      );
    });

    test('existing 自身已有重复时也被去掉（防御性）', () {
      expect(
        mergePendingRevisions(const [3, 3, 1, 1, 2], const []),
        [1, 2, 3],
      );
    });

    test('结果是新 list，对其修改不影响后续调用', () {
      final existing = [1, 2];
      final r1 = mergePendingRevisions(existing, const [3]);
      r1.add(99);
      final r2 = mergePendingRevisions(existing, const [3]);
      expect(r2, [1, 2, 3]); // 不被 r1.add 影响
    });
  });

  group('removeRevisionsFromPending', () {
    test('toRemove 为空 → 返回 existing 的浅拷贝（不是同一引用）', () {
      final existing = [1, 2, 3];
      final result = removeRevisionsFromPending(existing, const []);
      expect(result, [1, 2, 3]);
      expect(identical(result, existing), isFalse);
    });

    test('existing 为空 → 空 list', () {
      expect(removeRevisionsFromPending(const [], const [1, 2]), <int>[]);
    });

    test('保留未被移除项的原顺序（不排序）', () {
      // 原实现用 removeWhere，不会重新排序
      expect(
        removeRevisionsFromPending(const [9, 2, 7, 4, 1], const [2, 4]),
        [9, 7, 1],
      );
    });

    test('toRemove 内含 existing 没有的值不影响结果', () {
      expect(
        removeRevisionsFromPending(const [1, 2, 3], const [2, 99, 100]),
        [1, 3],
      );
    });

    test('全部被移除 → 空 list', () {
      expect(
        removeRevisionsFromPending(const [1, 2, 3], const [3, 1, 2]),
        <int>[],
      );
    });

    test('existing 含重复时全部该值都被移除', () {
      expect(
        removeRevisionsFromPending(const [1, 2, 1, 3, 1], const [1]),
        [2, 3],
      );
    });

    test('入参未被修改', () {
      final existing = [1, 2, 3];
      final toRemove = [2];
      removeRevisionsFromPending(existing, toRemove);
      expect(existing, [1, 2, 3]);
      expect(toRemove, [2]);
    });
  });

  group('clampPageIndex', () {
    test('负数夹到 0', () {
      expect(clampPageIndex(-1), 0);
      expect(clampPageIndex(-9999), 0);
    });

    test('0 与中段值原样返回', () {
      expect(clampPageIndex(0), 0);
      expect(clampPageIndex(42), 42);
    });

    test('恰好等于 maxPageIndex 不被夹', () {
      expect(clampPageIndex(maxPageIndex), maxPageIndex);
    });

    test('超过 maxPageIndex 被夹回 maxPageIndex', () {
      expect(clampPageIndex(maxPageIndex + 1), maxPageIndex);
      expect(clampPageIndex(1 << 30), maxPageIndex);
    });

    test('maxPageIndex 锁定为 999999（决策注释里固定的值）', () {
      // 任何把上限改成 int 最大值的"修复"都会让这条测试失败。
      expect(maxPageIndex, 999999);
    });
  });

  group('computeFallbackHasMore', () {
    test('totalPages = 0（还没数据）→ false（即使 currentPage 也是 0）', () {
      // 公式 0 < -1 = false，锁住空数据时不会错误报"有下一页"。
      expect(
        computeFallbackHasMore(currentPage: 0, totalPages: 0),
        isFalse,
      );
    });

    test('totalPages = 1, currentPage = 0 → false（唯一一页）', () {
      expect(
        computeFallbackHasMore(currentPage: 0, totalPages: 1),
        isFalse,
      );
    });

    test('最后一页 → false', () {
      expect(
        computeFallbackHasMore(currentPage: 4, totalPages: 5),
        isFalse,
      );
    });

    test('中间页 → true', () {
      expect(
        computeFallbackHasMore(currentPage: 3, totalPages: 5),
        isTrue,
      );
      expect(
        computeFallbackHasMore(currentPage: 0, totalPages: 5),
        isTrue,
      );
    });

    test('currentPage 超过末页（异常态）→ false', () {
      // 5 < 4 = false；不会因为 currentPage 越界返回 true。
      expect(
        computeFallbackHasMore(currentPage: 5, totalPages: 5),
        isFalse,
      );
    });
  });

  group('shouldUpdateCachedCountForSource', () {
    test('两侧 URL 一致 → true', () {
      expect(
        shouldUpdateCachedCountForSource(
          currentLastUrl: 'svn://repo/branches/release',
          incomingUrl: 'svn://repo/branches/release',
        ),
        isTrue,
      );
    });

    test('两侧 URL 不一致 → false（迟到的预加载结果应被忽略）', () {
      expect(
        shouldUpdateCachedCountForSource(
          currentLastUrl: 'svn://repo/branches/release',
          incomingUrl: 'svn://repo/trunk',
        ),
        isFalse,
      );
    });

    test('currentLastUrl 为 null（启动瞬态）→ true', () {
      // 应用刚启动还没选择源；回填总数应被允许。
      expect(
        shouldUpdateCachedCountForSource(
          currentLastUrl: null,
          incomingUrl: 'svn://repo/trunk',
        ),
        isTrue,
      );
    });

    test('两侧都是空字符串视为一致 → true', () {
      // 这是 == 字符串比较的自然行为；锁住"空串不会被特殊处理成不相等"。
      expect(
        shouldUpdateCachedCountForSource(
          currentLastUrl: '',
          incomingUrl: '',
        ),
        isTrue,
      );
    });
  });

  group('nextPageIndex', () {
    test('hasMore = true → currentPage + 1', () {
      expect(nextPageIndex(currentPage: 0, hasMore: true), 1);
      expect(nextPageIndex(currentPage: 7, hasMore: true), 8);
    });

    test('hasMore = false → null（不要推进 currentPage）', () {
      expect(nextPageIndex(currentPage: 0, hasMore: false), isNull);
      expect(nextPageIndex(currentPage: 99, hasMore: false), isNull);
    });
  });

  group('previousPageIndex', () {
    test('currentPage > 0 → currentPage - 1', () {
      expect(previousPageIndex(currentPage: 1), 0);
      expect(previousPageIndex(currentPage: 5), 4);
    });

    test('currentPage = 0 → null（已经在第一页）', () {
      expect(previousPageIndex(currentPage: 0), isNull);
    });

    test('currentPage 为负（异常态）→ null（不会返回 -2）', () {
      // 严格按 currentPage > 0 判定，避免负数往负方向滑。
      expect(previousPageIndex(currentPage: -1), isNull);
    });
  });

  group('formatRefreshLogEntriesHeaderLines', () {
    test('恒为 4 行，标题不带缩进，其余两空格缩进', () {
      final lines = formatRefreshLogEntriesHeaderLines(
        sourceUrl: 'svn://repo/branches/release',
        filter: const LogFilter(),
        page: 0,
        pageSize: 50,
      );

      expect(lines, hasLength(4));
      expect(lines[0], '【refreshLogEntries】开始从缓存读取日志');
      expect(lines[0].startsWith(' '), isFalse);
      for (final line in lines.sublist(1)) {
        expect(line.startsWith('  '), isTrue);
      }
    });

    test('字段顺序：sourceUrl → filter → page+pageSize', () {
      final lines = formatRefreshLogEntriesHeaderLines(
        sourceUrl: 'svn://repo/trunk',
        filter: const LogFilter(),
        page: 3,
        pageSize: 25,
      );

      expect(lines[1], '  sourceUrl: svn://repo/trunk');
      expect(lines[2], startsWith('  filter: '));
      expect(lines[3], '  page: 3, pageSize: 25');
    });

    test('filter 走 toString() 而不是 isEmpty 分支', () {
      // 锁住"任意 filter（包括空 filter）都用同一个 toString 渲染"。
      final lines = formatRefreshLogEntriesHeaderLines(
        sourceUrl: 'svn://repo/trunk',
        filter: const LogFilter(author: 'alice', title: 'fix'),
        page: 0,
        pageSize: 50,
      );

      expect(lines[2],
          '  filter: ${const LogFilter(author: 'alice', title: 'fix')}');
    });

    test('page+pageSize 同行，逗号空格分隔（与原 info 行格式一致）', () {
      final lines = formatRefreshLogEntriesHeaderLines(
        sourceUrl: 's',
        filter: const LogFilter(),
        page: 9,
        pageSize: 100,
      );

      expect(lines[3], '  page: 9, pageSize: 100');
    });
  });

  group('isUsableSourceUrl', () {
    // 真值表 4 角点
    test('null → false（未提供源 URL）', () {
      expect(isUsableSourceUrl(null), isFalse);
    });

    test('空字符串 → false（清空后的占位）', () {
      expect(isUsableSourceUrl(''), isFalse);
    });

    test('单字符 → true（最小可用值——锁定 isNotEmpty 而非 length > N）', () {
      // 边界：曾经的 `length > 1` 等过度防御会让这条红
      expect(isUsableSourceUrl('a'), isTrue);
    });

    test('正常 SVN URL → true', () {
      expect(
        isUsableSourceUrl('https://svn.example.com/repo/branches/feature-x'),
        isTrue,
      );
    });

    // #15 反向断言锁契约边界：仅 null 与空两条线，不做 trim/whitespace 校验
    test('单空格 → true（不做 trim——caller 责任）', () {
      // 这是有意为之：app_state setter 在 UI 路径上每秒可能触发多次（拖滑动条、
      // 输入框回调），不希望本谓词内部多做 trim 拷贝。如果未来需要 trim，
      // 应在 caller 写入 sourceUrl 之前做（saveSourceUrlToHistory 已实现 trim）。
      expect(isUsableSourceUrl(' '), isTrue);
    });

    test('换行/制表符 → true（同样不做 whitespace 归一化）', () {
      expect(isUsableSourceUrl('\n'), isTrue);
      expect(isUsableSourceUrl('\t'), isTrue);
    });

    // #9 形似但语义不同：与 isUsableWorkingDirectory 对照
    test('与 isUsableWorkingDirectory 形似但语义独立', () {
      // 两者都是 `String? -> bool`，且实现都是 `!= null && isNotEmpty`，
      // 但用途完全不同——本谓词是"是否值得调 refreshLogEntries"，
      // 后者是"是否值得用作 SVN 缓存键"。
      // 单测显式锁定本谓词的输入是 sourceUrl 语境，禁止合并到通名 helper。
      // 同时验证两个谓词在所有角点上输出一致（行为相同但语义不同）：
      expect(isUsableSourceUrl(null), isUsableWorkingDirectory(null));
      expect(isUsableSourceUrl(''), isUsableWorkingDirectory(''));
      expect(isUsableSourceUrl('x'), isUsableWorkingDirectory('x'));
    });

    // 反向：&& 不能误改成 ||
    test('null + 空 都 false 锁定 && 而非 ||（防 OR 误改）', () {
      // 如果谓词被误改成 `sourceUrl == null || sourceUrl.isNotEmpty`，
      // null 输入会走 true 路径（OR 短路）——这条会红
      expect(isUsableSourceUrl(null), isFalse);
      // 进一步：null 在 OR 误写下会变 true，本测试相当于
      // "null 时若返回 true 则 break"
    });

    // R88 漏迁巡检：main_screen_v3.dart:690 的 `_initializeFields` 曾内联
    // `appState.lastSourceUrl != null && appState.lastSourceUrl!.isNotEmpty`，
    // R88 替换为 `isUsableSourceUrl(appState.lastSourceUrl)`。本测以"曾经的
    // inline 入参形态"喂给谓词，验证两种表达式在所有角点上输出等价——
    // 这是 R85→R86→R88 漏迁等价测试模式的延续。
    test('R88 迁移：main_screen_v3._initializeFields inline 等价于本谓词', () {
      // 模拟 appState.lastSourceUrl 的所有可能形态
      final candidates = <String?>[
        null,
        '',
        'a',
        ' ',
        '\n',
        'https://svn.example.com/repo',
      ];
      for (final lastSourceUrl in candidates) {
        // ignore: unnecessary_null_comparison
        final inlineForm = lastSourceUrl != null && lastSourceUrl.isNotEmpty;
        expect(
          isUsableSourceUrl(lastSourceUrl),
          inlineForm,
          reason: 'lastSourceUrl=$lastSourceUrl 时两种表达式应等价',
        );
      }
    });
  });
}
