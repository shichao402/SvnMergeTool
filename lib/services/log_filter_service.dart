/// 日志过滤和分页服务
///
/// 独立模块，负责处理日志的过滤和分页逻辑
/// - 从缓存读取数据
/// - 应用过滤条件（作者、标题）
/// - 处理分页逻辑
/// - 不依赖 UI，纯业务逻辑
/// 
/// 重要设计原则：
/// - 过滤器只负责过滤 db 缓存中的数据
/// - 不触发任何网络请求
/// - 分支点过滤使用缓存的 minRevision 参数

import '../models/log_entry.dart';
import 'log_cache_service.dart';
import 'logger_service.dart';

/// 过滤条件
class LogFilter {
  final String? author;
  final String? title;
  /// 最小版本号（用于 stopOnCopy 过滤，排除此版本之前的记录）
  final int? minRevision;

  const LogFilter({
    this.author,
    this.title,
    this.minRevision,
  });

  /// 是否为空（无过滤条件）
  bool get isEmpty => (author == null || author!.isEmpty) && 
                      (title == null || title!.isEmpty) &&
                      minRevision == null;

  /// 复制并修改
  LogFilter copyWith({
    String? author,
    String? title,
    int? minRevision,
    bool clearMinRevision = false,
  }) {
    return LogFilter(
      author: author ?? this.author,
      title: title ?? this.title,
      minRevision: clearMinRevision ? null : (minRevision ?? this.minRevision),
    );
  }
  
  @override
  String toString() {
    return 'LogFilter(author: $author, title: $title, minRevision: $minRevision)';
  }
}

/// 分页结果
class PaginatedResult {
  final List<LogEntry> entries;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final int totalPages;
  /// 是否还有更多数据
  final bool hasMore;

  const PaginatedResult({
    required this.entries,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    required this.totalPages,
    this.hasMore = true,
  });
}

/// 日志过滤和分页服务
/// 
/// 设计原则：只负责从缓存读取和过滤数据，不触发任何网络请求
class LogFilterService {
  final LogCacheService _cacheService = LogCacheService();
  
  // COPY_TAIL 缓存：key = workingDirectory, value = branchPoint revision（分支分界点）
  // 注意：这是非持久化的内存缓存，应用重启后会自动清空
  static final Map<String, int?> _copyTailCache = {};

  /// 获取过滤后的日志条目（分页）
  /// 
  /// [sourceUrl] 源 URL
  /// [filter] 过滤条件（包含 author、title、minRevision）
  /// [page] 页码（从 0 开始）
  /// [pageSize] 每页大小
  /// 
  /// 返回分页结果
  /// 
  /// 注意：此方法只从缓存读取数据，不触发任何网络请求
  Future<PaginatedResult> getPaginatedEntries(
    String sourceUrl,
    LogFilter filter,
    int page,
    int pageSize,
  ) async {
    try {
      AppLogger.storage.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      AppLogger.storage.info('【过滤服务】获取分页数据（纯本地操作）');
      AppLogger.storage.info('  源 URL: $sourceUrl');
      AppLogger.storage.info('  页码: $page, 每页: $pageSize');
      AppLogger.storage.info('  过滤条件: $filter');
      
      // 初始化缓存服务
      await _cacheService.init();

      // 1. 获取符合过滤条件的总数
      final totalCount = await _cacheService.getEntryCount(
        sourceUrl,
        authorFilter: filter.author,
        titleFilter: filter.title,
        minRevision: filter.minRevision,
      );
      
      AppLogger.storage.info('  符合条件的总数: $totalCount');
      
      // 2. 计算总页数
      final totalPages = totalCount > 0 
          ? ((totalCount - 1) / pageSize).floor() + 1 
          : 0;
      
      // 3. 调整当前页（确保在有效范围内）
      final adjustedPage = totalCount > 0 
          ? page.clamp(0, totalPages - 1)
          : 0;
      
      if (adjustedPage != page) {
        AppLogger.storage.info('  页码调整: $page -> $adjustedPage (总页数: $totalPages)');
      }
      
      // 4. 计算 offset
      final offset = adjustedPage * pageSize;
      
      // 5. 从缓存获取当前页数据
      final entries = await _cacheService.getEntries(
        sourceUrl,
        limit: pageSize,
        offset: offset,
        authorFilter: filter.author,
        titleFilter: filter.title,
        minRevision: filter.minRevision,
      );
      
      // 6. 计算是否还有更多数据
      final hasMore = adjustedPage < totalPages - 1;
      
      AppLogger.storage.info('  返回: ${entries.length} 条, 第 ${adjustedPage + 1}/$totalPages 页, hasMore=$hasMore');
      AppLogger.storage.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      return PaginatedResult(
        entries: entries,
        totalCount: totalCount,
        currentPage: adjustedPage,
        pageSize: pageSize,
        totalPages: totalPages,
        hasMore: hasMore,
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取分页日志失败', e, stackTrace);
      return PaginatedResult(
        entries: [],
        totalCount: 0,
        currentPage: 0,
        pageSize: pageSize,
        totalPages: 0,
        hasMore: false,
      );
    }
  }

  /// 获取过滤后的总数（不返回具体条目，只返回数量）
  Future<int> getFilteredCount(
    String sourceUrl,
    LogFilter filter,
  ) async {
    try {
      await _cacheService.init();
      return await _cacheService.getEntryCount(
        sourceUrl,
        authorFilter: filter.author,
        titleFilter: filter.title,
        minRevision: filter.minRevision,
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取过滤后数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 缓存分支点（供外部调用，如 SvnService 查询后缓存）
  static void cacheBranchPoint(String workingDirectory, int? branchPoint) {
    _copyTailCache[workingDirectory] = branchPoint;
    AppLogger.storage.info('已缓存分支点: $workingDirectory -> r$branchPoint');
  }
  
  /// 获取缓存的分支点
  static int? getCachedBranchPoint(String? workingDirectory) {
    if (workingDirectory == null || workingDirectory.isEmpty) {
      return null;
    }
    return _copyTailCache[workingDirectory];
  }
  
  /// 清除分支点缓存
  static void clearBranchPointCache({String? workingDirectory}) {
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      _copyTailCache.remove(workingDirectory);
      AppLogger.storage.info('已清除分支点缓存: $workingDirectory');
    } else {
      _copyTailCache.clear();
      AppLogger.storage.info('已清除所有分支点缓存');
    }
  }

  /// 获取缓存中的总条目数（不带过滤）
  Future<int> getTotalCount(String sourceUrl) async {
    await _cacheService.init();
    return await _cacheService.getEntryCount(sourceUrl);
  }

  /// 根据 revision 列表获取日志条目
  Future<List<LogEntry>> getEntriesByRevisions(
    String sourceUrl,
    List<int> revisions,
  ) async {
    await _cacheService.init();
    return await _cacheService.getEntriesByRevisions(sourceUrl, revisions);
  }
}

