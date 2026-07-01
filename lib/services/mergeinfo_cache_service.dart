/// MergeInfo 缓存服务
///
/// 负责管理 SVN mergeinfo 的本地缓存
/// - 使用 SQLite 数据库存储（与 LogCacheService 共用数据库）
/// - 每个 sourceUrl + targetWc 组合对应独立的缓存
/// - 缓存只保存仓库 mergeinfo 的镜像，不保存未提交的工作副本本地属性
/// - 提供高效的查询接口
/// - 自动在程序启动时加载缓存
///
/// 设计原则：
/// - 单一职责：只负责 mergeinfo 的缓存和获取
/// - 单点数据：所有 mergeinfo 数据从这个服务获取
/// - 单一接口：提供统一的 API

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;

import 'app_paths_service.dart';
import 'logger_service.dart';
import 'svn_service.dart';

/// 把 (sourceUrl, targetWc) 折叠成内存缓存使用的 key。
///
/// 分隔符 `|` 不出现在合法 SVN URL 或工作副本路径中，因此可以安全用作
/// 拼接界。空字符串也会被原样保留——本服务不在内部对参数做防御性
/// 校验，调用方应在更高层（`fetchAndUpdateFromSvn` 等入口）拦截空值。
@visibleForTesting
String buildMergeInfoCacheKey(String sourceUrl, String targetWc) {
  return '$sourceUrl|$targetWc';
}

/// 计算 mergeinfo 数据库文件名所用的 16 位 hex hash。
///
/// 与 [buildMergeInfoCacheKey] 完全对齐：先拼 `sourceUrl|targetWc`，
/// 再用 md5 取前 16 位 hex。MD5 的碰撞概率在 16 位前缀下虽不为 0，
/// 但 mergeinfo 库每个 (sourceUrl, targetWc) 都是单独文件，调用方不会
/// 复用 hash 跨 key，因此这里不做碰撞重试（区别于 LogCacheService）。
@visibleForTesting
String mergeInfoDbHash(String sourceUrl, String targetWc) {
  final key = buildMergeInfoCacheKey(sourceUrl, targetWc);
  final bytes = utf8.encode(key);
  final digest = md5.convert(bytes);
  return digest.toString().substring(0, 16);
}

/// 由 (sourceUrl, targetWc) 派生的 16 位 hex hash 构造 mergeinfo 数据库文件名。
///
/// 命名约定 `mergeinfo_<hash>.db` 是 [MergeInfoCacheService] 的隐式协议：
/// `clearCache` 用它定位单个文件、`clearAllCache` 用 `.db` 后缀做粗粒度匹配、
/// `_getDbPath` 是唯一写入点。把这套字符串锁在顶层函数里有两个好处：
/// 1. 测试可在不构造 `MergeInfoCacheService` / `_cacheDir` 的情况下显式锁定文件名。
/// 2. 未来如果要给文件名加前缀（如多租户）或改 hash 长度，只需改这一处。
///
/// 不做 hash 合法性校验——上游的 [mergeInfoDbHash] 已经保证 16 位 hex；
/// 调用方传入怪异字符串会得到怪异文件名，这是调用方的责任。
@visibleForTesting
String buildMergeInfoDbFileName(String hash) {
  return 'mergeinfo_$hash.db';
}

/// 判定 mergeinfo 操作的入参是否合法（即非空字符串）。
///
/// 当 sourceUrl 或 targetWc 任一为空字符串时返回 false。
/// `getMergedRevisions` / `fetchAndUpdateFromSvn` 都用这个守卫做提前 short-circuit
/// 返回空集合——避免空字符串顺着 `_generateCacheKey` 拼出 `'|'` 这种异常 key、
/// 或顺着 `_svnService.*` 触发无意义的 SVN 调用。
///
/// **不做 trim**：UI 上层在 `_pendingSourceUrl` 等地方已经按需 trim；
/// 这里要锁定的是"显式空串视作 invalid"——传入仅含空白的字符串
/// 仍然视作 valid，以便和 SVN URL 的容忍度保持一致（极端情况下 SVN 可能
/// 接受带空白的路径，由调用方决定是否拒绝）。
@visibleForTesting
bool isMergeInfoArgsValid(String sourceUrl, String targetWc) {
  return sourceUrl.isNotEmpty && targetWc.isNotEmpty;
}

/// 把 SQLite 里读出的"毫秒时间戳"字段解析为 [DateTime]。
///
/// `cache_metadata` 表里 `last_updated` / `last_full_sync` 都按
/// `millisecondsSinceEpoch` 存 int。原代码在 `getLastUpdated` / `getLastFullSync`
/// 两处各写了一遍 `null → null`、`int → fromMillisecondsSinceEpoch`，
/// 完全相同；抽出来锁定语义。
///
/// **契约**：
/// - 入参 null（字段从未写过 / 行不存在）→ 返回 null。
/// - 入参非 null（包括 0）→ 返回对应 [DateTime]。0 视作合法值（epoch 起点），
///   不当作"未设置"——和原行为一致，调用方如果需要区分需自行判断。
@visibleForTesting
DateTime? parseDbTimestamp(int? millisecondsSinceEpoch) {
  if (millisecondsSinceEpoch == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
}

/// 批量计算每个 revision 是否在 [mergedSet] 中，返回 `Map<int, bool>`。
///
/// 与单个判定的 [MergeInfoCacheService.isRevisionMergedSync] 形成"批量/单点"
/// 对称：UI 一次性拿到 N 个 revision 的合并状态，避免在循环里重复
/// `_memoryCache[cacheKey]!.contains(rev)` 的 Map 查找。
///
/// **契约**：
/// - 输出 Map 的 key 顺序按 [revisions] 入参顺序（依赖 Dart 的 `LinkedHashMap`）。
/// - 同一 revision 多次出现：后写覆盖前写，但布尔值相同所以无可见效果。
/// - 不修改 [mergedSet]（只读）。
/// - [revisions] 用 `Iterable<int>` 接收，方便 `Set<int>` / `List<int>` 都能直接传入。
@visibleForTesting
Map<int, bool> buildMergedStatusMap(
  Iterable<int> revisions,
  Set<int> mergedSet,
) {
  final result = <int, bool>{};
  for (final rev in revisions) {
    result[rev] = mergedSet.contains(rev);
  }
  return result;
}

/// `getMergedRevisions` 在四种策略下应该走的分支。
enum MergeInfoFetchStrategy {
  /// fullRefresh：清空缓存后从 SVN 重拉。
  fullRefresh,

  /// forceRefresh：保留缓存但仍重拉一次（结果会写回缓存）。
  forceRefresh,

  /// 直接使用本地缓存（命中且非空）。
  useCache,

  /// 缓存为空，触发一次 SVN 拉取。
  fetchBecauseCacheEmpty,
}

/// 选择 `getMergedRevisions` 的执行策略。
///
/// 判定顺序（与原 if-链一致）：
/// 1. `fullRefresh=true` → fullRefresh，不论其它入参。
/// 2. `forceRefresh=true` → forceRefresh。
/// 3. `cacheIsEmpty=true` → fetchBecauseCacheEmpty。
/// 4. 默认 → useCache。
@visibleForTesting
MergeInfoFetchStrategy chooseMergeInfoFetchStrategy({
  required bool fullRefresh,
  required bool forceRefresh,
  required bool cacheIsEmpty,
}) {
  if (fullRefresh) return MergeInfoFetchStrategy.fullRefresh;
  if (forceRefresh) return MergeInfoFetchStrategy.forceRefresh;
  if (cacheIsEmpty) return MergeInfoFetchStrategy.fetchBecauseCacheEmpty;
  return MergeInfoFetchStrategy.useCache;
}

/// MergeInfo 缓存服务
///
/// 提供 mergeinfo 的缓存和获取功能
/// 所有 mergeinfo 相关的操作都应该通过这个服务
class MergeInfoCacheService {
  /// 单例模式
  static final MergeInfoCacheService _instance =
      MergeInfoCacheService._internal();
  factory MergeInfoCacheService() => _instance;
  MergeInfoCacheService._internal();

  /// 测试钩子：子类构造 fake。
  @visibleForTesting
  MergeInfoCacheService.forTesting();

  /// 数据库缓存目录
  String? _cacheDir;

  final AppPathsService _paths = AppPathsService();

  /// 当前打开的数据库（按 sourceUrl + targetWc hash 索引）
  final Map<String, Database> _databases = {};

  /// 内存缓存：已合并的 revision 集合
  /// key: _generateCacheKey(sourceUrl, targetWc)
  /// value: Set<int> 已合并的 revision 集合
  final Map<String, Set<int>> _memoryCache = {};

  /// 缓存是否已加载
  final Map<String, bool> _cacheLoaded = {};

  /// SVN 服务（用于获取 mergeinfo）
  final SvnService _svnService = SvnService();

  /// 数据库版本
  static const int _dbVersion = 1;

  /// 初始化服务
  ///
  /// R126 启动序列约束（2-step 顺序锁，path-only init）：
  /// step 1（path）：`_cacheDir = await _paths.getMergeInfoCacheDir()` —— path 解析
  ///   是后续所有 db open / cache hit 的前置条件（getOrLoadMergeInfo 调 _getDbPath
  ///   会用 _cacheDir）。
  /// step 2（log）：`AppLogger.storage.info('...初始化成功: $_cacheDir')` —— 表达
  ///   "服务已就绪可用"。
  ///
  /// **与 log_cache_service.init 不同形**：mergeinfo 不在 init 阶段加载 mapping
  /// 到内存（_dbCache 是按需 lazy-open，每个 cacheKey 第一次访问时 ensure 打开）；
  /// 因此 R126 启动方向单调原则在此实例化为简化形态 path → log（无 handle/memory
  /// 步骤）。catch + rethrow 与 log_cache_service.init 同——R119 档 3 兼容。
  Future<void> init() async {
    try {
      _cacheDir = await _paths.getMergeInfoCacheDir();

      AppLogger.storage.info('MergeInfo 缓存服务初始化成功: $_cacheDir');
    } catch (e, stackTrace) {
      AppLogger.storage.error('MergeInfo 缓存服务初始化失败', e, stackTrace);
      rethrow;
    }
  }

  /// 生成缓存 key
  String _generateCacheKey(String sourceUrl, String targetWc) =>
      buildMergeInfoCacheKey(sourceUrl, targetWc);

  /// 生成数据库文件名的 hash
  String _generateHash(String sourceUrl, String targetWc) =>
      mergeInfoDbHash(sourceUrl, targetWc);

  /// 获取数据库文件路径
  String _getDbPath(String hash) {
    return path.join(_cacheDir!, buildMergeInfoDbFileName(hash));
  }

  /// 确保服务已初始化
  Future<void> _ensureInit() async {
    if (_cacheDir == null) {
      await init();
    }
  }

  /// 获取或打开指定 sourceUrl + targetWc 的数据库
  Future<Database> _getDatabase(String sourceUrl, String targetWc) async {
    await _ensureInit();

    final hash = _generateHash(sourceUrl, targetWc);

    // 检查是否已打开
    if (_databases.containsKey(hash)) {
      return _databases[hash]!;
    }

    // 打开或创建数据库
    final dbPath = _getDbPath(hash);
    final dbExists = await File(dbPath).exists();

    final db = sqlite3.open(dbPath);

    // 性能优化设置
    try {
      db.execute('PRAGMA synchronous = NORMAL');
      db.execute('PRAGMA cache_size = -8000'); // 8MB 缓存
      db.execute('PRAGMA temp_store = MEMORY');
    } catch (e) {
      AppLogger.storage.warn('部分性能优化设置失败: $e');
    }

    if (!dbExists) {
      // 创建新数据库
      await _createTables(db, sourceUrl, targetWc);
    } else {
      // 检查并升级
      await _checkAndUpgrade(db);
    }

    _databases[hash] = db;
    AppLogger.storage.info('已打开 mergeinfo 数据库: $dbPath');

    return db;
  }

  /// 创建数据库表
  Future<void> _createTables(
      Database db, String sourceUrl, String targetWc) async {
    // 源信息表（用于校验）
    db.execute('''
      CREATE TABLE source_info (
        id INTEGER PRIMARY KEY,
        source_url TEXT NOT NULL,
        target_wc TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 插入源信息
    db.execute(
      'INSERT INTO source_info (id, source_url, target_wc, created_at) VALUES (1, ?, ?, ?)',
      [sourceUrl, targetWc, DateTime.now().millisecondsSinceEpoch],
    );

    // 已合并的 revision 表
    db.execute('''
      CREATE TABLE merged_revisions (
        revision INTEGER PRIMARY KEY,
        merged_at INTEGER NOT NULL
      )
    ''');

    // 创建索引
    db.execute('CREATE INDEX idx_revision ON merged_revisions(revision DESC)');

    // 元数据表
    db.execute('''
      CREATE TABLE cache_metadata (
        id INTEGER PRIMARY KEY,
        last_updated INTEGER NOT NULL,
        last_full_sync INTEGER
      )
    ''');

    // 初始化元数据
    db.execute(
      'INSERT INTO cache_metadata (id, last_updated, last_full_sync) VALUES (1, ?, NULL)',
      [DateTime.now().millisecondsSinceEpoch],
    );

    // 版本表
    db.execute('''
      CREATE TABLE db_version (
        version INTEGER PRIMARY KEY
      )
    ''');
    db.execute('INSERT INTO db_version (version) VALUES (?)', [_dbVersion]);

    AppLogger.storage.info('MergeInfo 数据库表创建完成');
  }

  /// 检查并升级数据库
  Future<void> _checkAndUpgrade(Database db) async {
    try {
      final versionResult = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='db_version'",
      );

      if (versionResult.isEmpty) {
        // 创建版本表
        db.execute('CREATE TABLE db_version (version INTEGER PRIMARY KEY)');
        db.execute('INSERT INTO db_version (version) VALUES (?)', [_dbVersion]);
      }
    } catch (e, stackTrace) {
      AppLogger.storage.warn('检查 mergeinfo 数据库版本失败: $e');
      AppLogger.storage.debug('详情', stackTrace);
    }
  }

  /// 从缓存加载已合并的 revision
  ///
  /// 这个方法会在程序启动时调用，加载缓存到内存
  Future<Set<int>> loadFromCache(String sourceUrl, String targetWc) async {
    final cacheKey = _generateCacheKey(sourceUrl, targetWc);

    // 如果已经加载过，直接返回内存缓存
    if (_cacheLoaded[cacheKey] == true && _memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }

    try {
      final db = await _getDatabase(sourceUrl, targetWc);
      final result = db.select('SELECT revision FROM merged_revisions');

      final revisions = result.map((row) => row.columnAt(0) as int).toSet();

      // 更新内存缓存
      _memoryCache[cacheKey] = revisions;
      _cacheLoaded[cacheKey] = true;

      AppLogger.storage.info('已从缓存加载 ${revisions.length} 个已合并的 revision');
      return revisions;
    } catch (e, stackTrace) {
      AppLogger.storage.error('从缓存加载 mergeinfo 失败', e, stackTrace);
      return {};
    }
  }

  /// 从 SVN 获取 mergeinfo 并更新缓存
  ///
  /// 这是获取 mergeinfo 的主要方法
  /// 会自动更新缓存
  ///
  /// SSOT 约束：
  /// - 已合并状态只以仓库 mergeinfo 为准。
  /// - 不能从目标工作副本的本地 svn:mergeinfo 属性推导，因为 `svn merge`
  ///   会先修改本地属性；若后续 commit 失败，本地属性仍会显示已合并。
  /// - 本服务的 SQLite / 内存集合只是仓库状态的缓存镜像，不是第二个状态源。
  ///
  /// [fullRefresh] 如果为 true，会先清空缓存再重新获取（用于 revert 后刷新）
  Future<Set<int>> fetchAndUpdateFromSvn(String sourceUrl, String targetWc,
      {bool fullRefresh = false}) async {
    if (!isMergeInfoArgsValid(sourceUrl, targetWc)) {
      return {};
    }

    try {
      // 如果是完整刷新，先清空缓存
      if (fullRefresh) {
        AppLogger.storage.info('完整刷新模式：清空现有缓存');
        final cacheKey = _generateCacheKey(sourceUrl, targetWc);
        _memoryCache.remove(cacheKey);
        _cacheLoaded.remove(cacheKey);

        // 清空数据库中的记录
        final db = await _getDatabase(sourceUrl, targetWc);
        db.execute('DELETE FROM merged_revisions');
      }

      final targetUrl = await _resolveRepositoryTarget(targetWc);
      AppLogger.storage.info('正在从仓库读取 mergeinfo: $sourceUrl -> $targetUrl');

      final mergedRevisions = await _svnService.getAllMergedRevisions(
        sourceUrl: sourceUrl,
        targetWc: targetUrl,
      );

      // 更新内存缓存（无论是否为空都要更新，以反映真实状态）
      final cacheKey = _generateCacheKey(sourceUrl, targetWc);
      _memoryCache[cacheKey] = mergedRevisions;
      _cacheLoaded[cacheKey] = true;

      await replaceCacheWithAuthoritativeRevisions(
        sourceUrl,
        targetWc,
        mergedRevisions,
      );

      AppLogger.storage.info('获取到 ${mergedRevisions.length} 个已合并的 revision');
      return mergedRevisions;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取 mergeinfo 失败', e, stackTrace);
      // 返回缓存中的数据
      return await loadFromCache(sourceUrl, targetWc);
    }
  }

  Future<String> _resolveRepositoryTarget(String targetWc) async {
    if (isSvnRepositoryUrl(targetWc)) {
      return targetWc;
    }
    final targetUrl = (await _svnService.getInfo(targetWc, item: 'url')).trim();
    if (targetUrl.isEmpty) {
      throw StateError('无法从目标工作副本解析 SVN URL，不能刷新 mergeinfo');
    }
    return targetUrl;
  }

  Future<void> replaceCacheWithAuthoritativeRevisions(
    String sourceUrl,
    String targetWc,
    Set<int> revisions,
  ) async {
    try {
      final db = await _getDatabase(sourceUrl, targetWc);
      final now = DateTime.now().millisecondsSinceEpoch;

      db.execute('BEGIN TRANSACTION');
      try {
        db.execute('DELETE FROM merged_revisions');
        if (revisions.isNotEmpty) {
          final stmt = db.prepare('''
            INSERT OR REPLACE INTO merged_revisions (revision, merged_at)
            VALUES (?, ?)
          ''');
          try {
            for (final rev in revisions) {
              stmt.execute([rev, now]);
            }
          } finally {
            stmt.dispose();
          }
        }

        db.execute(
          'UPDATE cache_metadata SET last_updated = ?, last_full_sync = ? WHERE id = 1',
          [now, now],
        );

        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }

      final cacheKey = _generateCacheKey(sourceUrl, targetWc);
      _memoryCache[cacheKey] = Set<int>.from(revisions);
      _cacheLoaded[cacheKey] = true;

      AppLogger.storage
          .info('已用仓库 mergeinfo 替换本地缓存: ${revisions.length} 个 revision');
    } catch (e, stackTrace) {
      AppLogger.storage.error('替换 mergeinfo 缓存失败', e, stackTrace);
    }
  }

  /// 同步检查指定的 revision 是否已合并（仅从内存缓存）
  ///
  /// 这是一个同步方法，只检查内存缓存
  /// 如果缓存未加载，返回 false
  ///
  /// 用于 UI 渲染时快速判断合并状态
  bool isRevisionMergedSync(String sourceUrl, String targetWc, int revision) {
    final cacheKey = _generateCacheKey(sourceUrl, targetWc);

    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!.contains(revision);
    }

    return false;
  }

  /// 同步获取已合并的 revision 集合（仅从内存缓存）
  ///
  /// 这是一个同步方法，只返回内存缓存中的数据
  /// 如果缓存未加载，返回空集合
  Set<int> getMergedRevisionsSync(String sourceUrl, String targetWc) {
    final cacheKey = _generateCacheKey(sourceUrl, targetWc);
    return _memoryCache[cacheKey] ?? {};
  }

  /// 检查指定的 revision 是否已合并
  ///
  /// 优先从内存缓存获取，如果没有则从数据库加载
  Future<bool> isRevisionMerged(
      String sourceUrl, String targetWc, int revision) async {
    final cacheKey = _generateCacheKey(sourceUrl, targetWc);

    // 先检查内存缓存
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!.contains(revision);
    }

    // 从缓存加载
    final revisions = await loadFromCache(sourceUrl, targetWc);
    return revisions.contains(revision);
  }

  /// 批量检查 revision 的合并状态
  ///
  /// 返回 Map<int, bool>，key 是 revision，value 是是否已合并
  Future<Map<int, bool>> checkMergedStatus(
    String sourceUrl,
    String targetWc,
    List<int> revisions,
  ) async {
    final cacheKey = _generateCacheKey(sourceUrl, targetWc);

    // 确保缓存已加载
    if (!_memoryCache.containsKey(cacheKey)) {
      await loadFromCache(sourceUrl, targetWc);
    }

    final mergedSet = _memoryCache[cacheKey] ?? {};

    return buildMergedStatusMap(revisions, mergedSet);
  }

  /// 获取所有已合并的 revision（从缓存）
  ///
  /// 如果缓存为空，会尝试从 SVN 获取
  ///
  /// [forceRefresh] 如果为 true，会重新从 SVN 获取（但保留缓存作为增量）
  /// [fullRefresh] 如果为 true，会先清空缓存再重新获取（用于 revert 后刷新）
  Future<Set<int>> getMergedRevisions(
    String sourceUrl,
    String targetWc, {
    bool forceRefresh = false,
    bool fullRefresh = false,
  }) async {
    if (!isMergeInfoArgsValid(sourceUrl, targetWc)) {
      return {};
    }

    // fullRefresh / forceRefresh 优先级最高，无需先读缓存
    if (fullRefresh) {
      return await fetchAndUpdateFromSvn(sourceUrl, targetWc,
          fullRefresh: true);
    }
    if (forceRefresh) {
      return await fetchAndUpdateFromSvn(sourceUrl, targetWc);
    }

    // 否则先看缓存，缓存为空再拉
    final cached = await loadFromCache(sourceUrl, targetWc);
    final strategy = chooseMergeInfoFetchStrategy(
      fullRefresh: false,
      forceRefresh: false,
      cacheIsEmpty: cached.isEmpty,
    );
    switch (strategy) {
      case MergeInfoFetchStrategy.useCache:
        return cached;
      case MergeInfoFetchStrategy.fetchBecauseCacheEmpty:
        return await fetchAndUpdateFromSvn(sourceUrl, targetWc);
      case MergeInfoFetchStrategy.fullRefresh:
      case MergeInfoFetchStrategy.forceRefresh:
        // 上面已经短路返回，这里不会到达；保留以让 switch 穷尽。
        return cached;
    }
  }

  /// 清空指定 sourceUrl + targetWc 的缓存
  ///
  /// **R125 关闭序列约束：dispose → memory cache → file 三阶段顺序锁**
  ///   阶段 1: `_databases[hash]!.dispose()` + `_databases.remove(hash)`（先释放
  ///           sqlite handle 再 drop map 引用——避免 use-after-free）；
  ///   阶段 2: `_memoryCache.remove(cacheKey)` + `_cacheLoaded.remove(cacheKey)`
  ///           （两条 mapping 同步 remove —— 与 R124 双结构同步 mutator 模式同源）；
  ///   阶段 3: `dbFile.delete()`（OS 层删文件）；
  ///   阶段 4: `AppLogger.storage.info(...)`（日志最后）。
  /// **为什么阶段 1 必须先于阶段 3**：与 `log_cache_service.clearCache` 同形约束
  /// （Windows 下 sqlite handle 持有文件锁，先 delete 后 dispose 会 PathAccessException）。
  /// **为什么阶段 2 在阶段 1 之后**：阶段 2 清空内存缓存条目；如果先于阶段 1，
  /// 在 dispose 期间若有并发 read（理论上）会从 _memoryCache miss 落到 _databases
  /// 仍持有的 handle 上、行为不一致——当前顺序保证"释放方向单调"（handle → memory
  /// → file → log）。
  /// **与 `log_cache_service.clearCache` 的差异锁**：本函数多一个 _memoryCache /
  /// _cacheLoaded 阶段（log_cache 没有内存缓存）—— 不是同形 inline duplication，
  /// 故意按"先释放 handle、再清内存、最后删文件"统一顺序模式而不抽 helper。
  Future<void> clearCache(String sourceUrl, String targetWc) async {
    try {
      final hash = _generateHash(sourceUrl, targetWc);
      final cacheKey = _generateCacheKey(sourceUrl, targetWc);

      // 关闭数据库
      if (_databases.containsKey(hash)) {
        _databases[hash]!.dispose();
        _databases.remove(hash);
      }

      // 清空内存缓存
      _memoryCache.remove(cacheKey);
      _cacheLoaded.remove(cacheKey);

      // 删除数据库文件
      final dbPath = _getDbPath(hash);
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      AppLogger.storage.info('已清空 mergeinfo 缓存: $sourceUrl -> $targetWc');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空 mergeinfo 缓存失败', e, stackTrace);
    }
  }

  /// 清空所有缓存
  ///
  /// **R134 档 3 unbounded-manual-nuke-all**：与 `LogCacheService.clearAllCache`
  /// 同档——sqlite-backed 服务无容量上限（K1 不变量满足）、用户显式触发、清空粒度
  /// = 全部 db 文件 + 内存（_databases / _memoryCache / _cacheLoaded 三 Map 同步
  /// 清，K4 双结构同步 mutator 三向化）。与档 1 [LogFileCacheService] 自动 LRU
  /// 形成对偶——三个 cache 服务策略**故意不同**，详见
  /// [LogFileCacheService] 类 doc 的 R134 章节（4 档分类 + K1/K2/K3/K4 不变量）。
  Future<void> clearAllCache() async {
    try {
      // 关闭所有数据库
      for (final db in _databases.values) {
        db.dispose();
      }
      _databases.clear();
      _memoryCache.clear();
      _cacheLoaded.clear();

      // 删除所有缓存文件
      if (_cacheDir != null) {
        final cacheDir = Directory(_cacheDir!);
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list()) {
            if (entity is File && entity.path.endsWith('.db')) {
              await entity.delete();
            }
          }
        }
      }

      AppLogger.storage.info('已清空所有 mergeinfo 缓存');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空所有 mergeinfo 缓存失败', e, stackTrace);
    }
  }

  /// 获取缓存的最后更新时间
  Future<DateTime?> getLastUpdated(String sourceUrl, String targetWc) async {
    try {
      final db = await _getDatabase(sourceUrl, targetWc);
      final result =
          db.select('SELECT last_updated FROM cache_metadata WHERE id = 1');

      if (result.isEmpty) {
        return null;
      }

      final timestamp = result.first.columnAt(0) as int?;
      return parseDbTimestamp(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// 获取上次全量同步时间
  Future<DateTime?> getLastFullSync(String sourceUrl, String targetWc) async {
    try {
      final db = await _getDatabase(sourceUrl, targetWc);
      final result =
          db.select('SELECT last_full_sync FROM cache_metadata WHERE id = 1');

      if (result.isEmpty) {
        return null;
      }

      final timestamp = result.first.columnAt(0) as int?;
      return parseDbTimestamp(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// 关闭所有数据库
  ///
  /// **R121 资源释放协议档 2：伪异步同步释放型**
  /// 签名是 `Future<void> close() async` 但函数体**无 `await`** —— `db.dispose()`
  /// 是 sqlite3 的同步 API、`_databases.clear()` 也是同步。**为什么保留 async**：
  /// 与 `log_cache_service.close()` / `logger_service.close()` 接口同形，便于
  /// `Future.wait([...])` 风格批量收口；改成 `void close()` 会破坏 dual-channel
  /// 一致性。**对称释放语义**：调用 `await close()` 仅保证内存映射已释放（map
  /// clear + sqlite handle dispose），**没有 IO 落盘语义**（档 1 的强保证）—— sqlite3
  /// 的 dispose 在 WAL 模式下不强制 checkpoint，但崩溃恢复由 sqlite3 文件协议保
  /// 证。**幂等机制**：`_databases.clear()` 后再次 close 遍历空 map 即 noop（不
  /// 像档 1 那样需要状态位）。**与 `log_cache_service.close()` 的同形锁**：两处
  /// 释放代码完全同结构，只差日志 tag —— 故意保留 inline duplication（档 2 的
  /// "1 行 for + 1 行 clear + 1 行 log"过于稀薄，抽 helper 不抵 duplication 成
  /// 本，与 R59 helper-vs-inline 阈值原则一致）。
  ///
  /// **R125 关闭序列约束：dispose-before-clear（三步顺序不可互换）**
  /// 函数体三步必须严格按当前顺序：
  ///   step 1: `for db in _databases.values { db.dispose(); }`（释放 sqlite handle）
  ///   step 2: `_databases.clear()`（map 清空）
  ///   step 3: `AppLogger.storage.info(...)`（日志记录）
  /// **为什么 step 1 必须先于 step 2**：clear 先调，**values 引用立即失效**
  /// （Dart Map.clear 不保证已 iterate 出的 values 仍可用），dispose 会在野指针
  /// 上调，**导致 sqlite3 native 层 use-after-free**。当前顺序保证 dispose 完
  /// 全跑完后才 drop map 引用——同形 callsite 锁。
  /// **为什么 step 3 必须在最后**：logger 是异步 fire-and-forget；如果 step 3
  /// 在 step 1 之前，"已关闭" 日志会先于真正关闭出现（误导性日志），违反
  /// "**日志反映系统状态而非意图**" 原则。
  /// **同形锁**：`log_cache_service.close()` 必须保持完全相同的三步顺序——R125
  /// 在 doc-as-test 用 `mergeinfo_cache_service.close 与 log_cache_service.close
  /// 同形 step 顺序锁定` 显式锁。
  Future<void> close() async {
    for (final db in _databases.values) {
      db.dispose();
    }
    _databases.clear();
    AppLogger.storage.info('MergeInfo 缓存数据库已关闭');
  }
}
