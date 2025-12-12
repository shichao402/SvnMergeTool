/// SVN 工作副本操作管理器
/// 
/// 采用门面模式 (Facade Pattern) + 互斥锁模式 (Mutex Pattern)
/// 
/// 设计原则：
/// - 单一职责原则 (SRP)：只负责工作副本操作的调度和锁管理
/// - 门面模式：提供统一的接口来访问所有工作副本操作
/// - 互斥锁模式：确保同一工作副本同一时间只有一个操作在执行
/// 
/// 使用方式：
/// ```dart
/// final wcManager = WorkingCopyManager();
/// 
/// // 执行 update 操作（自动加锁/解锁）
/// await wcManager.update(targetWc);
/// 
/// // 执行 revert 操作
/// await wcManager.revert(targetWc);
/// 
/// // 检查是否正在操作中
/// if (wcManager.isLocked(targetWc)) {
///   print('工作副本正在操作中...');
/// }
/// ```
/// 
/// 注意事项：
/// - 所有对工作副本的操作都必须通过此管理器
/// - 禁止直接调用 SvnService 的工作副本操作方法
/// - 操作会自动排队，后续操作需要等待前一个完成

import 'dart:async';
import 'logger_service.dart';
import 'svn_service.dart';
import 'mergeinfo_cache_service.dart';

/// 操作类型枚举
enum WcOperationType {
  update,
  revert,
  cleanup,
  merge,
  commit,
  status,
  info,
  propget,
}

/// 操作状态
enum WcOperationStatus {
  idle,      // 空闲
  running,   // 运行中
  waiting,   // 等待中（队列中）
}

/// 工作副本锁信息
class WcLockInfo {
  final String workingCopy;
  final WcOperationType operationType;
  final DateTime startTime;
  final String? description;
  
  WcLockInfo({
    required this.workingCopy,
    required this.operationType,
    required this.startTime,
    this.description,
  });
  
  Duration get elapsed => DateTime.now().difference(startTime);
  
  @override
  String toString() => 'WcLockInfo($workingCopy, $operationType, elapsed: ${elapsed.inSeconds}s)';
}

/// 工作副本操作管理器
/// 
/// 单例模式，全局唯一实例
class WorkingCopyManager {
  /// 单例实例
  static final WorkingCopyManager _instance = WorkingCopyManager._internal();
  factory WorkingCopyManager() => _instance;
  WorkingCopyManager._internal();
  
  /// SVN 服务
  final SvnService _svnService = SvnService();
  
  /// MergeInfo 缓存服务
  final MergeInfoCacheService _mergeInfoService = MergeInfoCacheService();
  
  /// 工作副本锁映射
  /// key: 工作副本路径（规范化后）
  /// value: Completer，用于等待锁释放
  final Map<String, Completer<void>> _locks = {};
  
  /// 当前锁信息
  final Map<String, WcLockInfo> _lockInfos = {};
  
  /// 操作状态变化通知
  final _statusController = StreamController<WcLockInfo?>.broadcast();
  
  /// 状态变化流
  Stream<WcLockInfo?> get statusStream => _statusController.stream;
  
  /// 规范化工作副本路径
  String _normalizePath(String path) {
    // 统一使用小写（Windows 不区分大小写）
    // 统一使用正斜杠
    // 移除末尾斜杠
    return path
        .toLowerCase()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
  }
  
  /// 检查工作副本是否被锁定
  bool isLocked(String workingCopy) {
    final normalized = _normalizePath(workingCopy);
    return _locks.containsKey(normalized);
  }
  
  /// 获取当前锁信息
  WcLockInfo? getLockInfo(String workingCopy) {
    final normalized = _normalizePath(workingCopy);
    return _lockInfos[normalized];
  }
  
  /// 获取所有锁信息
  List<WcLockInfo> get allLockInfos => _lockInfos.values.toList();
  
  /// 获取当前操作状态
  WcOperationStatus getStatus(String workingCopy) {
    final normalized = _normalizePath(workingCopy);
    if (_locks.containsKey(normalized)) {
      return WcOperationStatus.running;
    }
    return WcOperationStatus.idle;
  }
  
  /// 获取锁（内部方法）
  /// 
  /// 如果工作副本已被锁定，等待锁释放
  Future<void> _acquireLock(String workingCopy, WcOperationType operationType, {String? description}) async {
    final normalized = _normalizePath(workingCopy);
    
    // 如果已有锁，等待释放
    while (_locks.containsKey(normalized)) {
      AppLogger.svn.info('工作副本 $workingCopy 正在执行 ${_lockInfos[normalized]?.operationType}，等待中...');
      await _locks[normalized]!.future;
    }
    
    // 创建新锁
    _locks[normalized] = Completer<void>();
    _lockInfos[normalized] = WcLockInfo(
      workingCopy: workingCopy,
      operationType: operationType,
      startTime: DateTime.now(),
      description: description,
    );
    
    AppLogger.svn.info('已获取工作副本锁: $workingCopy ($operationType)');
    _statusController.add(_lockInfos[normalized]);
  }
  
  /// 释放锁（内部方法）
  void _releaseLock(String workingCopy) {
    final normalized = _normalizePath(workingCopy);
    
    if (_locks.containsKey(normalized)) {
      final lockInfo = _lockInfos[normalized];
      AppLogger.svn.info('释放工作副本锁: $workingCopy (耗时: ${lockInfo?.elapsed.inSeconds}s)');
      
      _locks[normalized]!.complete();
      _locks.remove(normalized);
      _lockInfos.remove(normalized);
      
      _statusController.add(null);
    }
  }
  
  /// 执行带锁的操作（内部方法）
  Future<T> _withLock<T>(
    String workingCopy,
    WcOperationType operationType,
    Future<T> Function() operation, {
    String? description,
  }) async {
    await _acquireLock(workingCopy, operationType, description: description);
    try {
      return await operation();
    } finally {
      _releaseLock(workingCopy);
    }
  }
  
  // ==================== 公开的操作方法 ====================
  
  /// SVN Update
  /// 
  /// 更新工作副本到最新版本
  Future<SvnProcessResult> update(
    String workingCopy, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.update,
      () => _svnService.update(workingCopy, username: username, password: password),
      description: 'Update 工作副本',
    );
  }
  
  /// SVN Revert
  /// 
  /// 还原工作副本的本地修改
  /// [refreshMergeInfo] 是否在 revert 后刷新 mergeinfo 缓存（默认 true）
  Future<SvnProcessResult> revert(
    String workingCopy, {
    bool recursive = true,
    String? sourceUrl,
    bool refreshMergeInfo = true,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.revert,
      () async {
        final result = await _svnService.revert(workingCopy, recursive: recursive);
        
        // Revert 成功后刷新 mergeinfo 缓存
        if (result.exitCode == 0 && refreshMergeInfo && sourceUrl != null && sourceUrl.isNotEmpty) {
          AppLogger.svn.info('Revert 后刷新 mergeinfo 缓存...');
          try {
            await _mergeInfoService.getMergedRevisions(
              sourceUrl,
              workingCopy,
              fullRefresh: true,
            );
            AppLogger.svn.info('Mergeinfo 缓存已刷新');
          } catch (e) {
            AppLogger.svn.warn('刷新 mergeinfo 缓存失败: $e');
          }
        }
        
        return result;
      },
      description: 'Revert 工作副本',
    );
  }
  
  /// SVN Cleanup
  /// 
  /// 清理工作副本（解锁、清理未完成的操作等）
  Future<SvnProcessResult> cleanup(
    String workingCopy, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.cleanup,
      () => _svnService.cleanup(workingCopy, username: username, password: password),
      description: 'Cleanup 工作副本',
    );
  }
  
  /// SVN Merge
  /// 
  /// 合并指定 revision 到工作副本
  Future<void> merge(
    String sourceUrl,
    int revision,
    String workingCopy, {
    bool dryRun = false,
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.merge,
      () => _svnService.merge(
        sourceUrl,
        revision,
        workingCopy,
        dryRun: dryRun,
        username: username,
        password: password,
      ),
      description: 'Merge r$revision',
    );
  }
  
  /// SVN Commit
  /// 
  /// 提交工作副本的修改
  Future<void> commit(
    String workingCopy,
    String message, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.commit,
      () => _svnService.commit(workingCopy, message, username: username, password: password),
      description: 'Commit',
    );
  }
  
  /// 自动合并并提交（带重试机制）
  /// 
  /// 这是一个复合操作，包含：update -> merge -> commit
  /// 整个过程会持有锁，确保原子性
  Future<void> autoMergeAndCommit({
    required String sourceUrl,
    required int revision,
    required String targetWc,
    int maxRetries = 5,
    bool dryRun = false,
    String? username,
    String? password,
  }) async {
    return _withLock(
      targetWc,
      WcOperationType.merge,
      () => _svnService.autoMergeAndCommit(
        sourceUrl: sourceUrl,
        revision: revision,
        targetWc: targetWc,
        maxRetries: maxRetries,
        dryRun: dryRun,
        username: username,
        password: password,
      ),
      description: 'Auto merge r$revision',
    );
  }
  
  /// 批量合并
  /// 
  /// 依次合并多个 revision
  /// 整个过程会持有锁
  Future<void> batchMerge({
    required String sourceUrl,
    required List<int> revisions,
    required String targetWc,
    int maxRetries = 5,
    void Function(int current, int total)? onProgress,
    String? username,
    String? password,
  }) async {
    return _withLock(
      targetWc,
      WcOperationType.merge,
      () => _svnService.batchMerge(
        sourceUrl: sourceUrl,
        revisions: revisions,
        targetWc: targetWc,
        maxRetries: maxRetries,
        onProgress: onProgress,
        username: username,
        password: password,
      ),
      description: 'Batch merge ${revisions.length} revisions',
    );
  }
  
  /// SVN Status
  /// 
  /// 获取工作副本状态
  Future<bool> hasConflicts(
    String workingCopy, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      workingCopy,
      WcOperationType.status,
      () => _svnService.hasConflicts(workingCopy, username: username, password: password),
      description: '检查冲突',
    );
  }
  
  /// SVN Info
  /// 
  /// 获取工作副本信息
  Future<String> getInfo(
    String path, {
    String? item,
    String? username,
    String? password,
  }) async {
    // Info 操作是只读的，可以不加锁
    // 但为了安全起见，还是加锁
    return _withLock(
      path,
      WcOperationType.info,
      () => _svnService.getInfo(path, item: item, username: username, password: password),
      description: '获取信息',
    );
  }
  
  /// 确保工作副本存在
  Future<String> ensureWorkingCopy(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    return _withLock(
      targetWc,
      WcOperationType.info,
      () => _svnService.ensureWorkingCopy(targetWc, username: username, password: password),
      description: '验证工作副本',
    );
  }
  
  /// 获取已合并的 revisions（从本地属性）
  /// 
  /// 这是只读操作，但为了数据一致性，还是加锁
  Future<Set<int>> getMergedRevisionsFromPropget({
    required String sourceUrl,
    required String targetWc,
  }) async {
    return _withLock(
      targetWc,
      WcOperationType.propget,
      () => _svnService.getMergedRevisionsFromPropget(
        sourceUrl: sourceUrl,
        targetWc: targetWc,
      ),
      description: '读取 mergeinfo',
    );
  }
  
  /// 释放所有资源
  void dispose() {
    _statusController.close();
  }
}
