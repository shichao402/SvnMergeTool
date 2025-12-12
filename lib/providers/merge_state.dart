/// 合并任务状态管理
///
/// 管理合并任务队列和执行状态
/// 
/// 支持任务暂停机制：
/// - 当合并失败（冲突、提交失败等）时，任务进入暂停状态
/// - 暂停状态下，用户只能：继续当前任务 或 完全取消当前任务
/// - 不能开始新任务（类似 Git rebase 的原子操作概念）

import 'package:flutter/foundation.dart';
import '../models/merge_job.dart';
import '../services/storage_service.dart';
import '../services/working_copy_manager.dart';
import '../services/logger_service.dart';
import '../services/mergeinfo_cache_service.dart';

class MergeState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final WorkingCopyManager _wcManager = WorkingCopyManager();
  final MergeInfoCacheService _mergeInfoService = MergeInfoCacheService();

  List<MergeJob> _jobs = [];
  int _currentJobIndex = -1;
  int _nextJobId = 1;
  bool _isProcessing = false;
  String _log = '';

  // Getters
  List<MergeJob> get jobs => _jobs;
  int get currentJobIndex => _currentJobIndex;
  bool get isProcessing => _isProcessing;
  String get log => _log;
  
  /// 是否有暂停的任务（需要人工介入）
  bool get hasPausedJob => _jobs.any((job) => job.status == JobStatus.paused);
  
  /// 获取暂停的任务（如果有）
  MergeJob? get pausedJob {
    try {
      return _jobs.firstWhere((job) => job.status == JobStatus.paused);
    } catch (_) {
      return null;
    }
  }
  
  /// 是否处于"锁定"状态（有暂停任务时，不能执行其他操作）
  bool get isLocked => hasPausedJob;

  /// 初始化
  Future<void> init() async {
    // 加载队列
    _jobs = await _storageService.loadQueue();

    // 计算下一个 job ID
    if (_jobs.isNotEmpty) {
      _nextJobId = _jobs.map((j) => j.jobId).reduce((a, b) => a > b ? a : b) + 1;
    }

    // 清空操作日志（启动时清空，只保留当前会话的日志）
    _log = '';
    
    // 检查是否有暂停的任务
    if (hasPausedJob) {
      final job = pausedJob!;
      _appendLog('[WARN] 检测到暂停的任务 #${job.jobId}');
      _appendLog('  暂停原因: ${job.pauseReason}');
      _appendLog('  进度: ${job.completedIndex}/${job.revisions.length}');
      _appendLog('  请选择：继续任务 或 取消任务');
    }

    notifyListeners();
  }

  /// 获取活跃任务（待执行、执行中和暂停的任务）
  /// 
  /// 用于UI显示，过滤掉已完成和失败的任务
  List<MergeJob> get activeJobs {
    return _jobs.where((job) => job.status.isActive).toList();
  }

  /// 添加任务到队列
  /// 
  /// 如果有暂停的任务，不允许添加新任务
  Future<void> addJob({
    required String sourceUrl,
    required String targetWc,
    required List<int> revisions,
    required int maxRetries,
  }) async {
    // 检查是否有暂停的任务
    if (isLocked) {
      _appendLog('[WARN] 有暂停的任务需要处理，无法添加新任务');
      _appendLog('  请先继续或取消暂停的任务');
      return;
    }
    
    final job = MergeJob(
      jobId: _nextJobId++,
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      maxRetries: maxRetries,
      revisions: revisions,
    );

    _jobs.add(job);
    await _storageService.saveQueue(_jobs);
    
    _appendLog('[INFO] 已添加任务到队列：#${job.jobId}');
    notifyListeners();

    // 如果当前没有正在执行的任务，启动下一个
    if (!_isProcessing) {
      await _startNextJob();
    }
  }

  /// 编辑任务
  Future<void> editJob(int jobId, {
    String? sourceUrl,
    String? targetWc,
    List<int>? revisions,
    int? maxRetries,
  }) async {
    final index = _jobs.indexWhere((j) => j.jobId == jobId);
    if (index == -1) return;

    final job = _jobs[index];
    if (job.status == JobStatus.running) {
      _appendLog('[WARN] 无法编辑正在运行的任务');
      return;
    }
    
    if (job.status == JobStatus.paused) {
      _appendLog('[WARN] 无法编辑暂停的任务，请先继续或取消');
      return;
    }

    _jobs[index] = job.copyWith(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      revisions: revisions,
      maxRetries: maxRetries,
      status: JobStatus.pending,  // 重置状态
      error: '',
      completedIndex: 0,
      pauseReason: '',
    );

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已更新');
    notifyListeners();

    // 如果当前没有正在执行的任务且没有暂停的任务，启动下一个
    if (!_isProcessing && !isLocked) {
      await _startNextJob();
    }
  }

  /// 删除任务
  Future<void> deleteJob(int jobId) async {
    final index = _jobs.indexWhere((j) => j.jobId == jobId);
    if (index == -1) return;

    final job = _jobs[index];
    if (job.status == JobStatus.running) {
      _appendLog('[WARN] 无法删除正在运行的任务');
      return;
    }
    
    if (job.status == JobStatus.paused) {
      _appendLog('[WARN] 无法直接删除暂停的任务，请使用"取消任务"功能');
      return;
    }

    _jobs.removeAt(index);

    // 调整 current index
    if (_currentJobIndex > index) {
      _currentJobIndex--;
    } else if (_currentJobIndex == index) {
      _currentJobIndex = -1;
    }

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已删除');
    notifyListeners();
  }

  /// 清空队列
  Future<void> clearQueue() async {
    // 保留正在运行和暂停的任务
    final activeJobs = _jobs.where((j) => 
      j.status == JobStatus.running || j.status == JobStatus.paused
    ).toList();
    _jobs = activeJobs;
    _currentJobIndex = activeJobs.isNotEmpty ? 0 : -1;

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 队列已清空（保留运行中和暂停的任务）');
    notifyListeners();
  }
  
  /// 继续暂停的任务
  /// 
  /// 从上次失败的 revision 继续执行
  Future<void> resumePausedJob() async {
    if (!hasPausedJob) {
      _appendLog('[WARN] 没有暂停的任务');
      return;
    }
    
    if (_isProcessing) {
      _appendLog('[WARN] 有任务正在执行中');
      return;
    }
    
    final job = pausedJob!;
    final jobIndex = _jobs.indexWhere((j) => j.jobId == job.jobId);
    if (jobIndex == -1) return;
    
    _appendLog('[INFO] 继续执行暂停的任务 #${job.jobId}');
    _appendLog('  从 revision r${job.currentRevision} 继续 (${job.completedIndex + 1}/${job.revisions.length})');
    
    // 将状态改为 running
    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.running,
      pauseReason: '',
    );
    await _storageService.saveQueue(_jobs);
    notifyListeners();
    
    // 继续执行
    await _executeJob(jobIndex, resumeFromIndex: job.completedIndex);
  }
  
  /// 取消暂停的任务
  /// 
  /// 将任务标记为失败，并还原工作副本
  Future<void> cancelPausedJob() async {
    if (!hasPausedJob) {
      _appendLog('[WARN] 没有暂停的任务');
      return;
    }
    
    final job = pausedJob!;
    final jobIndex = _jobs.indexWhere((j) => j.jobId == job.jobId);
    if (jobIndex == -1) return;
    
    _appendLog('[INFO] 取消暂停的任务 #${job.jobId}');
    
    // 还原工作副本（使用 WorkingCopyManager，自动刷新 mergeinfo）
    try {
      _appendLog('[INFO] 正在还原工作副本...');
      await _wcManager.revert(
        job.targetWc, 
        recursive: true,
        sourceUrl: job.sourceUrl,
        refreshMergeInfo: true,
      );
      _appendLog('[INFO] 工作副本已还原，mergeinfo 缓存已刷新');
    } catch (e) {
      _appendLog('[WARN] 还原工作副本失败: $e');
    }
    
    // 将任务标记为失败
    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.failed,
      error: '用户取消: ${job.pauseReason}',
    );
    
    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #${job.jobId} 已取消');
    notifyListeners();
    
    // 继续执行下一个任务
    await _startNextJob();
  }
  
  /// 跳过当前失败的 revision 并继续
  /// 
  /// 将当前 revision 标记为已完成（跳过），继续下一个
  Future<void> skipCurrentRevision() async {
    if (!hasPausedJob) {
      _appendLog('[WARN] 没有暂停的任务');
      return;
    }
    
    final job = pausedJob!;
    final jobIndex = _jobs.indexWhere((j) => j.jobId == job.jobId);
    if (jobIndex == -1) return;
    
    final skippedRevision = job.currentRevision;
    if (skippedRevision == null) {
      _appendLog('[WARN] 没有可跳过的 revision');
      return;
    }
    
    _appendLog('[INFO] 跳过 revision r$skippedRevision');
    
    // 还原工作副本（清除当前失败的合并状态）
    try {
      await _wcManager.revert(job.targetWc, recursive: true, refreshMergeInfo: false);
    } catch (e) {
      _appendLog('[WARN] 还原工作副本失败: $e');
    }
    
    // 更新进度（跳过当前 revision）
    final newCompletedIndex = job.completedIndex + 1;
    
    if (newCompletedIndex >= job.revisions.length) {
      // 所有 revision 都已处理（包括跳过的）
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.done,
        completedIndex: newCompletedIndex,
        pauseReason: '',
        error: '部分 revision 被跳过',
      );
      await _storageService.saveQueue(_jobs);
      _appendLog('[INFO] 任务 #${job.jobId} 已完成（部分 revision 被跳过）');
      notifyListeners();
      
      // 继续执行下一个任务
      await _startNextJob();
    } else {
      // 还有更多 revision，继续执行
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.running,
        completedIndex: newCompletedIndex,
        pauseReason: '',
      );
      await _storageService.saveQueue(_jobs);
      notifyListeners();
      
      // 继续执行剩余的 revision
      await _executeJob(jobIndex, resumeFromIndex: newCompletedIndex);
    }
  }

  /// 启动下一个待执行任务
  Future<void> _startNextJob() async {
    if (_isProcessing) return;
    
    // 如果有暂停的任务，不启动新任务
    if (isLocked) {
      _appendLog('[INFO] 有暂停的任务需要处理，等待用户操作');
      return;
    }

    // 查找下一个待执行任务
    int nextIndex = -1;
    for (int i = 0; i < _jobs.length; i++) {
      if (_jobs[i].status == JobStatus.pending) {
        nextIndex = i;
        break;
      }
    }

    if (nextIndex == -1) {
      _currentJobIndex = -1;
      await _storageService.saveQueue(_jobs);
      _appendLog('[INFO] 所有任务已执行完成');
      notifyListeners();
      return;
    }

    // 执行任务
    await _executeJob(nextIndex, resumeFromIndex: 0);
  }
  
  /// 执行任务
  /// 
  /// [jobIndex] 任务在列表中的索引
  /// [resumeFromIndex] 从哪个 revision 开始执行（用于恢复暂停的任务）
  Future<void> _executeJob(int jobIndex, {required int resumeFromIndex}) async {
    _currentJobIndex = jobIndex;
    _isProcessing = true;
    var job = _jobs[jobIndex];

    _jobs[jobIndex] = job.copyWith(status: JobStatus.running);
    await _storageService.saveQueue(_jobs);
    notifyListeners();

    if (resumeFromIndex == 0) {
      _appendLog('[INFO] 开始执行任务 #${job.jobId}');
      _appendLog('  源 URL: ${job.sourceUrl}');
      _appendLog('  目标工作副本: ${job.targetWc}');
      _appendLog('  待合并 revision: ${job.revisions.map((r) => 'r$r').join(', ')}');
    } else {
      _appendLog('[INFO] 继续执行任务 #${job.jobId}');
      _appendLog('  剩余 revision: ${job.remainingRevisions.map((r) => 'r$r').join(', ')}');
    }

    try {
      // 如果是从头开始，先还原工作副本
      if (resumeFromIndex == 0) {
        _appendLog('[INFO] 开始还原目标工作副本到干净状态...');
        await _wcManager.revert(job.targetWc, refreshMergeInfo: false);
        await _wcManager.cleanup(job.targetWc);
        await _wcManager.update(job.targetWc);
      }

      // 逐个合并 revision（从 resumeFromIndex 开始）
      final completedRevisions = <int>[];
      for (int i = resumeFromIndex; i < job.revisions.length; i++) {
        final rev = job.revisions[i];
        _appendLog('[INFO] 开始处理 revision r$rev (${i + 1}/${job.revisions.length})...');
        
        try {
          await _wcManager.autoMergeAndCommit(
            sourceUrl: job.sourceUrl,
            revision: rev,
            targetWc: job.targetWc,
            maxRetries: job.maxRetries,
          );
          
          completedRevisions.add(rev);
          
          // 更新进度
          _jobs[jobIndex] = job.copyWith(
            completedIndex: i + 1,
          );
          job = _jobs[jobIndex];
          await _storageService.saveQueue(_jobs);
          
          _appendLog('[INFO] r$rev 处理完成');
        } catch (e) {
          // 合并失败，进入暂停状态
          _appendLog('[ERROR] r$rev 合并失败：$e');
          
          final pauseReason = _extractPauseReason(e);
          
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,  // 当前 revision 未完成
            pauseReason: pauseReason,
            error: e.toString(),
          );
          
          _isProcessing = false;
          await _storageService.saveQueue(_jobs);
          
          _appendLog('[WARN] 任务 #${job.jobId} 已暂停');
          _appendLog('  暂停原因: $pauseReason');
          _appendLog('  进度: $i/${job.revisions.length}');
          _appendLog('  请选择：');
          _appendLog('    - 继续任务：解决问题后点击"继续"');
          _appendLog('    - 跳过当前：跳过 r$rev 继续下一个');
          _appendLog('    - 取消任务：放弃本次合并');
          
          notifyListeners();
          return;
        }
      }

      _appendLog('[INFO] 任务 #${job.jobId} 执行成功');

      // 更新任务状态为完成
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.done, 
        error: '',
        completedIndex: job.revisions.length,
        pauseReason: '',
      );
      
      // 更新 mergeinfo 缓存（将合并的 revision 添加到缓存）
      await _mergeInfoService.addMergedRevisions(
        job.sourceUrl,
        job.targetWc,
        job.revisions.toSet(),
      );
      AppLogger.merge.info('已更新 mergeinfo 缓存: ${job.revisions.length} 个 revision');
    } catch (e, stackTrace) {
      _appendLog('[ERROR] 任务 #${job.jobId} 执行失败：$e');
      AppLogger.merge.error('任务执行失败', e, stackTrace);

      // 更新任务状态为失败
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.failed,
        error: e.toString(),
      );

      // 失败时停止队列
      _isProcessing = false;
      await _storageService.saveQueue(_jobs);
      notifyListeners();
      return;
    }

    _isProcessing = false;
    await _storageService.saveQueue(_jobs);
    notifyListeners();

    // 继续执行下一个任务
    await _startNextJob();
  }
  
  /// 从异常中提取暂停原因
  String _extractPauseReason(dynamic e) {
    final errorStr = e.toString().toLowerCase();
    
    if (errorStr.contains('conflict') || errorStr.contains('冲突')) {
      return '合并冲突，需要手动解决';
    } else if (errorStr.contains('out-of-date') || errorStr.contains('out of date')) {
      return '工作副本过期，需要更新';
    } else if (errorStr.contains('authorization') || errorStr.contains('authentication')) {
      return '认证失败，需要重新登录';
    } else if (errorStr.contains('locked')) {
      return '工作副本被锁定，需要清理';
    } else {
      return '合并失败: ${e.toString().split('\n').first}';
    }
  }

  /// 添加日志
  void _appendLog(String message) {
    _log += '$message\n';
    AppLogger.merge.info(message);
    notifyListeners();
  }

  /// 清空日志
  void clearLog() {
    _log = '';
    notifyListeners();
  }

  /// 获取已完成的合并记录
  /// 
  /// 返回一个 Map，key 是 revision，value 是是否已合并
  /// 只返回本程序合并过的记录（状态为 done 的任务）
  /// 
  /// [sourceUrl] 源 URL（可选，用于过滤）
  /// [targetWc] 目标工作副本（可选，用于过滤）
  Map<int, bool> getMergedRevisions({
    String? sourceUrl,
    String? targetWc,
  }) {
    final result = <int, bool>{};
    
    // 遍历所有已完成的任务
    for (final job in _jobs) {
      if (job.status != JobStatus.done) continue;
      
      // 如果指定了 sourceUrl 或 targetWc，进行过滤
      if (sourceUrl != null && job.sourceUrl != sourceUrl) continue;
      if (targetWc != null && job.targetWc != targetWc) continue;
      
      // 记录所有已完成的 revision
      for (final rev in job.revisions) {
        result[rev] = true;
      }
    }
    
    return result;
  }
}
