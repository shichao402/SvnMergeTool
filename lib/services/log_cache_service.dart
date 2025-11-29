/// SVN 日志缓存服务
///
/// 负责管理 SVN 日志的本地缓存
/// - 使用 SQLite 数据库存储（支持百万级数据）
/// - 支持增量更新（从缓存最新版本到 HEAD）
/// - 提供高效的查询接口
/// - 支持所有平台（包括 Windows）

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;
import '../models/log_entry.dart';
import 'logger_service.dart';

class LogCacheService {
  /// 单例模式
  static final LogCacheService _instance = LogCacheService._internal();
  factory LogCacheService() => _instance;
  LogCacheService._internal();

  Database? _database;
  String? _dbPath;
  static const int _dbVersion = 2;

  /// 初始化数据库
  Future<void> init() async {
    if (_database != null) return;

    try {
      final appDir = await getApplicationSupportDirectory();
      final dbDir = Directory(path.join(appDir.path, 'SvnMergeTool', 'cache'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      _dbPath = path.join(dbDir.path, 'svn_logs.db');

      // 检查数据库是否存在，如果不存在则创建
      final dbExists = await File(_dbPath!).exists();
      _database = sqlite3.open(_dbPath!);

      // 性能优化设置（针对百万级数据）
      try {
        _database!.execute('PRAGMA synchronous = NORMAL'); // 平衡性能和安全性
        _database!.execute('PRAGMA cache_size = -64000'); // 64MB 缓存（默认 2MB）
        _database!.execute('PRAGMA temp_store = MEMORY'); // 临时表存储在内存
        AppLogger.storage.info('已应用性能优化设置（64MB 缓存）');
      } catch (e, stackTrace) {
        // 如果某些 PRAGMA 不支持，记录警告但继续
        AppLogger.storage.warn('部分性能优化设置失败（可能不支持）: $e');
        AppLogger.storage.debug('性能优化设置异常详情', stackTrace);
      }

      // 检查数据库版本并创建/升级表
      if (!dbExists) {
        await _onCreate();
      } else {
        await _checkAndUpgrade();
      }

      AppLogger.storage.info('日志缓存数据库初始化成功: $_dbPath');
    } catch (e, stackTrace) {
      AppLogger.storage.error('日志缓存数据库初始化失败', e, stackTrace);
      rethrow;
    }
  }

  /// 创建数据库表
  Future<void> _onCreate() async {
    // 日志条目表
    // 使用 sourceUrl 的 hash 作为索引，避免 URL 过长
    _database!.execute('''
      CREATE TABLE log_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_url TEXT NOT NULL,
        source_url_hash TEXT NOT NULL,
        revision INTEGER NOT NULL,
        author TEXT NOT NULL,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(source_url_hash, revision)
      )
    ''');

    // 创建索引以提高查询性能
    _database!.execute('CREATE INDEX idx_source_url_hash ON log_entries(source_url_hash)');
    _database!.execute('CREATE INDEX idx_revision ON log_entries(revision DESC)');
    _database!.execute('CREATE INDEX idx_source_revision ON log_entries(source_url_hash, revision DESC)');
    // 为 author 字段创建索引，提高提交者过滤效率
    _database!.execute('CREATE INDEX idx_author ON log_entries(author)');

    // 缓存元数据表（记录每个 sourceUrl 的最新版本）
    _database!.execute('''
      CREATE TABLE cache_metadata (
        source_url_hash TEXT PRIMARY KEY,
        source_url TEXT NOT NULL,
        latest_revision INTEGER NOT NULL,
        last_updated INTEGER NOT NULL
      )
    ''');

    // 创建版本表
    _database!.execute('''
      CREATE TABLE db_version (
        version INTEGER PRIMARY KEY
      )
    ''');
    _database!.execute('INSERT INTO db_version (version) VALUES (?)', [_dbVersion]);

    AppLogger.storage.info('数据库表创建完成');
  }

  /// 检查并升级数据库
  Future<void> _checkAndUpgrade() async {
    try {
      // 检查是否存在版本表
      final versionResult = _database!.select('SELECT name FROM sqlite_master WHERE type="table" AND name="db_version"');
      if (versionResult.isEmpty) {
        // 旧版本数据库，创建版本表并设置为版本 1
        _database!.execute('''
          CREATE TABLE db_version (
            version INTEGER PRIMARY KEY
          )
        ''');
        _database!.execute('INSERT INTO db_version (version) VALUES (1)');
        await _onUpgrade(1, _dbVersion);
      } else {
        // 获取当前版本
        final versionRows = _database!.select('SELECT version FROM db_version LIMIT 1');
        if (versionRows.isNotEmpty) {
          final versionValue = versionRows.first.columnAt(0);
          if (versionValue != null) {
            final currentVersion = versionValue as int;
            if (currentVersion < _dbVersion) {
              await _onUpgrade(currentVersion, _dbVersion);
              _database!.execute('UPDATE db_version SET version = ?', [_dbVersion]);
            }
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.storage.warn('检查数据库版本失败: $e');
      AppLogger.storage.debug('检查数据库版本异常详情', stackTrace);
    }
  }

  /// 数据库升级
  Future<void> _onUpgrade(int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 版本 2：添加 author 索引
      try {
        _database!.execute('CREATE INDEX IF NOT EXISTS idx_author ON log_entries(author)');
        AppLogger.storage.info('已添加 author 索引（数据库升级）');
      } catch (e, stackTrace) {
        AppLogger.storage.warn('添加 author 索引失败（可能已存在）: $e');
        AppLogger.storage.debug('添加索引异常详情', stackTrace);
      }
    }
  }

  /// 获取 sourceUrl 的 hash
  String _getSourceUrlHash(String sourceUrl) {
    return sourceUrl.hashCode.toString();
  }

  /// 获取缓存中指定 sourceUrl 的最新版本号
  /// 
  /// 返回最新版本号，如果没有缓存则返回 0
  Future<int> getLatestRevision(String sourceUrl) async {
    await _ensureInit();

    try {
      final urlHash = _getSourceUrlHash(sourceUrl);
      final result = _database!.select(
        'SELECT latest_revision FROM cache_metadata WHERE source_url_hash = ?',
        [urlHash],
      );

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
  /// 
  /// [sourceUrl] 源 URL
  /// [minRevision] 最小 revision（可选，用于 stopOnCopy 过滤）
  /// 
  /// 返回最早版本号，如果没有缓存则返回 0
  Future<int> getEarliestRevision(
    String sourceUrl, {
    int? minRevision,
  }) async {
    await _ensureInit();

    try {
      final urlHash = _getSourceUrlHash(sourceUrl);
      var query = 'SELECT MIN(revision) as min_revision FROM log_entries WHERE source_url_hash = ?';
      final args = <Object>[urlHash];

      if (minRevision != null && minRevision > 0) {
        query += ' AND revision >= ?';
        args.add(minRevision);
      }

      final result = _database!.select(query, args);

      if (result.isEmpty) {
        return 0;
      }

      final minRevisionValue = result.first.columnAt(0);
      if (minRevisionValue == null) {
        return 0;
      }

      return minRevisionValue as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最早版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 批量插入日志条目
  /// 
  /// [sourceUrl] 源 URL
  /// [entries] 日志条目列表
  /// 
  /// 注意：对于大量数据，会自动分批插入（每批 1000 条）以避免内存问题
  Future<void> insertEntries(String sourceUrl, List<LogEntry> entries) async {
    if (entries.isEmpty) return;

    await _ensureInit();

    try {
      // 批量大小限制：每批最多 1000 条，避免内存问题
      const batchSize = 1000;
      final urlHash = _getSourceUrlHash(sourceUrl);
      final now = DateTime.now().millisecondsSinceEpoch;

      // 分批插入
      for (int i = 0; i < entries.length; i += batchSize) {
        final batch = entries.sublist(
          i,
          (i + batchSize).clamp(0, entries.length),
        );

        // 使用事务
        _database!.execute('BEGIN TRANSACTION');
        try {
          // 批量插入日志条目（使用 INSERT OR REPLACE 避免重复）
          final stmt = _database!.prepare('''
            INSERT OR REPLACE INTO log_entries 
            (source_url, source_url_hash, revision, author, date, title, message, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''');

          for (final entry in batch) {
            stmt.execute([
              sourceUrl,
              urlHash,
              entry.revision,
              entry.author,
              entry.date,
              entry.title,
              entry.message,
              now,
            ]);
          }
          stmt.dispose();
          _database!.execute('COMMIT');
        } catch (e, stackTrace) {
          _database!.execute('ROLLBACK');
          AppLogger.storage.error('插入日志条目事务失败', e, stackTrace);
          rethrow;
        }
      }

      // 更新缓存元数据（使用最后一批的最大 revision）
      final latestRevision = entries.map((e) => e.revision).reduce((a, b) => a > b ? a : b);
      final metaStmt = _database!.prepare('''
        INSERT OR REPLACE INTO cache_metadata 
        (source_url_hash, source_url, latest_revision, last_updated)
        VALUES (?, ?, ?, ?)
      ''');
      metaStmt.execute([urlHash, sourceUrl, latestRevision, now]);
      metaStmt.dispose();

      AppLogger.storage.info('已插入 ${entries.length} 条日志到缓存: $sourceUrl（分 ${(entries.length / batchSize).ceil()} 批）');
    } catch (e, stackTrace) {
      AppLogger.storage.error('插入日志条目失败', e, stackTrace);
      rethrow;
    }
  }

  /// 从缓存获取日志条目
  /// 
  /// [sourceUrl] 源 URL
  /// [limit] 限制返回数量（可选，默认不限制）
  /// [offset] 偏移量（用于分页）
  /// [authorFilter] 作者过滤（可选，在数据库层面过滤）
  /// [titleFilter] 标题过滤（可选，在数据库层面过滤）
  /// [minRevision] 最小 revision（可选，用于 stopOnCopy 过滤）
  /// 
  /// 返回按 revision 降序排列的日志条目列表
  /// 
  /// 注意：如果提供了过滤条件，会在数据库层面进行过滤，提高性能
  Future<List<LogEntry>> getEntries(
    String sourceUrl, {
    int? limit,
    int offset = 0,
    String? authorFilter,
    String? titleFilter,
    int? minRevision,
  }) async {
    await _ensureInit();

    try {
      final urlHash = _getSourceUrlHash(sourceUrl);
      
      // 构建 WHERE 条件
      final whereConditions = <String>['source_url_hash = ?'];
      final whereArgs = <Object>[urlHash];
      
      // 添加最小 revision 过滤（用于 stopOnCopy）
      if (minRevision != null && minRevision > 0) {
        whereConditions.add('revision >= ?');
        whereArgs.add(minRevision);
      }
      
      // 添加作者过滤（数据库层面，全字匹配）
      if (authorFilter != null && authorFilter.isNotEmpty) {
        whereConditions.add('author = ?');
        whereArgs.add(authorFilter.trim()); // 全字匹配，不区分大小写（SQLite 默认不区分大小写）
      }
      
      // 添加标题过滤（数据库层面）
      if (titleFilter != null && titleFilter.isNotEmpty) {
        whereConditions.add('LOWER(title) LIKE ?');
        whereArgs.add('%${titleFilter.toLowerCase()}%');
      }
      
      var query = '''
        SELECT revision, author, date, title, message 
        FROM log_entries 
        WHERE ${whereConditions.join(' AND ')}
        ORDER BY revision DESC
      ''';
      
      if (limit != null) {
        query += ' LIMIT ? OFFSET ?';
        whereArgs.add(limit);
        whereArgs.add(offset);
      }

      final results = _database!.select(query, whereArgs);
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
  /// 
  /// [sourceUrl] 源 URL
  /// [authorFilter] 作者过滤（可选）
  /// [titleFilter] 标题过滤（可选）
  /// [minRevision] 最小 revision（可选，用于 stopOnCopy 过滤）
  /// 
  /// 返回符合条件的日志总数
  Future<int> getEntryCount(
    String sourceUrl, {
    String? authorFilter,
    String? titleFilter,
    int? minRevision,
  }) async {
    await _ensureInit();

    try {
      final urlHash = _getSourceUrlHash(sourceUrl);
      
      // 构建 WHERE 条件
      final whereConditions = <String>['source_url_hash = ?'];
      final whereArgs = <Object>[urlHash];
      
      // 添加最小 revision 过滤（用于 stopOnCopy）
      if (minRevision != null && minRevision > 0) {
        whereConditions.add('revision >= ?');
        whereArgs.add(minRevision);
      }
      
      // 添加作者过滤
      if (authorFilter != null && authorFilter.isNotEmpty) {
        whereConditions.add('LOWER(author) LIKE ?');
        whereArgs.add('%${authorFilter.toLowerCase()}%');
      }
      
      // 添加标题过滤
      if (titleFilter != null && titleFilter.isNotEmpty) {
        whereConditions.add('LOWER(title) LIKE ?');
        whereArgs.add('%${titleFilter.toLowerCase()}%');
      }
      
      final result = _database!.select(
        'SELECT COUNT(*) as count FROM log_entries WHERE ${whereConditions.join(' AND ')}',
        whereArgs,
      );
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取日志数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 清空指定 sourceUrl 的缓存
  Future<void> clearCache(String sourceUrl) async {
    await _ensureInit();

    try {
      final urlHash = _getSourceUrlHash(sourceUrl);
      _database!.execute('BEGIN TRANSACTION');
      try {
        _database!.execute('DELETE FROM log_entries WHERE source_url_hash = ?', [urlHash]);
        _database!.execute('DELETE FROM cache_metadata WHERE source_url_hash = ?', [urlHash]);
        _database!.execute('COMMIT');
        AppLogger.storage.info('已清空缓存: $sourceUrl');
      } catch (e, stackTrace) {
        _database!.execute('ROLLBACK');
        AppLogger.storage.error('清空缓存事务失败', e, stackTrace);
        rethrow;
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空缓存失败', e, stackTrace);
    }
  }

  /// 根据 revision 列表获取日志条目
  /// 
  /// [sourceUrl] 源 URL
  /// [revisions] revision 列表
  /// 
  /// 返回匹配的日志条目列表（按 revision 降序排列）
  Future<List<LogEntry>> getEntriesByRevisions(
    String sourceUrl,
    List<int> revisions,
  ) async {
    await _ensureInit();

    if (revisions.isEmpty) {
      return [];
    }

    try {
      final urlHash = _getSourceUrlHash(sourceUrl);
      
      // 使用 IN 查询获取指定的 revisions
      final placeholders = List.filled(revisions.length, '?').join(',');
      final query = '''
        SELECT revision, author, date, title, message 
        FROM log_entries 
        WHERE source_url_hash = ? AND revision IN ($placeholders)
        ORDER BY revision DESC
      ''';
      
      final results = _database!.select(
        query,
        [urlHash, ...revisions],
      );
      
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

  /// 清空所有缓存
  Future<void> clearAllCache() async {
    await _ensureInit();

    try {
      _database!.execute('BEGIN TRANSACTION');
      try {
        _database!.execute('DELETE FROM log_entries');
        _database!.execute('DELETE FROM cache_metadata');
        _database!.execute('COMMIT');
        AppLogger.storage.info('已清空所有缓存');
      } catch (e, stackTrace) {
        _database!.execute('ROLLBACK');
        AppLogger.storage.error('清空所有缓存事务失败', e, stackTrace);
        rethrow;
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空所有缓存失败', e, stackTrace);
    }
  }

  /// 确保数据库已初始化
  Future<void> _ensureInit() async {
    if (_database == null) {
      await init();
    }
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      _database!.dispose();
      _database = null;
      AppLogger.storage.info('日志缓存数据库已关闭');
    }
  }
}
