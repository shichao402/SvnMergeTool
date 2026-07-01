import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132/R133/R134/R135 复用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R135 sqlite transaction boundary 协议审计 — 4 档分类 + L1/L2/L3/L4 不变量**
///
/// 4 档分类（service 内 sqlite 子维度）：
/// - 档 1 sync-isolate-atomic-block: 单条 db.x() 在同步段，sqlite3 + 单 isolate 保证原子
/// - 档 2 explicit BEGIN/COMMIT batch-loop: prepare-stmt loop 包事务（多 row 写）
/// - 档 3 cross-await read-then-write decision: 跨 `await` 的 DB 读决策写序列
/// - 档 4 schema/PRAGMA bootstrap: 一次性 setup
///
/// 跨档 4 不变量：
/// - L1: sync-block atomicity（单同步段内 db.x() 不可被抢占）
/// - L2: BEGIN/COMMIT 必配对（COMMIT 与 ROLLBACK 二选一）
/// - L3: stmt.dispose 必在 COMMIT 之前（R125 / log_cache 1306-1317 同律）
/// - L4: cross-await 写序列由 caller 串行化兜底
void main() {
  final logCacheServiceFile =
      File('lib/services/log_cache_service.dart');
  final mergeInfoCacheServiceFile =
      File('lib/services/mergeinfo_cache_service.dart');

  group('R135 sqlite transaction boundary — 档 2 BEGIN/COMMIT 配对锁', () {
    test('log_cache_service.insertEntries: BEGIN ↔ COMMIT ↔ ROLLBACK 三向配对', () {
      final src = logCacheServiceFile.readAsStringSync();
      final stripped = _stripComments(src);

      final beginCount =
          'BEGIN TRANSACTION'.allMatches(stripped).length;
      final commitCount = "execute('COMMIT')".allMatches(stripped).length;
      final rollbackCount =
          "execute('ROLLBACK')".allMatches(stripped).length;

      expect(beginCount, 1,
          reason: 'log_cache_service 应有且仅有 1 处 BEGIN TRANSACTION'
              '（insertEntries 内 batch loop）');
      expect(commitCount, 1, reason: 'COMMIT 必与 BEGIN 1:1 配对');
      expect(rollbackCount, 1, reason: 'ROLLBACK 必存在于 catch 分支（L2 不变量）');
    });

    test('mergeinfo_cache_service.saveToCache: BEGIN ↔ COMMIT ↔ ROLLBACK 三向配对',
        () {
      final src = mergeInfoCacheServiceFile.readAsStringSync();
      final stripped = _stripComments(src);

      final beginCount =
          'BEGIN TRANSACTION'.allMatches(stripped).length;
      final commitCount = "execute('COMMIT')".allMatches(stripped).length;
      final rollbackCount =
          "execute('ROLLBACK')".allMatches(stripped).length;

      expect(beginCount, 1,
          reason: 'mergeinfo_cache_service 应有且仅有 1 处 BEGIN TRANSACTION'
              '（saveToCache 内 stmt loop）');
      expect(commitCount, 1, reason: 'COMMIT 必与 BEGIN 1:1 配对');
      expect(rollbackCount, 1, reason: 'ROLLBACK 必存在于 catch 分支（L2 不变量）');
    });

    test('两 sqlite 服务必同时存在档 2 transaction（不变量同形锁）', () {
      final logSrc = _stripComments(logCacheServiceFile.readAsStringSync());
      final mergeSrc =
          _stripComments(mergeInfoCacheServiceFile.readAsStringSync());

      expect(logSrc.contains('BEGIN TRANSACTION'), isTrue);
      expect(mergeSrc.contains('BEGIN TRANSACTION'), isTrue);
    });
  });

  group('R135 sqlite transaction boundary — 档 2 L3 stmt.dispose 顺序锁', () {
    test('log_cache_service.insertEntries: stmt.dispose 必在 COMMIT 之前出现', () {
      final src = logCacheServiceFile.readAsStringSync();
      final stripped = _stripComments(src);
      // 在 BEGIN ... COMMIT 之间寻找 stmt.dispose() 与 COMMIT 的相对位置
      final beginIdx = stripped.indexOf('BEGIN TRANSACTION');
      final commitIdx = stripped.indexOf("execute('COMMIT')");
      final disposeIdx = stripped.indexOf('stmt.dispose()');

      expect(beginIdx >= 0 && commitIdx >= 0 && disposeIdx >= 0, isTrue,
          reason: 'BEGIN / COMMIT / stmt.dispose 三段必同时存在');
      expect(disposeIdx > beginIdx, isTrue,
          reason: 'stmt.dispose 应在 BEGIN 之后');
      expect(disposeIdx < commitIdx, isTrue,
          reason: 'L3 不变量: stmt.dispose 必在 COMMIT 之前');
    });

    test('mergeinfo_cache_service.saveToCache: stmt.dispose 必在 COMMIT 之前出现',
        () {
      final src = mergeInfoCacheServiceFile.readAsStringSync();
      final stripped = _stripComments(src);
      final beginIdx = stripped.indexOf('BEGIN TRANSACTION');
      final commitIdx = stripped.indexOf("execute('COMMIT')");
      final disposeIdx = stripped.indexOf('stmt.dispose()');

      expect(beginIdx >= 0 && commitIdx >= 0 && disposeIdx >= 0, isTrue);
      expect(disposeIdx > beginIdx, isTrue);
      expect(disposeIdx < commitIdx, isTrue,
          reason: 'L3 不变量: mergeinfo saveToCache 内 stmt.dispose 必在 COMMIT 之前');
    });
  });

  group('R135 sqlite transaction boundary — 档 1 单同步段反例锁', () {
    test('log_cache_service._mergeAdjacentRanges: 方法内不应有 await（L1 同步段保证）',
        () {
      final src = logCacheServiceFile.readAsStringSync();
      final start = src.indexOf('Future<void> _mergeAdjacentRanges(');
      expect(start, greaterThan(0));
      // 找该方法体结束位置（下一个 ^  /// 或 ^  Future / int 等顶层成员声明）
      final end = src.indexOf('\n  }', start);
      expect(end, greaterThan(start));
      final body = src.substring(start, end);

      // 档 1 关键性质：方法体内不出现 `await`（除签名 async 关键字外）
      // 注意：方法签名 Future<void> ... async 的 async 不是 await
      expect(body.contains(' await '), isFalse,
          reason: '_mergeAdjacentRanges 是档 1 sync-block，不能出现 await，'
              '否则破坏 L1 不变量');
    });
  });

  group('R135 sqlite transaction boundary — 档 3 cross-await 站点 doc-as-test 锁',
      () {
    test('log_cache_service._updateRangesAfterInsert: doc 必显式声明档 3 + L4', () {
      final src = logCacheServiceFile.readAsStringSync();
      final markerIdx = src.indexOf('R135 档 3 cross-await read-then-write');
      expect(markerIdx, greaterThan(0),
          reason: '_updateRangesAfterInsert 必带 R135 档 3 doc 标注');
      final end =
          (markerIdx + 800).clamp(0, src.length);
      final region = src.substring(markerIdx, end);
      expect(region.contains('L4'), isTrue,
          reason: 'doc 必显式互引 L4 不变量（caller 串行化兜底）');
      expect(region.contains('log_sync_service'), isTrue,
          reason: 'doc 必声明唯一 caller 路径');
    });
  });

  group('R135 sqlite transaction boundary — doc-as-test 元说明锁', () {
    test('log_cache_service.insertEntries 类 doc 必含 R135 4 档分类 + L1-L4', () {
      final src = logCacheServiceFile.readAsStringSync();
      final markerIdx =
          src.indexOf('R135 sqlite transaction boundary 4 档分类');
      expect(markerIdx, greaterThan(0));
      final end = (markerIdx + 2400).clamp(0, src.length);
      final region = src.substring(markerIdx, end);

      expect(region.contains('档 1 sync-isolate-atomic-block'), isTrue);
      expect(region.contains('档 2 explicit BEGIN/COMMIT batch-loop'), isTrue);
      expect(region.contains('档 3 cross-await read-then-write decision'),
          isTrue);
      expect(region.contains('档 4 schema/PRAGMA bootstrap'), isTrue);
      expect(region.contains('L1'), isTrue);
      expect(region.contains('L2'), isTrue);
      expect(region.contains('L3'), isTrue);
      expect(region.contains('L4'), isTrue);
    });

    test('log_cache_service.insertEntries doc 必声明三档框架第 15 次复用 + R125/R134 接合面',
        () {
      final src = logCacheServiceFile.readAsStringSync();
      final markerIdx =
          src.indexOf('R135 sqlite transaction boundary 4 档分类');
      expect(markerIdx, greaterThan(0));
      final end = (markerIdx + 2400).clamp(0, src.length);
      final region = src.substring(markerIdx, end);
      expect(region.contains('三档框架第 15 次复用'), isTrue,
          reason: 'doc 必声明 framework 第 15 次复用');
      expect(region.contains('R125'), isTrue);
      expect(region.contains('R134'), isTrue);
      expect(region.contains('接合面'), isTrue);
    });

    test('mergeinfo_cache_service.saveToCache doc 必声明档 2 + L2/L3 + 与 log_cache 同档对偶',
        () {
      final src = mergeInfoCacheServiceFile.readAsStringSync();
      final markerIdx = src.indexOf(
          'R135 档 2 explicit BEGIN/COMMIT batch-loop');
      expect(markerIdx, greaterThan(0));
      final end = (markerIdx + 1200).clamp(0, src.length);
      final region = src.substring(markerIdx, end);

      expect(region.contains('L2'), isTrue);
      expect(region.contains('L3'), isTrue);
      expect(region.contains('log_cache_service'), isTrue,
          reason: 'doc 必互引 log_cache_service.insertEntries 同档对偶');
      expect(region.contains('R102'), isTrue,
          reason: 'doc 必互引 R102 形式化分裂的合法性同律');
    });

    test('R135 4 档分类 + L1-L4 在 insertEntries doc 内不变量逐字命中', () {
      final src = logCacheServiceFile.readAsStringSync();
      // 验证关键短语字面命中（防止后续 doc 改动破坏审计契约）
      const phrases = [
        'sync-isolate-atomic-block',
        'BEGIN/COMMIT batch-loop',
        'cross-await read-then-write decision',
        'schema/PRAGMA bootstrap',
        'sync-block atomicity',
        'BEGIN/COMMIT 必配对',
        'stmt.dispose 必在 COMMIT 之前',
        'cross-await 写序列由 caller 串行化',
      ];
      for (final p in phrases) {
        expect(src.contains(p), isTrue, reason: 'doc 必字面命中: $p');
      }
    });
  });
}
