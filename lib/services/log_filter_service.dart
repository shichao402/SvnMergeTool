/// 日志过滤和分页服务
///
/// 独立模块，负责处理日志的过滤和分页逻辑
/// - 从缓存读取数据
/// - 应用过滤条件（作者、标题）
/// - 处理分页逻辑
/// - 不依赖 UI，纯业务逻辑

import '../models/log_entry.dart';
import 'log_cache_service.dart';
import 'log_sync_service.dart';
import 'svn_service.dart';
import 'svn_xml_parser.dart';
import 'logger_service.dart';

/// 过滤条件
class LogFilter {
  final String? author;
  final String? title;

  const LogFilter({
    this.author,
    this.title,
  });

  /// 是否为空（无过滤条件）
  bool get isEmpty => (author == null || author!.isEmpty) && (title == null || title!.isEmpty);

  /// 复制并修改
  LogFilter copyWith({
    String? author,
    String? title,
  }) {
    return LogFilter(
      author: author ?? this.author,
      title: title ?? this.title,
    );
  }
}

/// 分页结果
class PaginatedResult {
  final List<LogEntry> entries;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final int totalPages;
  /// 是否还有更多数据（如果当前页返回的数据少于 pageSize，说明没有更多数据了）
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
class LogFilterService {
  final LogCacheService _cacheService = LogCacheService();
  final LogSyncService _syncService = LogSyncService();
  final SvnService _svnService = SvnService();
  
  // 数据加载状态回调（用于通知 UI 锁定/解锁）
  void Function(bool isLoading)? _onDataLoadingCallback;
  
  // COPY_TAIL 缓存：key = workingDirectory, value = branchPoint revision（分支分界点）
  // 注意：这是非持久化的内存缓存，应用重启后会自动清空
  // 注意：与 LogSyncService 共享缓存，避免重复查询
  static final Map<String, int?> _copyTailCache = {};
  
  // ROOT_TAIL 缓存：key = sourceUrl, value = rootTail revision（根尾，通常是1）
  // 注意：这是非持久化的内存缓存，应用重启后会自动清空
  static final Map<String, int?> _rootTailCache = {};
  
  // 边界标记：key = sourceUrl + workingDirectory + stopOnCopy, value = 是否已到边界
  // 用于记录某个配置下是否已经到达边界（HEAD或stopOnCopy边界），避免重复尝试获取
  static final Map<String, bool> _boundaryReachedCache = {};
  
  /// 设置数据加载状态回调
  /// 
  /// [callback] 回调函数，参数为是否正在加载数据
  void setOnDataLoadingCallback(void Function(bool isLoading) callback) {
    _onDataLoadingCallback = callback;
  }

  /// 获取过滤后的日志条目（分页）
  /// 
  /// [sourceUrl] 源 URL
  /// [filter] 过滤条件
  /// [page] 页码（从 0 开始）
  /// [pageSize] 每页大小
  /// [stopOnCopy] 是否在遇到拷贝/分支点时停止（用于自动获取更多数据）
  /// [workingDirectory] 工作目录（用于 stopOnCopy）
  /// [fetchLimit] 每次从 SVN 获取的最大条数（默认 500）
  /// 
  /// 返回分页结果
  /// 
  /// 注意：如果请求的数据范围超过缓存范围，会自动从 SVN 获取更多数据
  /// 持续获取直到满足需求或遇到 stopOnCopy 或没有更多数据
  Future<PaginatedResult> getPaginatedEntries(
    String sourceUrl,
    LogFilter filter,
    int page,
    int pageSize, {
    bool stopOnCopy = false,
    String? workingDirectory,
    int fetchLimit = 500,
  }) async {
    try {
      AppLogger.storage.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      AppLogger.storage.info('【步骤 1/6】初始化日志过滤服务');
      AppLogger.storage.info('  源 URL: $sourceUrl');
      AppLogger.storage.info('  页码: $page');
      AppLogger.storage.info('  每页大小: $pageSize');
      AppLogger.storage.info('  stopOnCopy: $stopOnCopy');
      AppLogger.storage.info('  工作目录: ${workingDirectory ?? "未指定"}');
      AppLogger.storage.info('  过滤条件: author=${filter.author ?? "无"}, title=${filter.title ?? "无"}');
      
      // 初始化缓存服务
      AppLogger.storage.info('【步骤 2/6】初始化缓存服务');
      await _cacheService.init();
      AppLogger.storage.info('  缓存服务初始化完成');

      // 检查是否需要获取更多数据
      AppLogger.storage.info('【步骤 3/6】计算请求的数据范围');
      // 计算请求的数据范围：如果请求的页码需要的数据超出了当前缓存，需要获取更多
      // 持续获取数据直到满足需求或遇到 stopOnCopy 或没有更多数据
      final requestedStartIndex = page * pageSize;
      final requestedEndIndex = requestedStartIndex + pageSize;
      AppLogger.storage.info('  请求的数据范围: 索引 $requestedStartIndex 到 $requestedEndIndex');
      
      // 如果 stopOnCopy=true，需要找到分支点，只统计从分支点开始的数据
      AppLogger.storage.info('【步骤 4/6】确定最小版本和边界（用于 stopOnCopy 过滤）');
      // 本质目的：只关注分支被创建之后的版本
      int? minRevision; // 用于过滤的最小版本
      int? copyTail; // COPY_TAIL：分支分界点的revision
      int? rootTail; // ROOT_TAIL：整个SVN路径的最早revision（通常是1）
      
      if (stopOnCopy && workingDirectory != null && workingDirectory.isNotEmpty) {
        try {
          AppLogger.storage.info('  stopOnCopy=true，需要查找分支点（COPY_TAIL）');
          // 对目标工作目录（分支）执行 svn log --stop-on-copy 找到分支点
          final branchPoint = await _findBranchPoint(workingDirectory);
          if (branchPoint != null) {
            minRevision = branchPoint;
            copyTail = branchPoint;
            AppLogger.storage.info('  找到分支点（COPY_TAIL）: r$branchPoint');
            AppLogger.storage.info('  只统计 r$branchPoint 及之后的数据');
          } else {
            AppLogger.storage.info('  未找到分支点，不限制版本范围');
          }
        } catch (e, stackTrace) {
          AppLogger.storage.warn('  查找分支点失败: $e');
          AppLogger.storage.debug('查找分支点异常详情', stackTrace);
        }
      } else if (stopOnCopy) {
        AppLogger.storage.warn('  stopOnCopy=true，但未提供工作目录，无法查找分支点');
      } else {
        AppLogger.storage.info('  stopOnCopy=false，需要查找根尾（ROOT_TAIL）');
        try {
          // 检查缓存
          if (_rootTailCache.containsKey(sourceUrl)) {
            rootTail = _rootTailCache[sourceUrl];
            AppLogger.storage.info('  使用缓存的ROOT_TAIL: r$rootTail');
          } else {
            // 获取ROOT_TAIL：通过 svn log -r 1:HEAD 获取最早的revision
            rootTail = await _svnService.findRootTail(
              sourceUrl,
              workingDirectory: workingDirectory,
            );
            if (rootTail != null) {
              AppLogger.storage.info('  找到根尾（ROOT_TAIL）: r$rootTail');
              // 缓存结果
              _rootTailCache[sourceUrl] = rootTail;
            } else {
              AppLogger.storage.info('  未找到根尾，默认使用 r1');
              rootTail = 1; // 默认ROOT_TAIL是1
              // 缓存默认值
              _rootTailCache[sourceUrl] = 1;
            }
          }
        } catch (e, stackTrace) {
          AppLogger.storage.warn('  查找根尾失败: $e，默认使用 r1');
          AppLogger.storage.debug('查找根尾异常详情', stackTrace);
          rootTail = 1; // 默认ROOT_TAIL是1
          // 缓存默认值
          _rootTailCache[sourceUrl] = 1;
        }
      }
      
      // 优化：只在开始时查询一次数据库，后续使用本地计数
      // 注意：如果 stopOnCopy=true，只统计从分支点开始的数据
      int cachedCount = await _cacheService.getEntryCount(
        sourceUrl,
        minRevision: minRevision,
      );
      
      // 检查是否已经到达边界（已到HEAD或stopOnCopy边界）
      // 如果之前获取时返回0条，说明已到边界，不应该再尝试获取
      final boundaryKey = '$sourceUrl|${workingDirectory ?? ''}|$stopOnCopy';
      bool hasReachedBoundary = _boundaryReachedCache[boundaryKey] ?? false;
      
      // 先检查缓存是否足够，如果足够则直接返回，不进入循环
      // 获取缓存中最小的revision（用于检查是否触达COPY_TAIL或ROOT_TAIL）
      final cachedMinRevision = await _cacheService.getEarliestRevision(
        sourceUrl,
        minRevision: minRevision,
      );
      
      // 检查是否满足返回条件（在循环外先检查一次）：
      // 1. 缓存已经足够满足需求
      // 2. 或者最早的revision触达COPY_TAIL（当stopOnCopy=true时）
      // 3. 或者最早的revision触达ROOT_TAIL（当stopOnCopy=false时）
      bool shouldReturn = false;
      String returnReason = '';
      
      if (requestedEndIndex <= cachedCount) {
        shouldReturn = true;
        returnReason = '缓存足够（缓存=$cachedCount, 需求=$requestedEndIndex）';
        AppLogger.storage.info('✓ $returnReason，直接返回，无需从SVN获取');
      } else if (stopOnCopy && copyTail != null && cachedMinRevision > 0) {
        // stopOnCopy=true：检查是否已触达COPY_TAIL（分支点）
        // 如果缓存最小revision <= COPY_TAIL，说明已经获取到了分支点及之前的数据
        // 由于stopOnCopy=true时只显示分支点之后的数据，所以应该返回
        if (cachedMinRevision <= copyTail) {
          shouldReturn = true;
          returnReason = '已触达COPY_TAIL（缓存最小revision=r$cachedMinRevision, COPY_TAIL=r$copyTail）';
          AppLogger.storage.info('✓ $returnReason，直接返回，无需从SVN获取');
        }
      } else if (!stopOnCopy && rootTail != null && cachedMinRevision > 0) {
        // stopOnCopy=false：检查是否已触达ROOT_TAIL（根尾，通常是1）
        // 如果缓存最小revision <= ROOT_TAIL，说明已经获取到了根尾及之前的数据，应该返回
        if (cachedMinRevision <= rootTail) {
          shouldReturn = true;
          returnReason = '已触达ROOT_TAIL（缓存最小revision=r$cachedMinRevision, ROOT_TAIL=r$rootTail）';
          AppLogger.storage.info('✓ $returnReason，直接返回，无需从SVN获取');
        }
      }
      
      // 如果缓存足够或已触达边界，直接跳过循环，进入数据查询阶段
      // 否则进入循环，从SVN获取更多数据
      const int maxIterations = 100; // 防止无限循环
      int iteration = 0;
      int retryCount = 0;
      const maxRetries = 3; // 最大重试次数
      
      if (!shouldReturn && !hasReachedBoundary) {
        // 缓存不足，需要从SVN获取更多数据
        AppLogger.storage.info('缓存不足，需要从SVN获取更多数据');
        
        // 通知 UI 开始加载数据（锁定界面）
        _onDataLoadingCallback?.call(true);
        
        try {
          while (iteration < maxIterations) {
          // 在循环中再次检查缓存（因为可能已经获取了一些数据）
          // 注意：这里不再重复查询 cachedMinRevision，因为边界不会改变
          
          // 检查是否满足返回条件：
          if (requestedEndIndex <= cachedCount) {
            shouldReturn = true;
            returnReason = '缓存足够（缓存=$cachedCount, 需求=$requestedEndIndex）';
            AppLogger.storage.info('满足返回条件: $returnReason');
            break;
          } else if (stopOnCopy && copyTail != null && cachedMinRevision > 0) {
            if (cachedMinRevision <= copyTail) {
              shouldReturn = true;
              returnReason = '已触达COPY_TAIL（缓存最小revision=r$cachedMinRevision, COPY_TAIL=r$copyTail）';
              AppLogger.storage.info('满足返回条件: $returnReason');
              break;
            }
          } else if (!stopOnCopy && rootTail != null && cachedMinRevision > 0) {
            if (cachedMinRevision <= rootTail) {
              shouldReturn = true;
              returnReason = '已触达ROOT_TAIL（缓存最小revision=r$cachedMinRevision, ROOT_TAIL=r$rootTail）';
              AppLogger.storage.info('满足返回条件: $returnReason');
              break;
            }
          }
          
          // 计算还需要多少数据
          final needMoreCount = requestedEndIndex - cachedCount;
          
          // 智能获取策略：如果需求超过 1 页，多获取 2-3 页作为缓冲，减少循环次数
          final bufferPages = needMoreCount > pageSize ? 2 : 1;
          final targetCount = needMoreCount + bufferPages * pageSize;
          final actualLimit = targetCount > fetchLimit ? fetchLimit : targetCount;
          
          AppLogger.storage.info(
            '请求的数据范围超出缓存: 缓存=$cachedCount, 请求结束=$requestedEndIndex, '
            '需要更多=$needMoreCount 条，本次获取=$actualLimit 条（含 ${bufferPages} 页缓冲）',
          );
          
          // 自动从 SVN 获取更多数据（带重试机制）
          int syncCount = 0;
          bool shouldRetry = false;
          
          do {
            try {
              AppLogger.storage.info('  │ 调用 LogSyncService.syncLogs() 获取数据...');
              syncCount = await _syncService.syncLogs(
                sourceUrl: sourceUrl,
                limit: actualLimit,
                stopOnCopy: stopOnCopy,
                workingDirectory: workingDirectory,
              );
              
              AppLogger.storage.info('  │ ✓ 获取完成，新增 $syncCount 条');
              retryCount = 0; // 重置重试计数
              shouldRetry = false;
            } on SvnException catch (e) {
            // 检查是否是 "No such revision" 错误（E160006）
            // 这表示请求的版本不存在，需要查询 HEAD 的实际版本号
            if (e.output != null && 
                (e.output!.contains('E160006') || 
                 e.output!.contains('No such revision'))) {
              AppLogger.storage.warn('  │ 检测到 "No such revision" 错误，查询 HEAD 实际版本号...');
              
              try {
                // 查询 HEAD 的实际版本号（通过获取最新一条日志）
                final headLog = await _svnService.log(
                  sourceUrl,
                  limit: 1,
                  workingDirectory: workingDirectory,
                  startRevision: null, // 不指定起始版本，从最新开始
                );
                final headEntries = SvnXmlParser.parseLog(headLog);
                
                if (headEntries.isNotEmpty) {
                  final actualHeadRevision = headEntries.first.revision;
                  AppLogger.storage.info('  │ HEAD 实际版本号: r$actualHeadRevision');
                  
                  // 获取缓存中的最新版本
                  final cachedLatestRevision = await _cacheService.getLatestRevision(sourceUrl);
                  
                  if (actualHeadRevision <= cachedLatestRevision) {
                    // HEAD 版本小于等于缓存版本，说明缓存已是最新
                    AppLogger.storage.info('  │ 缓存已是最新（缓存: r$cachedLatestRevision, HEAD: r$actualHeadRevision）');
                    syncCount = 0;
                    shouldRetry = false;
                    break;
                  } else {
                    // HEAD 版本大于缓存版本，说明有数据需要获取
                    // 但之前的请求版本不存在，可能是版本号计算错误
                    // 重新尝试从缓存最新版本+1开始获取
                    AppLogger.storage.warn('  │ HEAD 版本大于缓存版本，但请求版本不存在，可能是版本号计算错误');
                    AppLogger.storage.warn('  │ 将重试从缓存最新版本开始获取');
                    // 这里不重试，让上层逻辑处理
                    syncCount = 0;
                    shouldRetry = false;
                    break;
                  }
                } else {
                  AppLogger.storage.warn('  │ 无法获取 HEAD 版本号，停止获取');
                  syncCount = 0;
                  shouldRetry = false;
                  break;
                }
              } catch (headError, headStackTrace) {
                AppLogger.storage.error('  │ 查询 HEAD 版本号失败', headError, headStackTrace);
                syncCount = 0;
                shouldRetry = false;
                break;
              }
            } else {
              // 其他 SVN 错误，使用重试机制
              retryCount++;
              if (retryCount < maxRetries) {
                AppLogger.storage.warn('  │ ✗ 获取数据失败，${retryCount}/${maxRetries} 次重试: $e');
                await Future.delayed(const Duration(seconds: 1)); // 等待后重试
                shouldRetry = true;
              } else {
                // 注意：SvnException 可能没有 stackTrace，但我们需要记录错误
                AppLogger.storage.error('  │ ✗ 获取数据失败，已重试 $maxRetries 次', e);
                shouldRetry = false;
                break;
              }
            }
          } catch (e, stackTrace) {
            // 其他类型的错误，使用重试机制
            AppLogger.storage.error('获取数据异常', e, stackTrace);
            retryCount++;
            if (retryCount < maxRetries) {
              AppLogger.storage.warn('  │ ✗ 获取数据失败，${retryCount}/${maxRetries} 次重试: $e');
              await Future.delayed(const Duration(seconds: 1)); // 等待后重试
              shouldRetry = true;
            } else {
              AppLogger.storage.error('  │ ✗ 获取数据失败，已重试 $maxRetries 次', e, stackTrace);
              shouldRetry = false;
              break;
            }
          }
            } while (shouldRetry);
            
            // 如果没有获取到新数据，说明已经到达 stopOnCopy 或没有更多数据，退出循环
            if (syncCount == 0) {
              AppLogger.storage.info('  │ 没有更多数据可获取（可能遇到 stopOnCopy 或已到 HEAD）');
              AppLogger.storage.info('  └──────────────────────────────────────────');
              hasReachedBoundary = true; // 标记已到边界，后续不再尝试获取
              _boundaryReachedCache[boundaryKey] = true; // 缓存边界标记
              break;
            }
            
            // 更新本地计数（避免重复查询数据库）
            cachedCount += syncCount;
            AppLogger.storage.info('  │ 更新缓存计数: $cachedCount 条');
            AppLogger.storage.info('  └──────────────────────────────────────────');
            
            iteration++;
          }
        } finally {
          // 通知 UI 数据加载完成（解锁界面）
          _onDataLoadingCallback?.call(false);
        }
      }
      
      if (iteration >= maxIterations) {
        AppLogger.storage.warn('达到最大迭代次数，停止获取数据');
      }

      // 优化：在数据库层面进行过滤和分页，避免加载全部数据到内存
      // 这对于百万级数据非常重要
      
      // 注意：minRevision 已经在上面查找过了，这里直接使用
      // 如果 stopOnCopy=true，只显示从分支点开始的数据
      if (minRevision != null) {
        AppLogger.storage.info('stopOnCopy=true，分支点: r$minRevision，只显示 r$minRevision 及之后的数据');
      }
      
      // 1. 获取当前页的数据（不计算总数，因为不知道总共有多少条记录）
      // 注意：如果 stopOnCopy=true，只查询从分支点开始的数据
      // 注意：不再计算 totalCount 和 totalPages，因为不知道总共有多少条记录，计算也很耗时
      final currentPage = page.clamp(0, 999999); // 允许任意页码，由是否有数据决定是否可翻页
      
      // 2. 计算 offset 和 limit
      final offset = currentPage * pageSize;
      
      // 3. 如果已经到达边界且 offset 超出缓存，直接返回空列表
      // 这样可以避免显示空页
      List<LogEntry> paginatedEntries;
      bool hasMore;
      
      if (hasReachedBoundary && offset >= cachedCount) {
        // 已经到达边界，且 offset 超出缓存，说明已经是最后一页之后了
        AppLogger.storage.info('已到达边界且 offset($offset) >= cachedCount($cachedCount)，返回空列表');
        paginatedEntries = [];
        hasMore = false;
      } else {
        // 4. 如果已经到达边界且请求在缓存范围内，调整 limit 以返回所有剩余数据
        // 这样可以避免最后一页显示为空
        int actualLimit = pageSize;
        if (hasReachedBoundary && offset < cachedCount) {
          // 已经到达边界，但请求的 offset 还在缓存范围内
          // 计算剩余的数据量
          final remainingCount = cachedCount - offset;
          if (remainingCount > 0 && remainingCount < pageSize) {
            // 如果剩余数据少于 pageSize，只获取剩余的数据
            actualLimit = remainingCount;
            AppLogger.storage.info('已到达边界，调整 limit: $pageSize -> $actualLimit（剩余 $remainingCount 条）');
          }
        }
        
        // 5. 使用数据库分页查询，只获取当前页的数据
        // 注意：如果 stopOnCopy=true，只查询从分支点开始的数据
        paginatedEntries = await _cacheService.getEntries(
          sourceUrl,
          limit: actualLimit,
          offset: offset,
          authorFilter: filter.author,
          titleFilter: filter.title,
          minRevision: minRevision,
        );

        AppLogger.storage.debug(
          '获取分页日志: sourceUrl=$sourceUrl, page=$currentPage, pageSize=$pageSize, '
          '返回=${paginatedEntries.length} 条',
        );

        // 判断是否还有更多数据：
        // 1. 如果返回的数据量等于 pageSize，需要进一步判断：
        //    - 如果已到达边界且 offset + pageSize >= cachedCount，说明已经是最后一页（hasMore = false）
        //    - 否则可能还有更多数据（hasMore = true）
        // 2. 如果返回的数据量少于 pageSize，说明已经是最后一页了（hasMore = false）
        if (paginatedEntries.length >= pageSize) {
          // 返回的数据量等于 pageSize，需要进一步判断
          if (hasReachedBoundary && offset + pageSize >= cachedCount) {
            // 已到达边界，且下一页的 offset 会超出缓存，说明已经是最后一页
            hasMore = false;
            AppLogger.storage.info('已到达边界且 offset+pageSize(${offset + pageSize}) >= cachedCount($cachedCount)，hasMore=false');
          } else {
            // 可能还有更多数据
            hasMore = true;
          }
        } else {
          // 返回的数据量少于 pageSize，说明已经是最后一页
          hasMore = false;
        }
      }

      // 注意：不再返回 totalCount 和 totalPages，因为不知道总共有多少条记录
      return PaginatedResult(
        entries: paginatedEntries,
        totalCount: -1, // -1 表示未知
        currentPage: currentPage,
        pageSize: pageSize,
        totalPages: -1, // -1 表示未知
        hasMore: hasMore,
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取分页日志失败', e, stackTrace);
      return PaginatedResult(
        entries: [],
        totalCount: -1, // -1 表示未知
        currentPage: 0,
        pageSize: pageSize,
        totalPages: -1, // -1 表示未知
        hasMore: false, // 出错时没有更多数据
      );
    }
  }

  /// 应用过滤条件
  List<LogEntry> _applyFilter(List<LogEntry> entries, LogFilter filter) {
    if (filter.isEmpty) {
      return entries;
    }

    return entries.where((entry) {
      bool matchAuthor = filter.author == null ||
          filter.author!.isEmpty ||
          entry.author.toLowerCase().contains(filter.author!.toLowerCase());

      bool matchTitle = filter.title == null ||
          filter.title!.isEmpty ||
          entry.title.toLowerCase().contains(filter.title!.toLowerCase());

      return matchAuthor && matchTitle;
    }).toList();
  }

  /// 获取过滤后的总数（不返回具体条目，只返回数量）
  /// 
  /// 用于性能优化，在数据库层面使用 COUNT 查询
  /// 
  /// [stopOnCopy] 是否在遇到拷贝/分支点时停止（用于过滤显示）
  /// [workingDirectory] 工作目录（用于 stopOnCopy）
  Future<int> getFilteredCount(
    String sourceUrl,
    LogFilter filter, {
    bool stopOnCopy = false,
    String? workingDirectory,
  }) async {
    try {
      // 如果 stopOnCopy=true，需要找到分支点，只统计从分支点开始的数据
      // 本质目的：只关注分支被创建之后的版本
      int? minRevision;
      if (stopOnCopy && workingDirectory != null && workingDirectory.isNotEmpty) {
        try {
          // 对目标工作目录（分支）执行 svn log --stop-on-copy 找到分支点
          final branchPoint = await _findBranchPoint(workingDirectory);
          if (branchPoint != null) {
            minRevision = branchPoint;
          }
        } catch (e, stackTrace) {
          AppLogger.storage.warn('查找分支点失败: $e');
          AppLogger.storage.debug('查找分支点异常详情', stackTrace);
        }
      }
      
      return await _cacheService.getEntryCount(
        sourceUrl,
        authorFilter: filter.author,
        titleFilter: filter.title,
        minRevision: minRevision,
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取过滤后数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 查找分支点（用于 stopOnCopy）
  /// 注意：SVN 鉴权完全依赖 SVN 自身管理
  /// 使用缓存机制避免重复查询
  /// 
  /// [workingDirectory] 目标工作目录（分支的工作副本）
  /// 本质目的：找到分支是从哪个版本创建的，这样我们只需要关注分支被创建之后的版本
  Future<int?> _findBranchPoint(String workingDirectory) async {
    AppLogger.storage.info('  ┌─ 查找分支点 ──────────────────────────────');
    AppLogger.storage.info('  │ 工作目录: $workingDirectory');
    
    // 检查缓存（使用 workingDirectory 作为 key）
    if (_copyTailCache.containsKey(workingDirectory)) {
      final cached = _copyTailCache[workingDirectory];
      AppLogger.storage.info('  │ 使用缓存的COPY_TAIL: r$cached');
      AppLogger.storage.info('  └──────────────────────────────────────────');
      return cached;
    }
    
    try {
      AppLogger.storage.info('  │ 【子步骤 1/3】获取工作目录的 URL（分支 URL）');
      // 获取目标工作目录的 URL（分支的 URL）
      final branchUrl = await _svnService.getInfo(workingDirectory);
      AppLogger.storage.info('  │   分支 URL: $branchUrl');
      
      AppLogger.storage.info('  │ 【子步骤 2/3】查找分支点（COPY_TAIL）');
      AppLogger.storage.info('  │   命令: svn log --stop-on-copy -l 1 -r 1:HEAD');
      AppLogger.storage.info('  │   目的: 找到分支是从哪个版本创建的（分支点）');
      // 使用 SvnService 的专门方法查找分支点
      // 注意：必须使用 SvnService 的统一方法，不能自己组装命令
      final branchPoint = await _svnService.findBranchPoint(
        branchUrl,
        workingDirectory: workingDirectory,
      );
      
      if (branchPoint != null) {
        AppLogger.storage.info('  │   找到分支点（COPY_TAIL）: r$branchPoint');
      } else {
        AppLogger.storage.info('  │   未找到分支点');
      }
      
      // 缓存结果（包括 null，避免重复查询）
      _copyTailCache[workingDirectory] = branchPoint;
      AppLogger.storage.info('  │   已缓存COPY_TAIL');
      AppLogger.storage.info('  └──────────────────────────────────────────');
      return branchPoint;
    } catch (e, stackTrace) {
      AppLogger.storage.warn('  │ ❌ 查找分支点失败: $e');
      AppLogger.storage.debug('查找分支点异常详情', stackTrace);
      // 缓存失败结果，避免重复尝试
      _copyTailCache[workingDirectory] = null;
      AppLogger.storage.info('  └──────────────────────────────────────────');
      return null;
    }
  }

  /// 清除COPY_TAIL和ROOT_TAIL缓存
  /// 
  /// [sourceUrl] 源 URL（用于清除ROOT_TAIL缓存）
  /// [workingDirectory] 工作目录（用于清除COPY_TAIL缓存）
  /// 
  /// 注意：当源路径或目标路径发生变化时，应该调用此方法清除缓存
  static void clearTailCache({
    String? sourceUrl,
    String? workingDirectory,
  }) {
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      _rootTailCache.remove(sourceUrl);
      AppLogger.storage.info('已清除ROOT_TAIL缓存: $sourceUrl');
    }
    if (workingDirectory != null && workingDirectory.isNotEmpty) {
      _copyTailCache.remove(workingDirectory);
      AppLogger.storage.info('已清除COPY_TAIL缓存: $workingDirectory');
    }
  }

  /// 清除所有COPY_TAIL和ROOT_TAIL缓存
  static void clearAllTailCache() {
    _copyTailCache.clear();
    _rootTailCache.clear();
    _boundaryReachedCache.clear(); // 同时清除边界标记缓存
    AppLogger.storage.info('已清除所有 COPY_TAIL、ROOT_TAIL 和边界标记缓存');
  }
  
  /// 清除边界标记缓存（用于测试或强制刷新）
  static void clearBoundaryCache({String? sourceUrl, String? workingDirectory}) {
    if (sourceUrl != null || workingDirectory != null) {
      // 清除匹配的边界标记
      final keysToRemove = <String>[];
      for (final key in _boundaryReachedCache.keys) {
        if (sourceUrl != null && key.startsWith('$sourceUrl|')) {
          keysToRemove.add(key);
        } else if (workingDirectory != null && key.contains('|$workingDirectory|')) {
          keysToRemove.add(key);
        }
      }
      for (final key in keysToRemove) {
        _boundaryReachedCache.remove(key);
      }
      AppLogger.storage.info('已清除边界标记缓存: ${keysToRemove.length} 条');
    } else {
      _boundaryReachedCache.clear();
      AppLogger.storage.info('已清除所有边界标记缓存');
    }
  }

  /// 获取缓存中的总条目数
  Future<int> getTotalCount(String sourceUrl) async {
    return await _cacheService.getEntryCount(sourceUrl);
  }

  /// 根据 revision 列表获取日志条目
  /// 
  /// [sourceUrl] 源 URL
  /// [revisions] revision 列表
  /// 
  /// 返回匹配的日志条目列表（按 revision 降序排列）
  /// 
  /// 注意：这是本地数据模块的方法，只从缓存读取，不触发远端获取
  Future<List<LogEntry>> getEntriesByRevisions(
    String sourceUrl,
    List<int> revisions,
  ) async {
    await _cacheService.init();
    return await _cacheService.getEntriesByRevisions(sourceUrl, revisions);
  }
}

