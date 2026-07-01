import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/log_file_cache_service.dart';

/// 剥离 dart 源码内的 `///` doc 与 `//` 行注释——R130 doc-as-test 反向自匹配
/// 防御 helper（R132/R133/R134 复用）。
String _stripComments(String src) {
  return src
      .split('\n')
      .where((line) {
        final t = line.trimLeft();
        return !t.startsWith('///') && !t.startsWith('//');
      })
      .join('\n');
}

/// **R134 缓存淘汰/失效策略跨服务一致性审计 — 4 档分类 + K1/K2/K3/K4 不变量**
///
/// 4 档分类：
/// - 档 1 bounded-auto-LRU: [LogFileCacheService] (maxCacheSize=50 + LRU)
/// - 档 2 unbounded-manual-targeted-clear: log_cache_service / mergeinfo_cache_service
///        的 clearCache(...) 单实例清除
/// - 档 3 unbounded-manual-nuke-all: 两 sqlite 服务的 clearAllCache()
/// - 档 4 compaction-by-merge: log_cache_service `cached_ranges` 表区间合并
///
/// 跨档 4 不变量：
/// - K1: 容量上限存在 ⟺ 自动淘汰存在
/// - K2: 淘汰算法 ↔ input domain 用户驱动度
/// - K3: 释放序列 handle → memory → file → log（R125 强化）
/// - K4: 双结构同步 mutator（R124 复用）
void main() {
  group('R134 档 1 bounded-auto-LRU: LogFileCacheService 容量上限 + 自动驱逐', () {
    test('K1: maxCacheSize 是 const 字面量 = 50（容量上限存在）', () {
      expect(
        LogFileCacheService.maxCacheSize,
        50,
        reason: 'R134 K1 档 1: 容量上限来源是 const 字面量、非配置驱动',
      );
    });

    test('K1 反向锁: 档 1 必同时存在自动驱逐机制（planSaveFilesUpdate 返回 evictKey）', () {
      // 满载 + 新 key → 必给出 evictKey（最久未访问）
      final plan = planSaveFilesUpdate(
        existingKeys: {for (int i = 0; i < 50; i++) 'k$i'},
        accessOrder: [for (int i = 0; i < 50; i++) 'k$i'],
        key: 'kNew',
        maxSize: LogFileCacheService.maxCacheSize,
      );
      expect(
        plan.evictKey,
        'k0',
        reason: 'R134 K1: 档 1 必有自动驱逐——满载新 key 必驱逐最久未用 (LRU)',
      );
    });

    test('K2 LRU 适合用户驱动 input: 满载 + 新 key 驱逐最久未访问 (accessOrder.first)', () {
      // R134 K2: 用户驱动 input → 用 LRU（请求频率反映用户兴趣）
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b', 'c'},
        accessOrder: ['a', 'b', 'c'],
        key: 'd',
        maxSize: 3, // 已满
      );
      expect(plan.evictKey, 'a', reason: 'R134 K2 LRU: 驱逐 accessOrder.first (a)');
    });

    test('K2 LRU 不驱逐既存 key 复写: keyAlreadyExists=true → evictKey=null', () {
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b', 'c'},
        accessOrder: ['a', 'b', 'c'],
        key: 'a',
        maxSize: 3,
      );
      expect(
        plan.evictKey,
        isNull,
        reason: 'R134 K2: 复写既存 key 复用槽位、不驱逐——LRU 算法核心契约',
      );
    });

    test('K2 容量未满 + 新 key: evictKey=null（直接追加，不驱逐）', () {
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b'},
        accessOrder: ['a', 'b'],
        key: 'c',
        maxSize: 5, // 未满
      );
      expect(plan.evictKey, isNull, reason: 'R134 档 1: 容量未满不驱逐');
    });
  });

  group('R134 档 2 unbounded-manual-targeted-clear: sqlite 服务单实例清除', () {
    test('档 2: log_cache_service.clearCache(sourceUrl) 签名锁', () {
      final src = _stripComments(
          File('lib/services/log_cache_service.dart').readAsStringSync());
      // 必有 `Future<void> clearCache(String sourceUrl) async`
      expect(
        RegExp(r'Future<void>\s+clearCache\(String\s+sourceUrl\)\s+async')
            .hasMatch(src),
        isTrue,
        reason: 'R134 档 2: log_cache_service 单实例清除粒度 = sourceUrl',
      );
    });

    test('档 2: mergeinfo_cache_service.clearCache(sourceUrl, targetWc) 签名锁', () {
      final src = _stripComments(
          File('lib/services/mergeinfo_cache_service.dart').readAsStringSync());
      expect(
        RegExp(r'Future<void>\s+clearCache\(\s*String\s+sourceUrl,\s*String\s+targetWc\s*\)\s+async')
            .hasMatch(src),
        isTrue,
        reason: 'R134 档 2: mergeinfo 单实例清除粒度 = (sourceUrl, targetWc) 双键',
      );
    });

    test('档 2 vs 档 3 粒度差异锁: 两 sqlite 服务必同时有 clearCache + clearAllCache', () {
      final logSrc =
          File('lib/services/log_cache_service.dart').readAsStringSync();
      final mergeSrc =
          File('lib/services/mergeinfo_cache_service.dart').readAsStringSync();
      for (final src in [logSrc, mergeSrc]) {
        expect(
          src.contains('clearCache(') && src.contains('clearAllCache('),
          isTrue,
          reason: 'R134: sqlite 服务必同时提供单实例 (档 2) + 全部 (档 3) 清除 API',
        );
      }
    });
  });

  group('R134 档 3 unbounded-manual-nuke-all: clearAllCache() 全清', () {
    test('K3 释放序列 handle → memory → file → log: log_cache_service 4 阶段顺序锁', () {
      // 直接 grep 实际函数体（非 doc）的语句序列
      final src = File('lib/services/log_cache_service.dart').readAsStringSync();
      // 找 clearAllCache 函数体起始
      final start = src.indexOf('Future<void> clearAllCache() async {');
      expect(start, isNot(-1), reason: 'R134: 必有 clearAllCache 实现');
      final end = (start + 1500).clamp(0, src.length);
      final body = src.substring(start, end);
      final disposeIdx = RegExp(r'\.dispose\(\)').firstMatch(body)?.start ?? -1;
      final clearMapIdx = body.indexOf('_databases.clear()');
      final urlMapClearIdx = body.indexOf('_urlToHashMap.clear()');
      expect(
        disposeIdx >= 0 && clearMapIdx > disposeIdx,
        isTrue,
        reason: 'R134 K3: dispose 必先于 _databases.clear()（R125 同律）',
      );
      expect(
        urlMapClearIdx > clearMapIdx,
        isTrue,
        reason: 'R134 K3: mapping clear 在 _databases.clear 之后（阶段 3）',
      );
    });

    test('K4 双结构同步 mutator: mergeinfo_cache_service 三 Map 同步 clear', () {
      final src =
          File('lib/services/mergeinfo_cache_service.dart').readAsStringSync();
      final start = src.indexOf('Future<void> clearAllCache() async {');
      expect(start, isNot(-1));
      final end = (start + 800).clamp(0, src.length);
      final body = src.substring(start, end);
      // _databases / _memoryCache / _cacheLoaded 三 Map 必都有 clear
      expect(body.contains('_databases.clear()'), isTrue);
      expect(body.contains('_memoryCache.clear()'), isTrue);
      expect(body.contains('_cacheLoaded.clear()'), isTrue);
    });

    test('K4 反向锁: log_file_cache_service.clearCache 双结构同步 (cache + accessOrder)', () {
      final src = File('lib/services/log_file_cache_service.dart')
          .readAsStringSync();
      final start = src.indexOf('Future<void> clearCache() async {');
      expect(start, isNot(-1));
      final end = (start + 400).clamp(0, src.length);
      final body = src.substring(start, end);
      expect(body.contains('_cache.clear()'), isTrue);
      expect(body.contains('_accessOrder.clear()'), isTrue);
    });
  });

  group('R134 档 4 compaction-by-merge: cached_ranges 表区间合并独有', () {
    test('档 4 仅 log_cache_service: clearAllRanges API 存在', () {
      final src = File('lib/services/log_cache_service.dart').readAsStringSync();
      expect(
        src.contains('clearAllRanges('),
        isTrue,
        reason: 'R134 档 4: log_cache_service 独有 ranges API（区间合并/清空）',
      );
    });

    test('档 4 反向锁: 其他两 cache 服务无 clearAllRanges / planMergeAdjacentRanges', () {
      for (final f in [
        'lib/services/log_file_cache_service.dart',
        'lib/services/mergeinfo_cache_service.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(
          src.contains('clearAllRanges') || src.contains('planMergeAdjacentRanges'),
          isFalse,
          reason: 'R134 档 4 独有性: $f 不应有 ranges API',
        );
      }
    });
  });

  group('R134 doc-as-test: 4 档分类 + K1/K2/K3/K4 文案锁', () {
    test('LogFileCacheService 类 doc 包含 R134 4 档分类 + K1/K2/K3/K4 文案', () {
      final src = File('lib/services/log_file_cache_service.dart')
          .readAsStringSync();
      // doc 块本身（含 ///）必须有 R134 + 4 档关键词 + 4 不变量
      expect(src.contains('R134 缓存淘汰'), isTrue);
      expect(src.contains('档 1 bounded-auto-LRU'), isTrue);
      expect(src.contains('档 2 unbounded-manual-targeted-clear'), isTrue);
      expect(src.contains('档 3 unbounded-manual-nuke-all'), isTrue);
      expect(src.contains('档 4 compaction-by-merge'), isTrue);
      expect(src.contains('K1（容量自动淘汰对偶律）'), isTrue);
      expect(src.contains('K2（淘汰算法'), isTrue);
      expect(src.contains('K3（释放序列'), isTrue);
      expect(src.contains('K4（双结构同步 mutator）'), isTrue);
    });

    test('log_cache_service.clearAllCache 含 R134 档 3 标注', () {
      final src =
          File('lib/services/log_cache_service.dart').readAsStringSync();
      expect(
        src.contains('R134 档 3 unbounded-manual-nuke-all'),
        isTrue,
        reason: 'R134: log_cache_service.clearAllCache 必标注档 3',
      );
    });

    test('mergeinfo_cache_service.clearAllCache 含 R134 档 3 标注 + 互引 LogFileCacheService', () {
      final src = File('lib/services/mergeinfo_cache_service.dart')
          .readAsStringSync();
      expect(src.contains('R134 档 3 unbounded-manual-nuke-all'), isTrue);
      expect(
        src.contains('LogFileCacheService'),
        isTrue,
        reason: 'R134: mergeinfo_cache_service 档 3 doc 必互引档 1 LogFileCacheService',
      );
    });
  });
}
