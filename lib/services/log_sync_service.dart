/// 日志同步服务
///
/// 负责协调 SVN 日志抓取和缓存更新
/// - 支持区间管理：每次启动从 HEAD 开始获取
/// - 增量更新：向旧版本扩展最新区间
/// - 处理 stopOnCopy 逻辑

import 'svn_service.dart';
import 'log_cache_service.dart';
import 'logger_service.dart';
import 'svn_xml_parser.dart';

class LogSyncService {
  final SvnService _svnService = SvnService();
  final LogCacheService _cacheService = LogCacheService();
  
  // COPY_TAIL 缓存：key = workingDirectory, value = branchPoint revision（分支分界点）
  // 注意：这是非持久化的内存缓存，应用重启后会自动清空
  // 注意：与 LogFilterService 共享缓存，避免重复查询
  static final Map<String, int?> _copyTailCache = {};

  /// 从 HEAD 同步最新日志
  /// 
  /// 每次程序启动时调用，确保获取最新数据
  /// 
  /// [sourceUrl] 源 URL
  /// [limit] 每次抓取的条数限制
  /// [workingDirectory] 工作目录（可选）
  /// 
  /// 返回本次同步的日志条数
  Future<int> syncFromHead({
    required String sourceUrl,
    required int limit,
    String? workingDirectory,
  }) async {
    try {
      AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      AppLogger.svn.info('【从 HEAD 同步】开始');
      AppLogger.svn.info('  源 URL: $sourceUrl');
      AppLogger.svn.info('  限制条数: $limit');
      
      // 初始化缓存服务
      await _cacheService.init();
      
      // 步骤1：获取当前 HEAD revision
      AppLogger.svn.info('【步骤 1/4】获取 HEAD revision');
      final headRevision = await _getHeadRevision(sourceUrl, workingDirectory);
      if (headRevision == null || headRevision <= 0) {
        AppLogger.svn.warn('  无法获取 HEAD revision');
        AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return 0;
      }
      AppLogger.svn.info('  HEAD revision: r$headRevision');
      
      // 步骤2：获取最新区间信息
      AppLogger.svn.info('【步骤 2/4】检查缓存区间');
      final latestRange = await _cacheService.getLatestRange(sourceUrl);
      
      int fetchCount = limit;
      int? startRevision;
      
      if (latestRange != null) {
        AppLogger.svn.info('  最新区间: [${latestRange.startRevision}, ${latestRange.endRevision}]');
        
        // 计算 HEAD 到缓存头的距离
        final gap = headRevision - latestRange.startRevision;
        AppLogger.svn.info('  HEAD 到缓存头的距离: $gap');
        
        if (gap <= 0) {
          // 没有新数据
          AppLogger.svn.info('  没有新数据需要同步');
          AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          return 0;
        }
        
        // 取 gap 和 limit 的最小值
        fetchCount = gap < limit ? gap : limit;
        // 从 HEAD 开始获取，到缓存头为止
        startRevision = headRevision;
        AppLogger.svn.info('  将获取 $fetchCount 条（从 r$headRevision 到 r${latestRange.startRevision}）');
      } else {
        AppLogger.svn.info('  没有缓存区间，从 HEAD 开始获取');
        startRevision = null; // 从 HEAD 开始
      }
      
      // 步骤3：从 SVN 获取日志
      AppLogger.svn.info('【步骤 3/4】从 SVN 获取日志');
      final rawLog = await _svnService.log(
        sourceUrl,
        limit: fetchCount,
        workingDirectory: workingDirectory,
        startRevision: startRevision,
        reverseOrder: false,  // 从新到旧
      );
      
      // 解析 XML 日志
      var entries = SvnXmlParser.parseLog(rawLog);
      AppLogger.svn.info('  获取到 ${entries.length} 条日志');
      
      if (entries.isEmpty) {
        AppLogger.svn.info('  没有新日志');
        AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return 0;
      }
      
      // 如果有缓存区间，需要截断到缓存头，确保不重复
      if (latestRange != null) {
        final beforeCount = entries.length;
        entries = entries.where((e) => e.revision > latestRange.startRevision).toList();
        if (entries.length < beforeCount) {
          AppLogger.svn.info('  截断后剩余 ${entries.length} 条（排除已缓存的）');
        }
      }
      
      if (entries.isEmpty) {
        AppLogger.svn.info('  截断后没有新日志');
        AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return 0;
      }
      
      // 步骤4：更新缓存
      AppLogger.svn.info('【步骤 4/4】更新缓存');
      await _cacheService.insertEntries(sourceUrl, entries, isFromHead: true);
      
      AppLogger.svn.info('✓ 从 HEAD 同步完成，新增 ${entries.length} 条');
      AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return entries.length;
    } catch (e, stackTrace) {
      AppLogger.svn.error('从 HEAD 同步失败', e, stackTrace);
      rethrow;
    }
  }

  /// 获取 HEAD revision
  Future<int?> _getHeadRevision(String sourceUrl, String? workingDirectory) async {
    try {
      // 获取一条最新的日志来确定 HEAD
      final rawLog = await _svnService.log(
        sourceUrl,
        limit: 1,
        workingDirectory: workingDirectory,
      );
      final entries = SvnXmlParser.parseLog(rawLog);
      if (entries.isNotEmpty) {
        return entries.first.revision;
      }
      return null;
    } catch (e) {
      AppLogger.svn.error('获取 HEAD revision 失败: $e');
      return null;
    }
  }

  /// 同步日志（支持两种模式）
  /// 
  /// [sourceUrl] 源 URL
  /// [limit] 每次抓取的条数限制（从配置读取，默认500）
  /// [stopOnCopy] 是否在遇到拷贝/分支点时停止
  /// [workingDirectory] 工作目录（用于 stopOnCopy）
  /// [loadMore] 是否加载更多（true=从最新区间终点继续向旧版本读取，false=从HEAD开始刷新）
  /// 
  /// 注意：SVN 鉴权完全依赖 SVN 自身管理，不传递用户名密码
  /// 
  /// 返回本次同步的日志条数
  Future<int> syncLogs({
    required String sourceUrl,
    required int limit,
    bool stopOnCopy = false,
    String? workingDirectory,
    bool loadMore = false,
  }) async {
    try {
      AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      AppLogger.svn.info('【步骤 1/5】初始化日志同步服务');
      AppLogger.svn.info('  源 URL: $sourceUrl');
      AppLogger.svn.info('  限制条数: $limit');
      AppLogger.svn.info('  stopOnCopy: $stopOnCopy');
      AppLogger.svn.info('  工作目录: ${workingDirectory ?? "未指定"}');
      AppLogger.svn.info('  模式: ${loadMore ? "加载更多（从最新区间终点继续）" : "刷新最新（从HEAD开始）"}');
      
      // 初始化缓存服务
      AppLogger.svn.info('【步骤 2/5】初始化缓存服务');
      await _cacheService.init();
      AppLogger.svn.info('  缓存服务初始化完成');

      // 确定分支点（用于后续过滤）
      AppLogger.svn.info('【步骤 3/5】确定分支点');
      int? branchPoint;
      
      if (stopOnCopy && workingDirectory != null && workingDirectory.isNotEmpty) {
        AppLogger.svn.info('  stopOnCopy=true，需要查找分支点');
        AppLogger.svn.info('  工作目录: $workingDirectory');
        branchPoint = await _findBranchPoint(workingDirectory);
        if (branchPoint != null) {
          AppLogger.svn.info('  找到分支点: r$branchPoint');
        } else {
          AppLogger.svn.info('  未找到分支点');
        }
      } else {
        AppLogger.svn.info('  stopOnCopy=false 或未提供工作目录，不需要查找分支点');
      }

      // 获取最新区间信息
      AppLogger.svn.info('【步骤 4/5】查询缓存区间信息');
      final latestRange = await _cacheService.getLatestRange(sourceUrl);
      
      // 确定起始版本
      int? startRevision;
      bool isFromHead = !loadMore;
      
      if (loadMore) {
        // 加载更多模式：从最新区间的终点继续向旧版本读取
        if (latestRange != null) {
          startRevision = latestRange.endRevision;
          AppLogger.svn.info('  最新区间: [${latestRange.startRevision}, ${latestRange.endRevision}]');
          AppLogger.svn.info('  从 r$startRevision 开始向旧版本读取');
          
          // 如果已经到达分支点，不需要继续读取
          if (branchPoint != null && startRevision <= branchPoint) {
            AppLogger.svn.info('  已到达分支点 r$branchPoint，无需继续读取');
            AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
            return 0;
          }
        } else {
          // 没有区间，从 HEAD 开始
          AppLogger.svn.info('  没有缓存区间，从 HEAD 开始读取');
          isFromHead = true;
        }
      } else {
        // 刷新最新模式：使用 syncFromHead
        AppLogger.svn.info('  刷新模式：调用 syncFromHead');
        AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return await syncFromHead(
          sourceUrl: sourceUrl,
          limit: limit,
          workingDirectory: workingDirectory,
        );
      }

      // 抓取日志
      AppLogger.svn.info('【步骤 5/5】从 SVN 抓取日志');
      AppLogger.svn.info('  源 URL: $sourceUrl');
      AppLogger.svn.info('  起始版本: ${startRevision != null ? "r$startRevision" : "HEAD（最新）"}');
      AppLogger.svn.info('  方向: 向更旧版本');
      AppLogger.svn.info('  限制条数: $limit');
      AppLogger.svn.info('  分支点: ${branchPoint != null ? "r$branchPoint" : "无"}');
      
      final rawLog = await _svnService.log(
        sourceUrl,
        limit: limit,
        workingDirectory: workingDirectory,
        startRevision: startRevision,
        reverseOrder: true,  // 向更旧版本读取
      );

      // 解析 XML 日志
      AppLogger.svn.info('  解析 XML 日志...');
      final entries = SvnXmlParser.parseLog(rawLog);
      AppLogger.svn.info('  解析完成，获得 ${entries.length} 条日志');
      
      if (entries.isEmpty) {
        AppLogger.svn.info('  没有新日志需要同步');
        AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        return 0;
      }

      // 更新缓存
      AppLogger.svn.info('  更新缓存...');
      await _cacheService.insertEntries(sourceUrl, entries, isFromHead: isFromHead);
      AppLogger.svn.info('  缓存更新完成');

      AppLogger.svn.info('✓ 日志同步完成，新增 ${entries.length} 条');
      AppLogger.svn.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return entries.length;
    } catch (e, stackTrace) {
      AppLogger.svn.error('日志同步失败', e, stackTrace);
      rethrow;
    }
  }

  /// 查找分支点（用于 stopOnCopy）
  /// 注意：SVN 鉴权完全依赖 SVN 自身管理
  /// 使用缓存机制避免重复查询
  /// 
  /// [workingDirectory] 目标工作目录（分支的工作副本）
  /// 本质目的：找到分支是从哪个版本创建的，这样我们只需要关注分支被创建之后的版本
  Future<int?> _findBranchPoint(
    String workingDirectory,
  ) async {
    AppLogger.svn.info('  ┌─ 查找分支点 ──────────────────────────────');
    AppLogger.svn.info('  │ 工作目录: $workingDirectory');
    
          // 检查缓存（使用 workingDirectory 作为 key）
          if (_copyTailCache.containsKey(workingDirectory)) {
            final cached = _copyTailCache[workingDirectory];
            AppLogger.svn.info('  │ 使用缓存的COPY_TAIL: r$cached');
            AppLogger.svn.info('  └──────────────────────────────────────────');
            return cached;
          }
    
    try {
      AppLogger.svn.info('  │ 【子步骤 1/3】获取工作目录的 URL（分支 URL）');
      // 获取目标工作目录的 URL（分支的 URL）
      final branchUrl = await _svnService.getInfo(workingDirectory);
      AppLogger.svn.info('  │   分支 URL: $branchUrl');
      
      AppLogger.svn.info('  │ 【子步骤 2/3】查找分支点');
      AppLogger.svn.info('  │   命令: svn log --stop-on-copy -l 1 -r 1:HEAD');
      AppLogger.svn.info('  │   目的: 找到分支是从哪个版本创建的（分支点）');
      // 使用 SvnService 的专门方法查找分支点
      // 注意：必须使用 SvnService 的统一方法，不能自己组装命令
      final branchPoint = await _svnService.findBranchPoint(
        branchUrl,
        workingDirectory: workingDirectory,
      );
      
      if (branchPoint != null) {
        AppLogger.svn.info('  │   找到分支点: r$branchPoint');
      } else {
        AppLogger.svn.info('  │   未找到分支点');
      }
      
            // 缓存结果（包括 null，避免重复查询）
            _copyTailCache[workingDirectory] = branchPoint;
            AppLogger.svn.info('  │   已缓存COPY_TAIL');
            AppLogger.svn.info('  └──────────────────────────────────────────');
            return branchPoint;
          } catch (e, stackTrace) {
            AppLogger.svn.warn('  │ ❌ 查找分支点失败: $e');
            AppLogger.svn.debug('查找分支点异常详情', stackTrace);
            // 缓存失败结果，避免重复尝试
            _copyTailCache[workingDirectory] = null;
            AppLogger.svn.info('  └──────────────────────────────────────────');
            return null;
          }
        }

        /// 清除COPY_TAIL缓存（用于测试或强制刷新）
        /// 
        /// [workingDirectory] 工作目录（如果提供，只清除该目录的缓存；否则清除所有）
        static void clearCopyTailCache([String? workingDirectory]) {
          if (workingDirectory != null && workingDirectory.isNotEmpty) {
            _copyTailCache.remove(workingDirectory);
            AppLogger.svn.info('已清除COPY_TAIL缓存: $workingDirectory');
          } else {
            _copyTailCache.clear();
            AppLogger.svn.info('已清除所有COPY_TAIL缓存');
          }
        }

        /// 获取缓存的分支点（用于预加载服务检查停止条件）
        /// 
        /// [workingDirectory] 工作目录
        /// 返回缓存的分支点 revision，如果未缓存则返回 null
        static int? getCopyTailCache(String? workingDirectory) {
          if (workingDirectory == null || workingDirectory.isEmpty) {
            return null;
          }
          return _copyTailCache[workingDirectory];
        }

  /// 清空指定 sourceUrl 的缓存
  Future<void> clearCache(String sourceUrl) async {
    await _cacheService.clearCache(sourceUrl);
  }
}

