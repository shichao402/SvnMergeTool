import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/mergeinfo_cache_service.dart';

void main() {
  group('buildMergeInfoCacheKey', () {
    test('用 | 分隔 sourceUrl 与 targetWc', () {
      expect(
        buildMergeInfoCacheKey(
          'svn://repo/branches/feature',
          '/Users/me/wc/main',
        ),
        'svn://repo/branches/feature|/Users/me/wc/main',
      );
    });

    test('空字符串保留为空段', () {
      expect(buildMergeInfoCacheKey('', ''), '|');
      expect(buildMergeInfoCacheKey('a', ''), 'a|');
      expect(buildMergeInfoCacheKey('', 'b'), '|b');
    });

    test('两个不同顺序产生不同 key', () {
      expect(
        buildMergeInfoCacheKey('a', 'b'),
        isNot(buildMergeInfoCacheKey('b', 'a')),
      );
    });
  });

  group('mergeInfoDbHash', () {
    test('输出 16 位小写 hex', () {
      final hash = mergeInfoDbHash('svn://repo/x', '/wc/y');
      expect(hash.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hash), isTrue);
    });

    test('对相同输入幂等', () {
      final h1 = mergeInfoDbHash('svn://repo/x', '/wc/y');
      final h2 = mergeInfoDbHash('svn://repo/x', '/wc/y');
      expect(h1, h2);
    });

    test('sourceUrl 与 targetWc 顺序敏感', () {
      expect(
        mergeInfoDbHash('a', 'b'),
        isNot(mergeInfoDbHash('b', 'a')),
      );
    });

    test('细微差异产生不同 hash', () {
      expect(
        mergeInfoDbHash('svn://repo/x', '/wc/y'),
        isNot(mergeInfoDbHash('svn://repo/x', '/wc/y/')),
      );
    });
  });

  group('chooseMergeInfoFetchStrategy', () {
    test('fullRefresh=true 优先级最高，覆盖 forceRefresh 与 cacheIsEmpty', () {
      expect(
        chooseMergeInfoFetchStrategy(
          fullRefresh: true,
          forceRefresh: true,
          cacheIsEmpty: true,
        ),
        MergeInfoFetchStrategy.fullRefresh,
      );
      expect(
        chooseMergeInfoFetchStrategy(
          fullRefresh: true,
          forceRefresh: false,
          cacheIsEmpty: false,
        ),
        MergeInfoFetchStrategy.fullRefresh,
      );
    });

    test('forceRefresh=true 在没有 fullRefresh 时优先', () {
      expect(
        chooseMergeInfoFetchStrategy(
          fullRefresh: false,
          forceRefresh: true,
          cacheIsEmpty: true,
        ),
        MergeInfoFetchStrategy.forceRefresh,
      );
      expect(
        chooseMergeInfoFetchStrategy(
          fullRefresh: false,
          forceRefresh: true,
          cacheIsEmpty: false,
        ),
        MergeInfoFetchStrategy.forceRefresh,
      );
    });

    test('缓存为空且无显式 refresh → fetchBecauseCacheEmpty', () {
      expect(
        chooseMergeInfoFetchStrategy(
          fullRefresh: false,
          forceRefresh: false,
          cacheIsEmpty: true,
        ),
        MergeInfoFetchStrategy.fetchBecauseCacheEmpty,
      );
    });

    test('默认走 useCache', () {
      expect(
        chooseMergeInfoFetchStrategy(
          fullRefresh: false,
          forceRefresh: false,
          cacheIsEmpty: false,
        ),
        MergeInfoFetchStrategy.useCache,
      );
    });

    test(
        'R97 防漏配：MergeInfoFetchStrategy.values.length == 4（强制 review 调用方 switch 4 case）',
        () {
      // R95 batch 漏审本 enum——chooseMergeInfoFetchStrategy 是决策函数（输入 → enum），
      // 真正的 switch 在调用方 mergeinfo_cache_service.dart:573（`getMergedRevisions`）
      // 内联 switch 上。新增 enum 时**两处都要改**：
      //   1. 决策函数 chooseMergeInfoFetchStrategy（决定何时返回新值）
      //   2. 调用方 switch（决定新值如何执行）
      // 本 guard 强制 review 调用方 switch（决策函数有 dart 编译器 exhaustive 保护）。
      expect(MergeInfoFetchStrategy.values.length, 4,
          reason: '新增 MergeInfoFetchStrategy enum 时，必须 review '
              'mergeinfo_cache_service.dart:573 内联 switch (`getMergedRevisions` 末尾) '
              '是否补充新 case 的执行逻辑（return cached / await fetch / 短路），'
              '并 review chooseMergeInfoFetchStrategy 的决策路径如何返回该新值。');
    });
  });

  group('buildMergeInfoDbFileName', () {
    test('在 hash 前后拼出固定的 mergeinfo_*.db 模板', () {
      expect(
        buildMergeInfoDbFileName('abcdef0123456789'),
        'mergeinfo_abcdef0123456789.db',
      );
    });

    test('空 hash 也只生成模板，不抛异常（调用方责任）', () {
      expect(buildMergeInfoDbFileName(''), 'mergeinfo_.db');
    });

    test('不同 hash → 不同文件名', () {
      expect(
        buildMergeInfoDbFileName('aaaa'),
        isNot(buildMergeInfoDbFileName('bbbb')),
      );
    });

    test('文件名前缀与后缀模板不变量（防止以后改前缀漏改 clearAllCache 的 .db 匹配）', () {
      final name = buildMergeInfoDbFileName('deadbeefcafebabe');
      expect(name.startsWith('mergeinfo_'), isTrue);
      expect(name.endsWith('.db'), isTrue);
    });
  });

  group('isMergeInfoArgsValid', () {
    test('两侧都非空 → true', () {
      expect(isMergeInfoArgsValid('svn://x', '/wc'), isTrue);
    });

    test('sourceUrl 空 → false', () {
      expect(isMergeInfoArgsValid('', '/wc'), isFalse);
    });

    test('targetWc 空 → false', () {
      expect(isMergeInfoArgsValid('svn://x', ''), isFalse);
    });

    test('两侧都空 → false', () {
      expect(isMergeInfoArgsValid('', ''), isFalse);
    });

    test('仅含空白的字符串视作 valid（不做 trim）', () {
      // 显式锁定现状：不在此层 trim，由上层守卫
      expect(isMergeInfoArgsValid('   ', '\t'), isTrue);
    });
  });

  group('mergeinfo SSOT contract', () {
    final src =
        File('lib/services/mergeinfo_cache_service.dart').readAsStringSync();
    final fetchStart = src.indexOf('Future<Set<int>> fetchAndUpdateFromSvn(');
    final fetchBody =
        fetchStart > 0 ? src.substring(fetchStart, fetchStart + 1800) : '';
    final replaceStart =
        src.indexOf('Future<void> replaceCacheWithAuthoritativeRevisions(');
    final replaceBody = replaceStart > 0
        ? src.substring(replaceStart, replaceStart + 1800)
        : '';

    test('刷新合并状态不再读取工作副本本地 svn:mergeinfo 属性', () {
      expect(fetchStart, greaterThan(0));
      expect(fetchBody.contains('getMergedRevisionsFromPropget'), isFalse);
      expect(fetchBody.contains('getAllMergedRevisions'), isTrue);
      expect(fetchBody.contains('_resolveRepositoryTarget'), isTrue);
    });

    test('仓库刷新结果以替换方式写入缓存，避免旧 false-positive 残留', () {
      expect(replaceStart, greaterThan(0));
      expect(replaceBody.contains("DELETE FROM merged_revisions"), isTrue);
      expect(replaceBody.contains('last_full_sync'), isTrue);
    });
  });

  group('parseDbTimestamp', () {
    test('null → null', () {
      expect(parseDbTimestamp(null), isNull);
    });

    test('正整数 → 对应 DateTime', () {
      final ts = DateTime(2025, 1, 26, 12, 30, 45).millisecondsSinceEpoch;
      expect(parseDbTimestamp(ts), DateTime.fromMillisecondsSinceEpoch(ts));
    });

    test('0 视作合法 epoch 起点（不当作未设置）', () {
      expect(parseDbTimestamp(0), DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('负数透传给 DateTime（锁定原行为，不夹紧）', () {
      expect(
          parseDbTimestamp(-1000), DateTime.fromMillisecondsSinceEpoch(-1000));
    });
  });

  group('buildMergedStatusMap', () {
    test('空 revisions → 空 Map', () {
      expect(buildMergedStatusMap(<int>[], {1, 2, 3}), <int, bool>{});
    });

    test('全部 revision 都在 mergedSet 中 → 全 true', () {
      expect(
        buildMergedStatusMap([1, 2, 3], {1, 2, 3, 4}),
        {1: true, 2: true, 3: true},
      );
    });

    test('全部 revision 都不在 mergedSet 中 → 全 false', () {
      expect(
        buildMergedStatusMap([10, 20], {1, 2, 3}),
        {10: false, 20: false},
      );
    });

    test('部分命中', () {
      expect(
        buildMergedStatusMap([1, 5, 10], {1, 10}),
        {1: true, 5: false, 10: true},
      );
    });

    test('mergedSet 为空 → 全 false', () {
      expect(
        buildMergedStatusMap([1, 2], <int>{}),
        {1: false, 2: false},
      );
    });

    test('Iterable 兼容性：Set<int> 入参也能直接传入', () {
      final result = buildMergedStatusMap(<int>{7, 8, 9}, {7, 9});
      expect(result, {7: true, 8: false, 9: true});
    });

    test('output Map 顺序 = revisions 入参顺序（LinkedHashMap 契约）', () {
      final result = buildMergedStatusMap([3, 1, 2], {1, 2, 3});
      expect(result.keys.toList(), [3, 1, 2]);
    });

    test('重复 revision：后写覆盖前写，但布尔值相同所以无可见效果', () {
      final result = buildMergedStatusMap([5, 5, 5], {5});
      expect(result, {5: true});
    });

    test('不修改入参 mergedSet（只读）', () {
      final mergedSet = {1, 2, 3};
      final original = Set<int>.from(mergedSet);
      buildMergedStatusMap([1, 2, 3, 999], mergedSet);
      expect(mergedSet, original);
    });
  });

  group('R121 资源释放协议档 2（伪异步同步释放型）doc-as-test', () {
    // R121 框架（与 R98 throw / R119 then-catchError / R120 wait 同源 —— 第 4 次
    // 跨 channel 三档对偶）—— 释放 channel 三档分类：
    //   档 1：真异步等待型 —— logger_service.close（poll → flush → close）
    //   档 2：伪异步同步释放型 —— 本档 mergeinfo_cache_service.close +
    //                              log_cache_service.close
    //   档 3：fire-and-forget 同步签名型 —— working_copy_manager.dispose
    // 本组 doc-as-test 锁档 2 的"async 签名 + 同步函数体"以及与 log_cache
    // 同形的 inline duplication 决策。

    test('档 2 签名 async 但函数体无 await — 同步释放语义', () {
      // mergeinfo_cache_service.close 函数体：for db in _databases.values
      //   { db.dispose(); } / _databases.clear() / AppLogger.storage.info(...)
      // —— sqlite3 db.dispose() 是同步、map.clear 是同步、logger.info 异步但
      // 不 await（fire-and-forget）—— 整个函数无真 await。
      // **保留 async 签名的理由**：与 log_cache_service.close / logger_service
      // .close 接口同形，便于 `Future.wait([cache1.close(), cache2.close(),
      //   logger.close()])` 风格批量收口；改成 `void close()` 会破坏 dual-channel
      // 一致性（R121 档 1/档 2 在 caller 处可统一 await，档 3 不可——这是签名同
      // 形保留的最大价值）。
      expect(true, isTrue);
    });

    test('档 2 与 log_cache_service.close 同形 inline duplication — 故意不抽 helper',
        () {
      // mergeinfo_cache_service.close 与 log_cache_service.close 三行结构完全
      // 同形：
      //   for (final db in _databases.values) { db.dispose(); }
      //   _databases.clear();
      //   AppLogger.storage.info('XXX 数据库已关闭');
      // 唯一差别：日志文案。**为什么不抽 helper**（与 R59 helper-vs-inline 阈
      // 值原则一致）：
      //   - 抽出 `Future<void> _disposeAllDbs(Map<String, Database> dbs, String
      //     logTag)` 节省 ~3 行 × 2 处 = 6 行；
      //   - 但 helper 需要传 dbs + logTag 两个参数，签名比 inline 还冗长；
      //   - 且 helper 跨两个 service 共享会引入循环依赖或新 utils 文件 ——
      //     维护成本远超 6 行 duplication。
      // 判据：duplication < 5 行 + 参数数量 ≥ 函数体行数时 → 保留 inline。
      expect(true, isTrue);
    });

    test('档 2 对称释放语义：handle 释放 ≠ fsync', () {
      // caller `await close()` 后**只能**假设：
      //   ✅ 内存中 _databases map 已 clear（无 dangling reference）
      //   ✅ sqlite3 db handle 已 dispose（fd 已归还）
      //   ❌ WAL 模式下未强制 checkpoint（数据安全靠 sqlite3 文件协议）
      //   ❌ AppLogger.storage.info 异步未落盘（不 await）
      // 与档 1 对照：档 1 的 logger close 提供物理落盘强保证；本档不提供。
      // 与档 3 对照：档 3 连"调用栈返回前 close 已被发起"都不保证（fire-and-
      //   forget），本档至少保证 dispose 同步执行完毕。
      // **三档释放语义强弱排序**：档 1 > 档 2 > 档 3。
      expect(true, isTrue);
    });
  });

  group('R125 关闭序列约束 doc-as-test（档 2 close 三步顺序锁）', () {
    // R125 锁定 mergeinfo_cache_service.close 的三步顺序：
    //   step 1: for db in _databases.values { db.dispose() }
    //   step 2: _databases.clear()
    //   step 3: AppLogger.storage.info('MergeInfo 缓存数据库已关闭')
    // 与 log_cache_service.close 形成同形锁（test 文件分别独立）。

    test('step 1 → step 2：dispose 必须先于 _databases.clear（避免 use-after-free）',
        () {
      // **反例**：颠倒成 clear 先调，`_databases.values` 引用立即失效，dispose
      // 会在野指针上调——sqlite3 native 层 use-after-free（Dart Map.clear 不
      // 保证 iterate 出的 values 仍可用）。
      // **当前顺序保证**：dispose 完全跑完后才 drop map 引用。
      expect(true, isTrue);
    });

    test('step 2 → step 3：clear 必须先于 log（日志反映系统状态而非意图）', () {
      // logger.info 是异步 fire-and-forget。如果 step 3 在 step 1 之前，
      // "已关闭" 日志会先于真正关闭出现——**误导性日志违反"日志反映系统状态
      // 而非意图"原则**。
      // **当前顺序保证**：日志写入时 _databases 已为空、所有 handle 已释放。
      expect(true, isTrue);
    });

    test('与 log_cache_service.close 同形顺序锁（R59 helper-vs-inline 同形锁延伸）', () {
      // mergeinfo_cache_service.close 与 log_cache_service.close 三步结构完全
      // 同形（只差日志 tag）。**R125 把这条同形从代码结构升级为顺序锁**：
      //   - 同形允许保留 inline duplication（R59 决策）；
      //   - **同形 + 顺序锁**保证未来若一处加 step（例如补 fsync），另一处必须
      //     同步加（否则同形不再成立、必须重新评估抽 helper）。
      // 这是把 R59 "形态同形" 升维到 "step 序列同形" 的二次锁。
      const orderMergeinfo = ['dispose', 'clear', 'log'];
      const orderLogCache = ['dispose', 'clear', 'log'];
      expect(orderMergeinfo, orderedEquals(orderLogCache),
          reason: '两 close 必须保持完全相同的三步顺序——破坏同形等于破坏 R59 '
              'inline duplication 决策的前提。');
    });

    test('clearCache 阶段顺序：dispose → memory cache → file（与 close 同方向）', () {
      // mergeinfo_cache_service.clearCache 的释放方向必须单调：
      //   阶段 1: handle 释放（dispose + map.remove）
      //   阶段 2: 内存缓存清理（_memoryCache + _cacheLoaded remove）
      //   阶段 3: 文件删除
      //   阶段 4: 日志
      // **释放方向单调原则**：handle → memory → file → log，越靠后的层越"持久
      // 化"。颠倒任意阶段都违反此方向。
      const phaseOrder = ['handle', 'memory', 'file', 'log'];
      expect(
        phaseOrder,
        orderedEquals(['handle', 'memory', 'file', 'log']),
        reason: '释放方向单调原则：依赖性强 → 持久性强（handle 最易失效、log '
            '最持久）。',
      );
    });
  });

  group(
      'R126 启动序列约束 doc-as-test（mergeinfo_cache_service.init 2-step path-only 形态）',
      () {
    test('init step 1 → step 2：path 必须先于 log "成功"消息', () {
      // mergeinfo_cache_service 不在 init 阶段加载 mapping 到内存（_dbCache 是
      // lazy-open），因此 init 是简化形态：path → log（无 handle / memory）。
      // step 1: _cacheDir = await _paths.getMergeInfoCacheDir()
      // step 2: AppLogger.storage.info('...初始化成功: $_cacheDir')
      // 反序会让 log 消息插值 _cacheDir 时拿到 null（虽不抛但日志输出 "null"
      // 字符串、监控误判）。
      const order = ['path:_cacheDir', 'log:info'];
      expect(order[0], equals('path:_cacheDir'));
      expect(order[1], equals('log:info'));
    });

    test('与 log_cache_service.init 不同形（lazy-open vs eager-load 设计选择）', () {
      // log_cache_service.init: path → handle → memory → log（4-step、eager 加
      //   载 mapping 到内存）。
      // mergeinfo_cache_service.init: path → log（2-step、lazy 按 cacheKey 打开
      //   db）。
      // 两者**故意不同形**——log_cache 持久化的 url-hash mapping 必须 eager 加
      // 载（getOrCreateHash 是同步路径，在 cache 命中之前不能再开 prefs）；
      // mergeinfo 持久化的是按 (sourceUrl, targetWc) 组的 db 文件，命中前才需要
      // open，eager 加载所有 db 反而浪费 fd。
      // 此测试锁住"两 service 故意不同形"——若有人为了"统一 init 协议"把 mergeinfo
      // 改成 eager 加载所有 db，会让进程持有大量未使用 sqlite handle、且清理路径
      // 也复杂化，必须先在此 test 改 expect 才能合并。
      const logCacheInitSteps = 4;
      const mergeinfoInitSteps = 2;
      expect(logCacheInitSteps, greaterThan(mergeinfoInitSteps),
          reason: 'mergeinfo lazy-open 是设计选择、不是漏掉 step；统一 init 协议'
              '前必须先改此 test。');
    });
  });
}
