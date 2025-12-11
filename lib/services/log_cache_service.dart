/// SVN 日志缓存服务
///
/// 负责管理 SVN 日志的本地缓存
/// - 使用 SQLite 数据库存储（支持百万级数据）
/// - 每个 sourceUrl 对应独立的数据库文件（真正的分库）
/// - 支持增量更新（从缓存最新版本到 HEAD）
/// - 提供高效的查询接口
/// - 支持所有平台（包括 Windows）
/// - 双向校验确保数据库不会用错

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;
import '../models/log_entry.dart';
import 'logger_service.dart';

/// 缓存校验错误
class CacheValidationError {
  final String message;
  final String expectedUrl;
  final String actualUrl;
  final String dbPath;

  CacheValidationError({
    required this.message,
    required this.expectedUrl,
    required this.actualUrl,
    required this.dbPath,
  });

  @override
  String toString() => message;
}

/// 缓存校验错误回调类型
typedef CacheValidationErrorCallback = void Function(CacheValidationError error);

class LogCacheService {
  /// 单例模式
  static final LogCacheService _instance = LogCacheService._internal();
  factory LogCacheService() => _instance;
  LogCacheService._internal();

  /// 数据库缓存目录
  String? _cacheDir;
  
  /// 当前打开的数据库（按 sourceUrl hash 索引）
  final Map<String, Database> _databases = {};
  
  /// URL 到 hash 的映射（持久化存储）
  final Map<String, String> _urlToHashMap = {};
  
  /// hash 到 URL 的映射（用于反向查找）
  final Map<String, String> _hashToUrlMap = {};
  
  /// SharedPreferences 实例
  SharedPreferences? _prefs;
  
  /// 数据库版本
  static const int _dbVersion = 3;
  
  /// 映射存储的 key
  static const String _urlHashMapKey = 'log_cache_url_hash_map';
  
  /// 缓存校验错误回调
  CacheValidationErrorCallback? onValidationError;

  /// 初始化服务
  Future<void> init() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = path.join(appDir.path, 'SvnMergeTool', 'cache');
      
      // 确保缓存目录存在
      final cacheDir = Directory(_cacheDir!);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      
      // 加载 URL 到 hash 的映射
      _prefs = await SharedPreferences.getInstance();
      await _loadUrlHashMap();
      
      AppLogger.storage.info('日志缓存服务初始化成功: $_cacheDir');
    } catch (e, stackTrace) {
      AppLogger.storage.error('日志缓存服务初始化失败', e, stackTrace);
      rethrow;
    }
  }

  /// 加载 URL 到 hash 的映射
  Future<void> _loadUrlHashMap() async {
    try {
      final json = _prefs?.getString(_urlHashMapKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _urlToHashMap.clear();
        _hashToUrlMap.clear();
        for (final entry in map.entries) {
          _urlToHashMap[entry.key] = entry.value as String;
          _hashToUrlMap[entry.value as String] = entry.key;
        }
        AppLogger.storage.info('已加载 ${_urlToHashMap.length} 个 URL-hash 映射');
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('加载 URL-hash 映射失败', e, stackTrace);
    }
  }

  /// 保存 URL 到 hash 的映射
  Future<void> _saveUrlHashMap() async {
    try {
      final json = jsonEncode(_urlToHashMap);
      await _prefs?.setString(_urlHashMapKey, json);
    } catch (e, stackTrace) {
      AppLogger.storage.error('保存 URL-hash 映射失败', e, stackTrace);
    }
  }

  /// 生成 sourceUrl 的 hash（使用 MD5，取前 16 位）
  String _generateHash(String sourceUrl) {
    final bytes = utf8.encode(sourceUrl);
    final digest = md5.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// 获取或创建 sourceUrl 对应的 hash
  Future<String> _getOrCreateHash(String sourceUrl) async {
    // 先检查是否已有映射
    if (_urlToHashMap.containsKey(sourceUrl)) {
      return _urlToHashMap[sourceUrl]!;
    }
    
    // 生成新的 hash
    String hash = _generateHash(sourceUrl);
    
    // 检查 hash 冲突
    int attempt = 0;
    while (_hashToUrlMap.containsKey(hash) && _hashToUrlMap[hash] != sourceUrl) {
      // 发生冲突，添加后缀重新生成
      attempt++;
      hash = _generateHash('$sourceUrl#$attempt');
      AppLogger.storage.warn('检测到 hash 冲突，尝试第 $attempt 次: $sourceUrl');
    }
    
    // 保存映射
    _urlToHashMap[sourceUrl] = hash;
    _hashToUrlMap[hash] = sourceUrl;
    await _saveUrlHashMap();
    
    AppLogger.storage.info('创建新的 URL-hash 映射: $sourceUrl -> $hash');
    return hash;
  }

  /// 获取数据库文件路径
  String _getDbPath(String hash) {
    return path.join(_cacheDir!, 'cache_$hash.db');
  }

  /// 获取或打开指定 sourceUrl 的数据库
  Future<Database> _getDatabase(String sourceUrl) async {
    await _ensureInit();
    
    final hash = await _getOrCreateHash(sourceUrl);
    
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
      db.execute('PRAGMA cache_size = -64000'); // 64MB 缓存
      db.execute('PRAGMA temp_store = MEMORY');
    } catch (e) {
      AppLogger.storage.warn('部分性能优化设置失败: $e');
    }
    
    if (!dbExists) {
      // 创建新数据库
      await _createTables(db, sourceUrl);
    } else {
      // 校验现有数据库
      final isValid = await _validateDatabase(db, sourceUrl, dbPath);
      if (!isValid) {
        db.dispose();
        throw Exception('数据库校验失败: $dbPath');
      }
      // 检查并升级
      await _checkAndUpgrade(db);
    }
    
    _databases[hash] = db;
    AppLogger.storage.info('已打开数据库: $dbPath (sourceUrl: $sourceUrl)');
    
    return db;
  }

  /// 创建数据库表
  Future<void> _createTables(Database db, String sourceUrl) async {
    // 源信息表（用于校验）
    db.execute('''
      CREATE TABLE source_info (
        id INTEGER PRIMARY KEY,
        source_url TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    
    // 插入源 URL 信息
    db.execute(
      'INSERT INTO source_info (id, source_url, created_at) VALUES (1, ?, ?)',
      [sourceUrl, DateTime.now().millisecondsSinceEpoch],
    );
    
    // 日志条目表（简化版，不再需要 source_url_hash）
    db.execute('''
      CREATE TABLE log_entries (
        revision INTEGER PRIMARY KEY,
        author TEXT NOT NULL,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 创建索引
    db.execute('CREATE INDEX idx_revision ON log_entries(revision DESC)');
    db.execute('CREATE INDEX idx_author ON log_entries(author)');
    db.execute('CREATE INDEX idx_date ON log_entries(date DESC)');

    // 缓存元数据表
    db.execute('''
      CREATE TABLE cache_metadata (
        id INTEGER PRIMARY KEY,
        latest_revision INTEGER NOT NULL,
        earliest_revision INTEGER,
        last_updated INTEGER NOT NULL
      )
    ''');
    
    // 初始化元数据
    db.execute(
      'INSERT INTO cache_metadata (id, latest_revision, earliest_revision, last_updated) VALUES (1, 0, NULL, ?)',
      [DateTime.now().millisecondsSinceEpoch],
    );

    // 版本表
    db.execute('''
      CREATE TABLE db_version (
        version INTEGER PRIMARY KEY
      )
    ''');
    db.execute('INSERT INTO db_version (version) VALUES (?)', [_dbVersion]);

    AppLogger.storage.info('数据库表创建完成');
  }

  /// 校验数据库（双向校验）
  Future<bool> _validateDatabase(Database db, String expectedUrl, String dbPath) async {
    try {
      // 检查 source_info 表是否存在
      final tableResult = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='source_info'",
      );
      
      if (tableResult.isEmpty) {
        // 旧版本数据库，需要迁移
        AppLogger.storage.warn('检测到旧版本数据库，需要迁移: $dbPath');
        return await _migrateOldDatabase(db, expectedUrl);
      }
      
      // 读取存储的 source_url
      final result = db.select('SELECT source_url FROM source_info WHERE id = 1');
      if (result.isEmpty) {
        AppLogger.storage.error('数据库中缺少 source_info 记录: $dbPath');
        return false;
      }
      
      final storedUrl = result.first.columnAt(0) as String;
      
      // 校验 URL 是否匹配
      if (storedUrl != expectedUrl) {
        final error = CacheValidationError(
          message: '【严重错误】数据库 URL 不匹配！\n'
              '期望: $expectedUrl\n'
              '实际: $storedUrl\n'
              '数据库: $dbPath\n'
              '这可能是由于 hash 冲突或配置错误导致的。',
          expectedUrl: expectedUrl,
          actualUrl: storedUrl,
          dbPath: dbPath,
        );
        
        AppLogger.storage.error(error.message);
        
        // 触发错误回调
        onValidationError?.call(error);
        
        return false;
      }
      
      AppLogger.storage.info('数据库校验通过: $dbPath');
      return true;
    } catch (e, stackTrace) {
      AppLogger.storage.error('数据库校验失败', e, stackTrace);
      return false;
    }
  }

  /// 迁移旧版本数据库
  Future<bool> _migrateOldDatabase(Database db, String sourceUrl) async {
    try {
      // 创建 source_info 表
      db.execute('''
        CREATE TABLE source_info (
          id INTEGER PRIMARY KEY,
          source_url TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      
      db.execute(
        'INSERT INTO source_info (id, source_url, created_at) VALUES (1, ?, ?)',
        [sourceUrl, DateTime.now().millisecondsSinceEpoch],
      );
      
      AppLogger.storage.info('旧数据库迁移完成: 已添加 source_info 表');
      return true;
    } catch (e, stackTrace) {
      AppLogger.storage.error('旧数据库迁移失败', e, stackTrace);
      return false;
    }
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
        db.execute('INSERT INTO db_version (version) VALUES (1)');
        await _onUpgrade(db, 1, _dbVersion);
        db.execute('UPDATE db_version SET version = ?', [_dbVersion]);
      } else {
        final versionRows = db.select('SELECT version FROM db_version LIMIT 1');
        if (versionRows.isNotEmpty) {
          final currentVersion = versionRows.first.columnAt(0) as int;
          if (currentVersion < _dbVersion) {
            await _onUpgrade(db, currentVersion, _dbVersion);
            db.execute('UPDATE db_version SET version = ?', [_dbVersion]);
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.storage.warn('检查数据库版本失败: $e');
      AppLogger.storage.debug('详情', stackTrace);
    }
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // 版本 3：添加 date 索引
      try {
        db.execute('CREATE INDEX IF NOT EXISTS idx_date ON log_entries(date DESC)');
        AppLogger.storage.info('已添加 date 索引（数据库升级）');
      } catch (e) {
        AppLogger.storage.warn('添加 date 索引失败（可能已存在）: $e');
      }
    }
  }

  /// 确保服务已初始化
  Future<void> _ensureInit() async {
    if (_cacheDir == null) {
      await init();
    }
  }

  /// 获取缓存中指定 sourceUrl 的最新版本号
  Future<int> getLatestRevision(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select('SELECT latest_revision FROM cache_metadata WHERE id = 1');
      
      if (result.isEmpty) {
        return 0;
      }
      
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取缓存中指定 sourceUrl 的最早版本号
  Future<int> getEarliestRevision(String sourceUrl, {int? minRevision}) async {
    try {
      final db = await _getDatabase(sourceUrl);
      
      var query = 'SELECT MIN(revision) FROM log_entries';
      final args = <Object>[];
      
      if (minRevision != null && minRevision > 0) {
        query += ' WHERE revision >= ?';
        args.add(minRevision);
      }
      
      final result = db.select(query, args);
      
      if (result.isEmpty) {
        return 0;
      }
      
      final value = result.first.columnAt(0);
      return value != null ? value as int : 0;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最早版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 批量插入日志条目
  Future<void> insertEntries(String sourceUrl, List<LogEntry> entries) async {
    if (entries.isEmpty) return;

    try {
      final db = await _getDatabase(sourceUrl);
      const batchSize = 1000;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < entries.length; i += batchSize) {
        final batch = entries.sublist(
          i,
          (i + batchSize).clamp(0, entries.length),
        );

        db.execute('BEGIN TRANSACTION');
        try {
          final stmt = db.prepare('''
            INSERT OR REPLACE INTO log_entries 
            (revision, author, date, title, message, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
          ''');

          for (final entry in batch) {
            stmt.execute([
              entry.revision,
              entry.author,
              entry.date,
              entry.title,
              entry.message,
              now,
            ]);
          }
          stmt.dispose();
          db.execute('COMMIT');
        } catch (e) {
          db.execute('ROLLBACK');
          rethrow;
        }
      }

      // 更新元数据
      final latestRevision = entries.map((e) => e.revision).reduce((a, b) => a > b ? a : b);
      final earliestRevision = entries.map((e) => e.revision).reduce((a, b) => a < b ? a : b);
      
      // 获取当前元数据
      final currentMeta = db.select('SELECT latest_revision, earliest_revision FROM cache_metadata WHERE id = 1');
      int newLatest = latestRevision;
      int? newEarliest = earliestRevision;
      
      if (currentMeta.isNotEmpty) {
        final currentLatest = currentMeta.first.columnAt(0) as int;
        final currentEarliest = currentMeta.first.columnAt(1) as int?;
        
        if (currentLatest > newLatest) {
          newLatest = currentLatest;
        }
        if (currentEarliest != null && currentEarliest < newEarliest) {
          newEarliest = currentEarliest;
        }
      }
      
      db.execute(
        'UPDATE cache_metadata SET latest_revision = ?, earliest_revision = ?, last_updated = ? WHERE id = 1',
        [newLatest, newEarliest, now],
      );

      AppLogger.storage.info('已插入 ${entries.length} 条日志到缓存: $sourceUrl');
    } catch (e, stackTrace) {
      AppLogger.storage.error('插入日志条目失败', e, stackTrace);
      rethrow;
    }
  }

  /// 从缓存获取日志条目
  Future<List<LogEntry>> getEntries(
    String sourceUrl, {
    int? limit,
    int offset = 0,
    String? authorFilter,
    String? titleFilter,
    int? minRevision,
  }) async {
    try {
      final db = await _getDatabase(sourceUrl);
      
      final whereConditions = <String>[];
      final whereArgs = <Object>[];
      
      if (minRevision != null && minRevision > 0) {
        whereConditions.add('revision >= ?');
        whereArgs.add(minRevision);
      }
      
      if (authorFilter != null && authorFilter.isNotEmpty) {
        whereConditions.add('author = ?');
        whereArgs.add(authorFilter.trim());
      }
      
      if (titleFilter != null && titleFilter.isNotEmpty) {
        whereConditions.add('LOWER(title) LIKE ?');
        whereArgs.add('%${titleFilter.toLowerCase()}%');
      }
      
      var query = 'SELECT revision, author, date, title, message FROM log_entries';
      
      if (whereConditions.isNotEmpty) {
        query += ' WHERE ${whereConditions.join(' AND ')}';
      }
      
      query += ' ORDER BY revision DESC';
      
      if (limit != null) {
        query += ' LIMIT ? OFFSET ?';
        whereArgs.add(limit);
        whereArgs.add(offset);
      }

      final results = db.select(query, whereArgs);
      return results.map((row) => LogEntry(
        revision: row.columnAt(0) as int,
        author: row.columnAt(1) as String,
        date: row.columnAt(2) as String,
        title: row.columnAt(3) as String,
        message: row.columnAt(4) as String,
      )).toList();
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取日志条目失败', e, stackTrace);
      return [];
    }
  }

  /// 获取缓存中的日志总数
  Future<int> getEntryCount(
    String sourceUrl, {
    String? authorFilter,
    String? titleFilter,
    int? minRevision,
  }) async {
    try {
      final db = await _getDatabase(sourceUrl);
      
      final whereConditions = <String>[];
      final whereArgs = <Object>[];
      
      if (minRevision != null && minRevision > 0) {
        whereConditions.add('revision >= ?');
        whereArgs.add(minRevision);
      }
      
      if (authorFilter != null && authorFilter.isNotEmpty) {
        whereConditions.add('LOWER(author) LIKE ?');
        whereArgs.add('%${authorFilter.toLowerCase()}%');
      }
      
      if (titleFilter != null && titleFilter.isNotEmpty) {
        whereConditions.add('LOWER(title) LIKE ?');
        whereArgs.add('%${titleFilter.toLowerCase()}%');
      }
      
      var query = 'SELECT COUNT(*) FROM log_entries';
      
      if (whereConditions.isNotEmpty) {
        query += ' WHERE ${whereConditions.join(' AND ')}';
      }
      
      final result = db.select(query, whereArgs);
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取日志数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取缓存中的日志总数（不带过滤条件）
  Future<int> getTotalCount(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select('SELECT COUNT(*) FROM log_entries');
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取日志总数失败', e, stackTrace);
      return 0;
    }
  }

  /// 清空指定 sourceUrl 的缓存
  Future<void> clearCache(String sourceUrl) async {
    try {
      final hash = await _getOrCreateHash(sourceUrl);
      
      // 关闭数据库
      if (_databases.containsKey(hash)) {
        _databases[hash]!.dispose();
        _databases.remove(hash);
      }
      
      // 删除数据库文件
      final dbPath = _getDbPath(hash);
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      
      AppLogger.storage.info('已清空缓存: $sourceUrl');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空缓存失败', e, stackTrace);
    }
  }

  /// 根据 revision 列表获取日志条目
  Future<List<LogEntry>> getEntriesByRevisions(
    String sourceUrl,
    List<int> revisions,
  ) async {
    if (revisions.isEmpty) {
      return [];
    }

    try {
      final db = await _getDatabase(sourceUrl);
      
      final placeholders = List.filled(revisions.length, '?').join(',');
      final query = '''
        SELECT revision, author, date, title, message 
        FROM log_entries 
        WHERE revision IN ($placeholders)
        ORDER BY revision DESC
      ''';
      
      final results = db.select(query, revisions);
      
      return results.map((row) => LogEntry(
        revision: row.columnAt(0) as int,
        author: row.columnAt(1) as String,
        date: row.columnAt(2) as String,
        title: row.columnAt(3) as String,
        message: row.columnAt(4) as String,
      )).toList();
    } catch (e, stackTrace) {
      AppLogger.storage.error('根据 revision 获取日志条目失败', e, stackTrace);
      return [];
    }
  }

  /// 获取缓存中最早的日期
  Future<DateTime?> getEarliestDate(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select('SELECT MIN(date) FROM log_entries');

      if (result.isEmpty) {
        return null;
      }

      final value = result.first.columnAt(0);
      if (value == null) {
        return null;
      }

      try {
        return DateTime.parse(value as String);
      } catch (_) {
        return null;
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最早日期失败', e, stackTrace);
      return null;
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
      
      // 清空映射
      _urlToHashMap.clear();
      _hashToUrlMap.clear();
      await _saveUrlHashMap();
      
      AppLogger.storage.info('已清空所有缓存');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空所有缓存失败', e, stackTrace);
    }
  }

  /// 关闭所有数据库
  Future<void> close() async {
    for (final db in _databases.values) {
      db.dispose();
    }
    _databases.clear();
    AppLogger.storage.info('日志缓存数据库已关闭');
  }
  
  /// 获取所有已缓存的 URL 列表
  List<String> getCachedUrls() {
    return _urlToHashMap.keys.toList();
  }
  
  /// 获取缓存目录路径
  String? getCacheDir() => _cacheDir;
}
