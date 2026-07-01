/// 日志同步服务
///
/// 负责协调 SVN 日志抓取和缓存更新
/// - 支持区间管理：每次启动从 HEAD 开始获取
/// - 增量更新：向旧版本扩展最新区间
/// - 处理 stopOnCopy 逻辑

import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import 'log_filter_service.dart' show appLogSeparator, isUsableWorkingDirectory;
import 'svn_service.dart';
import 'log_cache_service.dart';
import 'logger_service.dart';
import 'svn_xml_parser.dart';

/// 「从 HEAD 同步」的决策结果。
///
/// 由 [planSyncFromHead] 给出，封装了 [LogSyncService.syncFromHead] 中原本散落的
/// 「是否跳过 / 这次拉多少 / 起始 revision / 截断阈值」四件事。
@visibleForTesting
class SyncFromHeadPlan {
  /// 是否直接跳过 SVN 调用（HEAD 不可用 或 没有新数据）。
  final bool skip;

  /// 计划从 SVN 拉取的条数。`skip=true` 时无意义（保持 0）。
  final int fetchCount;

  /// 传给 `svn log` 的起始版本；`null` 表示从 HEAD 开始。
  final int? startRevision;

  /// 拉到日志后，仅保留 `revision >= truncateAtRevision` 的条目。
  /// `null` 表示不截断（首次同步、缓存为空场景）。
  final int? truncateAtRevision;

  const SyncFromHeadPlan({
    required this.skip,
    required this.fetchCount,
    required this.startRevision,
    required this.truncateAtRevision,
  });
}

/// 评估 HEAD revision 是否可用于同步。
///
/// **核心契约**：仅当 [revision] 非 null **且** 严格大于 0 时才视为有效。
///
/// **为什么这个谓词单独抽**：原 `syncLogs` 步骤 1 (line 254) 与 `planSyncFromHead`
/// (line 64) 各自内联了同一句 `headRevision == null || headRevision <= 0` 反向
/// 表达——任何一处把 `<= 0` 误改成 `< 0` 都会让 `r0`（SVN 仓库初始 revision，
/// 历史上确有 0 起始的仓库）被错误放行进入后续 `gap = headRevision - cached`
/// 计算，结果是负 gap，触发 skip 路径但语义错配（"没有新数据" vs "HEAD 不可用"）。
///
/// **`<= 0` 而不是 `< 0`**：SVN 的 `r0` 是仓库创建前的"虚拟空版本"，永远没有
/// 业务内容；本助手把它视为不可用，与 SVN log 的"r0 不出现在 commit 历史"语义
/// 对齐。任何"清理"成 `< 0`（让 r0 通过）都会破坏后续 `gap > 0` 推理的归纳
/// 起点（`gap = 0 - 0 = 0` 走 skip，但路径走错——本应 head-invalid 提前出）。
///
/// **不内联到 caller**：两处 caller 的"出错动作"不同——
/// - `planSyncFromHead`：返回 `SyncFromHeadPlan(skip: true, ...)` 让 caller
///   静默跳过；
/// - `syncLogs` 步骤 1：直接 `AppLogger.svn.warn` + `return 0` 中断同步流程。
///
/// 抽出谓词后，**判定逻辑单一来源**，两处的"出错动作"分支保留各自的 caller
/// 语境，不强行合并到 helper 内（设计模式 #9：形似但语义不同的"出错动作"
/// 不能合并）。
@visibleForTesting
bool isHeadRevisionValid(int? revision) {
  return revision != null && revision > 0;
}

/// 计算「从 HEAD 同步」的拉取计划。
///
/// 规则（与 `syncFromHead` 内联实现严格等价）：
/// - `headRevision == null` 或 `<= 0` → `skip=true`
/// - 缓存为空（`cachedStartRevision == null`）→ 全量从 HEAD 拉 `limit` 条，不截断
/// - 否则 `gap = headRevision - cachedStartRevision`：
///   - `gap <= 0` → 没有新数据，`skip=true`
///   - 否则 `fetchCount = min(gap + 1, limit)`，从 HEAD 拉，截断阈值 = `cachedStartRevision`
///     （`+1` 用来包含已缓存区间的头部边界 revision，让区间可以连续合并）
///
/// 调用方需保证 `limit > 0`。
@visibleForTesting
SyncFromHeadPlan planSyncFromHead({
  required int? headRevision,
  required int? cachedStartRevision,
  required int limit,
}) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'must be > 0');
  }
  if (!isHeadRevisionValid(headRevision)) {
    return const SyncFromHeadPlan(
      skip: true,
      fetchCount: 0,
      startRevision: null,
      truncateAtRevision: null,
    );
  }
  final headRevisionValid = headRevision!;
  if (cachedStartRevision == null) {
    return SyncFromHeadPlan(
      skip: false,
      fetchCount: limit,
      startRevision: null, // 让 SVN 从 HEAD 自动开始
      truncateAtRevision: null,
    );
  }
  final gap = headRevisionValid - cachedStartRevision;
  if (gap <= 0) {
    return const SyncFromHeadPlan(
      skip: true,
      fetchCount: 0,
      startRevision: null,
      truncateAtRevision: null,
    );
  }
  return SyncFromHeadPlan(
    skip: false,
    fetchCount: gap < limit ? gap + 1 : limit,
    startRevision: headRevisionValid,
    truncateAtRevision: cachedStartRevision,
  );
}

/// 「加载更多」分支的决策结果（loadMore 模式）。
@visibleForTesting
class LoadMorePlan {
  /// 是否退化为「从 HEAD 同步」（缓存为空时）。
  final bool fallbackToHead;

  /// 是否已到达分支点，应直接 0 返回不拉取。
  final bool skipAtBranchPoint;

  /// 起始 revision；仅当 `fallbackToHead == false && skipAtBranchPoint == false` 时有意义。
  final int? startRevision;

  const LoadMorePlan({
    required this.fallbackToHead,
    required this.skipAtBranchPoint,
    required this.startRevision,
  });
}

/// 计算 `syncLogs(loadMore: true)` 的拉取计划。
///
/// 规则（与 `syncLogs` 内联实现严格等价）：
/// - `cachedEndRevision == null` → `fallbackToHead=true`
/// - 否则 `startRevision = cachedEndRevision`：
///   - `branchPoint != null && startRevision <= branchPoint` → `skipAtBranchPoint=true`
///   - 否则正常拉取
@visibleForTesting
LoadMorePlan planLoadMore({
  required int? cachedEndRevision,
  required int? branchPoint,
}) {
  if (cachedEndRevision == null) {
    return const LoadMorePlan(
      fallbackToHead: true,
      skipAtBranchPoint: false,
      startRevision: null,
    );
  }
  if (branchPoint != null && cachedEndRevision <= branchPoint) {
    return LoadMorePlan(
      fallbackToHead: false,
      skipAtBranchPoint: true,
      startRevision: cachedEndRevision,
    );
  }
  return LoadMorePlan(
    fallbackToHead: false,
    skipAtBranchPoint: false,
    startRevision: cachedEndRevision,
  );
}

/// 按 revision 阈值截断「从 HEAD 同步」拿到的 entries，仅保留
/// `revision >= threshold` 的条目，保留原顺序。
///
/// **`>=` 而不是 `>`** 是有意为之，对应 [LogSyncService.syncFromHead] 中
/// 原注释强调的契约：
///
/// > 使用 >= 而不是 >，因为 LogCacheService 使用 INSERT OR REPLACE
/// > 处理重复数据。这样可以确保 `earliestRevision == latestRange.startRevision`，
/// > 满足区间连续性判断。
///
/// 任何把 `>=` 改成 `>` 的"清理"都会破坏区间连续性 → 上游
/// `evaluatePreloadStopReason` / 缓存合并逻辑会误判出空洞，因此本契约由测试锁定。
@visibleForTesting
List<LogEntry> truncateEntriesAtRevision(
  List<LogEntry> entries,
  int threshold,
) {
  return entries.where((e) => e.revision >= threshold).toList();
}

/// 把 [LogSyncService.syncLogs] 步骤 1 的"5 行启动信息"渲染成字符串列表。
///
/// **契约**：
/// - 5 行顺序固定：sourceUrl / limit / stopOnCopy / targetWorkingDirectory / 模式
/// - `targetWorkingDirectory == null` → 显示 `'未指定'`（**不**做 `isEmpty` 判定，
///   保留原代码 `?? "未指定"` 行为：空字符串视为"已指定但为空"，与 `isUsableWorkingDirectory`
///   的"非空 + 非空白"语义解耦——本函数只负责日志格式化，可用性判断由调用方守卫）
/// - `loadMore` 走中文长描述："加载更多（从最新区间终点继续）" / "刷新最新（从HEAD开始）"
/// - 行首两空格缩进，与 syncLogs 中其它 `'  ...'` 行保持视觉对齐
@visibleForTesting
List<String> formatSyncLogsHeaderLines({
  required String sourceUrl,
  required int limit,
  required bool stopOnCopy,
  required String? targetWorkingDirectory,
  required bool loadMore,
}) {
  return [
    '  源 URL: $sourceUrl',
    '  限制条数: $limit',
    '  stopOnCopy: $stopOnCopy',
    '  目标工作副本: ${targetWorkingDirectory ?? "未指定"}',
    '  模式: ${loadMore ? "加载更多（从最新区间终点继续）" : "刷新最新（从HEAD开始）"}',
  ];
}

/// 把 [LogSyncService.syncLogs] 步骤 5 的"5 行抓取参数"渲染成字符串列表。
///
/// **契约**：
/// - 5 行顺序固定：sourceUrl / 起始版本 / 方向 / 限制条数 / 分支点
/// - `startRevision == null` → 显示 `'HEAD（最新）'`，否则 `'r$startRevision'`
/// - `branchPoint == null` → 显示 `'无'`，否则 `'r$branchPoint'`
/// - 方向是常量字符串 `'向更旧版本'`——本函数不暴露方向开关，因为 syncLogs
///   只走 reverseOrder=true 一条路径（向 HEAD 同步走的是 syncFromHead，不经此处）
@visibleForTesting
List<String> formatSyncLogsFetchLines({
  required String sourceUrl,
  required int? startRevision,
  required int limit,
  required int? branchPoint,
}) {
  return [
    '  源 URL: $sourceUrl',
    '  起始版本: ${startRevision != null ? "r$startRevision" : "HEAD（最新）"}',
    '  方向: 向更旧版本',
    '  限制条数: $limit',
    '  分支点: ${branchPoint != null ? "r$branchPoint" : "无"}',
  ];
}

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
  /// 仅根据 [sourceUrl] 拉取日志；源侧 SVN log 不需要目标工作副本作为 cwd。
  ///
  /// 返回本次同步的日志条数
  Future<int> syncFromHead({
    required String sourceUrl,
    required int limit,
  }) async {
    try {
      AppLogger.svn.info(appLogSeparator);
      AppLogger.svn.info('【从 HEAD 同步】开始');
      AppLogger.svn.info('  源 URL: $sourceUrl');
      AppLogger.svn.info('  限制条数: $limit');

      // 初始化缓存服务
      await _cacheService.init();

      // 步骤1：获取当前 HEAD revision
      AppLogger.svn.info('【步骤 1/4】获取 HEAD revision');
      final headRevision = await _getHeadRevision(sourceUrl);
      if (!isHeadRevisionValid(headRevision)) {
        AppLogger.svn.warn('  无法获取 HEAD revision');
        AppLogger.svn.info(appLogSeparator);
        return 0;
      }
      final headRevisionValid = headRevision!;
      AppLogger.svn.info('  HEAD revision: r$headRevisionValid');

      // 步骤2：获取最新区间信息
      AppLogger.svn.info('【步骤 2/4】检查缓存区间');
      final latestRange = await _cacheService.getLatestRange(sourceUrl);

      if (latestRange != null) {
        AppLogger.svn.info(
            '  最新区间: [${latestRange.startRevision}, ${latestRange.endRevision}]');
        AppLogger.svn.info(
            '  HEAD 到缓存头的距离: ${headRevisionValid - latestRange.startRevision}');
      } else {
        AppLogger.svn.info('  没有缓存区间，从 HEAD 开始获取');
      }

      final plan = planSyncFromHead(
        headRevision: headRevisionValid,
        cachedStartRevision: latestRange?.startRevision,
        limit: limit,
      );

      if (plan.skip) {
        AppLogger.svn.info('  没有新数据需要同步');
        AppLogger.svn.info(appLogSeparator);
        return 0;
      }

      if (latestRange != null) {
        AppLogger.svn.info(
            '  将获取 ${plan.fetchCount} 条（从 r$headRevisionValid 到 r${latestRange.startRevision}）');
      }

      // 步骤3：从 SVN 获取日志
      // 注意：从 HEAD 向旧版本读取，所以使用 reverseOrder: true
      AppLogger.svn.info('【步骤 3/4】从 SVN 获取日志');
      final rawLog = await _svnService.log(
        sourceUrl,
        limit: plan.fetchCount,
        startRevision: plan.startRevision,
        reverseOrder: true, // 从 HEAD 向旧版本读取
      );

      // 解析 XML 日志
      var entries = SvnXmlParser.parseLog(rawLog);
      AppLogger.svn.info('  获取到 ${entries.length} 条日志');

      if (entries.isEmpty) {
        AppLogger.svn.info('  没有新日志');
        AppLogger.svn.info(appLogSeparator);
        return 0;
      }

      // 如果有缓存区间，需要截断到缓存头（包含边界值，确保区间连续）
      if (plan.truncateAtRevision != null) {
        final beforeCount = entries.length;
        entries = truncateEntriesAtRevision(entries, plan.truncateAtRevision!);
        if (entries.length < beforeCount) {
          AppLogger.svn.info('  截断后剩余 ${entries.length} 条（排除已缓存的）');
        }
      }

      if (entries.isEmpty) {
        AppLogger.svn.info('  截断后没有新日志');
        AppLogger.svn.info(appLogSeparator);
        return 0;
      }

      // 步骤4：更新缓存
      AppLogger.svn.info('【步骤 4/4】更新缓存');
      await _cacheService.insertEntries(sourceUrl, entries, isFromHead: true);

      AppLogger.svn.info('✓ 从 HEAD 同步完成，新增 ${entries.length} 条');
      AppLogger.svn.info(appLogSeparator);
      return entries.length;
    } catch (e, stackTrace) {
      AppLogger.svn.error('从 HEAD 同步失败', e, stackTrace);
      rethrow;
    }
  }

  /// 获取 HEAD revision
  Future<int?> _getHeadRevision(String sourceUrl) async {
    try {
      // 获取一条最新的日志来确定 HEAD
      final rawLog = await _svnService.log(
        sourceUrl,
        limit: 1,
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
  /// [targetWorkingDirectory] 目标工作副本（仅用于 stopOnCopy 分支点判断）
  /// [loadMore] 是否加载更多（true=从最新区间终点继续向旧版本读取，false=从HEAD开始刷新）
  ///
  /// 注意：SVN 鉴权完全依赖 SVN 自身管理，不传递用户名密码
  ///
  /// 返回本次同步的日志条数
  Future<int> syncLogs({
    required String sourceUrl,
    required int limit,
    bool stopOnCopy = false,
    String? targetWorkingDirectory,
    bool loadMore = false,
  }) async {
    try {
      AppLogger.svn.info(appLogSeparator);
      AppLogger.svn.info('【步骤 1/5】初始化日志同步服务');
      for (final line in formatSyncLogsHeaderLines(
        sourceUrl: sourceUrl,
        limit: limit,
        stopOnCopy: stopOnCopy,
        targetWorkingDirectory: targetWorkingDirectory,
        loadMore: loadMore,
      )) {
        AppLogger.svn.info(line);
      }

      // 初始化缓存服务
      AppLogger.svn.info('【步骤 2/5】初始化缓存服务');
      await _cacheService.init();
      AppLogger.svn.info('  缓存服务初始化完成');

      // 确定分支点（用于后续过滤）
      AppLogger.svn.info('【步骤 3/5】确定分支点');
      int? branchPoint;

      if (stopOnCopy && isUsableWorkingDirectory(targetWorkingDirectory)) {
        AppLogger.svn.info('  stopOnCopy=true，需要查找分支点');
        AppLogger.svn.info('  目标工作副本: $targetWorkingDirectory');
        // isUsableWorkingDirectory 已保证 targetWorkingDirectory 非 null 且非空
        branchPoint = await _findBranchPoint(targetWorkingDirectory!);
        if (branchPoint != null) {
          AppLogger.svn.info('  找到分支点: r$branchPoint');
        } else {
          AppLogger.svn.info('  未找到分支点');
        }
      } else {
        AppLogger.svn.info('  stopOnCopy=false 或未提供目标工作副本，不需要查找分支点');
      }

      // 获取最新区间信息
      AppLogger.svn.info('【步骤 4/5】查询缓存区间信息');
      final latestRange = await _cacheService.getLatestRange(sourceUrl);

      // 确定起始版本
      int? startRevision;
      bool isFromHead = !loadMore;

      if (loadMore) {
        // 加载更多模式：从最新区间的终点继续向旧版本读取
        final loadPlan = planLoadMore(
          cachedEndRevision: latestRange?.endRevision,
          branchPoint: branchPoint,
        );

        if (loadPlan.fallbackToHead) {
          // 没有区间，从 HEAD 开始
          AppLogger.svn.info('  没有缓存区间，从 HEAD 开始读取');
          isFromHead = true;
        } else {
          startRevision = loadPlan.startRevision;
          AppLogger.svn.info(
              '  最新区间: [${latestRange!.startRevision}, ${latestRange.endRevision}]');
          AppLogger.svn.info('  从 r$startRevision 开始向旧版本读取');

          if (loadPlan.skipAtBranchPoint) {
            AppLogger.svn.info('  已到达分支点 r$branchPoint，无需继续读取');
            AppLogger.svn.info(appLogSeparator);
            return 0;
          }
        }
      } else {
        // 刷新最新模式：使用 syncFromHead
        AppLogger.svn.info('  刷新模式：调用 syncFromHead');
        AppLogger.svn.info(appLogSeparator);
        return await syncFromHead(
          sourceUrl: sourceUrl,
          limit: limit,
        );
      }

      // 抓取日志
      AppLogger.svn.info('【步骤 5/5】从 SVN 抓取日志');
      for (final line in formatSyncLogsFetchLines(
        sourceUrl: sourceUrl,
        startRevision: startRevision,
        limit: limit,
        branchPoint: branchPoint,
      )) {
        AppLogger.svn.info(line);
      }

      final rawLog = await _svnService.log(
        sourceUrl,
        limit: limit,
        startRevision: startRevision,
        reverseOrder: true, // 向更旧版本读取
      );

      // 解析 XML 日志
      AppLogger.svn.info('  解析 XML 日志...');
      final entries = SvnXmlParser.parseLog(rawLog);
      AppLogger.svn.info('  解析完成，获得 ${entries.length} 条日志');

      if (entries.isEmpty) {
        AppLogger.svn.info('  没有新日志需要同步');
        AppLogger.svn.info(appLogSeparator);
        return 0;
      }

      // 更新缓存
      AppLogger.svn.info('  更新缓存...');
      await _cacheService.insertEntries(sourceUrl, entries,
          isFromHead: isFromHead);
      AppLogger.svn.info('  缓存更新完成');

      AppLogger.svn.info('✓ 日志同步完成，新增 ${entries.length} 条');
      AppLogger.svn.info(appLogSeparator);
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
  /// [workingDirectory] 目标工作目录或目标 SVN URL
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
      final branchUrl = isSvnRepositoryUrl(workingDirectory)
          ? workingDirectory
          : await _svnService.getInfo(workingDirectory);
      AppLogger.svn.info('  │   分支 URL: $branchUrl');

      AppLogger.svn.info('  │ 【子步骤 2/3】查找分支点');
      AppLogger.svn.info('  │   命令: svn log --stop-on-copy -l 1 -r 1:HEAD');
      AppLogger.svn.info('  │   目的: 找到分支是从哪个版本创建的（分支点）');
      // 使用 SvnService 的专门方法查找分支点
      // 注意：必须使用 SvnService 的统一方法，不能自己组装命令
      final branchPoint = await _svnService.findBranchPoint(
        branchUrl,
        workingDirectory:
            isSvnRepositoryUrl(workingDirectory) ? null : workingDirectory,
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
    if (isUsableWorkingDirectory(workingDirectory)) {
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
    if (!isUsableWorkingDirectory(workingDirectory)) {
      return null;
    }
    return _copyTailCache[workingDirectory];
  }

  /// 清空指定 sourceUrl 的缓存
  Future<void> clearCache(String sourceUrl) async {
    await _cacheService.clearCache(sourceUrl);
  }
}
