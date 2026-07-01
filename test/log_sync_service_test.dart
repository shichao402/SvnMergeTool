import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/log_entry.dart';
import 'package:svn_auto_merge/services/log_sync_service.dart';

LogEntry _entry(int revision) => LogEntry(
      revision: revision,
      author: 'a',
      date: '2026-01-01T00:00:00Z',
      title: 't',
      message: 'm',
    );

void main() {
  group('planSyncFromHead', () {
    test('null head revision → skip', () {
      final plan = planSyncFromHead(
        headRevision: null,
        cachedStartRevision: null,
        limit: 100,
      );
      expect(plan.skip, isTrue);
      expect(plan.fetchCount, 0);
      expect(plan.startRevision, isNull);
      expect(plan.truncateAtRevision, isNull);
    });

    test('non-positive head revision → skip', () {
      // 极端防御：服务器返回 0 / 负数被视作不可用，不会触发拉取。
      expect(
        planSyncFromHead(headRevision: 0, cachedStartRevision: 100, limit: 50)
            .skip,
        isTrue,
      );
      expect(
        planSyncFromHead(headRevision: -1, cachedStartRevision: 100, limit: 50)
            .skip,
        isTrue,
      );
    });

    test('empty cache → full pull from HEAD without truncation', () {
      final plan = planSyncFromHead(
        headRevision: 1000,
        cachedStartRevision: null,
        limit: 50,
      );
      expect(plan.skip, isFalse);
      expect(plan.fetchCount, 50);
      expect(plan.startRevision, isNull); // 让 SVN 自动从 HEAD 起
      expect(plan.truncateAtRevision, isNull);
    });

    test('head equals cached start → gap == 0 → skip', () {
      final plan = planSyncFromHead(
        headRevision: 1000,
        cachedStartRevision: 1000,
        limit: 50,
      );
      expect(plan.skip, isTrue);
    });

    test('head below cached start → negative gap → skip', () {
      // 不应该出现，但防御性：仍然 skip 而不是抛错或拉负数条。
      final plan = planSyncFromHead(
        headRevision: 990,
        cachedStartRevision: 1000,
        limit: 50,
      );
      expect(plan.skip, isTrue);
    });

    test('gap less than limit → fetch gap plus cached boundary revision', () {
      final plan = planSyncFromHead(
        headRevision: 1010,
        cachedStartRevision: 1000,
        limit: 50,
      );
      expect(plan.skip, isFalse);
      expect(plan.fetchCount, 11); // gap = 10，额外包含 r1000 边界
      expect(plan.startRevision, 1010);
      expect(plan.truncateAtRevision, 1000);
    });

    test('gap larger than limit → fetch limit and truncate at cached start',
        () {
      final plan = planSyncFromHead(
        headRevision: 2000,
        cachedStartRevision: 1000,
        limit: 50,
      );
      expect(plan.skip, isFalse);
      expect(plan.fetchCount, 50);
      expect(plan.startRevision, 2000);
      expect(plan.truncateAtRevision, 1000);
    });

    test('gap exactly equal to limit → fetch the full gap', () {
      final plan = planSyncFromHead(
        headRevision: 1050,
        cachedStartRevision: 1000,
        limit: 50,
      );
      expect(plan.fetchCount, 50);
      expect(plan.startRevision, 1050);
    });

    test('limit <= 0 throws ArgumentError', () {
      expect(
        () => planSyncFromHead(
            headRevision: 100, cachedStartRevision: null, limit: 0),
        throwsArgumentError,
      );
      expect(
        () => planSyncFromHead(
            headRevision: 100, cachedStartRevision: null, limit: -3),
        throwsArgumentError,
      );
    });
  });

  group('planLoadMore', () {
    test('no cached range → fallback to head', () {
      final plan = planLoadMore(cachedEndRevision: null, branchPoint: null);
      expect(plan.fallbackToHead, isTrue);
      expect(plan.skipAtBranchPoint, isFalse);
      expect(plan.startRevision, isNull);
    });

    test('no cached range with branch point set → still fallback to head', () {
      // 缓存为空时，分支点不影响决策——仍然走 fallback。
      final plan = planLoadMore(cachedEndRevision: null, branchPoint: 500);
      expect(plan.fallbackToHead, isTrue);
    });

    test('cached range present, no branch point → continue loading', () {
      final plan = planLoadMore(cachedEndRevision: 800, branchPoint: null);
      expect(plan.fallbackToHead, isFalse);
      expect(plan.skipAtBranchPoint, isFalse);
      expect(plan.startRevision, 800);
    });

    test('cached end equals branch point → already at boundary, skip', () {
      // <= 边界视为已到达：保持与原实现一致。
      final plan = planLoadMore(cachedEndRevision: 500, branchPoint: 500);
      expect(plan.fallbackToHead, isFalse);
      expect(plan.skipAtBranchPoint, isTrue);
      expect(plan.startRevision, 500);
    });

    test('cached end below branch point → past boundary, skip', () {
      final plan = planLoadMore(cachedEndRevision: 400, branchPoint: 500);
      expect(plan.skipAtBranchPoint, isTrue);
    });

    test('cached end above branch point → still room to load', () {
      final plan = planLoadMore(cachedEndRevision: 600, branchPoint: 500);
      expect(plan.skipAtBranchPoint, isFalse);
      expect(plan.startRevision, 600);
    });
  });

  group('truncateEntriesAtRevision', () {
    test('空列表 → 空', () {
      expect(truncateEntriesAtRevision([], 100), isEmpty);
    });

    test('所有 revision < threshold → 空', () {
      final entries = [_entry(50), _entry(60), _entry(70)];
      expect(truncateEntriesAtRevision(entries, 100), isEmpty);
    });

    test('所有 revision >= threshold → 全保留', () {
      final entries = [_entry(100), _entry(150), _entry(200)];
      final result = truncateEntriesAtRevision(entries, 100);
      expect(result.map((e) => e.revision), [100, 150, 200]);
    });

    test('threshold 等于某条 entry.revision → 该条**包含**在内（锁定 >= 而非 >）', () {
      // 这是核心契约：源代码注释明确强调 ">=" 而非 ">"，因为 LogCacheService 用
      // INSERT OR REPLACE 处理重复，必须保证 earliestRevision == latestRange.startRevision
      // 的区间连续性。任何把 >= 改成 > 的"清理"都会让这条测试红。
      final entries = [_entry(99), _entry(100), _entry(101)];
      final result = truncateEntriesAtRevision(entries, 100);
      expect(result.map((e) => e.revision), [100, 101]);
    });

    test('混合：部分 >、部分 ==、部分 < threshold → 只保留 >=', () {
      final entries = [
        _entry(50),
        _entry(99),
        _entry(100), // boundary
        _entry(150),
        _entry(200),
      ];
      final result = truncateEntriesAtRevision(entries, 100);
      expect(result.map((e) => e.revision), [100, 150, 200]);
    });

    test('threshold = 0 → 全保留（实际 revision 都 > 0）', () {
      final entries = [_entry(1), _entry(50), _entry(100)];
      expect(truncateEntriesAtRevision(entries, 0).length, 3);
    });

    test('保留输入顺序（不做排序）', () {
      // SVN reverseOrder=true 下 entries 是「从大到小」，截断后仍保持原顺序
      final entries = [_entry(200), _entry(150), _entry(100), _entry(50)];
      final result = truncateEntriesAtRevision(entries, 100);
      expect(result.map((e) => e.revision), [200, 150, 100]);
    });

    test('返回新 List，不复用入参引用（避免调用方意外修改）', () {
      final entries = [_entry(100), _entry(200)];
      final result = truncateEntriesAtRevision(entries, 100);
      expect(identical(result, entries), isFalse);
    });
  });

  group('formatSyncLogsHeaderLines', () {
    test('完整路径：5 行固定顺序', () {
      final lines = formatSyncLogsHeaderLines(
        sourceUrl: 'svn://repo/trunk',
        limit: 50,
        stopOnCopy: true,
        targetWorkingDirectory: '/tmp/wc',
        loadMore: false,
      );
      expect(lines, [
        '  源 URL: svn://repo/trunk',
        '  限制条数: 50',
        '  stopOnCopy: true',
        '  目标工作副本: /tmp/wc',
        '  模式: 刷新最新（从HEAD开始）',
      ]);
    });

    test('loadMore=true → 模式行走"加载更多"长描述', () {
      final lines = formatSyncLogsHeaderLines(
        sourceUrl: 'u',
        limit: 1,
        stopOnCopy: false,
        targetWorkingDirectory: 'wc',
        loadMore: true,
      );
      expect(lines.last, '  模式: 加载更多（从最新区间终点继续）');
    });

    test('targetWorkingDirectory=null → 显示"未指定"', () {
      final lines = formatSyncLogsHeaderLines(
        sourceUrl: 'u',
        limit: 1,
        stopOnCopy: false,
        targetWorkingDirectory: null,
        loadMore: false,
      );
      expect(lines[3], '  目标工作副本: 未指定');
    });

    test('targetWorkingDirectory="" → 保留空字符串（不走 ?? 分支）', () {
      // 契约：?? 仅对 null 兜底；空串说明调用方已显式传入"已指定但为空"
      final lines = formatSyncLogsHeaderLines(
        sourceUrl: 'u',
        limit: 1,
        stopOnCopy: false,
        targetWorkingDirectory: '',
        loadMore: false,
      );
      expect(lines[3], '  目标工作副本: ');
    });

    test('总是返回 5 行', () {
      expect(
        formatSyncLogsHeaderLines(
          sourceUrl: 'u',
          limit: 1,
          stopOnCopy: false,
          targetWorkingDirectory: null,
          loadMore: false,
        ).length,
        5,
      );
    });

    test('每行以两空格缩进', () {
      final lines = formatSyncLogsHeaderLines(
        sourceUrl: 'u',
        limit: 1,
        stopOnCopy: false,
        targetWorkingDirectory: 'w',
        loadMore: false,
      );
      for (final line in lines) {
        expect(line.startsWith('  '), isTrue, reason: line);
      }
    });
  });

  group('源日志同步与目标工作副本解耦', () {
    final source = File('lib/services/log_sync_service.dart').readAsStringSync();

    test('syncFromHead 不接受工作目录参数', () {
      final start = source.indexOf('Future<int> syncFromHead({');
      final end = source.indexOf('}) async {', start);
      final signature = source.substring(start, end);

      expect(signature.contains('workingDirectory'), isFalse);
      expect(signature.contains('targetWorkingDirectory'), isFalse);
    });

    test('syncFromHead 内部调用 svn log 不传 workingDirectory', () {
      final start = source.indexOf('Future<int> syncFromHead({');
      final end = source.indexOf('  /// 获取 HEAD revision', start);
      final body = source.substring(start, end);

      expect(body.contains('workingDirectory:'), isFalse);
    });

    test('syncLogs 抓取源日志时不把目标工作副本作为 svn log cwd', () {
      final start = source.indexOf('Future<int> syncLogs({');
      final end = source.indexOf('  /// 查找分支点', start);
      final body = source.substring(start, end);
      final fetchLogStart = body.indexOf('final rawLog = await _svnService.log(');
      final fetchLogEnd = body.indexOf(');', fetchLogStart);
      final fetchLogCall = body.substring(fetchLogStart, fetchLogEnd);

      expect(fetchLogCall.contains('workingDirectory:'), isFalse);
      expect(body.contains('targetWorkingDirectory:'), isTrue,
          reason: '目标工作副本只应保留在 syncLogs 参数和分支点判断里');
    });
  });

  group('formatSyncLogsFetchLines', () {
    test('完整路径：5 行固定顺序', () {
      final lines = formatSyncLogsFetchLines(
        sourceUrl: 'svn://repo/trunk',
        startRevision: 200,
        limit: 50,
        branchPoint: 100,
      );
      expect(lines, [
        '  源 URL: svn://repo/trunk',
        '  起始版本: r200',
        '  方向: 向更旧版本',
        '  限制条数: 50',
        '  分支点: r100',
      ]);
    });

    test('startRevision=null → 显示 "HEAD（最新）"', () {
      final lines = formatSyncLogsFetchLines(
        sourceUrl: 'u',
        startRevision: null,
        limit: 1,
        branchPoint: null,
      );
      expect(lines[1], '  起始版本: HEAD（最新）');
    });

    test('branchPoint=null → 显示 "无"', () {
      final lines = formatSyncLogsFetchLines(
        sourceUrl: 'u',
        startRevision: 1,
        limit: 1,
        branchPoint: null,
      );
      expect(lines[4], '  分支点: 无');
    });

    test(r'startRevision=0 也走 r$X 分支（不会被 null 截胡）', () {
      // 防止有人把 `!= null` 改成 `!= 0` 之类的"优化"
      final lines = formatSyncLogsFetchLines(
        sourceUrl: 'u',
        startRevision: 0,
        limit: 1,
        branchPoint: 0,
      );
      expect(lines[1], '  起始版本: r0');
      expect(lines[4], '  分支点: r0');
    });

    test('方向行恒为常量"向更旧版本"', () {
      // 契约：本函数不暴露方向开关——syncLogs 只走 reverseOrder=true
      final lines = formatSyncLogsFetchLines(
        sourceUrl: 'u',
        startRevision: null,
        limit: 1,
        branchPoint: null,
      );
      expect(lines[2], '  方向: 向更旧版本');
    });

    test('总是返回 5 行', () {
      expect(
        formatSyncLogsFetchLines(
          sourceUrl: 'u',
          startRevision: null,
          limit: 1,
          branchPoint: null,
        ).length,
        5,
      );
    });
  });

  group('isHeadRevisionValid', () {
    // 真值表：null / 0 / 负 / 正 四个语义角点
    test('null → false（HEAD 不可用）', () {
      expect(isHeadRevisionValid(null), isFalse);
    });

    test('0 → false（SVN r0 是仓库虚拟空版本，不视为可用）', () {
      // 边界值：曾经的 `< 0` 误写会让 r0 错误通过——本测试锁定 `<= 0` 含义
      expect(isHeadRevisionValid(0), isFalse);
    });

    test('-1 → false（防御性，正常 SVN 不返回负值但仍锁住语义）', () {
      expect(isHeadRevisionValid(-1), isFalse);
    });

    test('1 → true（最小合法 revision）', () {
      // 边界：曾经的 `> 1` 误写会让最小合法 r1 错误失败
      expect(isHeadRevisionValid(1), isTrue);
    });

    test('大数（int 范围内）→ true', () {
      expect(isHeadRevisionValid(1 << 30), isTrue);
    });

    // #15 反向断言锁契约边界：`<= 0` 而不是 `< 0`
    test('0 与 1 跨越阈值（>= vs > 锁定）', () {
      // 如果谓词被误改成 `revision >= 0`（含 0），这条会红
      expect(isHeadRevisionValid(0), isFalse);
      expect(isHeadRevisionValid(1), isTrue);
    });

    // #9 形似但语义不同：与 planSyncFromHead 的 `limit <= 0` 反向断言
    test('与 planSyncFromHead 的 limit 校验形似但语义独立', () {
      // limit=0 在 planSyncFromHead 走 ArgumentError 路径，
      // headRevision=0 在 planSyncFromHead 走 skip=true 路径——
      // 两者都触发"无效输入"，但**出错动作完全不同**：异常 vs skip。
      // 锁定本谓词只锁 head revision 语义，不暗示与 limit 共享判定。
      expect(isHeadRevisionValid(0), isFalse);
      // limit=0 在 plan 中抛 ArgumentError
      expect(
        () => planSyncFromHead(
          headRevision: 100,
          cachedStartRevision: null,
          limit: 0,
        ),
        throwsArgumentError,
      );
    });

    // 与两处 caller 的等价性反向断言：
    // 1) planSyncFromHead 在 headRevision=null/0/负 时返回 skip=true plan
    // 2) syncLogs 步骤 1 的判定走相同语义（caller 行为不同但判定结果一致）
    test('与 planSyncFromHead 的 skip=true 角点等价', () {
      // 这条锁住"helper 抽出后行为不变"——三个无效角点都让 plan.skip=true
      for (final invalid in <int?>[null, 0, -1]) {
        final plan = planSyncFromHead(
          headRevision: invalid,
          cachedStartRevision: null,
          limit: 100,
        );
        expect(plan.skip, isTrue,
            reason: 'invalid head=$invalid should skip');
        expect(isHeadRevisionValid(invalid), isFalse,
            reason: 'invalid head=$invalid predicate should be false');
      }
      // 反向：合法 head + 空缓存 → 不 skip
      final ok = planSyncFromHead(
        headRevision: 100,
        cachedStartRevision: null,
        limit: 50,
      );
      expect(ok.skip, isFalse);
      expect(isHeadRevisionValid(100), isTrue);
    });
  });
}
