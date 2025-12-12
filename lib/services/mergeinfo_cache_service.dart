/// MergeInfo 缓存服务
///
/// 负责管理 SVN mergeinfo 的本地缓存
/// - 使用 SQLite 数据库存储（与 LogCacheService 共用数据库）
/// - 每个 sourceUrl + targetWc 组合对应独立的缓存
/// - 支持增量更新（只更新新的 revision）
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
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;
import 'logger_service.dart';
import 'svn_service.dart';

/// MergeInfo 缓存服务
/// 
/// 提供 mergeinfo 的缓存和获取功能
/// 所有 mergeinfo 相关的操作都应该通过这个服务
class MergeInfoCacheService {
  /// 单例模式
  static final MergeInfoCacheService _instance = MergeInfoCacheService._internal();
  factory MergeInfoCacheService() => _instance;
  MergeInfoCacheService._internal();

  /// 数据库缓存目录
  String? _cacheDir;
  
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
  Future<void> init() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = path.join(appDir.path, 'SvnMergeTool', 'mergeinfo_cache');
      
      // 确保缓存目录存在
      final cacheDir = Directory(_cacheDir!);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      
      AppLogger.storage.info('MergeInfo 缓存服务初始化成功: $_cacheDir');
    } catch (e, stackTrace) {
      AppLogger.storage.error('MergeInfo 缓存服务初始化失败', e, stackTrace);
      rethrow;
    }
  }

  /// 生成缓存 key
  String _generateCacheKey(String sourceUrl, String targetWc) {
    return '$sourceUrl|$targetWc';
  }

  /// 生成数据库文件名的 hash
  String _generateHash(String sourceUrl, String targetWc) {
    final key = _generateCacheKey(sourceUrl, targetWc);
    final bytes = utf8.encode(key);
    final digest = md5.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// 获取数据库文件路径
  String _getDbPath(String hash) {
    return path.join(_cacheDir!, 'mergeinfo_$hash.db');
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
  Future<void> _createTables(Database db, String sourceUrl, String targetWc) async {
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

  /// 保存已合并的 revision 到缓存
  Future<void> saveToCache(String sourceUrl, String targetWc, Set<int> revisions) async {
    if (revisions.isEmpty) return;
    
    try {
      final db = await _getDatabase(sourceUrl, targetWc);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      db.execute('BEGIN TRANSACTION');
      try {
        final stmt = db.prepare('''
          INSERT OR REPLACE INTO merged_revisions (revision, merged_at)
          VALUES (?, ?)
        ''');
        
        for (final rev in revisions) {
          stmt.execute([rev, now]);
        }
        stmt.dispose();
        
        // 更新元数据
        db.execute(
          'UPDATE cache_metadata SET last_updated = ? WHERE id = 1',
          [now],
        );
        
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
      
      // 更新内存缓存
      final cacheKey = _generateCacheKey(sourceUrl, targetWc);
      _memoryCache[cacheKey] ??= {};
      _memoryCache[cacheKey]!.addAll(revisions);
      
      AppLogger.storage.info('已保存 ${revisions.length} 个已合并的 revision 到缓存');
    } catch (e, stackTrace) {
      AppLogger.storage.error('保存 mergeinfo 到缓存失败', e, stackTrace);
    }
  }

  /// 从 SVN 获取 mergeinfo 并更新缓存
  /// 
  /// 这是获取 mergeinfo 的主要方法
  /// 会自动更新缓存
  /// 
  /// 优化策略：
  /// 1. 先尝试从本地 svn:mergeinfo 属性读取（快速，无网络请求）
  /// 2. 如果失败，再使用 svn mergeinfo 命令（慢，需要网络）
  /// 
  /// [fullRefresh] 如果为 true，会先清空缓存再重新获取（用于 revert 后刷新）
  Future<Set<int>> fetchAndUpdateFromSvn(String sourceUrl, String targetWc, {bool fullRefresh = false}) async {
    if (sourceUrl.isEmpty || targetWc.isEmpty) {
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
      
      AppLogger.storage.info('正在从本地属性读取 mergeinfo: $sourceUrl -> $targetWc');
      
      // 优先使用快速的本地属性读取
      var mergedRevisions = await _svnService.getMergedRevisionsFromPropget(
        sourceUrl: sourceUrl,
        targetWc: targetWc,
      );
      
      // 如果本地读取失败或为空，使用传统方法
      if (mergedRevisions.isEmpty) {
        AppLogger.storage.info('本地属性为空，使用 svn mergeinfo 命令...');
        mergedRevisions = await _svnService.getAllMergedRevisions(
          sourceUrl: sourceUrl,
          targetWc: targetWc,
        );
      }
      
      // 更新内存缓存（无论是否为空都要更新，以反映真实状态）
      final cacheKey = _generateCacheKey(sourceUrl, targetWc);
      _memoryCache[cacheKey] = mergedRevisions;
      _cacheLoaded[cacheKey] = true;
      
      if (mergedRevisions.isNotEmpty) {
        // 保存到数据库缓存
        await saveToCache(sourceUrl, targetWc, mergedRevisions);
        
        // 更新全量同步时间
        final db = await _getDatabase(sourceUrl, targetWc);
        db.execute(
          'UPDATE cache_metadata SET last_full_sync = ? WHERE id = 1',
          [DateTime.now().millisecondsSinceEpoch],
        );
      }
      
      AppLogger.storage.info('获取到 ${mergedRevisions.length} 个已合并的 revision');
      return mergedRevisions;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取 mergeinfo 失败', e, stackTrace);
      // 返回缓存中的数据
      return await loadFromCache(sourceUrl, targetWc);
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
  Future<bool> isRevisionMerged(String sourceUrl, String targetWc, int revision) async {
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
    final result = <int, bool>{};
    
    // 确保缓存已加载
    if (!_memoryCache.containsKey(cacheKey)) {
      await loadFromCache(sourceUrl, targetWc);
    }
    
    final mergedSet = _memoryCache[cacheKey] ?? {};
    
    for (final rev in revisions) {
      result[rev] = mergedSet.contains(rev);
    }
    
    return result;
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
    if (sourceUrl.isEmpty || targetWc.isEmpty) {
      return {};
    }
    
    // 如果完整刷新，清空缓存并重新获取
    if (fullRefresh) {
      return await fetchAndUpdateFromSvn(sourceUrl, targetWc, fullRefresh: true);
    }
    
    // 如果强制刷新，从 SVN 获取
    if (forceRefresh) {
      return await fetchAndUpdateFromSvn(sourceUrl, targetWc);
    }
    
    // 先尝试从缓存加载
    final cached = await loadFromCache(sourceUrl, targetWc);
    
    // 如果缓存为空，从 SVN 获取
    if (cached.isEmpty) {
      return await fetchAndUpdateFromSvn(sourceUrl, targetWc);
    }
    
    return cached;
  }

  /// 添加单个已合并的 revision（由本程序合并后调用）
  Future<void> addMergedRevision(String sourceUrl, String targetWc, int revision) async {
    await saveToCache(sourceUrl, targetWc, {revision});
  }

  /// 添加多个已合并的 revision
  Future<void> addMergedRevisions(String sourceUrl, String targetWc, Set<int> revisions) async {
    await saveToCache(sourceUrl, targetWc, revisions);
  }

  /// 清空指定 sourceUrl + targetWc 的缓存
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
      final result = db.select('SELECT last_updated FROM cache_metadata WHERE id = 1');
      
      if (result.isEmpty) {
        return null;
      }
      
      final timestamp = result.first.columnAt(0) as int?;
      if (timestamp == null) {
        return null;
      }
      
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// 获取上次全量同步时间
  Future<DateTime?> getLastFullSync(String sourceUrl, String targetWc) async {
    try {
      final db = await _getDatabase(sourceUrl, targetWc);
      final result = db.select('SELECT last_full_sync FROM cache_metadata WHERE id = 1');
      
      if (result.isEmpty) {
        return null;
      }
      
      final timestamp = result.first.columnAt(0) as int?;
      if (timestamp == null) {
        return null;
      }
      
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// 关闭所有数据库
  Future<void> close() async {
    for (final db in _databases.values) {
      db.dispose();
    }
    _databases.clear();
    AppLogger.storage.info('MergeInfo 缓存数据库已关闭');
  }
}
