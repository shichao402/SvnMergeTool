/// 合并任务状态管理
///
/// 管理合并任务队列和执行状态

import 'package:flutter/foundation.dart';
import '../models/merge_job.dart';
import '../services/storage_service.dart';
import '../services/svn_service.dart';
import '../services/logger_service.dart';

class MergeState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final SvnService _svnService = SvnService();

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

    // 设置 SVN 服务的日志回调，将所有 SVN 命令输出到操作记录
    _svnService.onLog = (message) {
      _appendLog(message);
    };

    notifyListeners();
  }

  /// 获取活跃任务（待执行和执行中的任务）
  /// 
  /// 用于UI显示，过滤掉已完成和失败的任务
  List<MergeJob> get activeJobs {
    return _jobs.where((job) => 
      job.status == JobStatus.pending || job.status == JobStatus.running
    ).toList();
  }

  /// 添加任务到队列
  Future<void> addJob({
    required String sourceUrl,
    required String targetWc,
    required List<int> revisions,
    required int maxRetries,
  }) async {
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

    _jobs[index] = job.copyWith(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      revisions: revisions,
      maxRetries: maxRetries,
      status: JobStatus.pending,  // 重置状态
      error: '',
    );

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已更新');
    notifyListeners();

    // 如果当前没有正在执行的任务，启动下一个
    if (!_isProcessing) {
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
    // 保留正在运行的任务
    final runningJobs = _jobs.where((j) => j.status == JobStatus.running).toList();
    _jobs = runningJobs;
    _currentJobIndex = runningJobs.isNotEmpty ? 0 : -1;

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 队列已清空（保留运行中的任务）');
    notifyListeners();
  }

  /// 启动下一个待执行任务
  Future<void> _startNextJob() async {
    if (_isProcessing) return;

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
    _currentJobIndex = nextIndex;
    _isProcessing = true;
    final job = _jobs[nextIndex];

    _jobs[nextIndex] = job.copyWith(status: JobStatus.running);
    await _storageService.saveQueue(_jobs);
    notifyListeners();

    _appendLog('[INFO] 开始执行任务 #${job.jobId}');
    _appendLog('  源 URL: ${job.sourceUrl}');
    _appendLog('  目标工作副本: ${job.targetWc}');
    _appendLog('  待合并 revision: ${job.revisions.map((r) => 'r$r').join(', ')}');

    try {
      // 在整个任务开始前，还原工作副本并更新到最新
      // 注意：SVN 鉴权完全依赖 SVN 自身管理，不传递用户名密码
      _appendLog('[INFO] 开始还原目标工作副本到干净状态...');
      await _svnService.revert(job.targetWc);

      await _svnService.cleanup(job.targetWc);

      await _svnService.update(job.targetWc);

      // 批量合并所有 revision
      await _svnService.batchMerge(
        sourceUrl: job.sourceUrl,
        revisions: job.revisions,
        targetWc: job.targetWc,
        maxRetries: job.maxRetries,
        onProgress: (current, total) {
          _appendLog('[INFO] 进度：$current/$total');
        },
      );

      // TODO: 执行插件脚本

      _appendLog('[INFO] 任务 #${job.jobId} 执行成功');

      // 更新任务状态为完成
      _jobs[nextIndex] = job.copyWith(status: JobStatus.done, error: '');
    } catch (e, stackTrace) {
      _appendLog('[ERROR] 任务 #${job.jobId} 执行失败：$e');
      AppLogger.merge.error('任务执行失败', e, stackTrace);

      // 更新任务状态为失败
      _jobs[nextIndex] = job.copyWith(
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

