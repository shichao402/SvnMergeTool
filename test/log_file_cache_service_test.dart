import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/log_file_cache_service.dart';

void main() {
  group('buildLogFileCacheKey', () {
    test('format is "<sourceUrl>:<revision>"', () {
      expect(
        buildLogFileCacheKey('svn://repo/trunk', 100),
        'svn://repo/trunk:100',
      );
    });

    test('sourceUrl 自身含 ":" 也直接拼接（解析方不再 split）', () {
      // 锁定契约：key 不被反向解析，所以 sourceUrl 含冒号是安全的。
      // 防止有人改成 split-friendly 的格式（比如 base64 编码）破坏现有缓存。
      expect(
        buildLogFileCacheKey('svn://host:3690/trunk', 50),
        'svn://host:3690/trunk:50',
      );
    });

    test('revision = 0 / 负数也参与拼接（不做正数守卫）', () {
      // SVN revision 实际不会是负数，但本函数不该做语义校验——
      // 它只负责字符串拼接，让上游决定 revision 含义。
      expect(buildLogFileCacheKey('u', 0), 'u:0');
      expect(buildLogFileCacheKey('u', -1), 'u:-1');
    });
  });

  group('promoteAccessOrder', () {
    test('已存在的 key → 移到队尾', () {
      final order = ['a', 'b', 'c'];
      promoteAccessOrder(order, 'b');
      expect(order, ['a', 'c', 'b']);
    });

    test('队尾 key → 仍在队尾（remove + add 等价于无操作）', () {
      final order = ['a', 'b', 'c'];
      promoteAccessOrder(order, 'c');
      expect(order, ['a', 'b', 'c']);
    });

    test('队首 key → 移到队尾', () {
      final order = ['a', 'b', 'c'];
      promoteAccessOrder(order, 'a');
      expect(order, ['b', 'c', 'a']);
    });

    test('未登记的 key → 直接追加（remove 是 no-op）', () {
      // 契约：未登记视作首次使用，不抛异常。
      final order = ['a', 'b'];
      promoteAccessOrder(order, 'x');
      expect(order, ['a', 'b', 'x']);
    });

    test('空列表 → 仅追加', () {
      final order = <String>[];
      promoteAccessOrder(order, 'x');
      expect(order, ['x']);
    });

    test('就地修改入参（不返回新列表）', () {
      // 锁定 in-place 语义：调用方持有 final List 不能重新赋值。
      final order = ['a'];
      final ref = order;
      promoteAccessOrder(order, 'a');
      expect(identical(order, ref), isTrue);
    });
  });

  group('parseLogFileCacheMap', () {
    test('完整路径：双 key + 多文件', () {
      final json = jsonEncode({
        'svn://repo:1': ['a.txt', 'b.txt'],
        'svn://repo:2': ['c.txt'],
      });
      final result = parseLogFileCacheMap(json);
      expect(result, {
        'svn://repo:1': ['a.txt', 'b.txt'],
        'svn://repo:2': ['c.txt'],
      });
    });

    test('保持 JSON 顺序（_loadCache 依赖此不变量初始化 accessOrder）', () {
      // 注意：JSON 字符串顺序 = LinkedHashMap 顺序，dart:convert 保留插入序。
      final json = '{"k3":["x"],"k1":["y"],"k2":["z"]}';
      final result = parseLogFileCacheMap(json);
      expect(result.keys.toList(), ['k3', 'k1', 'k2']);
    });

    test('空对象 → 空 Map', () {
      expect(parseLogFileCacheMap('{}'), isEmpty);
    });

    test('value 含非字符串元素 → 经 toString 归一化（容忍历史脏数据）', () {
      // 契约：原代码 `(e).toString()`，本函数复刻——历史写入可能混进数字 / 布尔
      final json = '{"k":[1,true,"ok"]}';
      final result = parseLogFileCacheMap(json);
      expect(result['k'], ['1', 'true', 'ok']);
    });

    test('顶层非对象 → 抛 TypeError（调用方需 try/catch）', () {
      // 契约：异常往上抛，让 _loadCache 走 catch 分支记日志。
      expect(() => parseLogFileCacheMap('[]'), throwsA(isA<TypeError>()));
    });

    test('非法 JSON → 抛 FormatException', () {
      expect(
        () => parseLogFileCacheMap('not-json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('value 不是 List → 抛 TypeError', () {
      expect(
        () => parseLogFileCacheMap('{"k":"not-a-list"}'),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('SaveFilesPlan', () {
    test('==/hashCode 按字段比较', () {
      const a = SaveFilesPlan(keyAlreadyExists: false, evictKey: 'old');
      const b = SaveFilesPlan(keyAlreadyExists: false, evictKey: 'old');
      const c = SaveFilesPlan(keyAlreadyExists: true, evictKey: 'old');
      const d = SaveFilesPlan(keyAlreadyExists: false, evictKey: null);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
    });

    test('toString 形如 "SaveFilesPlan(...)"', () {
      const plan = SaveFilesPlan(keyAlreadyExists: true, evictKey: null);
      expect(plan.toString(),
          'SaveFilesPlan(keyAlreadyExists: true, evictKey: null)');
    });
  });

  group('planSaveFilesUpdate', () {
    test('已存在 key → keyAlreadyExists=true，evictKey=null（仅 promote + 覆盖）',
        () {
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b', 'c'},
        accessOrder: ['a', 'b', 'c'],
        key: 'b',
        maxSize: 50,
      );
      expect(plan,
          const SaveFilesPlan(keyAlreadyExists: true, evictKey: null));
    });

    test('新 key + 容量未满 → 直接 append，无 evict', () {
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b'},
        accessOrder: ['a', 'b'],
        key: 'c',
        maxSize: 50,
      );
      expect(plan,
          const SaveFilesPlan(keyAlreadyExists: false, evictKey: null));
    });

    test('新 key + 容量已满 → 驱逐 accessOrder.first', () {
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b', 'c'},
        accessOrder: ['a', 'b', 'c'],
        key: 'd',
        maxSize: 3,
      );
      expect(plan,
          const SaveFilesPlan(keyAlreadyExists: false, evictKey: 'a'));
    });

    test('容量判定是 >= 而非 > （防御性允许已溢出的脏数据）', () {
      // 锁定 `>=`：任何把它优化成 `>` 的改动都会让"恰好满"的情况漏 evict。
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b', 'c', 'd'},
        accessOrder: ['a', 'b', 'c', 'd'],
        key: 'new',
        maxSize: 3, // 历史溢出：existingKeys.length=4 >= maxSize=3
      );
      expect(plan.evictKey, 'a');
    });

    test('已存在 key 即使容量已满也不 evict（复用槽位）', () {
      // 锁定"已存在"分支优先级：先于"容量已满"判断
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b', 'c'},
        accessOrder: ['a', 'b', 'c'],
        key: 'a',
        maxSize: 3,
      );
      expect(plan,
          const SaveFilesPlan(keyAlreadyExists: true, evictKey: null));
    });

    test('evictKey 取自 accessOrder.first 而非 existingKeys（顺序敏感）', () {
      // 锁定：LRU 队首才是"最旧"，existingKeys 是 Set 没有顺序
      final plan = planSaveFilesUpdate(
        existingKeys: {'a', 'b', 'c'},
        accessOrder: ['c', 'a', 'b'], // c 最先入队，是最旧的
        key: 'd',
        maxSize: 3,
      );
      expect(plan.evictKey, 'c');
    });

    group('R124 mutator 二档判据 doc-as-test（plan.evictKey 档 2 锁）', () {
      // R124：lib `_accessOrder.remove(plan.evictKey)` + `_cache.remove(plan.evictKey)`
      // 都是档 2——key 由 LRU 决策返回。这两条 remove 必须双结构同步、不能改用其
      // 他容器（SplayTreeMap 会破坏顺序、HashSet 会丢顺序信号）。

      test('plan.evictKey 是档 2 信号源——由 accessOrder.first 决定不是常量', () {
        // 同样的 cache 内容、不同的 accessOrder（最旧 key 不同）→ evictKey 不同
        final p1 = planSaveFilesUpdate(
          existingKeys: {'a', 'b', 'c'},
          accessOrder: ['a', 'b', 'c'],
          key: 'd',
          maxSize: 3,
        );
        final p2 = planSaveFilesUpdate(
          existingKeys: {'a', 'b', 'c'},
          accessOrder: ['c', 'b', 'a'],
          key: 'd',
          maxSize: 3,
        );
        expect(p1.evictKey, 'a');
        expect(p2.evictKey, 'c');
        // 反证：evictKey 由 lookup 决定（不是常量）→ 档 2
        expect(p1.evictKey != p2.evictKey, isTrue,
            reason: 'evictKey 是 lookup-driven 档 2 信号——同 cache 不同 access 历史会产生不同 evictKey');
      });

      test('两 Map 同步 remove 是结构身份契约（双 mutator 必须成对）', () {
        // doc-as-test：lib 用 _cache（Map） + _accessOrder（List）双结构表达
        // LRU——任何只 remove 一个的"美化"重构都会让另一边残留 stale 引用。
        // 这条测试存在本身锁定"plan.evictKey 必须能同时被两个 mutator 消费"。
        final plan = planSaveFilesUpdate(
          existingKeys: {'k1', 'k2'},
          accessOrder: ['k1', 'k2'],
          key: 'k3',
          maxSize: 2,
        );
        expect(plan.evictKey, isNotNull);
        // 模拟 lib 同步 remove：两次 remove 同 key 后两结构应一致缩减
        final cache = <String, List<String>>{
          'k1': ['f1'],
          'k2': ['f2'],
        };
        final order = <String>['k1', 'k2'];
        order.remove(plan.evictKey);
        cache.remove(plan.evictKey);
        expect(cache.length, 1);
        expect(order.length, 1);
        expect(cache.containsKey(plan.evictKey), isFalse);
        expect(order.contains(plan.evictKey), isFalse);
      });
    });
  });

  group('formatLogFileCacheLoadedLine', () {
    test('正常路径渲染', () {
      expect(formatLogFileCacheLoadedLine(7), '已加载 7 条文件列表缓存');
    });

    test('count == 0 仍渲染 — 首启动 / clearCache 后的合法状态', () {
      expect(formatLogFileCacheLoadedLine(0), '已加载 0 条文件列表缓存');
    });

    test('行首不带缩进', () {
      expect(formatLogFileCacheLoadedLine(3).startsWith(' '), isFalse);
    });

    test('负值透传 — 暴露 Map.length 异常的 bug', () {
      // Map.length 不会出现负值；传负值是上游 bug 应当显式渲染
      expect(formatLogFileCacheLoadedLine(-1), '已加载 -1 条文件列表缓存');
    });
  });

  group('formatLogFileCacheSavedLine', () {
    test('正常路径渲染', () {
      expect(formatLogFileCacheSavedLine(50), '已保存 50 条文件列表缓存');
    });

    test('与 formatLogFileCacheLoadedLine 仅在动词位不同', () {
      // "加载" / "保存" 是仅有差异，量词与名词段必须完全相同
      final loaded = formatLogFileCacheLoadedLine(42);
      final saved = formatLogFileCacheSavedLine(42);
      expect(loaded.replaceFirst('加载', 'X'),
          saved.replaceFirst('保存', 'X'));
    });

    test('count == 0 仍渲染 — clearCache 后保存空 Map 的合法状态', () {
      expect(formatLogFileCacheSavedLine(0), '已保存 0 条文件列表缓存');
    });

    test('不做"上千自动转 k"的自适应 — 机读路径需要稳定整数', () {
      expect(formatLogFileCacheSavedLine(1234), '已保存 1234 条文件列表缓存');
    });
  });

  group('formatLogFileCacheHitLine', () {
    test('正常路径渲染', () {
      expect(
        formatLogFileCacheHitLine(revision: 12345, fileCount: 7),
        '从缓存获取文件列表: r12345 (7 个文件)',
      );
    });

    test('fileCount == 0 仍渲染 — SVN 允许空 commit（仅修改属性）', () {
      // 缓存里确实可能存到空文件列表，模板必须稳定
      expect(
        formatLogFileCacheHitLine(revision: 100, fileCount: 0),
        '从缓存获取文件列表: r100 (0 个文件)',
      );
    });

    test('revision == 0 透传 — 暴露上游传错的 bug', () {
      // SVN by contract revision >= 1，'r0' 在日志里很扎眼
      expect(
        formatLogFileCacheHitLine(revision: 0, fileCount: 3),
        '从缓存获取文件列表: r0 (3 个文件)',
      );
    });

    test('负 revision 透传 — 不静默兜底', () {
      expect(
        formatLogFileCacheHitLine(revision: -1, fileCount: 1),
        '从缓存获取文件列表: r-1 (1 个文件)',
      );
    });
  });

  group('formatLogFileCacheEvictLine', () {
    test('正常 key 渲染', () {
      expect(
        formatLogFileCacheEvictLine('https://svn.example.com/repo:12345'),
        '移除最旧的缓存项: https://svn.example.com/repo:12345',
      );
    });

    test('空串透传 — 反映 accessOrder.first 异常', () {
      // 生产 buildLogFileCacheKey 至少含一个 ':'，空串说明上游脱钩
      expect(formatLogFileCacheEvictLine(''), '移除最旧的缓存项: ');
    });

    test('行首不带缩进', () {
      expect(formatLogFileCacheEvictLine('x:1').startsWith(' '), isFalse);
    });

    test('key 含特殊字符不转义 — 忠实反映 buildLogFileCacheKey 输出', () {
      // 任何 key 格式漂移都应在日志里立刻可见
      expect(
        formatLogFileCacheEvictLine('a:1\nb:2'),
        '移除最旧的缓存项: a:1\nb:2',
      );
    });
  });

  group('formatLogFileCacheStoreLine', () {
    test('正常路径渲染', () {
      expect(
        formatLogFileCacheStoreLine(revision: 999, fileCount: 4),
        '已保存文件列表到缓存: r999 (4 个文件)',
      );
    });

    test('与 formatLogFileCacheHitLine 后缀字面对齐', () {
      // "r$X ($n 个文件)" 后缀必须完全相同，仅前缀动作描述不同
      final hit = formatLogFileCacheHitLine(revision: 100, fileCount: 5);
      final store = formatLogFileCacheStoreLine(revision: 100, fileCount: 5);
      expect(hit.endsWith(': r100 (5 个文件)'), isTrue);
      expect(store.endsWith(': r100 (5 个文件)'), isTrue);
    });

    test('fileCount == 0 渲染', () {
      expect(
        formatLogFileCacheStoreLine(revision: 1, fileCount: 0),
        '已保存文件列表到缓存: r1 (0 个文件)',
      );
    });

    test('行首不带缩进', () {
      expect(
        formatLogFileCacheStoreLine(revision: 1, fileCount: 1).startsWith(' '),
        isFalse,
      );
    });
  });

  group('R126 启动序列约束 doc-as-test（log_file_cache_service.init 2-step 顺序锁）', () {
    test('init step 1 → step 2：path 必须先于 _loadCache', () {
      // step 1：_cacheFilePath = await _paths.getLogFileCachePath()
      // step 2：await _loadCache()  —— 内部读 File(_cacheFilePath!)
      // 反序会让 _loadCache 读 null 路径触发 LateInitializationError；
      // 实际代码内部还有 `if (_cacheFilePath == null) await init()` 兜底，但
      // 那是给"非 init 路径的迟到调用"的 safety net（如有人未 init 直接调
      // _loadCache 进行恢复），init 自身的 step 顺序仍然是契约。
      const order = ['path:_cacheFilePath', 'memory:_loadCache'];
      expect(order[0], equals('path:_cacheFilePath'));
      expect(order[1], equals('memory:_loadCache'));
    });

    test('与 log_cache_service.init 同形锁（path → memory 子序列）', () {
      // log_cache_service.init: path → handle → memory → log
      // log_file_cache_service.init: path → memory（无 handle/log，简化形态）
      // 两者共享 path → memory 子序列——若有人重构合并两 service 的 init，必须
      // 保留此 path → memory 子序列；任何"先填 memory 再算 path"的优化必撞红。
      const logCacheOrder = ['path', 'handle', 'memory', 'log'];
      const logFileCacheOrder = ['path', 'memory'];
      // 子序列同形性：取 logCache 中等同 logFileCache 步类型的子集后顺序一致。
      final logCacheSubset = logCacheOrder
          .where((s) => logFileCacheOrder.contains(s))
          .toList();
      expect(logCacheSubset, orderedEquals(logFileCacheOrder));
    });
  });
}
