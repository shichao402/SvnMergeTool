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

/// 缓存的版本区间
/// 
/// 表示一段连续缓存的 SVN 日志版本范围
/// [startRevision] 是较大的版本号（新），[endRevision] 是较小的版本号（旧）
class CachedRange {
  final int id;
  final int startRevision;  // 区间起点（较大值，新）
  final int endRevision;    // 区间终点（较小值，旧）
  final DateTime createdAt;
  final DateTime updatedAt;

  CachedRange({
    required this.id,
    required this.startRevision,
    required this.endRevision,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 检查是否与另一个区间连续（首尾相同才算连续）
  /// 
  /// 例如：[200, 100] 和 [100, 50] 是连续的，因为 100 == 100
  /// 但是：[200, 101] 和 [100, 50] 不是连续的，不能用 +1 判断
  bool isContinuousWith(CachedRange other) {
    return endRevision == other.startRevision || 
           other.endRevision == startRevision;
  }

  /// 合并两个连续的区间
  CachedRange mergeWith(CachedRange other) {
    if (!isContinuousWith(other)) {
      throw ArgumentError('区间不连续，无法合并');
    }
    final newStart = startRevision > other.startRevision ? startRevision : other.startRevision;
    final newEnd = endRevision < other.endRevision ? endRevision : other.endRevision;
    return CachedRange(
      id: id,  // 保留当前区间的 id
      startRevision: newStart,
      endRevision: newEnd,
      createdAt: createdAt.isBefore(other.createdAt) ? createdAt : other.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// 区间包含的版本数量（注意：这是 revision 范围，不是实际记录数）
  int get revisionSpan => startRevision - endRevision + 1;

  @override
  String toString() => 'CachedRange[$startRevision, $endRevision]';
}

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
  static const int _dbVersion = 4;
  
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

    // 缓存区间表（版本4新增）
    db.execute('''
      CREATE TABLE cached_ranges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_revision INTEGER NOT NULL,
        end_revision INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('CREATE INDEX idx_ranges_start ON cached_ranges(start_revision DESC)');

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
    
    if (oldVersion < 4) {
      // 版本 4：添加缓存区间表
      try {
        db.execute('''
          CREATE TABLE IF NOT EXISTS cached_ranges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_revision INTEGER NOT NULL,
            end_revision INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        db.execute('CREATE INDEX IF NOT EXISTS idx_ranges_start ON cached_ranges(start_revision DESC)');
        AppLogger.storage.info('已添加 cached_ranges 表（数据库升级）');
        
        // 迁移现有数据：根据现有的 log_entries 创建初始区间
        await _migrateExistingDataToRanges(db);
      } catch (e) {
        AppLogger.storage.warn('添加 cached_ranges 表失败: $e');
      }
    }
  }

  /// 迁移现有数据到区间表
  /// 
  /// 对于升级的数据库，根据现有的 log_entries 创建一个初始区间
  Future<void> _migrateExistingDataToRanges(Database db) async {
    try {
      // 获取现有数据的最大和最小 revision
      final maxResult = db.select('SELECT MAX(revision) FROM log_entries');
      final minResult = db.select('SELECT MIN(revision) FROM log_entries');
      
      final maxRev = maxResult.first.columnAt(0) as int?;
      final minRev = minResult.first.columnAt(0) as int?;
      
      if (maxRev != null && minRev != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          'INSERT INTO cached_ranges (start_revision, end_revision, created_at, updated_at) VALUES (?, ?, ?, ?)',
          [maxRev, minRev, now, now],
        );
        AppLogger.storage.info('已迁移现有数据到区间: [$maxRev, $minRev]');
      }
    } catch (e) {
      AppLogger.storage.warn('迁移现有数据到区间失败: $e');
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
  /// 
  /// [sourceUrl] 源 URL
  /// [entries] 日志条目列表
  /// [isFromHead] 是否从 HEAD 开始获取的数据（用于区间管理）
  ///   - true: 从 HEAD 向旧版本获取，需要创建新区间或扩展起点
  ///   - false: 从缓存最旧版本继续向旧版本获取，扩展区间终点
  Future<void> insertEntries(
    String sourceUrl, 
    List<LogEntry> entries, {
    bool isFromHead = false,
  }) async {
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

      // 更新元数据（保持向后兼容）
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

      // 更新区间
      await _updateRangesAfterInsert(sourceUrl, latestRevision, earliestRevision, isFromHead);

      AppLogger.storage.info('已插入 ${entries.length} 条日志到缓存: $sourceUrl (区间: [$latestRevision, $earliestRevision])');
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

  // ===== 区间管理方法 =====

  /// 获取所有缓存区间（按 startRevision 降序排列）
  Future<List<CachedRange>> getAllRanges(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select(
        'SELECT id, start_revision, end_revision, created_at, updated_at FROM cached_ranges ORDER BY start_revision DESC',
      );
      
      return result.map((row) => CachedRange(
        id: row.columnAt(0) as int,
        startRevision: row.columnAt(1) as int,
        endRevision: row.columnAt(2) as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.columnAt(3) as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.columnAt(4) as int),
      )).toList();
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取缓存区间失败', e, stackTrace);
      return [];
    }
  }

  /// 获取最新的区间（startRevision 最大的那个）
  Future<CachedRange?> getLatestRange(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select(
        'SELECT id, start_revision, end_revision, created_at, updated_at FROM cached_ranges ORDER BY start_revision DESC LIMIT 1',
      );
      
      if (result.isEmpty) {
        return null;
      }
      
      final row = result.first;
      return CachedRange(
        id: row.columnAt(0) as int,
        startRevision: row.columnAt(1) as int,
        endRevision: row.columnAt(2) as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.columnAt(3) as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.columnAt(4) as int),
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间失败', e, stackTrace);
      return null;
    }
  }

  /// 添加或更新区间
  /// 
  /// 插入新区间后会自动检查并合并连续的区间
  Future<void> addOrUpdateRange(String sourceUrl, int startRevision, int endRevision) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      // 插入新区间
      db.execute(
        'INSERT INTO cached_ranges (start_revision, end_revision, created_at, updated_at) VALUES (?, ?, ?, ?)',
        [startRevision, endRevision, now, now],
      );
      
      AppLogger.storage.info('已添加新区间: [$startRevision, $endRevision]');
      
      // 合并连续区间
      await _mergeAdjacentRanges(db);
    } catch (e, stackTrace) {
      AppLogger.storage.error('添加区间失败', e, stackTrace);
    }
  }

  /// 插入数据后更新区间
  /// 
  /// [latestRevision] 本次插入的最新版本
  /// [earliestRevision] 本次插入的最旧版本
  /// [isFromHead] 是否从 HEAD 开始获取的数据
  Future<void> _updateRangesAfterInsert(
    String sourceUrl,
    int latestRevision,
    int earliestRevision,
    bool isFromHead,
  ) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      
      if (latestRange == null) {
        // 没有区间，创建新区间
        await addOrUpdateRange(sourceUrl, latestRevision, earliestRevision);
        return;
      }
      
      if (isFromHead) {
        // 从 HEAD 获取的数据
        // 检查是否与现有最新区间连续
        if (earliestRevision == latestRange.startRevision) {
          // 连续：扩展最新区间的起点
          await extendLatestRangeStart(sourceUrl, latestRevision);
        } else if (latestRevision > latestRange.startRevision) {
          // 不连续且更新：创建新区间（这将成为最新区间）
          await addOrUpdateRange(sourceUrl, latestRevision, earliestRevision);
        }
        // 如果 latestRevision <= latestRange.startRevision，说明数据已存在，不需要更新
      } else {
        // 从缓存最旧版本继续获取的数据
        // 检查是否与最新区间连续
        if (latestRevision == latestRange.endRevision) {
          // 连续：扩展最新区间的终点
          await extendLatestRangeEnd(sourceUrl, earliestRevision);
        } else {
          // 不连续：这种情况理论上不应该发生
          // 但为了健壮性，仍然创建新区间
          AppLogger.storage.warn('检测到不连续的加载更多数据: [$latestRevision, $earliestRevision], 最新区间: $latestRange');
          await addOrUpdateRange(sourceUrl, latestRevision, earliestRevision);
        }
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('更新区间失败', e, stackTrace);
    }
  }

  /// 扩展最新区间的终点（向旧版本扩展）
  /// 
  /// [newEndRevision] 新的终点（较小的 revision）
  Future<void> extendLatestRangeEnd(String sourceUrl, int newEndRevision) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final latestRange = await getLatestRange(sourceUrl);
      
      if (latestRange == null) {
        AppLogger.storage.warn('没有最新区间可扩展');
        return;
      }
      
      // 只有当新终点更小时才更新
      if (newEndRevision < latestRange.endRevision) {
        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          'UPDATE cached_ranges SET end_revision = ?, updated_at = ? WHERE id = ?',
          [newEndRevision, now, latestRange.id],
        );
        AppLogger.storage.info('已扩展最新区间: [${latestRange.startRevision}, $newEndRevision]');
        
        // 检查是否需要合并
        await _mergeAdjacentRanges(db);
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('扩展区间失败', e, stackTrace);
    }
  }

  /// 扩展最新区间的起点（向新版本扩展）
  /// 
  /// [newStartRevision] 新的起点（较大的 revision）
  Future<void> extendLatestRangeStart(String sourceUrl, int newStartRevision) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final latestRange = await getLatestRange(sourceUrl);
      
      if (latestRange == null) {
        AppLogger.storage.warn('没有最新区间可扩展');
        return;
      }
      
      // 只有当新起点更大时才更新
      if (newStartRevision > latestRange.startRevision) {
        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          'UPDATE cached_ranges SET start_revision = ?, updated_at = ? WHERE id = ?',
          [newStartRevision, now, latestRange.id],
        );
        AppLogger.storage.info('已扩展最新区间起点: [$newStartRevision, ${latestRange.endRevision}]');
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('扩展区间起点失败', e, stackTrace);
    }
  }

  /// 合并相邻的连续区间
  /// 
  /// 关键规则：只有首尾相同的区间才算连续
  /// 例如：[200, 100] 和 [100, 50] 是连续的（100 == 100）
  Future<void> _mergeAdjacentRanges(Database db) async {
    try {
      // 获取所有区间，按 startRevision 降序
      final result = db.select(
        'SELECT id, start_revision, end_revision FROM cached_ranges ORDER BY start_revision DESC',
      );
      
      if (result.length < 2) {
        return; // 少于2个区间，无需合并
      }
      
      final ranges = result.map((row) => (
        id: row.columnAt(0) as int,
        start: row.columnAt(1) as int,
        end: row.columnAt(2) as int,
      )).toList();
      
      final toDelete = <int>[];
      final toUpdate = <({int id, int start, int end})>[];
      
      // 从最新区间开始，检查是否与下一个区间连续
      for (int i = 0; i < ranges.length - 1; i++) {
        final current = ranges[i];
        final next = ranges[i + 1];
        
        // 关键判断：首尾相同才算连续
        if (current.end == next.start) {
          // 合并：保留 current，删除 next，扩展 current 的 end
          toUpdate.add((id: current.id, start: current.start, end: next.end));
          toDelete.add(next.id);
          // 更新 ranges 以便继续检查
          ranges[i] = (id: current.id, start: current.start, end: next.end);
          ranges.removeAt(i + 1);
          i--; // 重新检查当前位置
        }
      }
      
      // 执行更新和删除
      if (toDelete.isNotEmpty || toUpdate.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        for (final update in toUpdate) {
          db.execute(
            'UPDATE cached_ranges SET end_revision = ?, updated_at = ? WHERE id = ?',
            [update.end, now, update.id],
          );
        }
        
        for (final id in toDelete) {
          db.execute('DELETE FROM cached_ranges WHERE id = ?', [id]);
        }
        
        AppLogger.storage.info('已合并 ${toDelete.length} 个连续区间');
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('合并区间失败', e, stackTrace);
    }
  }

  /// 获取最新区间内的日志条目数量
  Future<int> getLatestRangeEntryCount(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }
      
      final db = await _getDatabase(sourceUrl);
      final result = db.select(
        'SELECT COUNT(*) FROM log_entries WHERE revision >= ? AND revision <= ?',
        [latestRange.endRevision, latestRange.startRevision],
      );
      
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间条目数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取最新区间内的日志条目
  Future<List<LogEntry>> getEntriesInLatestRange(
    String sourceUrl, {
    int? limit,
    int offset = 0,
    String? authorFilter,
    String? titleFilter,
    int? minRevision,
  }) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return [];
      }
      
      final db = await _getDatabase(sourceUrl);
      
      final whereConditions = <String>[
        'revision >= ?',
        'revision <= ?',
      ];
      final whereArgs = <Object>[
        latestRange.endRevision,
        latestRange.startRevision,
      ];
      
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
      query += ' WHERE ${whereConditions.join(' AND ')}';
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
      AppLogger.storage.error('获取最新区间日志条目失败', e, stackTrace);
      return [];
    }
  }

  /// 获取最新区间内符合过滤条件的日志数量
  Future<int> getEntryCountInLatestRange(
    String sourceUrl, {
    String? authorFilter,
    String? titleFilter,
    int? minRevision,
  }) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }
      
      final db = await _getDatabase(sourceUrl);
      
      final whereConditions = <String>[
        'revision >= ?',
        'revision <= ?',
      ];
      final whereArgs = <Object>[
        latestRange.endRevision,
        latestRange.startRevision,
      ];
      
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
      query += ' WHERE ${whereConditions.join(' AND ')}';
      
      final result = db.select(query, whereArgs);
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间日志数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 清空所有区间（用于重建缓存）
  Future<void> clearAllRanges(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      db.execute('DELETE FROM cached_ranges');
      AppLogger.storage.info('已清空所有区间');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空区间失败', e, stackTrace);
    }
  }

  /// 获取最新区间的最早版本号
  Future<int> getEarliestRevisionInLatestRange(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }
      return latestRange.endRevision;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间最早版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取最新区间的最新版本号
  Future<int> getLatestRevisionInLatestRange(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }
      return latestRange.startRevision;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间最新版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取最新区间的最早日期
  Future<DateTime?> getEarliestDateInLatestRange(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return null;
      }
      
      final db = await _getDatabase(sourceUrl);
      final result = db.select(
        'SELECT MIN(date) FROM log_entries WHERE revision >= ? AND revision <= ?',
        [latestRange.endRevision, latestRange.startRevision],
      );

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
      AppLogger.storage.error('获取最新区间最早日期失败', e, stackTrace);
      return null;
    }
  }
}
