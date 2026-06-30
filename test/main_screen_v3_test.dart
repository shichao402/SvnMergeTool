import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/log_entry.dart';
import 'package:svn_auto_merge/models/merge_config.dart';
import 'package:svn_auto_merge/models/merge_job.dart';
import 'package:svn_auto_merge/screens/main_screen_v3.dart';
import 'package:svn_auto_merge/services/preload_service.dart';
import 'package:svn_auto_merge/services/working_copy_manager.dart';

MergeJob _job(int id) => MergeJob(
      jobId: id,
      sourceUrl: 'svn://example/source',
      targetWc: '/tmp/wc',
      maxRetries: 3,
      revisions: const [],
    );

LogEntry _entry(int revision) => LogEntry(
      revision: revision,
      author: 'tester',
      date: '2026-05-27',
      title: 'r$revision',
      message: '',
    );

void main() {
  group('SVN switch helper', () {
    test('deriveDefaultBranchesUrl keeps branches root for branch URL', () {
      expect(
        deriveDefaultBranchesUrl('svn://host/repo/branches/feature-a'),
        'svn://host/repo/branches',
      );
    });

    test('deriveDefaultBranchesUrl maps trunk/tags to sibling branches', () {
      expect(
        deriveDefaultBranchesUrl('svn://host/repo/trunk'),
        'svn://host/repo/branches',
      );
      expect(
        deriveDefaultBranchesUrl('svn://host/repo/tags/v1.0.0'),
        'svn://host/repo/branches',
      );
    });

    test('buildSwitchBranchHistory dedupes and keeps priority order', () {
      expect(
        buildSwitchBranchHistory(
          currentTargetUrl: 'svn://host/repo/branches/target',
          currentSourceUrl: 'svn://host/repo/branches/source',
          switchBranchHistory: const [
            'svn://host/repo/branches/switched',
          ],
          sourceUrlHistory: const [
            'svn://host/repo/branches/source',
            ' svn://host/repo/branches/history ',
          ],
          configuredSourceUrls: const [
            'svn://host/repo/branches/configured',
          ],
        ),
        [
          'svn://host/repo/branches/target',
          'svn://host/repo/branches/source',
          'svn://host/repo/branches/switched',
          'svn://host/repo/branches/history',
          'svn://host/repo/branches/configured',
        ],
      );
    });

    test('resolveInitialTargetUrl 优先使用 lastTargetUrl 并清理 URL 空白', () {
      expect(
        resolveInitialTargetUrl(
          lastTargetUrl: ' svn://host/repo/branches/target\n',
          targetUrlHistory: const ['svn://host/repo/branches/history'],
        ),
        'svn://host/repo/branches/target',
      );
    });

    test('resolveInitialTargetUrl fallback 到 targetUrlHistory，不读取 switch 历史',
        () {
      expect(
        resolveInitialTargetUrl(
          lastTargetUrl: null,
          targetUrlHistory: const [
            '  ',
            'svn://host/repo/branches/target-history',
          ],
        ),
        'svn://host/repo/branches/target-history',
      );
      expect(
        resolveInitialTargetUrl(
          lastTargetUrl: null,
          targetUrlHistory: const [],
        ),
        '',
      );
    });
  });

  group('buildSourceMessagesByRevision', () {
    test('uses original multiline LogEntry.message without list formatting',
        () {
      const entries = [
        LogEntry(
          revision: 101,
          author: 'alice',
          date: '2026-06-30',
          title: '标题',
          message: '标题\n\n正文第一行\n  正文第二行',
        ),
      ];

      expect(
        buildSourceMessagesByRevision(entries),
        {'101': '标题\n\n正文第一行\n  正文第二行'},
      );
    });
  });

  group('Gongfeng CR helper', () {
    test('buildGfCrTitle uses current revision and source/target branch names',
        () {
      const job = MergeJob(
        jobId: 1,
        sourceUrl: 'svn://example/repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        targetUrl: 'svn://example/repo/branches/b2',
        maxRetries: 3,
        revisions: [7],
        completedIndex: 0,
      );

      expect(buildGfCrTitle(job), 'Merge r7: b1 -> b2');
    });

    test('buildGfCrDescription includes revision, URLs and working copy', () {
      const job = MergeJob(
        jobId: 2,
        sourceUrl: 'svn://example/repo/branches/b1',
        targetWc: '/Users/dev/work/b2',
        targetUrl: 'svn://example/repo/branches/b2',
        maxRetries: 3,
        revisions: [8],
        completedIndex: 0,
      );

      expect(
        buildGfCrDescription(job),
        'Revision: r8\n'
        'Source: svn://example/repo/branches/b1\n'
        'Target: svn://example/repo/branches/b2\n'
        'Working copy: /Users/dev/work/b2',
      );
    });

    test('resolveGfAuthLoginCommand opens macOS Terminal with gf auth login',
        () {
      final command = resolveGfAuthLoginCommand(
        platform: 'macos',
        workingDirectory: '/Users/dev/work/b1',
      );

      expect(command, isNotNull);
      expect(command!.executable, 'osascript');
      expect(command.args.join('\n'), contains('Terminal'));
      expect(command.args.join('\n'),
          contains("cd '/Users/dev/work/b1'; gf auth login"));
    });

    test('shellSingleQuote handles paths with single quote', () {
      expect(shellSingleQuote("/tmp/a'b"), "'/tmp/a'\"'\"'b'");
    });

    test(
        'buildCodeReviewCommitMessage builds full message with auto-filled crid',
        () {
      const job = MergeJob(
        jobId: 3,
        sourceUrl: 'svn://example/repo/trunk',
        targetWc: '/Users/dev/work/b1',
        maxRetries: 3,
        revisions: [5],
        completedIndex: 0,
        commitSupplement: '--crid=9 Merge r5: trunk -> b1',
      );

      expect(
        buildCodeReviewCommitMessage(job),
        '[Merge] r5 from svn://example/repo/trunk\n\n'
        '--crid=9 Merge r5: trunk -> b1',
      );
    });

    test(
        'buildCodeReviewCommitMessage falls back to supplement without revision',
        () {
      const job = MergeJob(
        jobId: 4,
        sourceUrl: 'svn://example/repo/trunk',
        targetWc: '/Users/dev/work/b1',
        maxRetries: 3,
        revisions: [],
        commitSupplement: '--crid=9 Merge r5: trunk -> b1',
      );

      expect(
        buildCodeReviewCommitMessage(job),
        '--crid=9 Merge r5: trunk -> b1',
      );
    });
  });

  group('formatWcLockedMessage', () {
    test('lockInfo == null → 使用兜底 "当前操作"', () {
      expect(formatWcLockedMessage(null), '工作副本正在执行当前操作，请稍后再试');
    });

    test('优先使用 description 字段', () {
      final lock = WcLockInfo(
        workingCopy: '/tmp/wc',
        operationType: WcOperationType.merge,
        startTime: DateTime(2026, 5, 27),
        description: '正在合并 r12345',
      );
      expect(formatWcLockedMessage(lock), '工作副本正在执行正在合并 r12345，请稍后再试');
    });

    test('description 缺省时回落到 operationType.label', () {
      final lock = WcLockInfo(
        workingCopy: '/tmp/wc',
        operationType: WcOperationType.cleanup,
        startTime: DateTime(2026, 5, 27),
      );
      expect(formatWcLockedMessage(lock), '工作副本正在执行清理，请稍后再试');
    });

    test('与 describeLockOperation 的拼接关系：模板永远为 "正在执行X，请稍后再试"', () {
      // 显式锁定模板形状——未来若改文案，单测会同步红
      final lock = WcLockInfo(
        workingCopy: '/tmp/wc',
        operationType: WcOperationType.update,
        startTime: DateTime(2026, 5, 27),
      );
      final msg = formatWcLockedMessage(lock);
      expect(msg.startsWith('工作副本正在执行'), isTrue);
      expect(msg.endsWith('，请稍后再试'), isTrue);
      expect(msg.contains(describeLockOperation(lock)), isTrue);
    });
  });

  group('findJobById', () {
    test('空列表 → null', () {
      expect(findJobById(const <MergeJob>[], 1), isNull);
    });

    test('找不到 → null', () {
      expect(findJobById([_job(1), _job(2)], 99), isNull);
    });

    test('命中 → 返回首个匹配项（按 identical 验证不是新建对象）', () {
      final j1 = _job(1);
      final j2 = _job(2);
      final j3 = _job(3);
      final result = findJobById([j1, j2, j3], 2);
      expect(identical(result, j2), isTrue);
    });

    test('jobId 重复时只返回首个匹配（防御性，模型不强制唯一）', () {
      final first = _job(7);
      final second = _job(7);
      final result = findJobById([first, second], 7);
      expect(identical(result, first), isTrue);
    });

    test('接受任意 Iterable<MergeJob>，不强求 List', () {
      final set = <MergeJob>{_job(10), _job(20)};
      final result = findJobById(set, 20);
      expect(result, isNotNull);
      expect(result!.jobId, 20);
    });
  });

  group('computeMergedRevisions', () {
    test('空 entries → 空 Set', () {
      final result = computeMergedRevisions(
        entries: const <LogEntry>[],
        isMerged: (_) => false,
      );
      expect(result, isEmpty);
    });

    test('全部已合并 → Set 包含所有 revision', () {
      final result = computeMergedRevisions(
        entries: [_entry(1), _entry(2), _entry(3)],
        isMerged: (_) => true,
      );
      expect(result, {1, 2, 3});
    });

    test('全部未合并 → 空 Set', () {
      final result = computeMergedRevisions(
        entries: [_entry(1), _entry(2), _entry(3)],
        isMerged: (_) => false,
      );
      expect(result, isEmpty);
    });

    test('部分合并：仅奇数已合并', () {
      final result = computeMergedRevisions(
        entries: [_entry(1), _entry(2), _entry(3), _entry(4)],
        isMerged: (rev) => rev.isOdd,
      );
      expect(result, {1, 3});
    });

    test('顺序与 entries 一致（LinkedHashSet）', () {
      // Set 顺序通常不保证；本函数的 result 是字面量 `<int>{}`，
      // 保证 LinkedHashSet 的插入顺序——上层用 toList 取序展示时不应错位。
      final result = computeMergedRevisions(
        entries: [_entry(7), _entry(2), _entry(5)],
        isMerged: (_) => true,
      );
      expect(result.toList(), [7, 2, 5]);
    });

    test('与 computeSelectableRevisions 在同一行可同时为真（"已合并"与"在 pending"是独立维度）', () {
      // 一个 revision 既可"已合并"又"在 pending"——两个 Set 各自独立标记，本函数不关心 pending。
      final entriesList = [_entry(10)];
      final merged = computeMergedRevisions(
        entries: entriesList,
        isMerged: (_) => true,
      );
      final selectable = computeSelectableRevisions(
        entries: entriesList,
        pendingRevisions: const [10],
        isMerged: (_) => true,
      );
      // 同一 revision 在 merged 出现，在 selectable 缺席（被 pending + isMerged 双重排除）。
      expect(merged.contains(10), isTrue);
      expect(selectable.contains(10), isFalse);
    });
  });

  group('computeSelectableRevisions', () {
    test('空 entries → 空 Set', () {
      final result = computeSelectableRevisions(
        entries: const <LogEntry>[],
        pendingRevisions: const [],
        isMerged: (_) => false,
      );
      expect(result, isEmpty);
    });

    test('既未 pending 也未 merged 的全部入选', () {
      final result = computeSelectableRevisions(
        entries: [_entry(1), _entry(2), _entry(3)],
        pendingRevisions: const [],
        isMerged: (_) => false,
      );
      expect(result, {1, 2, 3});
    });

    test('已在 pending 列表的被排除', () {
      final result = computeSelectableRevisions(
        entries: [_entry(1), _entry(2), _entry(3)],
        pendingRevisions: const [2],
        isMerged: (_) => false,
      );
      expect(result, {1, 3});
    });

    test('被合并过的被排除', () {
      final result = computeSelectableRevisions(
        entries: [_entry(1), _entry(2), _entry(3)],
        pendingRevisions: const [],
        isMerged: (rev) => rev == 1,
      );
      expect(result, {2, 3});
    });

    test('pending 与 merged 同时排除', () {
      final result = computeSelectableRevisions(
        entries: [_entry(1), _entry(2), _entry(3), _entry(4)],
        pendingRevisions: const [2],
        isMerged: (rev) => rev == 4,
      );
      expect(result, {1, 3});
    });

    test('全部都被排除 → 空 Set', () {
      final result = computeSelectableRevisions(
        entries: [_entry(1), _entry(2)],
        pendingRevisions: const [1],
        isMerged: (rev) => rev == 2,
      );
      expect(result, isEmpty);
    });

    test('返回 Set 保持插入顺序（LinkedHashSet 契约）', () {
      // 用乱序输入显式锁定遍历顺序与 entries 一致
      final result = computeSelectableRevisions(
        entries: [_entry(100), _entry(50), _entry(75)],
        pendingRevisions: const [],
        isMerged: (_) => false,
      );
      expect(result.toList(), [100, 50, 75]);
    });

    test('isMerged 谓词只针对未 pending 的 revision 调用？——契约不保证顺序', () {
      // 不锁定调用顺序，只验证最终结果正确（即谓词组合是 OR 排除关系）
      final calls = <int>[];
      computeSelectableRevisions(
        entries: [_entry(1), _entry(2), _entry(3)],
        pendingRevisions: const [2],
        isMerged: (rev) {
          calls.add(rev);
          return false;
        },
      );
      // pending=2 已被剔除，因此 isMerged 至少会对 1 和 3 调用
      expect(calls.contains(1), isTrue);
      expect(calls.contains(3), isTrue);
    });
  });

  group('buildPendingSourceLabel', () {
    test('null → null', () {
      expect(buildPendingSourceLabel(null), isNull);
    });

    test('空字符串 → null', () {
      expect(buildPendingSourceLabel(''), isNull);
    });

    test('全空白 trim 后为空 → null', () {
      expect(buildPendingSourceLabel('   '), isNull);
    });

    test('正常 URL → 截到尾两段', () {
      expect(
        buildPendingSourceLabel('svn://example.com/svn/project/branches/v1'),
        'branches/v1',
      );
    });

    test('单段 URL → 原样 trim 返回（summarizeSourceUrl 行为）', () {
      expect(buildPendingSourceLabel('trunk'), 'trunk');
    });

    test('前后空白：buildPendingSourceLabel 用 trim() 守门，summarizeSourceUrl 段内 trim',
        () {
      // 'svn://.../branches/v2  '（v2 后带空格）经过 summarizeSourceUrl 后，
      // 段内/尾随空白都会被 trim 掉，拼出干净的 'branches/v2'。
      // （历史现状曾保留段内空格，Round 15 已修复并把契约改成段内 trim。）
      expect(
        buildPendingSourceLabel('  svn://example.com/proj/branches/v2  '),
        'branches/v2',
      );
    });

    test('正常输入（无尾随空白）→ 干净的 "尾两段"', () {
      expect(
        buildPendingSourceLabel('svn://example.com/proj/branches/v2'),
        'branches/v2',
      );
    });
  });

  group('resolvePreloadStatusText', () {
    test('sourceUrl 与 preloadSourceUrl 一致 + 描述非空 → 透传描述', () {
      expect(
        resolvePreloadStatusText(
          sourceUrl: 'svn://example/branch-A',
          preloadSourceUrl: 'svn://example/branch-A',
          statusDescription: '正在加载第 3 页',
        ),
        '正在加载第 3 页',
      );
    });

    test('sourceUrl 与 preloadSourceUrl 不一致 → null（静默隐藏，不显示"另一个分支"提示）', () {
      // 切分支后的旧进度对当前界面已经无意义；显式提示反而是噪音。
      expect(
        resolvePreloadStatusText(
          sourceUrl: 'svn://example/branch-A',
          preloadSourceUrl: 'svn://example/branch-B',
          statusDescription: '正在加载第 3 页',
        ),
        isNull,
      );
    });

    test('一致但描述为 null → null（不渲染空行）', () {
      expect(
        resolvePreloadStatusText(
          sourceUrl: 'svn://example/branch-A',
          preloadSourceUrl: 'svn://example/branch-A',
          statusDescription: null,
        ),
        isNull,
      );
    });

    test('preloadSourceUrl 为 null → null（视为不一致）', () {
      // 预加载未启动时 preloadSourceUrl 通常为 null，按字符串等值判定 != sourceUrl → null。
      expect(
        resolvePreloadStatusText(
          sourceUrl: 'svn://example/branch-A',
          preloadSourceUrl: null,
          statusDescription: '占位',
        ),
        isNull,
      );
    });

    test('sourceUrl 与 preloadSourceUrl 都为空字符串 + 描述非空 → 透传描述（按字面等值判定）', () {
      // 边界——两端都空算一致；生产路径下两者都为空时预加载不会跑、描述会是 null，进入空分支。
      expect(
        resolvePreloadStatusText(
          sourceUrl: '',
          preloadSourceUrl: '',
          statusDescription: '占位',
        ),
        '占位',
      );
    });

    test('描述不做 trim / 占位 / 截断（caller 决定排版）', () {
      // 入参原样透传，连前后空白都保留——避免在多个调用点偷偷做不同的截断。
      expect(
        resolvePreloadStatusText(
          sourceUrl: 'x',
          preloadSourceUrl: 'x',
          statusDescription: '   带前后空白的描述   ',
        ),
        '   带前后空白的描述   ',
      );
    });

    test('一侧 trim 不一致也判不一致（caller 必须先 trim）', () {
      // 防止 caller 漏 trim 时静默拼接出错的进度——契约要求两侧字面相等。
      expect(
        resolvePreloadStatusText(
          sourceUrl: 'svn://x',
          preloadSourceUrl: '  svn://x  ',
          statusDescription: '占位',
        ),
        isNull,
      );
    });
  });

  group('buildLogBoundaryDescription', () {
    LogBoundaryDescription call({
      String sourceUrl = 'svn://example/src',
      String targetWc = '/tmp/wc',
      int cachedLogCount = 100,
      bool stopOnCopy = false,
      int? cachedBranchPoint,
      int? earliestCachedRevision,
      String? preloadSourceUrl,
      PreloadStatus preloadStatus = PreloadStatus.idle,
      PreloadStopReason? preloadStopReason,
      String? noMoreHistorySourceUrl,
    }) {
      return buildLogBoundaryDescription(
        sourceUrl: sourceUrl,
        targetWc: targetWc,
        cachedLogCount: cachedLogCount,
        stopOnCopy: stopOnCopy,
        cachedBranchPoint: cachedBranchPoint,
        earliestCachedRevision: earliestCachedRevision,
        preloadSourceUrl: preloadSourceUrl,
        preloadStatus: preloadStatus,
        preloadStopReason: preloadStopReason,
        noMoreHistorySourceUrl: noMoreHistorySourceUrl,
      );
    }

    test(
        'cachedLogCount == 0 → noCache，文案为 null，但 canLoadMore=true（caller 自己用 count>0 关按钮）',
        () {
      final result = call(cachedLogCount: 0);
      expect(result.reason, LogBoundaryReason.noCache);
      expect(result.text, isNull);
      // 单独锁住这个反直觉点：reason=noCache 时仍允许 canLoadMore=true。
      // 真实 UI 里 canLoadMore = cachedLogCount > 0 && boundary.canLoadMore，
      // 所以 noCache 这一支用什么值都不会"误开"按钮，统一交给 caller 处理。
      expect(result.canLoadMore, isTrue);
    });

    test('stopOnCopy 模式 + 最早缓存 ≤ 分支点 → reachedBranchPoint，canLoadMore=false',
        () {
      final result = call(
        stopOnCopy: true,
        cachedBranchPoint: 1000,
        earliestCachedRevision: 999,
      );
      expect(result.reason, LogBoundaryReason.reachedBranchPoint);
      expect(result.text, '已到分支点，不再向更旧版本扩展');
      expect(result.canLoadMore, isFalse);
    });

    test('stopOnCopy 模式 + 最早缓存 == 分支点 → 仍算 reachedBranchPoint（边界 ≤）', () {
      // 锁住"≤"边界，避免有人误改成"<"导致分支点那一刻还以为可以继续加载
      final result = call(
        stopOnCopy: true,
        cachedBranchPoint: 1000,
        earliestCachedRevision: 1000,
      );
      expect(result.reason, LogBoundaryReason.reachedBranchPoint);
      expect(result.canLoadMore, isFalse);
    });

    test(
        'stopOnCopy 模式 + 最早缓存 > 分支点 → canExtendToBranchPoint，文案带 r{branchPoint}',
        () {
      final result = call(
        stopOnCopy: true,
        cachedBranchPoint: 1000,
        earliestCachedRevision: 1500,
      );
      expect(result.reason, LogBoundaryReason.canExtendToBranchPoint);
      expect(result.text, '还可继续加载到分支点 r1000');
      expect(result.canLoadMore, isTrue);
    });

    test('stopOnCopy=true 但 targetWc 为空 → 跳过分支点判定，落到默认分支', () {
      final result = call(
        stopOnCopy: true,
        targetWc: '',
        cachedBranchPoint: 1000,
        earliestCachedRevision: 999,
      );
      expect(result.reason, LogBoundaryReason.canLoadMore);
    });

    test('stopOnCopy=true 但 cachedBranchPoint=null → 跳过分支点判定', () {
      final result = call(
        stopOnCopy: true,
        cachedBranchPoint: null,
        earliestCachedRevision: 999,
      );
      expect(result.reason, LogBoundaryReason.canLoadMore);
    });

    test('预加载完成且 sourceUrl 匹配 + stopReason=noMoreData → preloadExhausted', () {
      final result = call(
        sourceUrl: 'svn://example/src',
        preloadSourceUrl: 'svn://example/src',
        preloadStatus: PreloadStatus.completed,
        preloadStopReason: PreloadStopReason.noMoreData,
      );
      expect(result.reason, LogBoundaryReason.preloadExhausted);
      expect(result.text, '历史已全部加载');
      expect(result.canLoadMore, isFalse);
    });

    test('预加载 sourceUrl 不匹配 → 不算 preloadExhausted（落默认分支）', () {
      final result = call(
        sourceUrl: 'svn://example/src',
        preloadSourceUrl: 'svn://example/OTHER',
        preloadStatus: PreloadStatus.completed,
        preloadStopReason: PreloadStopReason.noMoreData,
      );
      expect(result.reason, LogBoundaryReason.canLoadMore);
    });

    test('预加载完成但 stopReason 不是 noMoreData（如 countLimit）→ 不算 preloadExhausted',
        () {
      final result = call(
        sourceUrl: 'svn://example/src',
        preloadSourceUrl: 'svn://example/src',
        preloadStatus: PreloadStatus.completed,
        preloadStopReason: PreloadStopReason.countLimit,
      );
      expect(result.reason, LogBoundaryReason.canLoadMore);
    });

    test('noMoreHistorySourceUrl 与当前 sourceUrl 匹配 → noMoreHistory', () {
      final result = call(
        sourceUrl: 'svn://example/src',
        noMoreHistorySourceUrl: 'svn://example/src',
      );
      expect(result.reason, LogBoundaryReason.noMoreHistory);
      expect(result.text, '历史已全部加载');
      expect(result.canLoadMore, isFalse);
    });

    test('noMoreHistorySourceUrl 与当前 sourceUrl 不匹配 → 不消费，落默认分支', () {
      final result = call(
        sourceUrl: 'svn://example/src',
        noMoreHistorySourceUrl: 'svn://example/OTHER',
      );
      expect(result.reason, LogBoundaryReason.canLoadMore);
    });

    test('默认分支 → canLoadMore，文案 "可继续向更旧 revision 扩展"', () {
      final result = call();
      expect(result.reason, LogBoundaryReason.canLoadMore);
      expect(result.text, '可继续向更旧 revision 扩展');
      expect(result.canLoadMore, isTrue);
    });

    test('优先级：分支点判定优先于预加载判定（同时满足时返回 reachedBranchPoint）', () {
      // 防回归：未来若有人不小心把分支判定移到 preload 之后，本测试会爆
      final result = call(
        sourceUrl: 'svn://example/src',
        stopOnCopy: true,
        cachedBranchPoint: 1000,
        earliestCachedRevision: 1000,
        preloadSourceUrl: 'svn://example/src',
        preloadStatus: PreloadStatus.completed,
        preloadStopReason: PreloadStopReason.noMoreData,
      );
      expect(result.reason, LogBoundaryReason.reachedBranchPoint);
    });

    test('canLoadMore 字段语义：仅 3 种 reason 返回 false', () {
      // 显式把 enum→canLoadMore 的映射锁住，防止未来加新 enum 值时漏判
      const cannotLoad = {
        LogBoundaryReason.reachedBranchPoint,
        LogBoundaryReason.preloadExhausted,
        LogBoundaryReason.noMoreHistory,
      };
      for (final reason in LogBoundaryReason.values) {
        final desc = LogBoundaryDescription(text: null, reason: reason);
        expect(
          desc.canLoadMore,
          !cannotLoad.contains(reason),
          reason: 'reason=$reason 的 canLoadMore 与契约不符',
        );
      }
    });
  });

  group('resolveOperationPhase', () {
    // 注：本组测试覆盖 #11 防漏配 enum 真值表 + #15 反向断言契约边界。
    // 若以后 isProcessing/hasPausedJob 之外再引入第三个 flag，整张真值表必须重画——
    // 否则下面 4 条 case 会被绕过。

    test('(false, false) → select（唯一进入选择阶段的组合）', () {
      expect(
        resolveOperationPhase(isProcessing: false, hasPausedJob: false),
        OperationPhase.select,
      );
    });

    test('(false, true) → execute（仅暂停 job 也算执行阶段）', () {
      expect(
        resolveOperationPhase(isProcessing: false, hasPausedJob: true),
        OperationPhase.execute,
      );
    });

    test('(true, false) → execute（执行器在跑）', () {
      expect(
        resolveOperationPhase(isProcessing: true, hasPausedJob: false),
        OperationPhase.execute,
      );
    });

    test('(true, true) → execute（两个 flag 同真也算 OR 命中）', () {
      expect(
        resolveOperationPhase(isProcessing: true, hasPausedJob: true),
        OperationPhase.execute,
      );
    });

    test('反向契约：select 仅在 (false, false) 出现——其他三种组合都必须返回 execute', () {
      // #15 反向断言契约边界：从 4 种组合里**反向枚举**所有非 select 的输入，
      // 防止以后改成 AND（&&）或单条件判定时静默放过——例如若有人误改成
      // `isProcessing && hasPausedJob`，那 (true, false)/(false, true) 会变 select，
      // 这条断言会立即红。
      final nonSelectCombos = <({bool isProcessing, bool hasPausedJob})>[
        (isProcessing: false, hasPausedJob: true),
        (isProcessing: true, hasPausedJob: false),
        (isProcessing: true, hasPausedJob: true),
      ];
      for (final c in nonSelectCombos) {
        expect(
          resolveOperationPhase(
            isProcessing: c.isProcessing,
            hasPausedJob: c.hasPausedJob,
          ),
          OperationPhase.execute,
          reason:
              '组合 (isProcessing=${c.isProcessing}, hasPausedJob=${c.hasPausedJob}) 必须返回 execute',
        );
      }
    });
  });

  group('shouldWarnBeforeEditingConfig', () {
    // 真值表与 resolveOperationPhase 完全同型（OR 合并）；唯一差别是返回 bool
    // 而非 enum，覆盖 4 个组合 + 一条反向断言。

    test('(false, false) → false（idle 直接进配置弹窗，无警告）', () {
      expect(
        shouldWarnBeforeEditingConfig(isProcessing: false, hasPausedJob: false),
        isFalse,
      );
    });

    test('(false, true) → true（仅 paused 也要警告——sourceUrl 改了不影响 paused job）', () {
      expect(
        shouldWarnBeforeEditingConfig(isProcessing: false, hasPausedJob: true),
        isTrue,
      );
    });

    test('(true, false) → true（执行中切配置必警告）', () {
      expect(
        shouldWarnBeforeEditingConfig(isProcessing: true, hasPausedJob: false),
        isTrue,
      );
    });

    test('(true, true) → true（两 flag 同真）', () {
      expect(
        shouldWarnBeforeEditingConfig(isProcessing: true, hasPausedJob: true),
        isTrue,
      );
    });

    test('反向契约：返回 false 仅在 (false, false)——其他三种必须返回 true', () {
      // 防御未来误改成 AND：若有人写成 `isProcessing && hasPausedJob`，
      // (true, false) / (false, true) 会变 false，这条断言会立即红。
      final mustWarnCombos = <({bool isProcessing, bool hasPausedJob})>[
        (isProcessing: false, hasPausedJob: true),
        (isProcessing: true, hasPausedJob: false),
        (isProcessing: true, hasPausedJob: true),
      ];
      for (final c in mustWarnCombos) {
        expect(
          shouldWarnBeforeEditingConfig(
            isProcessing: c.isProcessing,
            hasPausedJob: c.hasPausedJob,
          ),
          isTrue,
          reason:
              '组合 (isProcessing=${c.isProcessing}, hasPausedJob=${c.hasPausedJob}) 必须返回 true',
        );
      }
    });
  });

  group('validateMergeStartPreconditions', () {
    // 通用 fixture：所有字段都合法，5 条校验都不会触发
    String? validate({
      String sourceUrl = 'svn://host/branches/v1',
      String targetWc = '/local/wc',
      String targetUrl = 'svn://host/branches/target',
      bool useTemporarySparseWorkingCopy = false,
      Iterable<int> pendingRevisions = const [100],
      String? pendingSourceUrl = 'svn://host/branches/v1',
      bool isLocked = false,
    }) {
      return validateMergeStartPreconditions(
        sourceUrl: sourceUrl,
        targetConfig: useTemporarySparseWorkingCopy
            ? TargetConfig.sparseTemporary(targetUrl)
            : TargetConfig.fullWorkingCopy(targetWc),
        pendingRevisions: pendingRevisions,
        pendingSourceUrl: pendingSourceUrl,
        isLocked: isLocked,
      );
    }

    test('全部合法 → 返回 null（通过）', () {
      expect(validate(), isNull);
    });

    test('sourceUrl 为空 → "请填写源 URL 和目标工作副本"', () {
      expect(validate(sourceUrl: ''), '请填写源 URL 和目标工作副本');
    });

    test('targetWc 为空 → "请填写源 URL 和目标工作副本"', () {
      expect(validate(targetWc: ''), '请填写源 URL 和目标工作副本');
    });

    test('精简模式 targetWc 为空但 targetUrl 有值 → 通过', () {
      expect(
        validate(
          targetWc: '',
          targetUrl: 'svn://host/branches/target',
          useTemporarySparseWorkingCopy: true,
        ),
        isNull,
      );
    });

    test('精简模式 targetUrl 为空 → 提示填写目标 SVN URL，不误报目标工作副本', () {
      expect(
        validate(
          targetWc: '',
          targetUrl: '',
          useTemporarySparseWorkingCopy: true,
        ),
        '请填写源 URL 和目标 SVN URL',
      );
    });

    test('两者都空 → 同一文案', () {
      expect(
        validate(sourceUrl: '', targetWc: ''),
        '请填写源 URL 和目标工作副本',
      );
    });

    test('精简模式 sourceUrl 与 targetUrl 都空 → 使用目标 SVN URL 文案', () {
      expect(
        validate(
          sourceUrl: '',
          targetWc: '',
          targetUrl: '',
          useTemporarySparseWorkingCopy: true,
        ),
        '请填写源 URL 和目标 SVN URL',
      );
    });

    test('pendingRevisions 为空 → "待合并列表为空"', () {
      expect(validate(pendingRevisions: const []), '待合并列表为空');
    });

    test('源/目标合法 + pending 非空 + pendingSourceUrl 不一致 → mismatch 文案', () {
      expect(
        validate(
          sourceUrl: 'svn://host/branches/v1',
          pendingSourceUrl: 'svn://host/branches/v2',
        ),
        '当前源分支与待合并列表不一致，请先清空待合并列表',
      );
    });

    test('pendingSourceUrl == null + pending 非空 → 缺源信息', () {
      // pendingSourceUrl == null 时 hasPendingSourceMismatch 返回 false（不算 mismatch），
      // 但 effectiveSourceUrl = (null ?? sourceUrl).trim()，sourceUrl 合法时不会触发缺源信息——
      // 这里用 sourceUrl 全空白来精准触发"缺源信息"分支。
      expect(
        validate(
          sourceUrl: '   ',
          targetWc: '/wc',
          pendingSourceUrl: null,
        ),
        // sourceUrl 全空白时，trim 后为空 → 第一道校验"sourceUrl.isEmpty"是 false（' ' 非空），
        // 走到 effectiveSourceUrl = (null ?? '   ').trim() = '' → 触发缺源信息
        '待合并列表缺少源分支信息，请重新选择 revision',
      );
    });

    test('pendingSourceUrl 全空白 + sourceUrl 也空白 → 缺源信息', () {
      // 锁定 trim 行为——pendingSourceUrl='   ' 不算 null，走 ?? 不会回退到 sourceUrl，
      // 但 trim 后为空 → 触发缺源信息分支
      expect(
        validate(
          sourceUrl: 'svn://host/branches/v1',
          pendingSourceUrl: '   ',
          // pendingRevisions 非空 + currentSourceUrl != pendingSourceUrl(全空白) → mismatch 触发
        ),
        // 注意：实际触发的是 mismatch 而非缺源——因为 hasPendingSourceMismatch 是 trim 比较
        // 这条测试验证"trim 后空白 pendingSourceUrl 不会被静默当通过"
        anyOf(
          equals('当前源分支与待合并列表不一致，请先清空待合并列表'),
          equals('待合并列表缺少源分支信息，请重新选择 revision'),
        ),
      );
    });

    test('isLocked 单独触发 → "有暂停的任务需要处理"', () {
      expect(validate(isLocked: true), '有暂停的任务需要处理');
    });

    test('顺序敏感：sourceUrl 空 + isLocked=true → 先报"请填写"，不报锁', () {
      // 锁住校验顺序——空字段是更基础的错误，必须先报。
      // 如果有人改成 isLocked 优先，用户会先看到"有暂停的任务"再发现自己根本没填字段。
      expect(
        validate(sourceUrl: '', isLocked: true),
        '请填写源 URL 和目标工作副本',
      );
    });

    test('顺序敏感：pending 空 + mismatch → 先报"待合并列表为空"', () {
      // 锁住"先验空，再验一致性"——空列表本来就不可能 mismatch，但 hasPendingSourceMismatch
      // 内部对空列表返回 false，所以即便顺序反过来也不会爆错；
      // 这里更多是锁文案优先级——空列表是更直接的问题，应先告知。
      expect(
        validate(
          pendingRevisions: const [],
          pendingSourceUrl: 'svn://other/branch',
        ),
        '待合并列表为空',
      );
    });

    test('顺序敏感：mismatch + isLocked → 先报 mismatch', () {
      expect(
        validate(
          sourceUrl: 'svn://host/branches/v1',
          pendingSourceUrl: 'svn://host/branches/v2',
          isLocked: true,
        ),
        '当前源分支与待合并列表不一致，请先清空待合并列表',
      );
    });

    test('pendingRevisions 是 Set / Iterable 也能正常工作', () {
      // 锁住"接受 Iterable<int> 而非 List<int>"的契约——caller 传 Set 也安全
      expect(
        validateMergeStartPreconditions(
          sourceUrl: 'svn://host/branches/v1',
          targetConfig: const TargetConfig.fullWorkingCopy('/local/wc'),
          pendingRevisions: <int>{100, 101, 102},
          pendingSourceUrl: 'svn://host/branches/v1',
          isLocked: false,
        ),
        isNull,
      );
    });

    test('pendingSourceUrl 为 null + sourceUrl 合法 + pending 非空 → 通过', () {
      // 这是"刚刚清空过 pending 又重新选了 revision、_pendingSourceUrl 还没回填"的中间态。
      // 有源 URL 就该允许，不应误报缺源信息。
      // hasPendingSourceMismatch 在 pendingSourceUrl==null 时返回 false（无视为 mismatch），
      // effectiveSourceUrl = (null ?? sourceUrl).trim() = 'svn://...' 非空 → 通过
      expect(
        validate(pendingSourceUrl: null),
        isNull,
      );
    });
  });

  group('describeJobDeletionSuccess', () {
    test('pending → "已移出队列"语义文案', () {
      // 还没跑过的任务被取消排队，用户视角是"从队列里拿掉"
      expect(
        describeJobDeletionSuccess(jobId: 7, status: JobStatus.pending),
        '任务 #7 已移出队列',
      );
    });

    test('done → "记录已移除"语义文案', () {
      // 已完成的任务删除是清理记录，不影响 SVN 仓库
      expect(
        describeJobDeletionSuccess(jobId: 7, status: JobStatus.done),
        '任务 #7 记录已移除',
      );
    });

    test('failed → "记录已移除"（与 done 同文案）', () {
      expect(
        describeJobDeletionSuccess(jobId: 7, status: JobStatus.failed),
        '任务 #7 记录已移除',
      );
    });

    test('running → "记录已移除"（理论上 caller 不会到这里，但函数本身仍走 fallback）', () {
      // QueueMutationStatus.applied 在 running 任务上不会出现（mutation 会 blocked），
      // 但函数纯粹以 status 为准，给 running 也返回 fallback 文案以防 caller 契约变化。
      expect(
        describeJobDeletionSuccess(jobId: 7, status: JobStatus.running),
        '任务 #7 记录已移除',
      );
    });

    test('paused → "记录已移除"（同上，函数本身仍走 fallback）', () {
      expect(
        describeJobDeletionSuccess(jobId: 7, status: JobStatus.paused),
        '任务 #7 记录已移除',
      );
    });

    test('jobId 直接拼接，不做合法性校验（0 / 负数照常拼）', () {
      // 与 formatSkipButtonLabel 同款契约——caller 保证 jobId 合法
      expect(
        describeJobDeletionSuccess(jobId: 0, status: JobStatus.pending),
        '任务 #0 已移出队列',
      );
      expect(
        describeJobDeletionSuccess(jobId: -1, status: JobStatus.done),
        '任务 #-1 记录已移除',
      );
    });

    test('全部 JobStatus.values 真值表覆盖（防止新增 enum 时漏配）', () {
      // 与 shouldShowTerminateHint / executorStatusIsBusy 同款"防漏配"契约：
      // 未来若 JobStatus 新增第 6 态（如 cancelled），本测会因没断言新值而强制
      // 提醒补 case——避免新枚举被默默归到"记录已移除" fallback。
      final movedOut = JobStatus.values
          .where((s) =>
              describeJobDeletionSuccess(jobId: 1, status: s) == '任务 #1 已移出队列')
          .toSet();
      expect(movedOut, {JobStatus.pending});
      expect(
        JobStatus.values.length,
        5,
        reason: '当 JobStatus 新增枚举值时本测会红，强制 review describeJobDeletionSuccess',
      );
    });

    test('与 JobStatusExtension.displayName 前缀刻意不同（防误合并）', () {
      // displayName 是"状态名"（'等待'/'完成'/...），本函数渲染的是"操作结果文案"
      // ('已移出队列'/'记录已移除')；两者都按 status 分发，但语义不同——
      // displayName 是名词、本函数是动作结果短语，不应合并。
      // 通过断言"包含 # + jobId 这种动作文案标记，displayName 没有"做反向锁定。
      for (final s in JobStatus.values) {
        final result = describeJobDeletionSuccess(jobId: 42, status: s);
        expect(result.contains('#42'), isTrue,
            reason: '动作文案必含 jobId 标记，displayName 不会');
      }
      // displayName 不会带 jobId 标记（间接断言："抽出来的两个 helper 是不同函数"）
      for (final s in JobStatus.values) {
        expect(s.displayName.contains('#'), isFalse);
      }
    });
  });

  group('buildDeleteJobConfirmMessage', () {
    test('completedIndex == 0 → 仅警告"任务无法恢复"，不显示进度数字', () {
      expect(
        buildDeleteJobConfirmMessage(completedIndex: 0, totalRevisions: 5),
        '删除后任务将从队列移除，任务无法恢复。',
      );
    });

    test('completedIndex > 0 → 显示 X / Y 进度', () {
      expect(
        buildDeleteJobConfirmMessage(completedIndex: 50, totalRevisions: 100),
        '删除后任务将从队列移除，已合并 50 / 100 个 revision 不会回滚但任务无法恢复。',
      );
    });

    test('completedIndex == totalRevisions → 全完成态文案（理论上 done 状态被删）', () {
      expect(
        buildDeleteJobConfirmMessage(completedIndex: 3, totalRevisions: 3),
        '删除后任务将从队列移除，已合并 3 / 3 个 revision 不会回滚但任务无法恢复。',
      );
    });

    test('completedIndex 越界（超过 total）→ clamp 到 totalRevisions', () {
      // 与 clampedCompletedRevisionCount 同款边界保护
      expect(
        buildDeleteJobConfirmMessage(completedIndex: 99, totalRevisions: 3),
        '删除后任务将从队列移除，已合并 3 / 3 个 revision 不会回滚但任务无法恢复。',
      );
    });

    test('completedIndex 负数 → clamp 到 0，走"无进度"分支', () {
      expect(
        buildDeleteJobConfirmMessage(completedIndex: -1, totalRevisions: 5),
        '删除后任务将从队列移除，任务无法恢复。',
      );
    });

    test('totalRevisions == 0（边界）→ clamp 后走"无进度"分支', () {
      expect(
        buildDeleteJobConfirmMessage(completedIndex: 0, totalRevisions: 0),
        '删除后任务将从队列移除，任务无法恢复。',
      );
    });

    test('文案与 R13 终止任务句式同型（破坏性操作家族一致）', () {
      // R13 终止任务文案：'终止后任务将从队列移除，已合并的 revision 不会回滚但任务无法恢复'
      // 删除任务文案：'删除后任务将从队列移除，已合并 X / Y 个 revision 不会回滚但任务无法恢复'
      // 共同结构：[动词]后任务将从队列移除，[已合并...]不会回滚但任务无法恢复
      final msg =
          buildDeleteJobConfirmMessage(completedIndex: 5, totalRevisions: 10);
      expect(msg.startsWith('删除后任务将从队列移除'), isTrue);
      expect(msg.contains('不会回滚但任务无法恢复'), isTrue);
    });
  });

  group('_deleteQueueJob 接二次确认（doc-as-test）', () {
    // 用户场景：失败任务可能含数十至数百已合并 revision，原 _deleteQueueJob 直连
    // mergeState.deleteJob(jobId) 无确认，误点不可恢复。同 panel 同级操作（清空待执行 /
    // 终止任务 / 清理历史）都走 _confirmQueueAction，唯有单条删除原裸调——这条收口拉齐。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test('_deleteQueueJob 内调用 _confirmQueueAction 走二次确认', () {
      final start = src.indexOf(
          'Future<void> _deleteQueueJob(\n    MergeExecutionState mergeState,');
      expect(start, greaterThan(0), reason: '必须存在 _deleteQueueJob 方法');
      final body = src.substring(start, start + 1500);
      expect(
        body.contains('await _confirmQueueAction('),
        isTrue,
        reason: '_deleteQueueJob 必须先走二次确认 dialog',
      );
      expect(
        body.contains("title: '删除任务 #\$jobId',"),
        isTrue,
        reason: '确认 dialog title 必须含具体 jobId',
      );
      expect(
        body.contains("confirmLabel: '删除',"),
        isTrue,
        reason: '确认按钮文案必须是"删除"（与 R13 终止任务的"终止" / 清空的"清空"对偶）',
      );
    });

    test('确认 message 走 buildDeleteJobConfirmMessage 复用文案 helper', () {
      final start = src.indexOf(
          'Future<void> _deleteQueueJob(\n    MergeExecutionState mergeState,');
      final body = src.substring(start, start + 1500);
      expect(
        body.contains('message: buildDeleteJobConfirmMessage('),
        isTrue,
        reason: '不能 inline 拼字符串，必须复用 buildDeleteJobConfirmMessage 单测过的文案',
      );
      expect(
        body.contains('completedIndex: job.completedIndex,'),
        isTrue,
      );
      expect(
        body.contains('totalRevisions: job.revisions.length,'),
        isTrue,
      );
    });

    test('!confirmed 早退（不进入 deleteJob）', () {
      final start = src.indexOf(
          'Future<void> _deleteQueueJob(\n    MergeExecutionState mergeState,');
      final body = src.substring(start, start + 1500);
      expect(
        body.contains('if (!confirmed) return;'),
        isTrue,
        reason: 'confirmed 为 false 时必须早退，不能 fallthrough 到 deleteJob',
      );
      // 确认 confirmed 检查必须出现在 mergeState.deleteJob 调用之前
      final confirmIdx = body.indexOf('if (!confirmed) return;');
      final deleteIdx = body.indexOf('await mergeState.deleteJob(jobId);');
      expect(confirmIdx, greaterThan(0));
      expect(deleteIdx, greaterThan(confirmIdx),
          reason: 'deleteJob 必须在 confirmed 守卫之后调用');
    });

    test('job == null 早退仍在 confirm 之前（先 sanity check 再问用户）', () {
      final start = src.indexOf(
          'Future<void> _deleteQueueJob(\n    MergeExecutionState mergeState,');
      final body = src.substring(start, start + 1500);
      final notFoundIdx = body.indexOf("'任务不存在，列表已更新'");
      final confirmIdx = body.indexOf('await _confirmQueueAction(');
      expect(notFoundIdx, greaterThan(0));
      expect(confirmIdx, greaterThan(notFoundIdx),
          reason: 'job==null 检查必须先于 confirm dialog——避免对已不存在的任务弹无意义对话框');
    });
  });

  group('_clearPendingRevisions 接二次确认（doc-as-test，第三十五轮）', () {
    // 用户场景：手工挑选数十/上百个 revision 加入"待合并"列表后，PendingPanel 标题区
    // 的"清空待合并"按钮（IconButton onPressed: onClearPending）原本直连
    // appState.clearPendingRevisions() 无任何确认。误点后整个待合并列表丢失、不可恢复。
    // 同 panel 的 _cancelPausedJobWithConfirm / _deleteQueueJob / _clearPendingJobs /
    // _clearFinishedJobs 都已走 _confirmQueueAction，唯有此处裸调——这条收口拉齐
    // 破坏性操作的 confirm 覆盖率。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test('_clearPendingRevisions 改为 async 并调用 _confirmQueueAction', () {
      final start =
          src.indexOf('Future<void> _clearPendingRevisions() async {');
      expect(start, greaterThan(0),
          reason:
              '_clearPendingRevisions 必须升级为 async（裸 sync 不能 await confirm）');
      final body = src.substring(start, start + 1200);
      expect(
        body.contains('await _confirmQueueAction('),
        isTrue,
        reason: '必须复用 _confirmQueueAction helper（与同 panel 其它破坏性按钮对偶）',
      );
      expect(
        body.contains("title: '清空待合并列表',"),
        isTrue,
        reason: 'dialog title 必须明确为"清空待合并列表"',
      );
      expect(
        body.contains("confirmLabel: '清空',"),
        isTrue,
        reason: '确认按钮文案必须是"清空"（与 _clearPendingJobs / _clearFinishedJobs 对偶）',
      );
      expect(
        body.contains(r"将移除 $count 个待合并 revision，操作不可恢复。"),
        isTrue,
        reason: 'message 必须透传 count 并明示"不可恢复"',
      );
    });

    test('!confirmed 早退（不进入 clearPendingRevisions）', () {
      final start =
          src.indexOf('Future<void> _clearPendingRevisions() async {');
      final body = src.substring(start, start + 1200);
      expect(
        body.contains('if (!confirmed) return;'),
        isTrue,
        reason:
            'confirmed 为 false 时必须早退，不能 fallthrough 到 clearPendingRevisions',
      );
      // confirmed 守卫必须出现在 appState.clearPendingRevisions 调用之前
      final confirmIdx = body.indexOf('if (!confirmed) return;');
      final clearIdx = body.indexOf('appState.clearPendingRevisions();');
      expect(confirmIdx, greaterThan(0));
      expect(clearIdx, greaterThan(confirmIdx),
          reason: 'clearPendingRevisions 必须在 confirmed 守卫之后调用');
    });

    test('isEmpty 早退仍在 confirm 之前（先 sanity check 再问用户）', () {
      final start =
          src.indexOf('Future<void> _clearPendingRevisions() async {');
      final body = src.substring(start, start + 1200);
      final emptyIdx = body.indexOf("'待合并列表已经是空的'");
      final confirmIdx = body.indexOf('await _confirmQueueAction(');
      expect(emptyIdx, greaterThan(0));
      expect(confirmIdx, greaterThan(emptyIdx),
          reason: 'isEmpty 检查必须先于 confirm dialog——空列表无需弹无意义对话框');
    });

    test('R131 档 3 守护 — confirm 之后、setState 之前必带 mounted check', () {
      final start =
          src.indexOf('Future<void> _clearPendingRevisions() async {');
      final body = src.substring(start, start + 1200);
      final mountedIdx = body.indexOf('if (!mounted) return;');
      final setStateIdx =
          body.indexOf('setState(() => _pendingSourceUrl = null);');
      expect(mountedIdx, greaterThan(0),
          reason: '跨 await 后必须前置 mounted check（R131 档 3 不变量 I1）');
      expect(setStateIdx, greaterThan(mountedIdx),
          reason: 'setState 必须在 mounted 守卫之后');
    });
  });

  group('resolveLogTargetStateKey', () {
    test('完整工作副本模式使用工作副本路径作为状态查询目标', () {
      expect(
        resolveLogTargetStateKey(
          TargetConfig.fullWorkingCopy('  /local/wc  '),
        ),
        '/local/wc',
      );
    });

    test('临时精简工作副本模式使用目标 SVN URL 作为状态查询目标', () {
      expect(
        resolveLogTargetStateKey(
          TargetConfig.sparseTemporary('  svn://host/branches/target  '),
        ),
        'svn://host/branches/target',
      );
    });
  });

  group('resolveCanLoadMore', () {
    // 构造 LogBoundaryDescription 的便捷工厂，按 reason 自动派生 canLoadMore——
    // 与 LogBoundaryDescription.canLoadMore getter 的字段绑定保持一致。
    LogBoundaryDescription boundary(LogBoundaryReason reason) {
      return LogBoundaryDescription(text: null, reason: reason);
    }

    test('cachedLogCount > 0 + boundary.canLoadMore=true → true', () {
      expect(
        resolveCanLoadMore(
          cachedLogCount: 5,
          boundary: boundary(LogBoundaryReason.canLoadMore),
        ),
        isTrue,
      );
    });

    test('cachedLogCount == 0 + boundary.canLoadMore=true → false（合取必须都成立）',
        () {
      // 反向锁定：boundary 单独允许加载、但 cachedLogCount==0 时**仍**不应启用按钮——
      // 因为 LogBoundaryDescription.canLoadMore 注释说 noCache 也算"可加载"，
      // caller 必须额外用 cachedLogCount > 0 把"还没开始"分裂出去。
      expect(
        resolveCanLoadMore(
          cachedLogCount: 0,
          boundary: boundary(LogBoundaryReason.noCache),
        ),
        isFalse,
      );
    });

    test('cachedLogCount > 0 + boundary.canLoadMore=false → false', () {
      // 已加载过日志，但已到分支点 / 历史耗尽——按钮禁用
      expect(
        resolveCanLoadMore(
          cachedLogCount: 100,
          boundary: boundary(LogBoundaryReason.reachedBranchPoint),
        ),
        isFalse,
      );
    });

    test('cachedLogCount == 0 + boundary.canLoadMore=false → false（双 false）',
        () {
      expect(
        resolveCanLoadMore(
          cachedLogCount: 0,
          boundary: boundary(LogBoundaryReason.noMoreHistory),
        ),
        isFalse,
      );
    });

    test('cachedLogCount 负数 → 视为 0（"> 0" 判定，false）', () {
      // 防御性：上游不该传负数，但传入也不应错误地启用按钮
      expect(
        resolveCanLoadMore(
          cachedLogCount: -1,
          boundary: boundary(LogBoundaryReason.canLoadMore),
        ),
        isFalse,
      );
    });

    test('cachedLogCount = 1 是边界（启用阈值的最小值）', () {
      // 锁住 ">" 而非 ">=" ——cachedLogCount==1 应该启用，==0 不启用
      expect(
        resolveCanLoadMore(
          cachedLogCount: 1,
          boundary: boundary(LogBoundaryReason.canLoadMore),
        ),
        isTrue,
      );
    });

    test('真值表全覆盖：(cachedLogCount cmp 0) × LogBoundaryReason.values', () {
      // 锁定"两条独立维度"——cachedLogCount 是否为正、boundary 是否允许，
      // 唯一应当为 true 的组合是 (cachedLogCount > 0 && boundary.canLoadMore)，
      // 其他全 false。
      const counts = [-5, 0, 1, 100];
      for (final count in counts) {
        for (final reason in LogBoundaryReason.values) {
          final b = boundary(reason);
          final expected = count > 0 && b.canLoadMore;
          expect(
            resolveCanLoadMore(cachedLogCount: count, boundary: b),
            expected,
            reason: 'count=$count reason=$reason expected=$expected',
          );
        }
      }
    });

    test('与 LogBoundaryDescription.canLoadMore 直接耦合（不重算 reason 名单）', () {
      // resolveCanLoadMore 应该信任 boundary.canLoadMore 这个 getter，不自己复算
      // 6 个 reason 哪些算"可加载"——单一来源避免两份名单不同步。
      // 通过遍历每个 reason、对比 resolveCanLoadMore(count=1, ...) 与 boundary.canLoadMore：
      for (final reason in LogBoundaryReason.values) {
        final b = boundary(reason);
        expect(
          resolveCanLoadMore(cachedLogCount: 1, boundary: b),
          equals(b.canLoadMore),
          reason:
              'reason=$reason 在 cachedLogCount>0 下应直接复用 boundary.canLoadMore',
        );
      }
    });
  });

  group('R126 启动序列约束 doc-as-test（_initServices 5-step 多服务编排顺序锁）', () {
    test('5 步顺序固定：底层服务 → 中间服务 → 配置注入 → UI 调度', () {
      const order = [
        'step1:logFileCacheService.init',
        'step2:logCacheService.init+callback',
        'step3:preloadService.init+callback',
        'step4:loadPreloadSettings',
        'step5:postFrameCallback(autoLoadLogsIfPossible)',
      ];
      expect(order.length, equals(5));
      expect(order.first, startsWith('step1:'));
      expect(order.last, contains('postFrameCallback'));
    });

    test('step 2 → step 3：log_cache 必须先于 preload（preload 依赖 log_cache 内部状态）',
        () {
      // PreloadService.init 内部 `await _cacheService.init()` 再次调
      // logCacheService（idempotent 但状态依赖）；callback onProgressChanged 也
      // 在 init resolve 后挂到 service 上。任意反序会让 preload 调 logCache 时后
      // 者 _prefs 还是 null，url-hash mapping 全丢。
      const dependencyChain = [
        'logCacheService.ready',
        'preloadService.uses(logCacheService)',
      ];
      expect(dependencyChain[0], equals('logCacheService.ready'));
      expect(dependencyChain[1], contains('uses(logCacheService)'));
    });

    test('step 3 → step 4：preloadService 必须先于 _loadPreloadSettings', () {
      // _loadPreloadSettings 把 storage 持久化的 settings 灌入 preload service
      // 内部状态 —— preload service 必须 init 完成才有 internal state 接收
      // settings；反序会触发 LateInitializationError 或写到尚未存在的字段。
      const order = ['preloadService.init', 'loadPreloadSettings'];
      expect(
          order, orderedEquals(['preloadService.init', 'loadPreloadSettings']));
    });

    test(
        'step 5 必须最后：postFrameCallback 是 fire-and-forget 但前序 4 步保证 schedule 时刻',
        () {
      // step 5 不 await（addPostFrameCallback 不返回 Future），但 framework 保证
      // callback 在首帧 build 完成后才触发。前序 4 步 await 完后 schedule 时刻
      // 一定在所有 init 完成后；callback fire 时刻 ≥ 首帧。**必须最后**：放
      // step 1 前会让 _autoLoadLogsIfPossible 调用时 services 未 init。
      const order = [
        'step1:fileCacheInit',
        'step2:logCacheInit',
        'step3:preloadInit',
        'step4:loadSettings',
        'step5:postFrameCallback',
      ];
      expect(order.last, equals('step5:postFrameCallback'));
    });

    test('R126 启动方向单调原则（多服务编排式实例化）：底层 → 中间 → 配置 → UI', () {
      // 服务 init 抽象层级（自底向上）：
      // 底层服务（无依赖）：logFileCacheService（仅文件列表）
      // 中间服务（依赖底层）：logCacheService → preloadService（uses logCache）
      // 配置注入：loadPreloadSettings（storage → preload internal state）
      // UI 调度：postFrameCallback（依赖 widget tree mount）
      const layers = ['底层服务', '中间服务', '配置注入', 'UI 调度'];
      expect(layers.length, equals(4));
      expect(layers.first, equals('底层服务'));
      expect(layers.last, equals('UI 调度'));
      // R125 close 方向（function 内 step）：handle → memory → file → log
      // R126 init 方向（多服务编排）：底层 → 中间 → 配置 → UI
      // 共同点：都是单调链——晚步骤依赖早步骤已就绪。
    });
  });

  group('_removePendingRevision SnackBar 反馈契约（doc-as-test）', () {
    // 用户场景：用户点 PendingPanel 行尾 close 按钮 → 期望 SnackBar 反馈
    // "已从待合并移除 r$revision"。这与同文件 _clearPendingRevisions 的 SnackBar
    // 体验对齐，避免删除单条时反馈空白让用户怀疑是否生效。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test(r'_removePendingRevision 调 _showInfo 渲染 r$revision 文案', () {
      // 锁定字面量；改文案时单测同步红，避免静默回归。
      expect(
        src.contains("_showInfo('已从待合并移除 r\$revision');"),
        isTrue,
        reason: r'_removePendingRevision 末尾必须 _showInfo("已从待合并移除 r$revision")',
      );
    });

    test('_removePendingRevision 仍保留清空 _pendingSourceUrl 的副作用', () {
      // 防止"加 SnackBar 时不小心删了原副作用"——确保 pending 列表清空后
      // _pendingSourceUrl 也被同步清回 null。
      expect(
        src.contains(
            'if (appState.pendingRevisions.isEmpty && _pendingSourceUrl != null)'),
        isTrue,
        reason: '空列表 + 残留 sourceUrl 的清理副作用必须保留',
      );
    });
  });

  group(
      '_resumePausedJobWithFeedback / _skipCurrentRevisionWithFeedback SnackBar 反馈契约（doc-as-test）',
      () {
    // 用户场景：暂停态点"继续执行" / "跳过 (rN)"按钮 → 期望 SnackBar 立即反馈
    // 而非沉默生效；与 _cancelPausedJobWithConfirm 终止反馈、_runSvnCleanup
    // cleanup 反馈、_markConflictsResolved resolve 反馈四种 paused-action 的
    // 体验对齐。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test(
        'onResume 接 _resumePausedJobWithFeedback（不再裸调 mergeState.resumePausedJob）',
        () {
      expect(
        src.contains(
            'onResume: () => _resumePausedJobWithFeedback(mergeState),'),
        isTrue,
        reason: 'onResume 必须走包装方法以触发 SnackBar',
      );
      expect(
        src.contains('onResume: () => mergeState.resumePausedJob(),'),
        isFalse,
        reason: '裸调路径必须被包装替换',
      );
    });

    test(
        'onSkip 接 _skipCurrentRevisionWithFeedback（不再裸调 mergeState.skipCurrentRevision）',
        () {
      expect(
        src.contains(
            'onSkip: () => _skipCurrentRevisionWithFeedback(mergeState),'),
        isTrue,
        reason: 'onSkip 必须走包装方法以触发 SnackBar',
      );
      expect(
        src.contains('onSkip: () => mergeState.skipCurrentRevision(),'),
        isFalse,
        reason: '裸调路径必须被包装替换',
      );
    });

    test(r'_resumePausedJobWithFeedback 渲染 #$jobId 文案', () {
      expect(
        src.contains("_showInfo('继续执行任务 #\$jobId');"),
        isTrue,
        reason: 'resume 包装必须 _showInfo("继续执行任务 #N")',
      );
    });

    test(r'_skipCurrentRevisionWithFeedback 渲染 r$rev + #$jobId 双信息', () {
      expect(
        src.contains(
            "_showInfo('已跳过 r\$skippedRevision，继续执行任务 #\${paused.jobId}');"),
        isTrue,
        reason: 'skip 包装必须 _showInfo("已跳过 rN，继续执行任务 #M")',
      );
    });

    test('两个包装都对 pausedJob == null 早退展 _showInfo', () {
      // 防止异步态翻转后包装方法访问空对象。
      expect(
        src.contains('当前没有暂停中的任务'),
        isTrue,
        reason: '至少有一处对 pausedJob == null 的兜底文案',
      );
      // skip 还需对 currentRevision == null 兜底（任务已切到下一条但还未执行）
      expect(
        src.contains('当前任务没有可跳过的 revision'),
        isTrue,
        reason: 'skip 必须对 currentRevision == null 兜底',
      );
    });
  });

  group('CSV 导出 SnackBar 加"打开"按钮接线契约（doc-as-test）', () {
    // 用户场景：导出 CSV 后 SnackBar 仅显示文案"已导出 N 条到 path"，
    // 用户想验证导出结果必须手动复制路径打开。同 panel _openConflictFile
    // 已用 resolveOpenFileCommand + Process.run 跨平台打开文件——这里
    // 加 SnackBarAction "打开" 一键复用同款体验。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test('成功 SnackBar 含 SnackBarAction(label: 打开)', () {
      expect(
        src.contains("label: '打开',"),
        isTrue,
        reason: '导出成功 SnackBar 必须有 打开 action 按钮',
      );
      expect(
        src.contains('SnackBarAction('),
        isTrue,
        reason: '必须用 SnackBarAction 而非自造按钮',
      );
    });

    test('打开按钮 onPressed 接到 _openExportedCsvFile', () {
      expect(
        src.contains('onPressed: () => _openExportedCsvFile(savePath),'),
        isTrue,
        reason: '打开按钮必须调 _openExportedCsvFile 而非 inline Process.run',
      );
    });

    test('_openExportedCsvFile 复用 resolveOpenFileCommand', () {
      expect(
        src.contains('Future<void> _openExportedCsvFile(String path) async {'),
        isTrue,
      );
      // 必须复用 resolveOpenFileCommand（与 _openConflictFile 同款跨平台逻辑）
      final fileStart =
          src.indexOf('Future<void> _openExportedCsvFile(String path) async {');
      expect(fileStart, greaterThan(0));
      // 取从 _openExportedCsvFile 开始向后 60 行内查找 resolveOpenFileCommand
      final body = src.substring(fileStart, fileStart + 1200);
      expect(
        body.contains('resolveOpenFileCommand('),
        isTrue,
        reason: '_openExportedCsvFile 必须用 resolveOpenFileCommand 而非自造命令解析',
      );
      expect(
        body.contains('Process.run(command.executable, command.args)'),
        isTrue,
        reason: '_openExportedCsvFile 必须 Process.run 调起平台命令',
      );
    });

    test('SnackBar duration 延长到 6 秒（让用户来得及点"打开"）', () {
      // 默认 SnackBar 4 秒消失太短——加 action 后必须延长
      expect(
        src.contains("duration: const Duration(seconds: 6),"),
        isTrue,
        reason: 'CSV 导出成功 SnackBar 必须有 6 秒 duration（默认 4 秒太短点不到"打开"）',
      );
    });
  });

  group('_loadPreloadSettings 加载失败 SnackBar 反馈（doc-as-test）', () {
    // 用户场景：应用启动 initState 链路中 _loadPreloadSettings 读 SharedPreferences /
    // 持久化文件失败（磁盘权限 / 文件损坏），原 catch 仅 AppLogger.ui.error 无任何 UI
    // 反馈，配置静默回退到默认值 — 用户启动后看不到错误，以为偏好被重置但不确定。
    // 与已落地 R21 设置保存 / R20 CSV 导出 / R8 svn cleanup SnackBar 反馈体系对称补齐。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test('_loadPreloadSettings catch 内调用 _showError 含"加载设置失败"前缀', () {
      final start = src.indexOf('Future<void> _loadPreloadSettings() async {');
      expect(start, greaterThan(0), reason: '必须存在 _loadPreloadSettings 方法');
      final body = src.substring(start, start + 1200);
      expect(
        body.contains("_showError('加载设置失败，已使用默认值: \$e');"),
        isTrue,
        reason: 'catch 必须 _showError 反馈 — 不能仅 logger 静默',
      );
    });

    test('catch 内 _showError 包在 mounted 守卫内', () {
      final start = src.indexOf('Future<void> _loadPreloadSettings() async {');
      final body = src.substring(start, start + 1200);
      // 找 catch 块起点
      final catchIdx = body.indexOf('} catch (e) {');
      expect(catchIdx, greaterThan(0));
      final catchEnd = (catchIdx + 800).clamp(0, body.length) as int;
      final catchBlock = body.substring(catchIdx, catchEnd);
      expect(
        catchBlock.contains('if (mounted) {'),
        isTrue,
        reason: 'catch 块必须 mounted 守卫保护 ScaffoldMessenger 上下文',
      );
      final mountedIdx = catchBlock.indexOf('if (mounted) {');
      final showErrorIdx = catchBlock.indexOf('_showError(');
      expect(showErrorIdx, greaterThan(mountedIdx),
          reason: '_showError 必须出现在 mounted 守卫之后');
    });

    test('_showError 通过 addPostFrameCallback 推迟到下一帧（避免 first-frame race）', () {
      final start = src.indexOf('Future<void> _loadPreloadSettings() async {');
      final body = src.substring(start, start + 1200);
      expect(
        body.contains('WidgetsBinding.instance.addPostFrameCallback((_) {'),
        isTrue,
        reason:
            '_loadPreloadSettings 在 initState 链路 await，catch 时 first frame 可能未渲染，必须推迟',
      );
    });

    test('logger 旁路保留（catch 不能丢日志）', () {
      final start = src.indexOf('Future<void> _loadPreloadSettings() async {');
      final body = src.substring(start, start + 1200);
      expect(
        body.contains("AppLogger.ui.error('加载设置失败', e);"),
        isTrue,
        reason: 'logger 旁路必须保留 — 用户拿不到 SnackBar 时仍可从日志文件看到详情',
      );
      // 顺序：先 logger 后 SnackBar（与 lib 其他 catch 块协议一致）
      final loggerIdx = body.indexOf("AppLogger.ui.error('加载设置失败', e);");
      final showErrorIdx = body.indexOf('_showError(');
      expect(showErrorIdx, greaterThan(loggerIdx),
          reason: 'logger 必须先记录，再做 UI 反馈');
    });
  });

  group('设置保存成功后主屏 SnackBar 反馈（doc-as-test）', () {
    // 用户场景：用户在设置页改了若干字段、点"保存并关闭"后回到主屏，
    // 现状只 setState 更新本地缓存却没有任何视觉反馈，与同期 resume / skip /
    // CSV 导出 / 待合并移除等多处 SnackBar 反馈风格不一致——用户无法判断
    // 设置是否真的保存成功（特别是 SettingsScreen.show 在保存成功才 pop
    // 出 result，所以 result != null 一定是"成功"分支）。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test('_openSettings 在 result != null 路径调用 _showSuccess(已保存设置)', () {
      final start = src.indexOf('Future<void> _openSettings() async {');
      expect(start, greaterThan(0), reason: '必须存在 _openSettings 方法');
      // 取方法体（往后 600 字符足够覆盖完整方法）
      final body = src.substring(start, start + 600);
      expect(
        body.contains("_showSuccess('已保存设置');"),
        isTrue,
        reason: '_openSettings 必须在保存成功（result != null）路径加 _showSuccess 反馈',
      );
    });

    test('_showSuccess 调用位于 setState 之后（先持久化再反馈）', () {
      final start = src.indexOf('Future<void> _openSettings() async {');
      final body = src.substring(start, start + 600);
      final setStateIdx = body.indexOf('setState(() {');
      final feedbackIdx = body.indexOf("_showSuccess('已保存设置');");
      expect(setStateIdx, greaterThan(0));
      expect(feedbackIdx, greaterThan(setStateIdx),
          reason: '_showSuccess 必须出现在 setState 之后，否则旧值反馈语义不一致');
    });

    test('_showSuccess 调用包在 result != null && mounted 守卫内', () {
      final start = src.indexOf('Future<void> _openSettings() async {');
      final body = src.substring(start, start + 600);
      final guardIdx = body.indexOf('if (result != null && mounted) {');
      final feedbackIdx = body.indexOf("_showSuccess('已保存设置');");
      expect(guardIdx, greaterThan(0));
      expect(feedbackIdx, greaterThan(guardIdx),
          reason:
              '_showSuccess 必须在 result != null && mounted 守卫之内（保护 ScaffoldMessenger 上下文）');
    });
  });

  group('title/message filter 持久化对称（与 author 同模板）', () {
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test('_loadAuthorFilterHistory 同时载 author/title/message', () {
      final start =
          src.indexOf('Future<void> _loadAuthorFilterHistory() async {');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 800);
      expect(body.contains('storageService.getLastAuthorFilter()'), isTrue);
      expect(body.contains('storageService.getLastTitleFilter()'), isTrue);
      expect(body.contains('storageService.getLastMessageFilter()'), isTrue);
    });

    test('_loadAuthorFilterHistory 三个 .text= 都在 mounted 守卫之后', () {
      final start =
          src.indexOf('Future<void> _loadAuthorFilterHistory() async {');
      final body = src.substring(start, start + 800);
      final guardIdx = body.indexOf('if (!mounted) return;');
      final authorWriteIdx =
          body.indexOf('_filterAuthorController.text = lastAuthor;');
      final titleWriteIdx =
          body.indexOf('_filterTitleController.text = lastTitle;');
      final messageWriteIdx =
          body.indexOf('_filterMessageController.text = lastMessage;');
      expect(guardIdx, greaterThan(0));
      expect(authorWriteIdx, greaterThan(guardIdx));
      expect(titleWriteIdx, greaterThan(guardIdx));
      expect(messageWriteIdx, greaterThan(guardIdx));
    });

    test('_loadAuthorFilterHistory 三个写都带 isNotEmpty 守卫', () {
      final start =
          src.indexOf('Future<void> _loadAuthorFilterHistory() async {');
      final body = src.substring(start, start + 800);
      expect(
          body.contains('lastAuthor != null && lastAuthor.isNotEmpty'), isTrue);
      expect(
          body.contains('lastTitle != null && lastTitle.isNotEmpty'), isTrue);
      expect(body.contains('lastMessage != null && lastMessage.isNotEmpty'),
          isTrue);
    });

    test('_applyFilter 同时 save author/title/message', () {
      final start = src.indexOf('Future<void> _applyFilter() async {');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 1200);
      expect(body.contains('storageService.saveLastAuthorFilter('), isTrue);
      expect(body.contains('storageService.saveLastTitleFilter('), isTrue);
      expect(body.contains('storageService.saveLastMessageFilter('), isTrue);
    });

    test('_applyFilter 三个 save 都带 isNotEmpty 守卫', () {
      final start = src.indexOf('Future<void> _applyFilter() async {');
      final body = src.substring(start, start + 1200);
      expect(body.contains('if (authorFilter.isNotEmpty) {'), isTrue);
      expect(body.contains('if (titleFilter.isNotEmpty) {'), isTrue);
      expect(body.contains('if (messageFilter.isNotEmpty) {'), isTrue);
    });
  });

  group('_startMerge SVN 连通性预校验', () {
    final src = File(
      'lib/screens/main_screen_v3.dart',
    ).readAsStringSync();

    test('_isValidatingMerge 字段在 State 中声明', () {
      expect(
        src.contains('bool _isValidatingMerge = false;'),
        isTrue,
        reason: '需要 _isValidatingMerge 标志位避免 probe 期间双击重入',
      );
    });

    test('_startMerge 入口立刻早退保护重入', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 200);
      expect(
        body.contains('if (_isValidatingMerge) {'),
        isTrue,
        reason: '_startMerge 必须在入口检查 _isValidatingMerge 早退',
      );
    });

    test('_startMerge probe 前 setState true，finally 内 setState false', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      expect(
          body.contains('setState(() => _isValidatingMerge = true);'), isTrue);
      expect(body.contains('} finally {'), isTrue);
      expect(
          body.contains('setState(() => _isValidatingMerge = false);'), isTrue);
    });

    test('_startMerge 在 validateMergeStartPreconditions 通过后才 probe', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      final validateIdx = body.indexOf('validateMergeStartPreconditions(');
      final probeIdx = body.indexOf('_svnService.probeSvnLocation(');
      expect(validateIdx, greaterThan(0));
      expect(probeIdx, greaterThan(validateIdx),
          reason: 'probe 必须晚于 validateMergeStartPreconditions');
    });

    test('_startMerge probe sourceUrl 用 effectiveSourceUrl + role=源 URL', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      expect(
        body.contains(
          "_svnService.probeSvnLocation(\n"
          "        effectiveSourceUrl,\n"
          "        role: '源 URL',\n"
          "      )",
        ),
        isTrue,
      );
    });

    test('_startMerge probe 目标配置按模式选择 URL 或工作副本 role', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      expect(body.contains('targetConfig.probeTarget,'), isTrue);
      expect(
        body.contains('role: targetConfig.probeRole,'),
        isTrue,
        reason: '精简模式 probe 目标 SVN URL，完整模式继续 probe 目标工作副本',
      );
    });

    test('_startMerge probe 失败 → _showError + return（不 addJob）', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      expect(body.contains('if (sourceProbeError != null) {'), isTrue);
      expect(body.contains('_showError(sourceProbeError);'), isTrue);
      expect(body.contains('if (targetProbeError != null) {'), isTrue);
      expect(body.contains('_showError(targetProbeError);'), isTrue);
    });

    test('_startMerge probe 之间 / 之后 mounted 守卫', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      // 两个 probe 各自 await 后必须有 mounted check 防止异步态翻转
      expect('!mounted'.allMatches(body).length, greaterThanOrEqualTo(2));
    });

    test('PendingPanel.canStartMerge 集成 !_isValidatingMerge 锁', () {
      expect(
        src.contains(
          'canStartMerge: appState.pendingRevisions.isNotEmpty &&\n'
          '                !hasPendingSourceMismatch &&\n'
          '                !_isValidatingMerge,',
        ),
        isTrue,
      );
    });

    test('probe 必须在 addJob 之前调用', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      final probeIdx = body.indexOf('_svnService.probeSvnLocation(');
      final addJobIdx = body.indexOf('mergeState.addJob(');
      expect(probeIdx, greaterThan(0));
      expect(addJobIdx, greaterThan(probeIdx),
          reason: 'addJob 必须晚于 probe，避免无效配置入队');
    });

    test('_startMerge 完整模式从目标工作副本解析 targetUrl 后再入队', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      final getInfoIdx =
          body.indexOf(".getInfo(targetConfig.workingCopyPath, item: 'url')");
      final addJobIdx = body.indexOf('mergeState.addJob(');
      expect(getInfoIdx, greaterThan(0),
          reason: '目标展示和 {targetUrl} 模板变量必须使用 svn info 的真实目标 URL');
      expect(addJobIdx, greaterThan(getInfoIdx),
          reason: 'addJob 必须保存已解析 targetUrl，不能只保存本地工作副本名');
      expect(body.contains('targetConfig: resolvedTargetConfig,'), isTrue);
    });

    test('_startMerge 精简模式入队时目标配置来自当前 TargetConfig', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);
      expect(
          body.contains('final targetConfig = _currentTargetConfig(appState);'),
          isTrue);
      expect(body.contains('var resolvedTargetConfig = targetConfig;'), isTrue);
      expect(body.contains('targetConfig: resolvedTargetConfig,'), isTrue);
    });

    test('_startMerge 精简模式保存独立 targetUrlHistory，不写 switchBranchHistory', () {
      final start = src.indexOf('Future<void> _startMerge() async {');
      final end = src.indexOf('void _showError', start);
      final body = src.substring(start, end);

      expect(body.contains('await appState.saveTargetConfig(targetConfig);'),
          isTrue);
      expect(
        body.contains('await appState.saveSwitchBranchToHistory('),
        isFalse,
      );
    });
  });

  group('_adjustJobMaxRetries 暂停态调整重试上限（doc-as-test）', () {
    // 用户场景：commit out-of-date 重试耗尽暂停时，hint 文案明示"提高重试上限"
    // 但 UI 此前无入口；用户必须中断任务回到设置改全局 maxRetries 才能继续。
    // 本组锁 dialog/contract/SnackBar 三方面，避免静默回归。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

    test('_adjustJobMaxRetries 接受 MergeJob 入参', () {
      expect(
        src.contains('Future<void> _adjustJobMaxRetries(MergeJob job) async {'),
        isTrue,
        reason: '签名锁：caller 直接传 pausedJob，方法读 job.maxRetries / job.jobId',
      );
    });

    test('dialog 标题含任务编号', () {
      expect(
        src.contains("Text('调整任务 #\${job.jobId} 重试次数')"),
        isTrue,
        reason: '标题应该展示用户当前操作的具体任务，避免误改其它任务',
      );
    });

    test('TextField 默认填当前 maxRetries', () {
      expect(
        src.contains('TextEditingController(text: job.maxRetries.toString())'),
        isTrue,
        reason: '默认值应该是当前上限，让用户在此基础上调高',
      );
    });

    test('helperText 提示"只能调高"', () {
      expect(
        src.contains("helperText: '只能调高（必须大于当前值）'"),
        isTrue,
        reason: 'UI 必须提前告知用户调低会被拒绝，避免输入后才报错',
      );
    });

    test('调用 mergeState.updateJobMaxRetries 持久化', () {
      expect(
        src.contains('mergeState.updateJobMaxRetries(job.jobId, newValue)'),
        isTrue,
        reason: '必须走 provider 方法而非直接改 _jobs，保证 saveQueue + notify',
      );
    });

    test('成功 SnackBar 文案含新值与"继续"提示', () {
      expect(
        src.contains("已将任务 #\${job.jobId} 的重试上限调整为 \$newValue，可点击\"继续\"重试"),
        isTrue,
        reason: '与 _runSvnCleanup / _markConflictsResolved 同款"显式触发 resume"语义',
      );
    });

    test('失败 SnackBar 文案明确说明拒绝条件', () {
      expect(
        src.contains("调整失败：新值必须大于当前上限 \${job.maxRetries}"),
        isTrue,
        reason: 'updateJobMaxRetries 返回 false 时让用户知道当前上限是多少；'
            '原 "非负整数" 文案在 inputFormatters: [digitsOnly] 加入后已是不可达分支',
      );
    });

    test('TextField 加 FilteringTextInputFormatter.digitsOnly 与设置页对齐', () {
      // 真 bug：原 dialog 仅 keyboardType=number，缺 inputFormatters；
      // 用户可输入 -5 / 1.5 / abc，被 updateJobMaxRetries 的 < 0 守卫拒掉
      // 报通用 "非负整数" 错误。settings_screen 内所有数字字段（_maxRetries /
      // _maxDays / _maxCount / _stopRevision）都用 [FilteringTextInputFormatter.digitsOnly]
      // 拦截非数字、负号、小数点；本 dialog 必须对齐这条家族契约。
      final start = src
          .indexOf('Future<void> _adjustJobMaxRetries(MergeJob job) async {');
      final end = src.indexOf('Future<void> _openConflictFile', start);
      final body = src.substring(start, end);
      expect(
        body.contains(
            'inputFormatters: [FilteringTextInputFormatter.digitsOnly]'),
        isTrue,
        reason: '与 settings_screen 内 4 个数字字段同款 input filtering 家族对齐',
      );
    });

    test('lib import flutter/services 支持 FilteringTextInputFormatter', () {
      expect(
        src.contains("import 'package:flutter/services.dart';"),
        isTrue,
        reason: 'FilteringTextInputFormatter 来自 flutter/services',
      );
    });

    test('dialog 关闭后 controller 必须 dispose', () {
      final start = src
          .indexOf('Future<void> _adjustJobMaxRetries(MergeJob job) async {');
      final end = src.indexOf('Future<void> _openConflictFile', start);
      final body = src.substring(start, end);
      expect(
        body.contains('controller.dispose();'),
        isTrue,
        reason: 'TextEditingController 必须显式 dispose，避免泄漏',
      );
    });

    test('updateJobMaxRetries 调用前必须 mounted 守卫', () {
      final start = src
          .indexOf('Future<void> _adjustJobMaxRetries(MergeJob job) async {');
      final end = src.indexOf('Future<void> _openConflictFile', start);
      final body = src.substring(start, end);
      // 至少有 await 后的两个 mounted 守卫：dialog await 后 + updateJobMaxRetries await 后
      final mountedMatches = '!mounted'.allMatches(body).length;
      expect(mountedMatches, greaterThanOrEqualTo(2),
          reason: 'dialog 与 updateJobMaxRetries 两个 await 后都需 mounted 守卫');
    });

    test(
        'MergeExecutionPanel.onAdjustMaxRetries 接线非 null 时调 _adjustJobMaxRetries',
        () {
      expect(
        src.contains('onAdjustMaxRetries: mergeState.pausedJob == null'),
        isTrue,
      );
      expect(
        src.contains(
            '=> _adjustJobMaxRetries(\n                            mergeState.pausedJob!,\n                          )'),
        isTrue,
        reason:
            '与 onCleanup / onMarkResolved / onOpenConflictFile 同款 null-safe 接线',
      );
    });
  });

  group('formatMarkResolvedFeedback（svn resolve 后冲突仍存在补警告）', () {
    // 真 bug：`svn resolve --accept <mode> -R .` exit 0 不保证 working copy 真的干净——
    // tree conflict / mode 不匹配 / 部分文件未被 -R 命中等场景下 exit 0 但 svn status 仍
    // 出现 'C' 行。原 _markConflictsResolved 只看 result.isSuccess，用户点"继续"任务跑到
    // merge 步又重新冲突暂停。本 helper 把"是否还有冲突"语义化为"剩余冲突文件数"两档分流。
    test('remainingConflictCount == 0 → 走原成功文案', () {
      expect(
        formatMarkResolvedFeedback(
            modeFlag: 'working', remainingConflictCount: 0),
        '已标记冲突为已解决（accept working），可点击"继续"重试',
      );
    });

    test('remainingConflictCount < 0（防御）→ 走原成功文案', () {
      // listConflictedFiles 实际不会返回负数，但 helper 接 int 不应在边界上崩
      expect(
        formatMarkResolvedFeedback(
            modeFlag: 'mine-full', remainingConflictCount: -1),
        '已标记冲突为已解决（accept mine-full），可点击"继续"重试',
      );
    });

    test('remainingConflictCount == 1 → 警告文案含数字 1', () {
      expect(
        formatMarkResolvedFeedback(
            modeFlag: 'working', remainingConflictCount: 1),
        '已运行 svn resolve（accept working），但仍检测到 1 个冲突文件，请手动检查后再继续',
      );
    });

    test('remainingConflictCount > 1 → 警告文案含具体数字', () {
      expect(
        formatMarkResolvedFeedback(
            modeFlag: 'theirs-full', remainingConflictCount: 7),
        '已运行 svn resolve（accept theirs-full），但仍检测到 7 个冲突文件，请手动检查后再继续',
      );
    });

    test('modeFlag 透传到文案（4 种 SvnResolveAccept 都走 cliFlag 字面量）', () {
      // 与 SvnResolveAccept enum 的 4 种 cliFlag (working / mine-full / theirs-full / base)
      // 形成对照测试，避免 helper 写死某一种 mode
      for (final flag in const [
        'working',
        'mine-full',
        'theirs-full',
        'base'
      ]) {
        final ok = formatMarkResolvedFeedback(
            modeFlag: flag, remainingConflictCount: 0);
        expect(ok.contains('accept $flag'), isTrue, reason: '成功文案必须含 modeFlag');
        final warn = formatMarkResolvedFeedback(
            modeFlag: flag, remainingConflictCount: 2);
        expect(warn.contains('accept $flag'), isTrue,
            reason: '警告文案必须含 modeFlag');
      }
    });

    test('警告文案明示"请手动检查后再继续"指导用户不要直接点继续', () {
      // 核心：用户必须知道"按继续会再次冲突"——文案必须明确禁止直接点继续
      final warn = formatMarkResolvedFeedback(
          modeFlag: 'working', remainingConflictCount: 3);
      expect(warn.contains('请手动检查后再继续'), isTrue);
      expect(warn.contains('"继续"'), isFalse, reason: '警告文案不应像成功文案那样诱导点"继续"');
    });

    test('成功 / 警告文案首字母不同——视觉上立即可辨', () {
      // 成功："已标记冲突为已解决"
      // 警告："已运行 svn resolve"
      // 用户扫一眼 SnackBar 头部就能区分
      final ok = formatMarkResolvedFeedback(
          modeFlag: 'working', remainingConflictCount: 0);
      final warn = formatMarkResolvedFeedback(
          modeFlag: 'working', remainingConflictCount: 1);
      expect(ok.startsWith('已标记冲突为已解决'), isTrue);
      expect(warn.startsWith('已运行 svn resolve'), isTrue);
    });
  });

  group(
      '_markConflictsResolved 走 formatMarkResolvedFeedback + listConflictedFiles 后验',
      () {
    // 真 bug：原 _markConflictsResolved 只检查 result.isSuccess，未读 svn status 验证
    // working copy 真的清空。本组锁接线契约：成功路径必须再调一次 listConflictedFiles
    // 取剩余冲突列表，并把 length 传给 formatMarkResolvedFeedback 决定文案分流。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _markConflictsResolved(');
    final body = start > 0 ? src.substring(start, start + 2000) : '';

    test('源代码必须存在 _markConflictsResolved 方法', () {
      expect(start, greaterThan(0));
    });

    test('成功分支调 _svnService.listConflictedFiles(targetWc) 取剩余冲突', () {
      expect(
        body.contains('await _svnService.listConflictedFiles(targetWc);'),
        isTrue,
        reason: 'svn resolve exit 0 不保证 WC 干净，必须再读一次 svn status 验证',
      );
    });

    test('成功分支调用 formatMarkResolvedFeedback 而非 inline 拼字符串', () {
      expect(
        body.contains('formatMarkResolvedFeedback('),
        isTrue,
        reason: '文案必须走 helper 单测覆盖，不能 inline',
      );
      expect(
        body.contains('modeFlag: mode.cliFlag,'),
        isTrue,
      );
      expect(
        body.contains('remainingConflictCount: remaining.length,'),
        isTrue,
        reason: 'helper 接 int 而非 bool——便于在文案里报"还剩 N 个"',
      );
    });

    test('listConflictedFiles 之后保留 mounted 守卫', () {
      // svn status 也是 await，可能跨多帧；返回时 widget 可能已 dispose
      // 仅锁 listConflictedFiles 之后必须有 mounted 守卫，不锁守卫前的代码块顺序
      final after =
          body.substring(body.indexOf('listConflictedFiles(targetWc);'));
      expect(
        after.contains('if (!mounted) return;'),
        isTrue,
        reason: 'listConflictedFiles 是 await，返回后必须再守一次 mounted',
      );
    });

    test('原"已标记冲突为已解决"字面量已不再 inline（防回归）', () {
      // 防御：未来有人 revert helper 调用回到 inline 拼字符串
      // 注意 helper 内部仍有这个字面量，所以仅锁 _markConflictsResolved 函数体内不再 inline
      expect(
        body.contains("'已标记冲突为已解决（accept \${mode.cliFlag}）"),
        isFalse,
        reason: '_markConflictsResolved 内部不应有 inline 拼写——必须走 helper',
      );
    });

    test('失败分支保持原文案不变（仅成功分支补后验，不动失败语义）', () {
      // 决策权衡：本轮仅修复"成功但实际仍有冲突"的隐藏漏洞
      // 失败分支（result.isSuccess == false）保持原 SnackBar，不引入 listConflictedFiles
      expect(
        body.contains(
            "'标记失败: \${result.stderr.isEmpty ? \"未知错误\" : result.stderr}'"),
        isTrue,
        reason: '失败分支文案不变',
      );
    });
  });

  group('_testSvnConnectivity（network 暂停态测试连通性按钮，doc-as-test）', () {
    // 真缺口：第二十六轮已落地"启动合并前 SVN 连通性预校验"（_startMerge 调
    // probeSvnLocation），但任务执行中遇到 network 故障暂停后，用户没有同款入口验证
    // 网络是否恢复——只能盲点"继续"重试整个 merge step。本组锁 _testSvnConnectivity
    // 接线契约：复用第二十六轮 probeSvnLocation 顺序探测 sourceUrl/targetWc，并 SnackBar 反馈。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
    final start =
        src.indexOf('Future<void> _testSvnConnectivity(MergeJob job)');
    final body = start > 0 ? src.substring(start, start + 2000) : '';

    test('源代码必须存在 _testSvnConnectivity(MergeJob job) 方法', () {
      expect(start, greaterThan(0),
          reason: '签名必须接 MergeJob 而非主屏 controller——见方法 dartdoc 决策权衡');
    });

    test('依次 probe job.sourceUrl 与 job.targetWc（复用 probeSvnLocation）', () {
      expect(
        body.contains(
            "await _svnService.probeSvnLocation(\n      job.sourceUrl,\n      role: '源 URL',\n    )"),
        isTrue,
        reason: '必须先 probe sourceUrl，role 与第二十六轮 _startMerge 一致',
      );
      expect(
        body.contains(
            "await _svnService.probeSvnLocation(\n      job.targetWc,\n      role: '目标工作副本',\n    )"),
        isTrue,
        reason: '再 probe targetWc，role 与 _startMerge 一致',
      );
    });

    test('双 await 后各自 mounted 守卫（防 use-after-dispose）', () {
      // 与第二十六轮 _startMerge 同款：每个 probe await 后立即 mounted 检查
      final occurrences = 'if (!mounted) return;'.allMatches(body).length;
      expect(occurrences, greaterThanOrEqualTo(2),
          reason: '双 probe 之后必须各有一道 mounted 守卫');
    });

    test('sourceUrl probe 失败 → _showError + return 早退（不再 probe targetWc）', () {
      expect(
        body.contains(
            'if (sourceProbeError != null) {\n      _showError(sourceProbeError);\n      return;\n    }'),
        isTrue,
        reason: '错误信息要明确告诉用户哪一项不通，顺序 probe 而非并行',
      );
    });

    test('targetWc probe 失败 → _showError + return 早退', () {
      expect(
        body.contains(
            'if (targetProbeError != null) {\n      _showError(targetProbeError);\n      return;\n    }'),
        isTrue,
      );
    });

    test('双 probe 通过 → _showSuccess 绿底 SnackBar 文案明确"可点击继续"', () {
      expect(
        body.contains("_showSuccess('连通性正常，SVN 可访问，可点击\"继续\"重试');"),
        isTrue,
        reason:
            '与 cleanup / adjustMaxRetries 等 paused-action 反馈一致——不自动 resume，引导用户手动点继续',
      );
    });

    test('不调 mergeState.resumePausedJob — 与 cleanup / mark-resolved 同款显式触发语义',
        () {
      expect(
        body.contains('resumePausedJob('),
        isFalse,
        reason: '测试连通性是诊断动作，不应自动 resume',
      );
    });

    test('panel 接线 onTestConnectivity null-safe 调 _testSvnConnectivity', () {
      expect(
        src.contains('onTestConnectivity: mergeState.pausedJob == null'),
        isTrue,
      );
      expect(
        src.contains(
            '=> _testSvnConnectivity(\n                            mergeState.pausedJob!,\n                          )'),
        isTrue,
        reason: '与 onCleanup / onAdjustMaxRetries 同款 null-safe 接线',
      );
    });
  });

  group('formatCleanupFeedback（svn cleanup 后 WC 仍不可用补警告）', () {
    // 真 bug：`svn cleanup` exit 0 不保证 working copy 真的可用——外部进程持有文件锁、
    // .svn 元数据损坏、磁盘 / 权限故障下 svn cleanup 仍可能 exit 0（cleanup 只能处理
    // "卡住的事务"，处理不了"WC 结构性损坏 / 外部占用"）。原 _runSvnCleanup 只看
    // result.isSuccess，用户点"继续"任务又因 .svn 不可读再次暂停。本 helper 把
    // "WC 是否真可用"语义化为"probeSvnLocation 返回的错误描述（null = 通过）"两档分流。
    test('probeError == null → 走原成功文案', () {
      expect(
        formatCleanupFeedback(probeError: null),
        '已执行 svn cleanup，可点击"继续"重试',
      );
    });

    test('probeError 缺省（默认 null）→ 走原成功文案', () {
      // 防御：caller 偶发不传 named 入参也应走成功路径（cleanup 退出 0 + 未做 probe 的兼容缺口）
      expect(
        formatCleanupFeedback(),
        '已执行 svn cleanup，可点击"继续"重试',
      );
    });

    test('probeError == empty string（防御）→ 走原成功文案', () {
      // probeSvnLocation 实际不会返回空字符串，但 helper 接 String? 不应在边界上崩
      expect(
        formatCleanupFeedback(probeError: ''),
        '已执行 svn cleanup，可点击"继续"重试',
      );
    });

    test('probeError 非空 → 警告文案含 probe 错误描述原文', () {
      final warn = formatCleanupFeedback(probeError: '工作副本不可读：.svn 目录损坏');
      expect(warn.contains('工作副本不可读：.svn 目录损坏'), isTrue,
          reason: 'probeError 必须原样进入文案，不做二次翻译');
    });

    test('警告文案明示"请手动检查后再继续"指导用户不要直接点继续', () {
      final warn = formatCleanupFeedback(probeError: '路径不存在');
      expect(warn.contains('请手动检查后再继续'), isTrue);
      expect(warn.contains('"继续"'), isFalse, reason: '警告文案不应像成功文案那样诱导点"继续"');
    });

    test('成功 / 警告文案首字母不同——视觉上立即可辨', () {
      // 成功："已执行 svn cleanup"
      // 警告："已运行 svn cleanup"
      // 与 R28 markResolved 同款"已标记..." vs "已运行 svn resolve" 视觉差异家族
      final ok = formatCleanupFeedback(probeError: null);
      final warn = formatCleanupFeedback(probeError: 'WC 不可用');
      expect(ok.startsWith('已执行 svn cleanup'), isTrue);
      expect(warn.startsWith('已运行 svn cleanup'), isTrue);
    });

    test('警告文案不诱导点继续——不含字面"继续"二字', () {
      // 与 formatMarkResolvedFeedback 同款契约——警告路径明确禁止直接点继续
      final warn = formatCleanupFeedback(probeError: '权限不足');
      expect(warn.contains('"继续"'), isFalse);
    });
  });

  group('_runSvnCleanup 走 formatCleanupFeedback + probeSvnLocation 后验', () {
    // 真 bug：原 _runSvnCleanup 只检查 result.isSuccess，未做 WC 后验。本组锁接线契约：
    // 成功路径必须再调一次 probeSvnLocation(targetWc, role: '工作副本') 验证 WC 元数据
    // 仍可读，并把结果传给 formatCleanupFeedback 决定文案分流。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _runSvnCleanup(String targetWc)');
    final body = start > 0 ? src.substring(start, start + 2000) : '';

    test('源代码必须存在 _runSvnCleanup(String targetWc) 方法', () {
      expect(start, greaterThan(0));
    });

    test('成功分支调 _svnService.probeSvnLocation(targetWc, role: ...) 后验', () {
      expect(
        body.contains(
            "await _svnService.probeSvnLocation(\n          targetWc,\n          role: '工作副本',\n        )"),
        isTrue,
        reason: 'svn cleanup exit 0 不保证 WC 可用，必须用 probeSvnLocation 后验元数据可读',
      );
    });

    test('成功分支调用 formatCleanupFeedback 而非 inline 拼字符串', () {
      expect(
        body.contains('formatCleanupFeedback('),
        isTrue,
        reason: '文案必须走 helper 单测覆盖，不能 inline',
      );
      expect(
        body.contains('probeError: probeError'),
        isTrue,
        reason: 'probeError 直接透传——helper 内部决定 null/empty/非空分流',
      );
    });

    test('probeSvnLocation 之后保留 mounted 守卫', () {
      // probeSvnLocation 走 svn info 是 await，可能跨多帧；返回时 widget 可能已 dispose
      final after = body.substring(body.indexOf('probeSvnLocation('));
      expect(
        after.contains('if (!mounted) return;'),
        isTrue,
        reason: 'probeSvnLocation 是 await，返回后必须再守一次 mounted',
      );
    });

    test('原"已执行 svn cleanup"字面量已不再 inline（防回归）', () {
      // 防御：未来有人 revert helper 调用回到 inline 拼字符串
      // 注意 helper 内部仍有这个字面量，所以仅锁 _runSvnCleanup 函数体内不再 inline
      expect(
        body.contains("Text('已执行 svn cleanup"),
        isFalse,
        reason: '_runSvnCleanup 内部不应有 inline 拼写——必须走 helper',
      );
    });

    test('失败分支保持原文案不变（仅成功分支补后验，不动失败语义）', () {
      // 决策权衡：本轮仅修复"成功但 WC 仍不可用"的隐藏漏洞
      // 失败分支（result.isSuccess == false）保持原 SnackBar，不引入 probeSvnLocation
      expect(
        body.contains(
            "'cleanup 失败: \${result.stderr.isEmpty ? \"未知错误\" : result.stderr}'"),
        isTrue,
        reason: '失败分支文案不变',
      );
    });

    test('role 入参与第二十六/二十九轮预校验风格一致', () {
      // _startMerge 用 role: '源 URL' / '目标工作副本'
      // _testSvnConnectivity 用 role: '源 URL' / '目标工作副本'
      // _runSvnCleanup 用 role: '工作副本'——单 path probe，role 表语境而非区分谁是谁
      expect(body.contains("role: '工作副本',"), isTrue,
          reason: 'cleanup 仅 probe targetWc 一项，role 不必带"目标"前缀');
    });
  });

  group('formatCleanupFeedback resumePrompt 维度（主屏工具栏 vs 暂停态语境分流）', () {
    // 第三十一轮：发现 _svnCleanup（主屏工具栏）跟 _runSvnCleanup（暂停态）
    // 同款 cleanup 但仅 _showSuccess('清理完成')、无 WC 后验，是与第三十轮完美对称的
    // 隐藏漏洞。本组锁 helper 复用契约——同一 helper 用 resumePrompt 入参分流两种语境。
    test('resumePrompt 默认 true（向后兼容暂停态调用）', () {
      // 防御：第三十轮 _runSvnCleanup 调用未传 resumePrompt，必须保持原行为
      expect(
        formatCleanupFeedback(probeError: null),
        '已执行 svn cleanup，可点击"继续"重试',
      );
      expect(
        formatCleanupFeedback(probeError: 'WC 不可用'),
        '已运行 svn cleanup，但工作副本仍不可用：WC 不可用，请手动检查后再继续',
      );
    });

    test('resumePrompt: false + probeError == null → 清理完成，工作副本已可用', () {
      // 主屏工具栏成功文案：不诱导点"继续"，明示 WC 已经过 probe 验证
      expect(
        formatCleanupFeedback(probeError: null, resumePrompt: false),
        '清理完成，工作副本已可用',
      );
    });

    test('resumePrompt: false + probeError == empty string → 清理完成，工作副本已可用', () {
      // empty string 防御：probeSvnLocation 实际不返回 ''，但 helper 不应在边界崩
      expect(
        formatCleanupFeedback(probeError: '', resumePrompt: false),
        '清理完成，工作副本已可用',
      );
    });

    test('resumePrompt: false + probeError 非空 → 警告文案，不诱导继续', () {
      final warn = formatCleanupFeedback(
        probeError: '权限不足',
        resumePrompt: false,
      );
      expect(warn.contains('权限不足'), isTrue, reason: 'probeError 必须原样进入文案');
      expect(warn.contains('请手动检查'), isTrue);
      expect(warn.contains('"继续"'), isFalse,
          reason: '主屏工具栏不在暂停 → 继续语境，警告文案不应诱导点继续');
      expect(warn.contains('再继续'), isFalse,
          reason: 'resumePrompt: false 时 tail 应当是"请手动检查"而非"请手动检查后再继续"');
    });

    test('resumePrompt: true vs false 成功文案首字母不同——视觉语境立辨', () {
      // 暂停态："已执行 svn cleanup，可点击..."（强调动作完成 + 下一步）
      // 主屏  ："清理完成，工作副本已可用"（强调结果可用）
      final paused =
          formatCleanupFeedback(probeError: null, resumePrompt: true);
      final toolbar =
          formatCleanupFeedback(probeError: null, resumePrompt: false);
      expect(paused, isNot(equals(toolbar)),
          reason: '同一 probe 状态在两种语境必须输出不同文案');
      expect(paused.startsWith('已执行 svn cleanup'), isTrue);
      expect(toolbar.startsWith('清理完成'), isTrue);
    });

    test('resumePrompt: true vs false 警告文案 tail 不同', () {
      // 暂停态："...请手动检查后再继续"（暗示用户仍要走继续流程）
      // 主屏  ："...请手动检查"（仅止于检查，无后续动作约束）
      final paused = formatCleanupFeedback(
        probeError: 'X',
        resumePrompt: true,
      );
      final toolbar = formatCleanupFeedback(
        probeError: 'X',
        resumePrompt: false,
      );
      expect(paused.endsWith('请手动检查后再继续'), isTrue);
      expect(toolbar.endsWith('请手动检查'), isTrue);
      expect(toolbar.endsWith('请手动检查后再继续'), isFalse);
    });

    test('两种语境警告文案都含 probeError 原文（不二次翻译）', () {
      // probeError 已经过 formatProbeFailureReason 翻译，helper 不应再加工
      final paused = formatCleanupFeedback(
        probeError: '路径不存在',
        resumePrompt: true,
      );
      final toolbar = formatCleanupFeedback(
        probeError: '路径不存在',
        resumePrompt: false,
      );
      expect(paused.contains('路径不存在'), isTrue);
      expect(toolbar.contains('路径不存在'), isTrue);
    });
  });

  group('_svnCleanup（主屏工具栏）走 formatCleanupFeedback + probeSvnLocation 后验', () {
    // 真 bug：原 _svnCleanup 仅 if (result.isSuccess) _showSuccess('清理完成')，
    // 与第三十轮闭合的 _runSvnCleanup 隐藏漏洞完美对称——cleanup exit 0 不保证 WC 可用。
    // 本组锁主屏入口接线契约：成功路径必须 probe + 走 helper（resumePrompt: false 语境）。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _svnCleanup() async {');
    final body = start > 0 ? src.substring(start, start + 2000) : '';

    test('源代码必须存在 _svnCleanup() 方法', () {
      expect(start, greaterThan(0));
    });

    test('成功分支调 _svnService.probeSvnLocation(targetWc, role: ...) 后验', () {
      expect(
        body.contains(
            "await _svnService.probeSvnLocation(\n          targetWc,\n          role: '工作副本',\n        )"),
        isTrue,
        reason: 'svn cleanup exit 0 不保证 WC 可用，必须用 probeSvnLocation 后验元数据可读',
      );
    });

    test('成功分支调用 formatCleanupFeedback 而非 inline 拼字符串', () {
      expect(
        body.contains('formatCleanupFeedback('),
        isTrue,
        reason: '文案必须走 helper 单测覆盖，不能 inline',
      );
      expect(
        body.contains('probeError: probeError'),
        isTrue,
        reason: 'probeError 直接透传——helper 内部决定 null/empty/非空分流',
      );
    });

    test('helper 调用使用 resumePrompt: false（主屏工具栏语境）', () {
      // 与 _runSvnCleanup（默认 true）的核心差异——主屏不在暂停 → 继续语境
      expect(
        body.contains('resumePrompt: false'),
        isTrue,
        reason: '主屏工具栏 cleanup 不诱导用户点"继续"',
      );
    });

    test('probeSvnLocation 之后保留 mounted 守卫', () {
      // probeSvnLocation 走 svn info 是 await，可能跨多帧；返回时 widget 可能已 dispose
      final after = body.substring(body.indexOf('probeSvnLocation('));
      expect(
        after.contains('if (!mounted) return;'),
        isTrue,
        reason: 'probeSvnLocation 是 await，返回后必须再守一次 mounted',
      );
    });

    test('probe 通过走 _showSuccess、probe 失败走 _showError（视觉立辨）', () {
      // 与 _runSvnCleanup 走同一个 ScaffoldMessenger.showSnackBar 不同——
      // 主屏复用 _showSuccess（绿）/ _showError（红），用户从 SnackBar 颜色立辨
      expect(
        body.contains('_showSuccess(message)'),
        isTrue,
        reason: 'probe 通过应当走 _showSuccess（绿色 SnackBar）',
      );
      expect(
        body.contains('_showError(message)'),
        isTrue,
        reason: 'probe 失败应当走 _showError（红色 SnackBar）',
      );
    });

    test('原"清理完成"字面量已不再 inline（防回归）', () {
      // 第三十一轮前的实现：_showSuccess('清理完成')
      expect(
        body.contains("_showSuccess('清理完成')"),
        isFalse,
        reason: '_svnCleanup 不应再 inline 文案——必须走 helper',
      );
    });

    test('失败分支保持原文案不变（仅成功分支补后验，不动失败语义）', () {
      // 决策权衡：本轮仅修复"成功但 WC 仍不可用"的隐藏漏洞
      // result.isSuccess == false 走 _showError('清理失败: ...') 不变
      expect(
        body.contains("_showError('清理失败: \${result.stderr}')"),
        isTrue,
        reason: '失败分支文案不变',
      );
    });

    test('catch 分支保持原异常文案不变', () {
      // catch (e, stackTrace) → _showError('清理异常: \$e')
      expect(
        body.contains("_showError('清理异常: \$e')"),
        isTrue,
        reason: 'catch 分支保持原异常处理',
      );
    });

    test('cleanup 后 WC 不可用要 AppLogger.ui.error 留痕', () {
      // 防御：probe 失败仅 SnackBar 转瞬即逝，运行日志须留痕便于事后排查
      expect(
        body.contains("AppLogger.ui.error('cleanup 后 WC 仍不可用"),
        isTrue,
        reason: 'probe 失败必须打 ui.error 日志（与 _showError 共同留痕）',
      );
    });
  });

  group('formatUpdateFeedback（svn update 后冲突仍存在补警告）', () {
    // 真 bug：`svn update` 在服务器侧改动与本地修改冲突时仅把文件标 'C' 状态，仍 exit 0。
    // 原 _svnUpdate 只看 result.isSuccess，用户随后启动合并任务又因 'C' 状态文件再次暂停。
    // 本 helper 把"是否还有冲突"语义化为"剩余冲突文件数"两档分流——与
    // formatMarkResolvedFeedback 同款 int 维度（而非 formatCleanupFeedback 的 String? probe 维度）。
    test('remainingConflictCount == 0 → 走原成功文案', () {
      expect(
        formatUpdateFeedback(remainingConflictCount: 0),
        '更新完成，工作副本干净',
      );
    });

    test('默认入参等价于 0 → 兼容空冲突场景', () {
      expect(
        formatUpdateFeedback(),
        '更新完成，工作副本干净',
      );
    });

    test('remainingConflictCount < 0（防御）→ 走成功文案不抛', () {
      // listConflictedFiles 实际不会返回负数，但 helper 接 int 不应在边界上崩
      expect(
        formatUpdateFeedback(remainingConflictCount: -1),
        '更新完成，工作副本干净',
      );
    });

    test('remainingConflictCount == 1 → 警告文案含数字 1', () {
      expect(
        formatUpdateFeedback(remainingConflictCount: 1),
        '已执行 svn update，但仍有 1 个冲突文件，请手动解决',
      );
    });

    test('remainingConflictCount > 1 → 警告文案含具体数字', () {
      expect(
        formatUpdateFeedback(remainingConflictCount: 5),
        '已执行 svn update，但仍有 5 个冲突文件，请手动解决',
      );
    });

    test('成功 vs 警告两档文案不同（视觉立辨）', () {
      final ok = formatUpdateFeedback(remainingConflictCount: 0);
      final warn = formatUpdateFeedback(remainingConflictCount: 3);
      expect(ok == warn, isFalse);
      expect(ok.contains('干净'), isTrue);
      expect(warn.contains('请手动解决'), isTrue);
    });

    test('警告文案明确禁止直接点继续', () {
      // 与 formatMarkResolvedFeedback / formatCleanupFeedback 警告路径同款契约
      final warn = formatUpdateFeedback(remainingConflictCount: 2);
      expect(warn.contains('继续'), isFalse, reason: 'WC 仍有冲突时不应诱导用户点"继续"');
      expect(warn.contains('手动'), isTrue);
    });
  });

  group('_svnUpdate（主屏工具栏）走 formatUpdateFeedback + listConflictedFiles 后验', () {
    // 真 bug：原 _svnUpdate 仅 if (result.isSuccess) _showSuccess('更新完成')，
    // svn update exit 0 时 'C' 状态文件可能仍存在。本组锁主屏入口接线契约：
    // 成功路径必须 listConflictedFiles + 走 helper + 视觉立辨。
    final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
    final start = src.indexOf('Future<void> _svnUpdate() async {');
    final body = start > 0 ? src.substring(start, start + 2000) : '';

    test('源代码必须存在 _svnUpdate() 方法', () {
      expect(start, greaterThan(0));
    });

    test('成功分支调 _svnService.listConflictedFiles(targetWc) 后验', () {
      expect(
        body.contains('await _svnService.listConflictedFiles(targetWc)'),
        isTrue,
        reason: 'svn update exit 0 不保证 WC 干净，必须用 listConflictedFiles 后验',
      );
    });

    test('成功分支调用 formatUpdateFeedback 而非 inline 拼字符串', () {
      expect(
        body.contains('formatUpdateFeedback('),
        isTrue,
        reason: '文案必须走 helper 单测覆盖，不能 inline',
      );
      expect(
        body.contains('remainingConflictCount: conflicts.length'),
        isTrue,
        reason: 'conflicts.length 直接透传——helper 内部决定 0/正数分流',
      );
    });

    test('listConflictedFiles 之后保留 mounted 守卫', () {
      // listConflictedFiles 走 svn status 是 await，可能跨多帧；返回时 widget 可能已 dispose
      final after = body.substring(body.indexOf('listConflictedFiles('));
      expect(
        after.contains('if (!mounted) return;'),
        isTrue,
        reason: 'listConflictedFiles 是 await，返回后必须再守一次 mounted',
      );
    });

    test('无冲突走 _showSuccess、有冲突走 _showError（视觉立辨）', () {
      // 与第三十一轮 _svnCleanup 同款——主屏入口用 _showSuccess（绿）/ _showError（红）
      // 让用户从 SnackBar 颜色立辨"WC 真干净 vs 仍有冲突"
      expect(
        body.contains('_showSuccess(message)'),
        isTrue,
        reason: '无冲突应当走 _showSuccess（绿色 SnackBar）',
      );
      expect(
        body.contains('_showError(message)'),
        isTrue,
        reason: '有冲突应当走 _showError（红色 SnackBar）',
      );
    });

    test('原"更新完成"字面量已不再 inline（防回归）', () {
      // 第三十二轮前的实现：_showSuccess('更新完成')
      expect(
        body.contains("_showSuccess('更新完成')"),
        isFalse,
        reason: '_svnUpdate 不应再 inline 文案——必须走 helper',
      );
    });

    test('失败分支保持原文案不变（仅成功分支补后验，不动失败语义）', () {
      // 决策权衡：本轮仅修复"成功但 WC 仍有冲突"的隐藏漏洞
      // result.isSuccess == false 走 _showError('更新失败: ...') 不变
      expect(
        body.contains("_showError('更新失败: \${result.stderr}')"),
        isTrue,
        reason: '失败分支文案不变',
      );
    });

    test('catch 分支保持原异常文案不变', () {
      // catch (e, stackTrace) → _showError('更新异常: \$e')
      expect(
        body.contains("_showError('更新异常: \$e')"),
        isTrue,
        reason: 'catch 分支保持原异常处理',
      );
    });

    test('update 后仍有冲突要 AppLogger.ui.error 留痕', () {
      // 防御：SnackBar 转瞬即逝，运行日志须留痕便于事后排查
      expect(
        body.contains("AppLogger.ui.error('update 后仍有冲突"),
        isTrue,
        reason: '剩余冲突必须打 ui.error 日志（与 _showError 共同留痕）',
      );
    });

    test('成功分支保留原 _updateMergedStatus 调用（不动现有副作用）', () {
      // 决策权衡：本轮仅补冲突后验，不动"更新成功后刷新 merged 状态"的现有副作用。
      // _updateMergedStatus 必须仍在成功分支被调（无论是否有冲突——已下载到本地的 revision
      // 应当被刷新到 mergeinfo 缓存，便于后续待合并列表反映最新状态）。
      expect(
        body.contains(
            '_updateMergedStatus(sourceUrl, targetWc, forceRefresh: true)'),
        isTrue,
        reason: '更新成功后仍需刷新 merged 状态——本轮不动这条线',
      );
    });
  });

  group('formatPendingAddSnackBar（添加到待合并的反馈数 == 真实新增数）', () {
    // 真 bug：原 _addSelectedToPending 弹 _showSuccess('已添加 $count 个 revision'),
    // count = _selectedRevisions.length；但 addPendingRevisions → mergePendingRevisions
    // 做 union 去重——选中已存在 revision 时实际新增数 < count，但 SnackBar 仍报 count，
    // 与项目其它"反馈数 == 真实数"家族（_showInfo('已清空 N 个待合并 revision') /
    // _showSuccess('已删除任务 #ID')）不一致。本 helper 接 (selectedCount, addedCount)
    // 三档分流给出真实文案。
    test('addedCount == 0 → 全部已存在文案', () {
      expect(
        formatPendingAddSnackBar(selectedCount: 5, addedCount: 0),
        '全部 5 个 revision 已在待合并列表中',
      );
    });

    test('addedCount == selectedCount → 走原文案保兼容', () {
      expect(
        formatPendingAddSnackBar(selectedCount: 3, addedCount: 3),
        '已添加 3 个 revision',
      );
    });

    test('0 < addedCount < selectedCount → 部分跳过文案含具体数字', () {
      expect(
        formatPendingAddSnackBar(selectedCount: 7, addedCount: 4),
        '已添加 4 个 revision（其中 3 个已在列表中跳过）',
      );
    });

    test('addedCount == 1, selectedCount == 1 → 单数走原文案', () {
      expect(
        formatPendingAddSnackBar(selectedCount: 1, addedCount: 1),
        '已添加 1 个 revision',
      );
    });

    test('addedCount == 1, selectedCount == 5 → 4 个跳过文案', () {
      expect(
        formatPendingAddSnackBar(selectedCount: 5, addedCount: 1),
        '已添加 1 个 revision（其中 4 个已在列表中跳过）',
      );
    });

    test('防御 — selectedCount == 0 → addedCount 必然 0 → 第一档文案', () {
      // caller 用 if (_selectedRevisions.isEmpty) 已拦掉空选；本测试仅锁 helper
      // 边界容错——不会崩、不会走错档。
      expect(
        formatPendingAddSnackBar(selectedCount: 0, addedCount: 0),
        '全部 0 个 revision 已在待合并列表中',
      );
    });

    test('lib 字面量锁 — main_screen_v3.dart 引用 helper 而非内联 `已添加 \$count`', () {
      // 锁住"_addSelectedToPending 调 helper 而非内联文案"的契约——回归时若有人
      // 把 helper 调用改回内联 `已添加 $count 个 revision` 字符串，本测试立即报失败。
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      // helper 函数定义存在
      expect(src.contains('String formatPendingAddSnackBar({'), isTrue,
          reason: 'lib 顶层必须有 formatPendingAddSnackBar helper 定义');
      // _addSelectedToPending 调用 helper
      expect(
        src.contains('_showSuccess(formatPendingAddSnackBar('),
        isTrue,
        reason: '_addSelectedToPending 必须把 helper 结果喂给 _showSuccess',
      );
      // _addSelectedToPending 跨 addPendingRevisions 取真实 addedCount
      expect(
        src.contains('final beforeLen = appState.pendingRevisions.length;'),
        isTrue,
        reason: '必须前后取 length 差值算真实新增数',
      );
      expect(
        src.contains(
            'final addedCount = appState.pendingRevisions.length - beforeLen;'),
        isTrue,
        reason: '必须用差值算 addedCount 而非沿用 _selectedRevisions.length',
      );
      // 原内联文案已消失
      expect(
        src.contains("_showSuccess('已添加 \$count 个 revision')"),
        isFalse,
        reason: '原内联文案 `已添加 \$count 个 revision` 必须被 helper 替代',
      );
    });
  });

  group('formatOpenConflictFileFeedback — 打开冲突文件后 SnackBar 文案', () {
    test('单冲突 → 简版文案，不含 1/N 与"继续"提示', () {
      expect(
        formatOpenConflictFileFeedback(
          totalCount: 1,
          openedRelative: 'src/foo.dart',
        ),
        '已打开冲突文件: src/foo.dart',
      );
    });

    test('多冲突 N=2 → 显示 1/2 + 提示改完点继续', () {
      expect(
        formatOpenConflictFileFeedback(
          totalCount: 2,
          openedRelative: 'src/bar.dart',
        ),
        '已打开冲突文件 1/2: src/bar.dart；改完后点"继续"会自动检测剩余冲突',
      );
    });

    test('多冲突 N=10 → 显示 1/10 + 提示改完点继续', () {
      expect(
        formatOpenConflictFileFeedback(
          totalCount: 10,
          openedRelative: 'lib/services/svn_service.dart',
        ),
        '已打开冲突文件 1/10: lib/services/svn_service.dart；改完后点"继续"会自动检测剩余冲突',
      );
    });

    test('防御 — totalCount == 0 → 走单冲突分支（caller 不该传 0，仅边界容错）', () {
      // _openConflictFile 已在外层用 if (conflicted.isEmpty) 拦掉空列表；
      // 本测试仅锁 helper 边界——不崩、不走多冲突档。
      expect(
        formatOpenConflictFileFeedback(
          totalCount: 0,
          openedRelative: 'whatever.dart',
        ),
        '已打开冲突文件: whatever.dart',
      );
    });

    test('lib 字面量锁 — _openConflictFile 在 Process.run 后调 helper 弹 SnackBar', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      // helper 定义存在
      expect(
        src.contains('String formatOpenConflictFileFeedback({'),
        isTrue,
        reason: 'lib 顶层必须有 formatOpenConflictFileFeedback helper 定义',
      );
      // 两档分流字面量
      expect(
        src.contains("'已打开冲突文件: \$openedRelative'"),
        isTrue,
        reason: '单冲突文案字面量必须存在',
      );
      expect(
        src.contains(
            "'已打开冲突文件 1/\$totalCount: \$openedRelative；改完后点\"继续\"会自动检测剩余冲突'"),
        isTrue,
        reason: '多冲突文案字面量必须存在',
      );
      // _openConflictFile 调 helper 而非内联
      expect(
        src.contains('formatOpenConflictFileFeedback('),
        isTrue,
        reason: '_openConflictFile 必须把 helper 结果喂给 SnackBar',
      );
      // Process.run 之后必须有 mounted 守 + SnackBar 反馈块
      // 顺序锁：await Process.run -> if (!mounted) return; -> SnackBar
      final processRunIdx = src.indexOf(
          'await Process.run(command.executable, command.args);\n        if (!mounted) return;');
      expect(processRunIdx, isNot(-1),
          reason: 'Process.run 后必须紧跟 if (!mounted) return; 守卫');
      // helper 在该守卫之后被调用
      final mountedIdx = src.indexOf('if (!mounted) return;', processRunIdx);
      final helperIdx =
          src.indexOf('formatOpenConflictFileFeedback(', mountedIdx);
      expect(helperIdx, greaterThan(mountedIdx),
          reason: 'helper 调用必须在 mounted 守卫之后（同一 _openConflictFile 路径）');
    });
  });

  group('formatLogApplyFailureFeedback（sync 段成功 / apply 段失败的反馈分流，第四十一轮）', () {
    test('addedCount > 0 → 主信息突出"已同步 N 条" + 提示 apply 失败可重试', () {
      expect(
        formatLogApplyFailureFeedback(
          addedCount: 12,
          error: 'database is locked',
        ),
        '日志已同步 12 条，但界面刷新失败: database is locked；'
        '可重试同步或切换源 URL 重新加载',
      );
    });

    test('addedCount > 0 边界单条 — addedCount == 1', () {
      expect(
        formatLogApplyFailureFeedback(
          addedCount: 1,
          error: 'permission denied',
        ),
        '日志已同步 1 条，但界面刷新失败: permission denied；'
        '可重试同步或切换源 URL 重新加载',
      );
    });

    test('addedCount == 0 → 走"无新数据但刷新失败"档（与 noChangeMessage 路径对偶）', () {
      expect(
        formatLogApplyFailureFeedback(
          addedCount: 0,
          error: 'cache service exception',
        ),
        '日志同步完成但界面刷新失败: cache service exception；可切换源 URL 重新加载',
      );
    });

    test('防御 addedCount < 0 → 走 addedCount <= 0 档（caller 不该传负，仅边界容错）', () {
      expect(
        formatLogApplyFailureFeedback(
          addedCount: -1,
          error: 'whatever',
        ),
        '日志同步完成但界面刷新失败: whatever；可切换源 URL 重新加载',
      );
    });

    test('lib 字面量锁 — helper 定义 + _runLogDataAction 拆段使用 helper', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

      // helper 定义存在
      expect(
        src.contains('String formatLogApplyFailureFeedback({'),
        isTrue,
        reason: 'lib 顶层必须有 formatLogApplyFailureFeedback helper 定义',
      );

      // 两档分流字面量
      expect(
        src.contains("'日志已同步 \$addedCount 条，但界面刷新失败: \$error；'"),
        isTrue,
        reason: 'addedCount > 0 文案字面量必须存在',
      );
      expect(
        src.contains("'日志同步完成但界面刷新失败: \$error；可切换源 URL 重新加载'"),
        isTrue,
        reason: 'addedCount <= 0 文案字面量必须存在',
      );

      // _runLogDataAction 拆段：sync 段 catch 与 apply 段 catch 各自独立
      expect(
        src.contains("AppLogger.ui.error('日志数据操作失败（sync 段）'"),
        isTrue,
        reason: 'sync 段必须有独立 catch 块带"sync 段"标签',
      );
      expect(
        src.contains("AppLogger.ui.error('日志数据操作失败（apply 段）'"),
        isTrue,
        reason: 'apply 段必须有独立 catch 块带"apply 段"标签',
      );

      // sync 段失败仍走原 "日志同步失败: \$e" 文案
      expect(
        src.contains("_showError('日志同步失败: \$e')"),
        isTrue,
        reason: 'sync 段失败必须保留"日志同步失败"原文案',
      );

      // apply 段失败必须把 helper 结果喂给 _showError
      expect(
        src.contains('formatLogApplyFailureFeedback('),
        isTrue,
        reason: '_runLogDataAction 必须调 helper 渲染 apply 段失败 SnackBar',
      );
    });

    test('lib 顺序锁 — sync 段 try 在 apply 段 try 之前 + addedCount 在外层声明', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();

      // 定位 _runLogDataAction 方法体——以下一个 top-level method 起点为 endIdx
      // （而非 '\n  }' — 后者会被嵌套 try 的闭合括号干扰）。
      final methodIdx = src.indexOf('Future<void> _runLogDataAction(');
      expect(methodIdx, isNot(-1));
      final methodEndIdx =
          src.indexOf('Future<void> _autoLoadLogsIfPossible(', methodIdx);
      expect(methodEndIdx, greaterThan(methodIdx));
      final methodBody = src.substring(methodIdx, methodEndIdx);

      // addedCount 必须在外层（两个 try 之前）声明，让 apply 段能拿到 sync 段返回值
      final addedCountDeclIdx = methodBody.indexOf('int addedCount = 0;');
      expect(addedCountDeclIdx, isNot(-1),
          reason: 'addedCount 必须在两个 try 之前的外层声明并初始化为 0');

      // sync 段 catch（"sync 段" 标签）必须在 apply 段 catch（"apply 段" 标签）之前
      final syncCatchIdx =
          methodBody.indexOf("AppLogger.ui.error('日志数据操作失败（sync 段）'");
      final applyCatchIdx =
          methodBody.indexOf("AppLogger.ui.error('日志数据操作失败（apply 段）'");
      expect(syncCatchIdx, isNot(-1));
      expect(applyCatchIdx, isNot(-1));
      expect(applyCatchIdx, greaterThan(syncCatchIdx),
          reason: 'sync 段 catch 必须在 apply 段 catch 之前（执行顺序锁）');
      expect(addedCountDeclIdx, lessThan(syncCatchIdx),
          reason: 'addedCount 声明必须在两个 catch 之前');

      // sync 段 catch 内 return —— 让 apply 段不会在 sync 失败后被调
      final syncReturnIdx = methodBody.indexOf('return;', syncCatchIdx);
      expect(syncReturnIdx, lessThan(applyCatchIdx),
          reason: 'sync 段 catch 必须 return，避免 sync 失败后还跑 apply');

      // 旧统一 catch 文案不再存在
      expect(
        methodBody.contains("AppLogger.ui.error('日志数据操作失败',"),
        isFalse,
        reason: '旧统一 catch（无段标签）必须已被拆段替换',
      );
    });
  });

  group('_svnRevert R131 档 3 mounted 守卫（第四十二轮）', () {
    test('lib 字面量锁：showDialog / revert / catch 后必有 mounted 守卫', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final methodIdx = src.indexOf('Future<void> _svnRevert(');
      expect(methodIdx, isNot(-1), reason: '_svnRevert 方法必须存在');
      final methodEndIdx = src.indexOf('Future<void> _svnCleanup(', methodIdx);
      expect(methodEndIdx, isNot(-1));
      final methodBody = src.substring(methodIdx, methodEndIdx);

      // 1) showDialog 之后、_showInfo 之前的 mounted 守卫
      expect(
        methodBody.contains('if (confirmed != true) return;\n'
            '    if (!mounted) return;'),
        isTrue,
        reason: 'showDialog 跨 await 后必须前置 if (!mounted) return;',
      );

      // 2) _wcManager.revert(...) 之后的 mounted 守卫
      expect(
        methodBody.contains('refreshMergeInfo: true,\n'
            '      );\n'
            '\n'
            '      if (!mounted) return;'),
        isTrue,
        reason: '_wcManager.revert(...) 之后必须前置 if (!mounted) return; '
            '再判定 result.isSuccess',
      );

      // 3) catch 块内 _showError 之前的 mounted 守卫
      expect(
        methodBody.contains("AppLogger.ui.error('工作副本还原异常', e, stackTrace);\n"
            '      if (!mounted) return;\n'
            "      _showError('还原异常: \$e');"),
        isTrue,
        reason: 'catch 块内 _showError 之前必须前置 if (!mounted) return;',
      );
    });

    test('lib 顺序锁：mounted 守卫先于对应 SnackBar 调用', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final methodIdx = src.indexOf('Future<void> _svnRevert(');
      final methodEndIdx = src.indexOf('Future<void> _svnCleanup(', methodIdx);
      final methodBody = src.substring(methodIdx, methodEndIdx);

      // mounted 守卫 1（showDialog 后）必须在 _showInfo('正在还原工作副本...') 之前
      final guard1Idx = methodBody
          .indexOf('if (confirmed != true) return;\n    if (!mounted) return;');
      final showInfoIdx = methodBody.indexOf("_showInfo('正在还原工作副本...')");
      expect(guard1Idx, isNot(-1));
      expect(showInfoIdx, isNot(-1));
      expect(guard1Idx, lessThan(showInfoIdx),
          reason: 'showDialog 后的 mounted 守卫必须先于 _showInfo');

      // mounted 守卫 2（revert 后）必须在 _showSuccess('还原完成') 与 _showError('还原失败...') 之前
      final guard2Idx = methodBody.indexOf(
          'refreshMergeInfo: true,\n      );\n\n      if (!mounted) return;');
      final showSuccessIdx = methodBody.indexOf("_showSuccess('还原完成')");
      final showErrorBranchIdx = methodBody.indexOf("_showError('还原失败:");
      expect(guard2Idx, isNot(-1));
      expect(showSuccessIdx, isNot(-1));
      expect(showErrorBranchIdx, isNot(-1));
      expect(guard2Idx, lessThan(showSuccessIdx),
          reason: 'revert 后的 mounted 守卫必须先于 _showSuccess');
      expect(guard2Idx, lessThan(showErrorBranchIdx),
          reason: 'revert 后的 mounted 守卫必须先于 isSuccess=false 分支的 _showError');

      // mounted 守卫 3（catch 内）必须在 catch 内 _showError('还原异常: $e') 之前
      final catchGuardIdx = methodBody.indexOf(
          "AppLogger.ui.error('工作副本还原异常', e, stackTrace);\n      if (!mounted) return;");
      final catchShowErrorIdx = methodBody.indexOf("_showError('还原异常:");
      expect(catchGuardIdx, isNot(-1));
      expect(catchShowErrorIdx, isNot(-1));
      expect(catchGuardIdx, lessThan(catchShowErrorIdx),
          reason: 'catch 内 mounted 守卫必须先于 _showError');
    });
  });

  group('_svnUpdate / _svnCleanup R131 档 3 mounted 守卫（第四十三轮）', () {
    test('_svnUpdate lib 字面量锁：isSuccess=false 分支 + catch 块前置 mounted 守卫', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final methodIdx = src.indexOf('Future<void> _svnUpdate(');
      expect(methodIdx, isNot(-1), reason: '_svnUpdate 方法必须存在');
      final methodEndIdx = src.indexOf('Future<void> _svnRevert(', methodIdx);
      expect(methodEndIdx, isNot(-1));
      final methodBody = src.substring(methodIdx, methodEndIdx);

      // isSuccess=false 分支 _showError 之前的 mounted 守卫
      expect(
        methodBody
            .contains("AppLogger.ui.error('工作副本更新失败: \${result.stderr}');\n"
                '        if (!mounted) return;\n'
                "        _showError('更新失败: \${result.stderr}');"),
        isTrue,
        reason: 'isSuccess=false 分支 _showError 之前必须前置 if (!mounted) return;',
      );

      // catch 块内 _showError 之前的 mounted 守卫
      expect(
        methodBody.contains("AppLogger.ui.error('工作副本更新异常', e, stackTrace);\n"
            '      if (!mounted) return;\n'
            "      _showError('更新异常: \$e');"),
        isTrue,
        reason: 'catch 块内 _showError 之前必须前置 if (!mounted) return;',
      );
    });

    test('_svnUpdate lib 顺序锁：mounted 守卫先于 SnackBar 调用', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final methodIdx = src.indexOf('Future<void> _svnUpdate(');
      final methodEndIdx = src.indexOf('Future<void> _svnRevert(', methodIdx);
      final methodBody = src.substring(methodIdx, methodEndIdx);

      // isSuccess=false 分支
      final failGuardIdx = methodBody.indexOf(
          "AppLogger.ui.error('工作副本更新失败: \${result.stderr}');\n        if (!mounted) return;");
      final failShowErrorIdx = methodBody.indexOf("_showError('更新失败:");
      expect(failGuardIdx, isNot(-1));
      expect(failShowErrorIdx, isNot(-1));
      expect(failGuardIdx, lessThan(failShowErrorIdx),
          reason: 'isSuccess=false 分支 mounted 守卫必须先于 _showError');

      // catch 块
      final catchGuardIdx = methodBody.indexOf(
          "AppLogger.ui.error('工作副本更新异常', e, stackTrace);\n      if (!mounted) return;");
      final catchShowErrorIdx = methodBody.indexOf("_showError('更新异常:");
      expect(catchGuardIdx, isNot(-1));
      expect(catchShowErrorIdx, isNot(-1));
      expect(catchGuardIdx, lessThan(catchShowErrorIdx),
          reason: 'catch 内 mounted 守卫必须先于 _showError');
    });

    test('_svnCleanup lib 字面量锁：isSuccess=false 分支 + catch 块前置 mounted 守卫', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final methodIdx = src.indexOf('Future<void> _svnCleanup(');
      expect(methodIdx, isNot(-1), reason: '_svnCleanup 方法必须存在');
      final methodEndIdx =
          src.indexOf('Future<void> _openSettings(', methodIdx);
      expect(methodEndIdx, isNot(-1));
      final methodBody = src.substring(methodIdx, methodEndIdx);

      expect(
        methodBody
            .contains("AppLogger.ui.error('工作副本清理失败: \${result.stderr}');\n"
                '        if (!mounted) return;\n'
                "        _showError('清理失败: \${result.stderr}');"),
        isTrue,
        reason: 'isSuccess=false 分支 _showError 之前必须前置 if (!mounted) return;',
      );

      expect(
        methodBody.contains("AppLogger.ui.error('工作副本清理异常', e, stackTrace);\n"
            '      if (!mounted) return;\n'
            "      _showError('清理异常: \$e');"),
        isTrue,
        reason: 'catch 块内 _showError 之前必须前置 if (!mounted) return;',
      );
    });

    test('_svnCleanup lib 顺序锁：mounted 守卫先于 SnackBar 调用', () {
      final src = File('lib/screens/main_screen_v3.dart').readAsStringSync();
      final methodIdx = src.indexOf('Future<void> _svnCleanup(');
      final methodEndIdx =
          src.indexOf('Future<void> _openSettings(', methodIdx);
      final methodBody = src.substring(methodIdx, methodEndIdx);

      final failGuardIdx = methodBody.indexOf(
          "AppLogger.ui.error('工作副本清理失败: \${result.stderr}');\n        if (!mounted) return;");
      final failShowErrorIdx = methodBody.indexOf("_showError('清理失败:");
      expect(failGuardIdx, isNot(-1));
      expect(failShowErrorIdx, isNot(-1));
      expect(failGuardIdx, lessThan(failShowErrorIdx),
          reason: 'isSuccess=false 分支 mounted 守卫必须先于 _showError');

      final catchGuardIdx = methodBody.indexOf(
          "AppLogger.ui.error('工作副本清理异常', e, stackTrace);\n      if (!mounted) return;");
      final catchShowErrorIdx = methodBody.indexOf("_showError('清理异常:");
      expect(catchGuardIdx, isNot(-1));
      expect(catchShowErrorIdx, isNot(-1));
      expect(catchGuardIdx, lessThan(catchShowErrorIdx),
          reason: 'catch 内 mounted 守卫必须先于 _showError');
    });
  });
}
