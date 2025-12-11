/// 预加载服务
///
/// 负责后台静默预加载 SVN 日志数据
/// 
/// 功能：
/// - 后台静默加载日志到缓存
/// - 支持多种停止条件（分支点、天数、条数、版本、日期）
/// - 提供加载进度回调
/// - 支持手动触发"加载全部到分支点"
/// - 使用区间管理：每次启动从 HEAD 开始

import 'dart:async';
import '../models/app_config.dart';
import 'log_sync_service.dart';
import 'log_cache_service.dart';
import 'logger_service.dart';

/// 预加载状态
enum PreloadStatus {
  /// 空闲（未开始或已完成）
  idle,
  /// 正在加载
  loading,
  /// 已暂停
  paused,
  /// 已完成（到达停止条件）
  completed,
  /// 出错
  error,
}

/// 预加载停止原因
enum PreloadStopReason {
  /// 未停止
  none,
  /// 到达分支点
  branchPoint,
  /// 到达天数限制
  daysLimit,
  /// 到达条数限制
  countLimit,
  /// 到达指定版本
  revisionLimit,
  /// 到达指定日期
  dateLimit,
  /// 没有更多数据
  noMoreData,
  /// 用户手动停止
  userStopped,
  /// 发生错误
  error,
}

/// 预加载进度信息
class PreloadProgress {
  /// 当前状态
  final PreloadStatus status;
  
  /// 停止原因
  final PreloadStopReason stopReason;
  
  /// 已加载条数
  final int loadedCount;
  
  /// 最早加载的日期
  final DateTime? earliestDate;
  
  /// 最早加载的版本
  final int? earliestRevision;
  
  /// 分支点版本（如果已知）
  final int? branchPoint;
  
  /// 错误信息（如果有）
  final String? errorMessage;
  
  /// 当前加载的源 URL
  final String? sourceUrl;

  const PreloadProgress({
    this.status = PreloadStatus.idle,
    this.stopReason = PreloadStopReason.none,
    this.loadedCount = 0,
    this.earliestDate,
    this.earliestRevision,
    this.branchPoint,
    this.errorMessage,
    this.sourceUrl,
  });

  PreloadProgress copyWith({
    PreloadStatus? status,
    PreloadStopReason? stopReason,
    int? loadedCount,
    DateTime? earliestDate,
    int? earliestRevision,
    int? branchPoint,
    String? errorMessage,
    String? sourceUrl,
  }) {
    return PreloadProgress(
      status: status ?? this.status,
      stopReason: stopReason ?? this.stopReason,
      loadedCount: loadedCount ?? this.loadedCount,
      earliestDate: earliestDate ?? this.earliestDate,
      earliestRevision: earliestRevision ?? this.earliestRevision,
      branchPoint: branchPoint ?? this.branchPoint,
      errorMessage: errorMessage ?? this.errorMessage,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
  
  /// 获取状态描述
  String get statusDescription {
    switch (status) {
      case PreloadStatus.idle:
        return '空闲';
      case PreloadStatus.loading:
        return '加载中...';
      case PreloadStatus.paused:
        return '已暂停';
      case PreloadStatus.completed:
        return _getStopReasonDescription();
      case PreloadStatus.error:
        return '出错: ${errorMessage ?? "未知错误"}';
    }
  }
  
  String _getStopReasonDescription() {
    switch (stopReason) {
      case PreloadStopReason.none:
        return '已完成';
      case PreloadStopReason.branchPoint:
        return '已到达分支点 r$branchPoint';
      case PreloadStopReason.daysLimit:
        return '已到达天数限制';
      case PreloadStopReason.countLimit:
        return '已到达条数限制 ($loadedCount 条)';
      case PreloadStopReason.revisionLimit:
        return '已到达指定版本';
      case PreloadStopReason.dateLimit:
        return '已到达指定日期';
      case PreloadStopReason.noMoreData:
        return '已加载全部数据';
      case PreloadStopReason.userStopped:
        return '用户停止';
      case PreloadStopReason.error:
        return '出错: ${errorMessage ?? "未知错误"}';
    }
  }
}

/// 预加载服务
class PreloadService {
  /// 单例模式
  static final PreloadService _instance = PreloadService._internal();
  factory PreloadService() => _instance;
  PreloadService._internal();

  final LogSyncService _syncService = LogSyncService();
  final LogCacheService _cacheService = LogCacheService();
  
  /// 当前进度
  PreloadProgress _progress = const PreloadProgress();
  PreloadProgress get progress => _progress;
  
  /// 进度回调
  void Function(PreloadProgress)? onProgressChanged;
  
  /// 是否应该停止
  bool _shouldStop = false;
  
  /// 当前加载的源 URL
  String? _currentSourceUrl;
  
  /// 初始化
  Future<void> init() async {
    await _cacheService.init();
  }
  
  /// 开始后台预加载
  /// 
  /// [sourceUrl] 源 URL
  /// [settings] 预加载设置
  /// [workingDirectory] 工作目录（用于 stopOnCopy）
  /// [fetchLimit] 每次从 SVN 获取的条数
  Future<void> startPreload({
    required String sourceUrl,
    required PreloadSettings settings,
    String? workingDirectory,
    int fetchLimit = 200,
  }) async {
    if (_progress.status == PreloadStatus.loading) {
      AppLogger.preload.warn('预加载已在进行中，忽略重复请求');
      return;
    }
    
    _shouldStop = false;
    _currentSourceUrl = sourceUrl;
    
    AppLogger.preload.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.preload.info('【预加载服务】开始后台预加载');
    AppLogger.preload.info('  源 URL: $sourceUrl');
    AppLogger.preload.info('  设置:');
    AppLogger.preload.info('    - 到达分支点停止: ${settings.stopOnBranchPoint}');
    AppLogger.preload.info('    - 天数限制: ${settings.maxDays > 0 ? "${settings.maxDays} 天" : "无限制"}');
    AppLogger.preload.info('    - 条数限制: ${settings.maxCount > 0 ? "${settings.maxCount} 条" : "无限制"}');
    AppLogger.preload.info('    - 版本限制: ${settings.stopRevision > 0 ? "r${settings.stopRevision}" : "无限制"}');
    AppLogger.preload.info('    - 日期限制: ${settings.stopDate ?? "无限制"}');
    
    _updateProgress(_progress.copyWith(
      status: PreloadStatus.loading,
      stopReason: PreloadStopReason.none,
      sourceUrl: sourceUrl,
    ));
    
    try {
      // 【重要】首先从 HEAD 同步新数据（使用新的 syncFromHead 方法）
      AppLogger.preload.info('  步骤1: 从 HEAD 同步新数据...');
      final newDataCount = await _syncService.syncFromHead(
        sourceUrl: sourceUrl,
        limit: fetchLimit,
        workingDirectory: workingDirectory,
      );
      if (newDataCount > 0) {
        AppLogger.preload.info('  从 HEAD 获取了 $newDataCount 条新数据');
      } else {
        AppLogger.preload.info('  没有新数据');
      }
      
      // 获取当前缓存状态（使用最新区间）
      final totalCount = await _cacheService.getLatestRangeEntryCount(sourceUrl);
      final earliestRevision = await _cacheService.getEarliestRevisionInLatestRange(sourceUrl);
      final earliestDate = await _cacheService.getEarliestDateInLatestRange(sourceUrl);
      
      _updateProgress(_progress.copyWith(
        loadedCount: totalCount,
        earliestRevision: earliestRevision > 0 ? earliestRevision : null,
        earliestDate: earliestDate,
      ));
      
      AppLogger.preload.info('  当前最新区间缓存: $totalCount 条');
      if (earliestRevision > 0) {
        AppLogger.preload.info('  最早版本: r$earliestRevision');
      }
      
      // 步骤2: 继续加载更旧的数据
      AppLogger.preload.info('  步骤2: 继续加载更旧的数据...');
      
      // 计算停止条件
      final now = DateTime.now();
      final daysLimitDate = settings.maxDays > 0 
          ? now.subtract(Duration(days: settings.maxDays))
          : null;
      final stopDate = settings.stopDateTime;
      
      // 循环加载直到满足停止条件
      while (!_shouldStop) {
        // 检查停止条件
        final stopReason = await _checkStopConditions(
          sourceUrl: sourceUrl,
          settings: settings,
          workingDirectory: workingDirectory,
          daysLimitDate: daysLimitDate,
          stopDate: stopDate,
        );
        
        if (stopReason != PreloadStopReason.none) {
          _updateProgress(_progress.copyWith(
            status: PreloadStatus.completed,
            stopReason: stopReason,
          ));
          AppLogger.preload.info('✓ 预加载完成: ${_progress.statusDescription}');
          break;
        }
        
        // 加载更多数据
        AppLogger.preload.info('  加载更多数据...');
        final newCount = await _syncService.syncLogs(
          sourceUrl: sourceUrl,
          limit: fetchLimit,
          stopOnCopy: settings.stopOnBranchPoint,
          workingDirectory: workingDirectory,
          loadMore: true,
        );
        
        if (newCount == 0) {
          _updateProgress(_progress.copyWith(
            status: PreloadStatus.completed,
            stopReason: PreloadStopReason.noMoreData,
          ));
          AppLogger.preload.info('✓ 预加载完成: 没有更多数据');
          break;
        }
        
        // 更新进度（使用最新区间的统计）
        final updatedCount = await _cacheService.getLatestRangeEntryCount(sourceUrl);
        final updatedEarliestRev = await _cacheService.getEarliestRevisionInLatestRange(sourceUrl);
        final updatedEarliestDate = await _cacheService.getEarliestDateInLatestRange(sourceUrl);
        
        _updateProgress(_progress.copyWith(
          loadedCount: updatedCount,
          earliestRevision: updatedEarliestRev > 0 ? updatedEarliestRev : null,
          earliestDate: updatedEarliestDate,
        ));
        
        AppLogger.preload.info('  已加载: $updatedCount 条, 最早: r$updatedEarliestRev');
        
        // 短暂延迟，避免过度占用资源
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (_shouldStop && _progress.status == PreloadStatus.loading) {
        _updateProgress(_progress.copyWith(
          status: PreloadStatus.completed,
          stopReason: PreloadStopReason.userStopped,
        ));
        AppLogger.preload.info('✓ 预加载已停止（用户请求）');
      }
      
    } catch (e, stackTrace) {
      AppLogger.preload.error('预加载失败', e, stackTrace);
      _updateProgress(_progress.copyWith(
        status: PreloadStatus.error,
        stopReason: PreloadStopReason.error,
        errorMessage: e.toString(),
      ));
    }
    
    AppLogger.preload.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
  
  /// 检查停止条件
  Future<PreloadStopReason> _checkStopConditions({
    required String sourceUrl,
    required PreloadSettings settings,
    String? workingDirectory,
    DateTime? daysLimitDate,
    DateTime? stopDate,
  }) async {
    // 获取当前缓存状态（使用最新区间的统计）
    final totalCount = await _cacheService.getLatestRangeEntryCount(sourceUrl);
    final earliestRevision = await _cacheService.getEarliestRevisionInLatestRange(sourceUrl);
    final earliestDate = await _cacheService.getEarliestDateInLatestRange(sourceUrl);
    
    // 1. 检查条数限制
    if (settings.maxCount > 0 && totalCount >= settings.maxCount) {
      return PreloadStopReason.countLimit;
    }
    
    // 2. 检查版本限制
    if (settings.stopRevision > 0 && earliestRevision > 0 && earliestRevision <= settings.stopRevision) {
      return PreloadStopReason.revisionLimit;
    }
    
    // 3. 检查天数限制
    if (daysLimitDate != null && earliestDate != null && earliestDate.isBefore(daysLimitDate)) {
      return PreloadStopReason.daysLimit;
    }
    
    // 4. 检查日期限制
    if (stopDate != null && earliestDate != null && earliestDate.isBefore(stopDate)) {
      return PreloadStopReason.dateLimit;
    }
    
    // 5. 检查分支点（通过 LogSyncService 的缓存）
    if (settings.stopOnBranchPoint && workingDirectory != null) {
      final branchPoint = LogSyncService.getCopyTailCache(workingDirectory);
      if (branchPoint != null && earliestRevision > 0 && earliestRevision <= branchPoint) {
        _updateProgress(_progress.copyWith(branchPoint: branchPoint));
        return PreloadStopReason.branchPoint;
      }
    }
    
    return PreloadStopReason.none;
  }
  
  /// 停止预加载
  void stopPreload() {
    _shouldStop = true;
    AppLogger.preload.info('请求停止预加载...');
  }
  
  /// 加载全部到分支点
  /// 
  /// 忽略其他停止条件，直接加载到分支点
  Future<void> loadAllToBranchPoint({
    required String sourceUrl,
    String? workingDirectory,
    int fetchLimit = 200,
  }) async {
    await startPreload(
      sourceUrl: sourceUrl,
      settings: const PreloadSettings(
        enabled: true,
        stopOnBranchPoint: true,
        maxDays: 0,      // 不限制
        maxCount: 0,     // 不限制
        stopRevision: 0, // 不限制
        stopDate: null,  // 不限制
      ),
      workingDirectory: workingDirectory,
      fetchLimit: fetchLimit,
    );
  }
  
  /// 更新进度并通知
  void _updateProgress(PreloadProgress newProgress) {
    _progress = newProgress;
    onProgressChanged?.call(_progress);
  }
  
  /// 重置状态
  void reset() {
    _shouldStop = false;
    _currentSourceUrl = null;
    _progress = const PreloadProgress();
  }
}
