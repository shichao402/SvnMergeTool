/// SVN 日志文件列表缓存服务
///
/// 缓存 revision 涉及的文件列表，最多缓存 50 条
/// 使用 LRU（最近最少使用）策略管理缓存

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths_service.dart';
import 'logger_service.dart';

/// 渲染缓存 key：`'<sourceUrl>:<revision>'`。
///
/// **契约**：使用单一冒号 `:` 作为分隔符——缓存文件落地为 JSON，反序列化时不再
/// 解析 key（只用作 lookup），因此即使 sourceUrl 自身含 `:` 也不会出错；但**不要**
/// 改成 `'-'` 或 `'#'` 之类的分隔符——已经写入磁盘的旧缓存文件 key 会突然失配，
/// 导致全量 cache miss。如果真要改格式，必须配合升级路径（清空 / 迁移）。
@visibleForTesting
String buildLogFileCacheKey(String sourceUrl, int revision) =>
    '$sourceUrl:$revision';

/// LRU 提升：把 [key] 移到访问顺序队尾（"最近使用"位置）。
///
/// **就地修改入参 [order]**——与原 `_updateAccessOrder` 行为完全一致，调用方持有
/// `final List<String> _accessOrder` 不能重新赋值。如果 [key] 不在列表里，
/// `remove` 是无操作，最终只追加一次（与"未登记的 key 视作首次使用"语义一致）。
@visibleForTesting
void promoteAccessOrder(List<String> order, String key) {
  order.remove(key);
  order.add(key);
}

/// 反序列化 [LogFileCacheService] 落盘的 JSON 字符串，得到 `key → files` 映射。
///
/// **契约**：
/// - 顶层必须是 JSON 对象，否则抛 [FormatException]/[TypeError]（调用方 try/catch
///   后写日志、放弃缓存——与原 `_loadCache` 异常处理完全等价）
/// - 每个 value 必须是 List；List 元素经 `toString()` 归一化为 `String`（容忍历史
///   写入时混入的非字符串元素，最大化兼容性，与原代码 `(e).toString()` 等价）
/// - 返回的 Map **保持 JSON 顺序**（`Map.entries` 在 Dart 中等价于 LinkedHashMap，
///   这条不变量被 `_loadCache` 用于初始化 `_accessOrder`，不能破坏）
@visibleForTesting
Map<String, List<String>> parseLogFileCacheMap(String jsonContent) {
  final json = jsonDecode(jsonContent) as Map<String, dynamic>;
  final result = <String, List<String>>{};
  for (final entry in json.entries) {
    final files =
        (entry.value as List<dynamic>).map((e) => e.toString()).toList();
    result[entry.key] = files;
  }
  return result;
}

/// 由 [planSaveFilesUpdate] 给出的"插入/更新前置动作"决策。
///
/// 调用方按以下流程消费：
/// 1. 如果 [evictKey] 非空 → 从 cache 与 accessOrder 各移除一次该 key
/// 2. 调用 `promoteAccessOrder(order, key)` 或直接 `order.add(key)`：
///    - [keyAlreadyExists] = true → promote（既存 key 走 LRU 提升）
///    - [keyAlreadyExists] = false → append（新 key 直接入队尾）
/// 3. 写入 `cache[key] = files`
///
/// 这一三步流程与原 `saveFiles` 的 if/else 分支完全等价，但把"决定要不要 evict /
/// 是 promote 还是 append"的判断从命令式 IO 段抽离出来，便于单测覆盖三条路径。
@visibleForTesting
class SaveFilesPlan {
  /// 该 key 在 cache 中是否已存在；true 时调用方应走 promote 而非 append。
  final bool keyAlreadyExists;

  /// 需要驱逐的最旧 key；非空时调用方先从 cache + accessOrder 移除该 key 再插入新条目。
  /// 仅在 cache 已满（`existingKeys.length >= maxSize`）且 [keyAlreadyExists] = false
  /// 时为非空——已存在的 key 不会触发 evict，因为复用的是同一个槽位。
  final String? evictKey;

  const SaveFilesPlan({
    required this.keyAlreadyExists,
    required this.evictKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaveFilesPlan &&
          other.keyAlreadyExists == keyAlreadyExists &&
          other.evictKey == evictKey;

  @override
  int get hashCode => Object.hash(keyAlreadyExists, evictKey);

  @override
  String toString() =>
      'SaveFilesPlan(keyAlreadyExists: $keyAlreadyExists, evictKey: $evictKey)';
}

/// 决定 [LogFileCacheService.saveFiles] 在写入 [key] 前需要做什么。
///
/// **三条路径**（与原 `saveFiles` if/else 严格等价）：
/// - **已存在**：[keyAlreadyExists] = true，[evictKey] = null（直接覆盖 + LRU 提升）
/// - **新 key + 容量已满**：[keyAlreadyExists] = false，[evictKey] = `accessOrder.first`
///   （驱逐最旧的，腾位置给新条目）
/// - **新 key + 容量未满**：[keyAlreadyExists] = false，[evictKey] = null（直接追加）
///
/// **契约决策**：
/// - "容量已满"判定是 `>=` 而非 `>`——与原代码 `_cache.length >= maxCacheSize` 一致；
///   防御性允许"已经溢出"的历史脏数据走驱逐路径。
/// - [accessOrder] 在 cache 已满时**不能为空**：cache 与 accessOrder 在生产代码里
///   是配对维护的（每次 add cache 都会 add accessOrder）。这里**不**再防御性处理
///   `accessOrder.isEmpty` 时取 `first` 抛异常的边界——如果两者真的脱钩，是上游 bug，
///   不应被本函数静默吞掉。
/// - 已存在的 key **不**触发 evict：复用槽位，cache 大小不变。
@visibleForTesting
SaveFilesPlan planSaveFilesUpdate({
  required Set<String> existingKeys,
  required List<String> accessOrder,
  required String key,
  required int maxSize,
}) {
  if (existingKeys.contains(key)) {
    return const SaveFilesPlan(keyAlreadyExists: true, evictKey: null);
  }
  if (existingKeys.length >= maxSize) {
    return SaveFilesPlan(
      keyAlreadyExists: false,
      evictKey: accessOrder.first,
    );
  }
  return const SaveFilesPlan(keyAlreadyExists: false, evictKey: null);
}

/// 渲染 `_loadCache` 末尾的"已加载 N 条文件列表缓存"info 行。
///
/// **契约**：固定模板 `'已加载 $count 条文件列表缓存'`，行首**不带缩进**——
/// 这是 storage 子系统下的顶层提示，与 `formatLogFileCacheSavedLine` 形成
/// "加载/保存"前缀对仗。**不**对 `count == 0` 做防御——空缓存加载是合法状态
/// （首次启动 / clearCache 后），日志显式输出 `'已加载 0 条'` 比静默更利于排查。
/// **不**对负值做防御：`Map.length` 不会出现负值，传负值是上游 bug 应当暴露。
@visibleForTesting
String formatLogFileCacheLoadedLine(int count) =>
    '已加载 $count 条文件列表缓存';

/// 渲染 `_saveCache` 末尾的"已保存 N 条文件列表缓存"info 行。
///
/// **契约**：固定模板 `'已保存 $count 条文件列表缓存'`，与 [formatLogFileCacheLoadedLine]
/// 对仗——**单测显式断言**两条只在动词位（"加载"/"保存"）不同，量词与名词段完全相同。
/// **不**做"超过 N 条压缩成 N k"的自适应——日志走机读路径，纯整数 + 固定单位最稳。
@visibleForTesting
String formatLogFileCacheSavedLine(int count) =>
    '已保存 $count 条文件列表缓存';

/// 渲染 `getFiles` 命中缓存时的 debug 行。
///
/// **契约**：固定模板 `'从缓存获取文件列表: r$revision ($fileCount 个文件)'`。
/// `fileCount` 与 `revision` 都不做防御：
/// - `revision <= 0`：SVN by contract revision >= 1，传 0/负数是上游 bug 应当暴露
///   （`'r0'` / `'r-1'` 在日志里很容易扫到）
/// - `fileCount == 0`：SVN 允许空 commit（仅修改属性），缓存里**确实**可能存到 0 文件
///   列表；不做"= 0 时省略"分支，保持模板稳定。
/// **单测显式锁定** `fileCount == 0` 渲染成 `'(0 个文件)'`。
@visibleForTesting
String formatLogFileCacheHitLine({
  required int revision,
  required int fileCount,
}) =>
    '从缓存获取文件列表: r$revision ($fileCount 个文件)';

/// 渲染 LRU 驱逐时的 debug 行。
///
/// **契约**：固定模板 `'移除最旧的缓存项: $evictedKey'`。`evictedKey` 来自
/// `accessOrder.first`（[planSaveFilesUpdate] 决策），其格式天然是
/// `'<sourceUrl>:<revision>'`（[buildLogFileCacheKey] 的输出），但本函数
/// **不**做格式校验——日志渲染应忠实反映传入值，让任何 key 格式漂移在日志
/// 里立刻可见。
///
/// **不**对空串 evictKey 做防御：`accessOrder.first` 不会返回空串（key 必经
/// `buildLogFileCacheKey` 构造，至少含一个 `:`），但即使真传了空串，渲染成
/// `'移除最旧的缓存项: '` 也好过静默改写为"未知"。**单测显式锁定**空串路径。
@visibleForTesting
String formatLogFileCacheEvictLine(String evictedKey) =>
    '移除最旧的缓存项: $evictedKey';

/// 渲染 `saveFiles` 完成时的 debug 行。
///
/// **契约**：固定模板 `'已保存文件列表到缓存: r$revision ($fileCount 个文件)'`，
/// 与 [formatLogFileCacheHitLine] 同构（"r$revision ($n 个文件)" 后缀完全相同），
/// 仅前缀动作描述不同。**单测显式断言** "(... 个文件)" 后缀字面对齐。
@visibleForTesting
String formatLogFileCacheStoreLine({
  required int revision,
  required int fileCount,
}) =>
    '已保存文件列表到缓存: r$revision ($fileCount 个文件)';

/// **R134 缓存淘汰/失效策略跨服务一致性审计 — 档位与不变量**
///
/// 本服务在 lib/services 三个 cache 服务里属于**档 1 bounded-auto-LRU**，与
/// 另两个 sqlite-backed cache 服务（[LogCacheService] / [MergeInfoCacheService]
/// 同属档 2/档 3 unbounded-manual）形成对偶。R134 把 R98/R119/R120/R121/R125/R127
/// 三档框架第 14 次复用到"缓存淘汰策略"维度，**4 档分类**：
///
/// - **档 1 bounded-auto-LRU**（本服务）：`maxCacheSize = 50` 常量上限 + 满即按
///   `_accessOrder.first` 驱逐最久未用条目。运行时全自动、无需调用方干预。
/// - **档 2 unbounded-manual-targeted-clear**（[LogCacheService.clearCache]
///   / [MergeInfoCacheService.clearCache]）：sqlite 容量随 OS 文件系统、无内置上限，
///   仅按 `(sourceUrl)` 或 `(sourceUrl, targetWc)` 粒度手动 full-clear 单实例。
/// - **档 3 unbounded-manual-nuke-all**（两 sqlite 服务的 `clearAllCache()`）：
///   全部数据库文件删除 + 内存映射清空，仅由"清缓存"按钮触发。
/// - **档 4 compaction-by-merge**（仅 [LogCacheService] 的 `cached_ranges` 表）：
///   不是淘汰、是**合并**——相邻 revision 区间自动 merge 成 super-range 压缩存储；
///   是 R134 唯一非"删除"形态的"缓存空间回收"，与 R116/R118 集合操作 contract 族
///   的 "fold/reduce" 同源。
///
/// **跨服务 4 不变量 K1/K2/K3/K4**（任一档新缓存服务必同时满足）：
/// - **K1（容量自动淘汰对偶律）**：服务**有容量上限** ⟺ **存在自动淘汰**——
///   两条件不可单存。本服务 `maxCacheSize = 50 + LRU` 满足；sqlite 服务**无上限
///   即无自动淘汰**也满足。违反 K1 = "声明上限但无淘汰"（=程序崩死）或"无上限但
///   有淘汰"（=语义无意义）。
/// - **K2（淘汰算法 ↔ input domain 用户驱动度）**：算法选择由 input domain 是否
///   用户驱动决定——LRU/FIFO 适合**用户驱动 input**（请求频率反映用户兴趣，本
///   服务 `getFiles(sourceUrl, revision)` 由用户 UI 操作触发）；版本/区间 merge 适合
///   **范围式 input**（log_cache_service `cached_ranges` 是 SVN log 拉取范围，本
///   质是连续整数线段并集）；full-clear 适合**重置语义 input**（用户按"清缓存"
///   = 显式重置）。
/// - **K3（释放序列 handle → memory → file → log）**：R125 关闭序列约束在 cache
///   family 维度的强化——所有 close/clearCache/clearAllCache 路径必按此顺序。本
///   服务 `clearCache()` 退化为 2-step（无 sqlite handle），但 memory clear ↔ file
///   save 顺序仍受 R125 约束（save 在 clear 之后才能让重启后看到"已清空"状态）。
/// - **K4（双结构同步 mutator）**：R124 双结构同步 mutator 模式在 cache 维度的
///   实例化——本服务 `_cache.remove(evictKey) + _accessOrder.remove(evictKey)`
///   必同 key 同步，否则 stale 引用泄漏（access order 指向已被 evict 的 key 让
///   下次 promote 错位）；mergeinfo_cache_service 的 `_memoryCache.remove +
///   _cacheLoaded.remove` 同律。
///
/// **R134 与 R85-R89 漏迁巡检关系**：本轮 0 真实漏档——3 个 cache 服务策略**故意
/// 不同**（用户驱动度 + 容量需求 + 持久性各不相同），强行统一会破坏 K2 不变量。
/// 这是 R102 "三种 nullable 模式互不一致用测试 doc 化、不强行统一" 在 service
/// 维度的对偶——审计的产出是**形式化分裂的合法性**而非"消除分裂"。
///
/// **与 R125/R126/R127/R128/R129/R130/R131/R132/R133 接合面**：R125 锁释放序列
/// （函数体内部 step），R126 锁启动序列，R127 锁 provider init step，R128 锁
/// notify trigger，R129 锁 widget dispose，R130 锁 cross-provider 通信，R131 锁
/// setState，R132 锁 .text=，R133 锁 controller 流向，**R134 锁 cache 服务自身的
/// 淘汰策略**——是 service-level 资源生命周期审计的最后一片（R125 是单服务函数体
/// 内部、R134 是跨服务策略层面）。
class LogFileCacheService {
  /// 单例模式
  static final LogFileCacheService _instance = LogFileCacheService._internal();
  factory LogFileCacheService() => _instance;
  LogFileCacheService._internal();

  /// 最大缓存数量（R134 档 1 bounded-auto-LRU 的容量上限来源——const 字面量、
  /// 非配置驱动；K1 不变量要求"有上限即有自动淘汰"，本服务满足——见
  /// `planSaveFilesUpdate` LRU 决策与 `saveFiles` 内 evictKey 处理）。
  static const int maxCacheSize = 50;

  /// 缓存数据：key 是 "sourceUrl:revision"，value 是文件列表
  final Map<String, List<String>> _cache = {};

  /// 访问顺序：用于实现 LRU
  final List<String> _accessOrder = [];

  /// 缓存文件路径
  String? _cacheFilePath;

  final AppPathsService _paths = AppPathsService();

  /// 初始化
  ///
  /// R126 启动序列约束（2-step 顺序锁，与 log_cache_service.init step 1+3 同形）：
  /// step 1（path）：`_cacheFilePath = await _paths.getLogFileCachePath()` —— 必须
  ///   最先；step 2 的 _loadCache 直接读 _cacheFilePath。
  /// step 2（memory）：`await _loadCache()` —— 把磁盘 cache 文件加载到内存 _cache /
  ///   _accessOrder 双结构。**必须**在 step 1 之后（`_loadCache` 内部已 doc 化的兜底
  ///   `if (_cacheFilePath == null) await init()` 是双保险、不是设计意图——init() 自
  ///   己就该按序走，兜底是给"非 init 路径的迟到调用"的 safety net）。
  ///
  /// **R126 启动方向单调原则**：path → memory（无 handle 步骤——LogFileCacheService
  /// 持久化用 plain text 文件、不开 sqlite handle，比 log_cache_service 简化一档）。
  Future<void> init() async {
    _cacheFilePath = await _paths.getLogFileCachePath();
    await _loadCache();
  }

  /// 加载缓存
  Future<void> _loadCache() async {
    if (_cacheFilePath == null) {
      await init();
    }

    try {
      final file = File(_cacheFilePath!);
      if (!await file.exists()) {
        return;
      }

      final content = await file.readAsString();
      final parsed = parseLogFileCacheMap(content);

      _cache.clear();
      _accessOrder.clear();

      _cache.addAll(parsed);
      _accessOrder.addAll(parsed.keys);

      AppLogger.storage.info(formatLogFileCacheLoadedLine(_cache.length));
    } catch (e, stackTrace) {
      AppLogger.storage.error('加载文件列表缓存失败', e, stackTrace);
    }
  }

  /// 保存缓存
  Future<void> _saveCache() async {
    if (_cacheFilePath == null) {
      await init();
    }

    try {
      final file = File(_cacheFilePath!);
      final json = <String, dynamic>{};

      for (final entry in _cache.entries) {
        json[entry.key] = entry.value;
      }

      final content = const JsonEncoder.withIndent('  ').convert(json);
      await file.writeAsString(content);

      AppLogger.storage.info(formatLogFileCacheSavedLine(_cache.length));
    } catch (e, stackTrace) {
      AppLogger.storage.error('保存文件列表缓存失败', e, stackTrace);
    }
  }

  /// 获取缓存 key
  String _getCacheKey(String sourceUrl, int revision) =>
      buildLogFileCacheKey(sourceUrl, revision);

  /// 更新访问顺序（LRU）
  void _updateAccessOrder(String key) => promoteAccessOrder(_accessOrder, key);

  /// 获取文件列表（优先从缓存读取）
  ///
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  ///
  /// 返回文件列表，如果缓存中没有则返回 null
  List<String>? getFiles(String sourceUrl, int revision) {
    final key = _getCacheKey(sourceUrl, revision);

    if (_cache.containsKey(key)) {
      _updateAccessOrder(key);
      AppLogger.storage.debug(formatLogFileCacheHitLine(
        revision: revision,
        fileCount: _cache[key]!.length,
      ));
      return _cache[key]!;
    }

    return null;
  }

  /// 保存文件列表到缓存
  ///
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  /// [files] 文件列表
  Future<void> saveFiles(
      String sourceUrl, int revision, List<String> files) async {
    final key = _getCacheKey(sourceUrl, revision);

    final plan = planSaveFilesUpdate(
      existingKeys: _cache.keys.toSet(),
      accessOrder: _accessOrder,
      key: key,
      maxSize: maxCacheSize,
    );

    if (plan.evictKey != null) {
      // R124 mutator 二档判据：`_accessOrder.remove(plan.evictKey)` +
      // `_cache.remove(plan.evictKey)` 都是**档 2**——key 由 [planSaveFilesUpdate]
      // LRU 决策返回，不是常量。调用方不能改 Map → 其他结构（如 LinkedHashMap →
      // SplayTreeMap）：plan.evictKey 依赖 LRU 顺序（access order = 最久未访问的
      // 前置 key），红黑树会破坏顺序语义；同时 `_cache.remove(...)` 在评测路径要
      // 求 O(1) 平均时间，红黑树 O(log n) 反而退化。结构身份（Map + List）必须保
      // 留，与 R123 merge_execution_state 位置依赖同形（局部 mutator 站点不能改，
      // 因为 lib 内同类有"位置/顺序"语义耦合）。
      _accessOrder.remove(plan.evictKey);
      _cache.remove(plan.evictKey);
      AppLogger.storage.debug(formatLogFileCacheEvictLine(plan.evictKey!));
    }

    if (plan.keyAlreadyExists) {
      promoteAccessOrder(_accessOrder, key);
    } else {
      _accessOrder.add(key);
    }
    _cache[key] = files;

    await _saveCache();
    AppLogger.storage.debug(formatLogFileCacheStoreLine(
      revision: revision,
      fileCount: files.length,
    ));
  }

  /// 清除缓存
  Future<void> clearCache() async {
    _cache.clear();
    _accessOrder.clear();
    await _saveCache();
    AppLogger.storage.info('已清除文件列表缓存');
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _cache.length,
      'maxSize': maxCacheSize,
      'keys': _accessOrder.toList(),
    };
  }
}
