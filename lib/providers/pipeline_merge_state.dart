/// 基于 Pipeline 的合并任务状态管理
///
/// 这是 MergeState 的重构版本，使用 Pipeline 引擎执行合并任务
/// 
/// 设计原则：
/// - 保持与原 MergeState 相同的公开接口，确保向后兼容
/// - 内部使用 PipelineFacade 执行任务
/// - 支持 Pipeline 的可视化和阶段控制

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/merge_job.dart';
import '../pipeline/pipeline.dart';
import '../services/logger_service.dart';
import '../services/mergeinfo_cache_service.dart';
import '../services/storage_service.dart';
import '../services/working_copy_manager.dart';

/// 基于 Pipeline 的合并状态管理
class PipelineMergeState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final WorkingCopyManager _wcManager = WorkingCopyManager();
  final MergeInfoCacheService _mergeInfoService = MergeInfoCacheService();

  /// Pipeline 门面
  final PipelineFacade _pipeline = PipelineFacade();

  /// 任务列表
  List<MergeJob> _jobs = [];

  /// 当前任务索引
  int _currentJobIndex = -1;

  /// 下一个任务 ID
  int _nextJobId = 1;

  /// 日志
  String _log = '';

  /// 当前使用的 Pipeline 配置
  PipelineConfig _currentPipelineConfig = PipelineConfig.simple();

  /// 事件订阅
  StreamSubscription<PipelineEvent>? _eventSubscription;

  // ==================== Getters ====================

  List<MergeJob> get jobs => _jobs;
  int get currentJobIndex => _currentJobIndex;
  String get log => _log;

  /// 是否正在处理
  bool get isProcessing => _pipeline.isRunning;

  /// 是否有暂停的任务
  bool get hasPausedJob =>
      _jobs.any((job) => job.status == JobStatus.paused) || _pipeline.isPaused;

  /// 获取暂停的任务
  MergeJob? get pausedJob {
    try {
      return _jobs.firstWhere((job) => job.status == JobStatus.paused);
    } catch (_) {
      return null;
    }
  }

  /// 是否锁定（有暂停任务时不能执行其他操作）
  bool get isLocked => hasPausedJob;

  /// 活跃任务列表
  List<MergeJob> get activeJobs {
    return _jobs.where((job) => job.status.isActive).toList();
  }

  /// 当前 Pipeline 状态
  PipelineState? get pipelineState => _pipeline.state;

  /// 当前 Pipeline 配置
  PipelineConfig get currentPipelineConfig => _currentPipelineConfig;

  /// 是否可以继续
  bool get canResume => _pipeline.canResume;

  /// 是否可以取消
  bool get canCancel => _pipeline.canCancel;

  /// 是否可以回滚
  bool get canRollback => _pipeline.canRollback;

  /// 当前用户输入请求
  UserInputRequest? get currentInputRequest => _pipeline.currentInputRequest;

  // ==================== 初始化 ====================

  /// 初始化
  Future<void> init() async {
    // 初始化 Pipeline
    _pipeline.initialize();

    // 订阅 Pipeline 事件
    _eventSubscription = _pipeline.events.listen(_onPipelineEvent);

    // 监听 Pipeline 状态变化
    _pipeline.addListener(_onPipelineChanged);

    // 加载任务队列
    _jobs = await _storageService.loadQueue();

    // 计算下一个 job ID
    if (_jobs.isNotEmpty) {
      _nextJobId =
          _jobs.map((j) => j.jobId).reduce((a, b) => a > b ? a : b) + 1;
    }

    // 清空日志
    _log = '';

    // 检查暂停的任务
    if (hasPausedJob) {
      final job = pausedJob!;
      _appendLog('[WARN] 检测到暂停的任务 #${job.jobId}');
      _appendLog('  暂停原因: ${job.pauseReason}');
      _appendLog('  进度: ${job.completedIndex}/${job.revisions.length}');
      _appendLog('  请选择：继续任务 或 取消任务');
    }

    notifyListeners();
  }

  // ==================== Pipeline 配置 ====================

  /// 设置 Pipeline 配置
  void setPipelineConfig(PipelineConfig config) {
    _currentPipelineConfig = config;
    notifyListeners();
  }

  /// 获取可用的 Pipeline 配置列表
  List<PipelineConfig> getAvailablePipelineConfigs() {
    // TODO: 从配置文件加载
    return [
      PipelineConfig.simple(),
      // 可以添加更多预设配置
    ];
  }

  // ==================== 任务管理 ====================

  /// 添加任务
  Future<void> addJob({
    required String sourceUrl,
    required String targetWc,
    required List<int> revisions,
    required int maxRetries,
  }) async {
    if (isLocked) {
      _appendLog('[WARN] 有暂停的任务需要处理，无法添加新任务');
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

    // 如果没有正在执行的任务，启动
    if (!isProcessing) {
      await _startNextJob();
    }
  }

  /// 编辑任务
  Future<void> editJob(
    int jobId, {
    String? sourceUrl,
    String? targetWc,
    List<int>? revisions,
    int? maxRetries,
  }) async {
    final index = _jobs.indexWhere((j) => j.jobId == jobId);
    if (index == -1) return;

    final job = _jobs[index];
    if (job.status == JobStatus.running || job.status == JobStatus.paused) {
      _appendLog('[WARN] 无法编辑运行中或暂停的任务');
      return;
    }

    _jobs[index] = job.copyWith(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      revisions: revisions,
      maxRetries: maxRetries,
      status: JobStatus.pending,
      error: '',
      completedIndex: 0,
      pauseReason: '',
    );

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #$jobId 已更新');
    notifyListeners();

    if (!isProcessing && !isLocked) {
      await _startNextJob();
    }
  }

  /// 删除任务
  Future<void> deleteJob(int jobId) async {
    final index = _jobs.indexWhere((j) => j.jobId == jobId);
    if (index == -1) return;

    final job = _jobs[index];
    if (job.status == JobStatus.running || job.status == JobStatus.paused) {
      _appendLog('[WARN] 无法删除运行中或暂停的任务');
      return;
    }

    _jobs.removeAt(index);

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
    final activeJobs = _jobs
        .where(
            (j) => j.status == JobStatus.running || j.status == JobStatus.paused)
        .toList();
    _jobs = activeJobs;
    _currentJobIndex = activeJobs.isNotEmpty ? 0 : -1;

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 队列已清空');
    notifyListeners();
  }

  // ==================== 任务执行控制 ====================

  /// 继续暂停的任务
  Future<void> resumePausedJob({String? userInput}) async {
    if (!hasPausedJob) {
      _appendLog('[WARN] 没有暂停的任务');
      return;
    }

    if (_pipeline.isPaused) {
      // Pipeline 级别的暂停，使用 Pipeline 恢复
      _appendLog('[INFO] 继续执行 Pipeline...');
      await _pipeline.resume(userInput: userInput);
    } else {
      // 任务级别的暂停，重新启动 Pipeline
      final job = pausedJob!;
      final jobIndex = _jobs.indexWhere((j) => j.jobId == job.jobId);
      if (jobIndex == -1) return;

      _appendLog('[INFO] 继续执行暂停的任务 #${job.jobId}');

      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.running,
        pauseReason: '',
      );
      await _storageService.saveQueue(_jobs);
      notifyListeners();

      await _executeJobWithPipeline(jobIndex, resumeFromIndex: job.completedIndex);
    }
  }

  /// 取消暂停的任务
  Future<void> cancelPausedJob() async {
    if (!hasPausedJob) {
      _appendLog('[WARN] 没有暂停的任务');
      return;
    }

    // 取消 Pipeline
    if (_pipeline.canCancel) {
      await _pipeline.cancel();
    }

    final job = pausedJob!;
    final jobIndex = _jobs.indexWhere((j) => j.jobId == job.jobId);
    if (jobIndex == -1) return;

    _appendLog('[INFO] 取消暂停的任务 #${job.jobId}');

    // 回滚工作副本
    try {
      _appendLog('[INFO] 正在还原工作副本...');
      await _wcManager.revert(
        job.targetWc,
        recursive: true,
        sourceUrl: job.sourceUrl,
        refreshMergeInfo: true,
      );
      _appendLog('[INFO] 工作副本已还原');
    } catch (e) {
      _appendLog('[WARN] 还原工作副本失败: $e');
    }

    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.failed,
      error: '用户取消: ${job.pauseReason}',
    );

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #${job.jobId} 已取消');
    notifyListeners();

    await _startNextJob();
  }

  /// 跳过当前阶段/revision
  Future<void> skipCurrentStage() async {
    if (_pipeline.isPaused) {
      await _pipeline.skipCurrentStage();
    } else {
      await skipCurrentRevision();
    }
  }

  /// 跳过当前 revision
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

    try {
      await _wcManager.revert(job.targetWc, recursive: true, refreshMergeInfo: false);
    } catch (e) {
      _appendLog('[WARN] 还原工作副本失败: $e');
    }

    final newCompletedIndex = job.completedIndex + 1;

    if (newCompletedIndex >= job.revisions.length) {
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.done,
        completedIndex: newCompletedIndex,
        pauseReason: '',
        error: '部分 revision 被跳过',
      );
      await _storageService.saveQueue(_jobs);
      _appendLog('[INFO] 任务 #${job.jobId} 已完成（部分 revision 被跳过）');
      notifyListeners();
      await _startNextJob();
    } else {
      _jobs[jobIndex] = job.copyWith(
        status: JobStatus.running,
        completedIndex: newCompletedIndex,
        pauseReason: '',
      );
      await _storageService.saveQueue(_jobs);
      notifyListeners();
      await _executeJobWithPipeline(jobIndex, resumeFromIndex: newCompletedIndex);
    }
  }

  /// 回滚到 Pipeline 开始
  Future<void> rollback() async {
    if (_pipeline.canRollback) {
      await _pipeline.rollback();
    }
  }

  /// 提交用户输入
  void submitUserInput(String value) {
    _pipeline.submitUserInput(value);
  }

  /// 取消用户输入
  void cancelUserInput() {
    _pipeline.cancelUserInput();
  }

  // ==================== 内部方法 ====================

  /// 启动下一个任务
  Future<void> _startNextJob() async {
    if (isProcessing || isLocked) return;

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

    await _executeJobWithPipeline(nextIndex, resumeFromIndex: 0);
  }

  /// 使用 Pipeline 执行任务
  Future<void> _executeJobWithPipeline(int jobIndex, {required int resumeFromIndex}) async {
    _currentJobIndex = jobIndex;
    var job = _jobs[jobIndex];

    _jobs[jobIndex] = job.copyWith(status: JobStatus.running);
    await _storageService.saveQueue(_jobs);
    notifyListeners();

    _appendLog('[INFO] 开始执行任务 #${job.jobId}');
    _appendLog('  源 URL: ${job.sourceUrl}');
    _appendLog('  目标工作副本: ${job.targetWc}');
    _appendLog('  待合并 revision: ${job.revisions.map((r) => 'r$r').join(', ')}');
    _appendLog('  使用 Pipeline: ${_currentPipelineConfig.name}');

    // 逐个 revision 执行 Pipeline
    for (int i = resumeFromIndex; i < job.revisions.length; i++) {
      final rev = job.revisions[i];
      _appendLog('[INFO] 开始处理 revision r$rev (${i + 1}/${job.revisions.length})...');

      try {
        // 启动 Pipeline
        await _pipeline.start(
          config: _currentPipelineConfig,
          jobParams: {
            'targetWc': job.targetWc,
            'sourceUrl': job.sourceUrl,
            'currentRevision': rev,
            'revisions': job.revisions,
            'maxRetries': job.maxRetries,
          },
        );

        // 等待 Pipeline 完成
        await _waitForPipelineCompletion();

        final state = _pipeline.state;
        if (state == null) continue;

        if (state.status == PipelineStatus.completed) {
          // 更新进度
          _jobs[jobIndex] = job.copyWith(completedIndex: i + 1);
          job = _jobs[jobIndex];
          await _storageService.saveQueue(_jobs);
          _appendLog('[INFO] r$rev 处理完成');
        } else if (state.status == PipelineStatus.paused) {
          // Pipeline 暂停，任务也暂停
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: state.pauseReason ?? 'Pipeline 暂停',
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[WARN] 任务暂停: ${state.pauseReason}');
          notifyListeners();
          return;
        } else if (state.status == PipelineStatus.failed ||
            state.status == PipelineStatus.cancelled) {
          // Pipeline 失败或取消
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: state.error ?? 'Pipeline 失败',
            error: state.error,
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[ERROR] Pipeline 失败: ${state.error}');
          notifyListeners();
          return;
        }
      } catch (e) {
        _appendLog('[ERROR] r$rev 执行异常: $e');
        _jobs[jobIndex] = job.copyWith(
          status: JobStatus.paused,
          completedIndex: i,
          pauseReason: e.toString(),
          error: e.toString(),
        );
        await _storageService.saveQueue(_jobs);
        notifyListeners();
        return;
      }
    }

    // 所有 revision 完成
    _appendLog('[INFO] 任务 #${job.jobId} 执行成功');

    _jobs[jobIndex] = job.copyWith(
      status: JobStatus.done,
      error: '',
      completedIndex: job.revisions.length,
      pauseReason: '',
    );

    // 更新 mergeinfo 缓存
    await _mergeInfoService.addMergedRevisions(
      job.sourceUrl,
      job.targetWc,
      job.revisions.toSet(),
    );

    await _storageService.saveQueue(_jobs);
    notifyListeners();

    // 重置 Pipeline
    _pipeline.reset();

    // 继续下一个任务
    await _startNextJob();
  }

  /// 等待 Pipeline 完成
  Future<void> _waitForPipelineCompletion() async {
    final completer = Completer<void>();

    void listener() {
      final state = _pipeline.state;
      if (state != null && state.status.isTerminal) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }

    _pipeline.addListener(listener);

    // 检查是否已经完成
    final currentState = _pipeline.state;
    if (currentState != null && currentState.status.isTerminal) {
      _pipeline.removeListener(listener);
      return;
    }

    await completer.future;
    _pipeline.removeListener(listener);
  }

  /// Pipeline 事件处理
  void _onPipelineEvent(PipelineEvent event) {
    if (event.type == PipelineEventType.log && event.message != null) {
      _appendLog(event.message!);
    }
  }

  /// Pipeline 状态变化
  void _onPipelineChanged() {
    notifyListeners();
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
  Map<int, bool> getMergedRevisions({
    String? sourceUrl,
    String? targetWc,
  }) {
    final result = <int, bool>{};

    for (final job in _jobs) {
      if (job.status != JobStatus.done) continue;
      if (sourceUrl != null && job.sourceUrl != sourceUrl) continue;
      if (targetWc != null && job.targetWc != targetWc) continue;

      for (final rev in job.revisions) {
        result[rev] = true;
      }
    }

    return result;
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _pipeline.removeListener(_onPipelineChanged);
    _pipeline.dispose();
    super.dispose();
  }
}
