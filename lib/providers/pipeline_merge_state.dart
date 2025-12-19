/// 基于 Graph Pipeline 的合并任务状态管理
///
/// 使用 GraphPipelineFacade 执行合并任务

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../models/merge_job.dart';
import '../pipeline/graph/graph.dart';
import '../services/logger_service.dart';
import '../services/mergeinfo_cache_service.dart';
import '../services/storage_service.dart';
import '../services/working_copy_manager.dart';

/// 基于 Graph Pipeline 的合并状态管理
class PipelineMergeState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final WorkingCopyManager _wcManager = WorkingCopyManager();
  final MergeInfoCacheService _mergeInfoService = MergeInfoCacheService();

  /// Pipeline 门面
  final GraphPipelineFacade _pipeline = GraphPipelineFacade();

  /// 任务列表
  List<MergeJob> _jobs = [];

  /// 当前任务索引
  int _currentJobIndex = -1;

  /// 下一个任务 ID
  int _nextJobId = 1;

  /// 日志
  String _log = '';

  /// 事件订阅
  StreamSubscription<GraphPipelineEvent>? _eventSubscription;
  
  /// 用户选择的流程路径（null 表示使用内置标准流程）
  String? _selectedFlowPath;
  
  /// 用户流程控制器缓存
  NodeFlowController<StageData>? _customFlowController;

  // ==================== Getters ====================

  List<MergeJob> get jobs => _jobs;
  int get currentJobIndex => _currentJobIndex;
  String get log => _log;

  /// 是否正在处理
  bool get isProcessing => _pipeline.isRunning;

  /// 是否有暂停的任务（包括等待输入）
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

  // ==================== Graph Pipeline 接口 ====================

  /// 流程控制器
  NodeFlowController<StageData>? get controller => _pipeline.controller;

  /// 当前执行状态
  GraphExecutorStatus get status => _pipeline.status;

  /// 当前执行的节点
  Node<StageData>? get currentNode => _pipeline.currentNode;

  /// 是否等待用户输入
  bool get isWaitingInput => _pipeline.isWaitingInput;

  /// 等待输入的节点
  Node<StageData>? get waitingInputNode => _pipeline.waitingInputNode;

  /// 是否可以继续
  bool get canResume => _pipeline.canResume;

  /// 是否可以取消
  bool get canCancel => _pipeline.canCancel;

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
    
    // 加载用户选择的流程
    await _loadSelectedFlow();

    // 检查暂停的任务
    if (hasPausedJob) {
      final job = pausedJob!;
      _appendLog('[WARN] 检测到暂停的任务 #${job.jobId}');
      _appendLog('  暂停原因: ${job.pauseReason}');
      _appendLog('  进度: ${job.completedIndex}/${job.revisions.length}');
      _appendLog('  请选择：继续任务 或 取消任务');
    }

    notifyListeners();
    
    // 如果有 pending 任务且没有暂停任务，自动开始执行
    if (!hasPausedJob) {
      final pendingJobs = _jobs.where((j) => j.status == JobStatus.pending).toList();
      if (pendingJobs.isNotEmpty) {
        _appendLog('[INFO] 检测到 ${pendingJobs.length} 个待执行任务，自动开始执行...');
        await _startNextJob();
      }
    }
  }
  
  /// 加载用户选择的流程
  Future<void> _loadSelectedFlow() async {
    _selectedFlowPath = await _storageService.getSelectedFlowPath();
    _customFlowController = null;
    
    if (_selectedFlowPath != null) {
      try {
        final file = File(_selectedFlowPath!);
        if (file.existsSync()) {
          final content = await file.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          _customFlowController = MergeFlowBuilder.fromJson(json);
          _appendLog('[INFO] 已加载自定义流程: ${_selectedFlowPath!.split('/').last}');
        } else {
          _appendLog('[WARN] 自定义流程文件不存在，使用标准流程');
          _selectedFlowPath = null;
        }
      } catch (e) {
        _appendLog('[ERROR] 加载自定义流程失败: $e，使用标准流程');
        _selectedFlowPath = null;
      }
    }
  }
  
  /// 重新加载流程（设置变更后调用）
  Future<void> reloadFlow() async {
    await _loadSelectedFlow();
    notifyListeners();
  }
  
  /// 获取当前使用的流程名称
  String get currentFlowName {
    if (_selectedFlowPath == null) {
      return '标准合并流程';
    }
    return _selectedFlowPath!.split('/').last.replaceAll('.flow.json', '');
  }

  // ==================== 任务管理 ====================

  /// 添加任务
  Future<void> addJob({
    required String sourceUrl,
    required String targetWc,
    required List<int> revisions,
    required int maxRetries,
    String? commitMessageTemplate,
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
      commitMessageTemplate: commitMessageTemplate,
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

    // 如果是等待输入状态，提交输入
    if (isWaitingInput && userInput != null) {
      _appendLog('[INFO] 提交用户输入...');
      await _pipeline.submitUserInput(userInput);
      return;
    }

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

  /// 提交用户输入
  Future<void> submitUserInput(String value) async {
    if (isWaitingInput) {
      await _pipeline.submitUserInput(value);
      return;
    }
    
    // 从持久化恢复的"等待输入"状态
    if (hasPausedJob && pausedJob!.pauseReason.startsWith('等待输入')) {
      _appendLog('[INFO] 提交用户输入: $value，恢复任务执行...');
      _pendingUserInput = value;
      await resumePausedJob();
      return;
    }
    
    _appendLog('[WARN] 当前不在等待输入状态');
  }
  
  /// 待提交的用户输入（用于持久化恢复场景）
  String? _pendingUserInput;

  /// 取消暂停的任务
  Future<void> cancelPausedJob() async {
    // 如果正在运行，先取消 Pipeline
    if (_pipeline.isRunning || _pipeline.canCancel) {
      _appendLog('[INFO] 正在取消执行...');
      _pipeline.cancel();
    }

    if (!hasPausedJob && _currentJobIndex < 0) {
      _appendLog('[WARN] 没有可取消的任务');
      return;
    }

    // 获取要取消的任务
    MergeJob? job;
    int jobIndex = -1;
    
    if (hasPausedJob) {
      job = pausedJob!;
      jobIndex = _jobs.indexWhere((j) => j.jobId == job!.jobId);
    } else if (_currentJobIndex >= 0 && _currentJobIndex < _jobs.length) {
      job = _jobs[_currentJobIndex];
      jobIndex = _currentJobIndex;
    }
    
    if (job == null || jobIndex == -1) {
      _appendLog('[WARN] 找不到要取消的任务');
      return;
    }

    _appendLog('[INFO] 取消任务 #${job.jobId}');

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
      error: '用户取消: ${job.pauseReason.isNotEmpty ? job.pauseReason : "手动停止"}',
    );

    await _storageService.saveQueue(_jobs);
    _appendLog('[INFO] 任务 #${job.jobId} 已取消');
    notifyListeners();

    await _startNextJob();
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
    _appendLog('  使用流程: $currentFlowName');

    // 逐个 revision 执行 Pipeline
    for (int i = resumeFromIndex; i < job.revisions.length; i++) {
      final rev = job.revisions[i];
      _appendLog('[INFO] 开始处理 revision r$rev (${i + 1}/${job.revisions.length})...');

      try {
        // 启动 Pipeline，使用用户选择的流程
        final success = await _pipeline.start(
          controller: _customFlowController,
          jobParams: {
            'targetWc': job.targetWc,
            'sourceUrl': job.sourceUrl,
            'currentRevision': rev,
            'revisions': job.revisions,
            'maxRetries': job.maxRetries,
          },
        );

        final currentStatus = _pipeline.status;

        if (success) {
          // 更新进度
          _jobs[jobIndex] = job.copyWith(completedIndex: i + 1);
          job = _jobs[jobIndex];
          await _storageService.saveQueue(_jobs);
          _appendLog('[INFO] r$rev 处理完成');
        } else if (currentStatus == GraphExecutorStatus.paused) {
          // 等待用户输入，任务暂停
          final waitingNode = _pipeline.waitingInputNode;
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: '等待输入: ${waitingNode?.data?.name ?? 'unknown'}',
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[INFO] 等待用户输入');
          notifyListeners();
          return;
        } else if (currentStatus == GraphExecutorStatus.failed) {
          // Pipeline 失败
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: '执行失败',
            error: '执行失败',
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[ERROR] Pipeline 失败');
          notifyListeners();
          return;
        } else if (currentStatus == GraphExecutorStatus.cancelled) {
          // Pipeline 取消
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: '已取消',
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[INFO] Pipeline 已取消');
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

  /// Pipeline 事件处理
  void _onPipelineEvent(GraphPipelineEvent event) {
    if (event.type == GraphPipelineEventType.log && event.message != null) {
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
