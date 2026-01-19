/// 基于新 FlowEngine 的合并任务状态管理
///
/// 使用 FlowEngine 执行合并任务
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/merge_job.dart';
import '../pipeline/data/data.dart';
import '../pipeline/engine/engine.dart';
import '../pipeline/engine/execution_context.dart' as engine;
import '../services/logger_service.dart';
import '../services/mergeinfo_cache_service.dart';
import '../services/storage_service.dart';
import '../services/svn_service.dart';
import '../services/standard_flow_service.dart';
import '../services/working_copy_manager.dart';

/// 基于 FlowEngine 的合并状态管理
class PipelineMergeState extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final WorkingCopyManager _wcManager = WorkingCopyManager();
  final MergeInfoCacheService _mergeInfoService = MergeInfoCacheService();
  final SvnService _svnService = SvnService();

  /// 流程执行引擎
  FlowEngine? _engine;

  /// 执行上下文
  ExecutionContext? _context;

  /// 当前加载的流程图
  FlowGraphData? _flowGraph;

  /// 任务列表
  List<MergeJob> _jobs = [];

  /// 当前任务索引
  int _currentJobIndex = -1;

  /// 下一个任务 ID
  int _nextJobId = 1;

  /// 日志
  String _log = '';

  /// 事件订阅
  StreamSubscription<ExecutionEvent>? _eventSubscription;
  
  /// 用户选择的流程路径（null 表示使用内置标准流程）
  String? _selectedFlowPath;

  /// 执行器状态
  ExecutorStatus _status = ExecutorStatus.idle;

  /// 当前执行的节点 ID
  String? _currentNodeId;

  /// 等待用户输入的 Completer
  Completer<String?>? _userInputCompleter;

  /// 当前等待的用户输入配置
  UserInputConfig? _waitingInputConfig;

  /// 节点执行快照
  final ExecutionSnapshots _snapshots = ExecutionSnapshots();

  // ==================== Getters ====================

  List<MergeJob> get jobs => _jobs;
  int get currentJobIndex => _currentJobIndex;
  String get log => _log;

  /// 是否正在处理
  bool get isProcessing => _status == ExecutorStatus.running;

  /// 是否有暂停的任务（包括等待输入）
  bool get hasPausedJob =>
      _jobs.any((job) => job.status == JobStatus.paused) || 
      _status == ExecutorStatus.paused;

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

  // ==================== FlowEngine 接口 ====================

  /// 当前执行状态
  ExecutorStatus get status => _status;

  /// 当前执行的节点 ID
  String? get currentNodeId => _currentNodeId;

  /// 是否等待用户输入
  bool get isWaitingInput => _userInputCompleter != null;

  /// 当前等待的用户输入配置
  UserInputConfig? get waitingInputConfig => _waitingInputConfig;

  /// 当前加载的流程图数据
  FlowGraphData? get flowGraph => _flowGraph;

  /// 节点执行快照
  ExecutionSnapshots get snapshots => _snapshots;

  /// 是否可以继续
  bool get canResume => _status == ExecutorStatus.paused;

  /// 是否可以取消
  bool get canCancel => _status == ExecutorStatus.running || _status == ExecutorStatus.paused;

  // ==================== 初始化 ====================

  /// 初始化
  Future<void> init() async {
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
    _flowGraph = null;
    
    if (_selectedFlowPath != null) {
      try {
        final file = File(_selectedFlowPath!);
        if (file.existsSync()) {
          final content = await file.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          _flowGraph = FlowGraphData.fromJson(json);
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
    
    // 如果没有自定义流程，加载标准流程
    if (_flowGraph == null) {
      _flowGraph = await StandardFlowService.loadStandardFlow();
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
      submitUserInput(userInput);
      return;
    }

    // 任务级别的暂停，重新启动执行
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

    await _executeJobWithEngine(jobIndex, resumeFromIndex: job.completedIndex);
  }

  /// 提交用户输入
  void submitUserInput(String value) {
    if (_userInputCompleter != null && !_userInputCompleter!.isCompleted) {
      _userInputCompleter!.complete(value);
      _userInputCompleter = null;
      _status = ExecutorStatus.running;
      notifyListeners();
    }
  }

  /// 取消暂停的任务
  Future<void> cancelPausedJob() async {
    // 如果正在运行，先取消引擎
    if (_engine != null && canCancel) {
      _appendLog('[INFO] 正在取消执行...');
      _engine!.cancel();
      _status = ExecutorStatus.cancelled;
    }

    // 取消用户输入等待
    if (_userInputCompleter != null && !_userInputCompleter!.isCompleted) {
      _userInputCompleter!.complete(null);
      _userInputCompleter = null;
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

    _status = ExecutorStatus.idle;
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
      await _executeJobWithEngine(jobIndex, resumeFromIndex: newCompletedIndex);
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

    await _executeJobWithEngine(nextIndex, resumeFromIndex: 0);
  }

  /// 使用 FlowEngine 执行任务
  Future<void> _executeJobWithEngine(int jobIndex, {required int resumeFromIndex}) async {
    // 每次执行前重新加载流程图，确保使用最新版本
    await _loadSelectedFlow();
    
    if (_flowGraph == null) {
      _appendLog('[ERROR] 流程图未加载');
      return;
    }

    _currentJobIndex = jobIndex;
    var job = _jobs[jobIndex];

    _jobs[jobIndex] = job.copyWith(status: JobStatus.running);
    await _storageService.saveQueue(_jobs);
    _status = ExecutorStatus.running;
    notifyListeners();

    _appendLog('[INFO] 开始执行任务 #${job.jobId}');
    _appendLog('  源 URL: ${job.sourceUrl}');
    _appendLog('  目标工作副本: ${job.targetWc}');
    _appendLog('  待合并 revision: ${job.revisions.map((r) => 'r$r').join(', ')}');
    _appendLog('  使用流程: $currentFlowName');

    // 逐个 revision 执行
    for (int i = resumeFromIndex; i < job.revisions.length; i++) {
      final rev = job.revisions[i];
      _appendLog('[INFO] 开始处理 revision r$rev (${i + 1}/${job.revisions.length})...');

      // 更新 job 的 currentRevision
      _jobs[jobIndex] = job.copyWith(completedIndex: i);
      job = _jobs[jobIndex];

      try {
        // 创建执行上下文
        _context = ExecutionContext(
          job: job,
          svnService: _svnService,
          workDir: job.targetWc,
          onUserInput: _handleUserInput,
          onLog: _handleEngineLog,
        );

        // 创建并配置引擎
        _engine = FlowEngine();
        _engine!.loadGraph(_flowGraph!);

        // 订阅事件
        _eventSubscription?.cancel();
        _eventSubscription = _engine!.events.listen(_onEngineEvent);

        // 执行流程
        final success = await _engine!.execute(_context!);

        if (success) {
          // 更新进度
          _jobs[jobIndex] = job.copyWith(completedIndex: i + 1);
          job = _jobs[jobIndex];
          await _storageService.saveQueue(_jobs);
          _appendLog('[INFO] r$rev 处理完成');
          
          // 只有当 merge 节点真正执行了合并操作时，才更新 mergeinfo 缓存
          if (_context!.revisionMerged) {
            await _mergeInfoService.addMergedRevision(
              job.sourceUrl,
              job.targetWc,
              rev,
            );
            _appendLog('[DEBUG] r$rev 已标记为已合并');
          }
        } else if (_status == ExecutorStatus.paused) {
          // 等待用户输入，任务暂停
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: '等待用户操作',
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[INFO] 等待用户操作');
          notifyListeners();
          return;
        } else if (_status == ExecutorStatus.cancelled) {
          // 已取消
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: '已取消',
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[INFO] 执行已取消');
          notifyListeners();
          return;
        } else {
          // 执行失败
          _jobs[jobIndex] = job.copyWith(
            status: JobStatus.paused,
            completedIndex: i,
            pauseReason: '执行失败',
            error: '执行失败',
          );
          await _storageService.saveQueue(_jobs);
          _appendLog('[ERROR] 执行失败');
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
        _status = ExecutorStatus.failed;
        notifyListeners();
        return;
      } finally {
        _eventSubscription?.cancel();
        _eventSubscription = null;
        _engine?.dispose();
        _engine = null;
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

    // 注意：mergeinfo 缓存已在每个 revision 执行成功时更新
    // 只有真正执行了 merge 节点的 revision 才会被标记为已合并

    await _storageService.saveQueue(_jobs);
    _status = ExecutorStatus.completed;
    notifyListeners();

    // 继续下一个任务
    _status = ExecutorStatus.idle;
    await _startNextJob();
  }

  /// 处理用户输入请求
  Future<String?> _handleUserInput({
    required String prompt,
    String? label,
    String? defaultValue,
    String? validationPattern,
    String? validationMessage,
  }) async {
    _status = ExecutorStatus.paused;
    _userInputCompleter = Completer<String?>();
    _waitingInputConfig = UserInputConfig(
      label: label ?? prompt,
      hint: prompt,
      validationRegex: validationPattern,
      required: true,
    );
    notifyListeners();

    _appendLog('[INFO] 等待用户输入: $prompt');

    // 等待用户输入
    final result = await _userInputCompleter!.future;
    _userInputCompleter = null;
    _waitingInputConfig = null;

    return result;
  }

  /// 处理引擎日志
  void _handleEngineLog(String message, {engine.LogLevel level = engine.LogLevel.info}) {
    final prefix = switch (level) {
      engine.LogLevel.debug => '[DEBUG]',
      engine.LogLevel.info => '[INFO]',
      engine.LogLevel.warning => '[WARN]',
      engine.LogLevel.error => '[ERROR]',
    };
    _appendLog('$prefix $message');
  }

  /// 引擎事件处理
  void _onEngineEvent(ExecutionEvent event) {
    _currentNodeId = event.nodeId;

    switch (event.type) {
      case ExecutionEventType.nodeStarted:
        _appendLog('[INFO] 开始执行节点: ${event.nodeName ?? event.nodeTypeId}');
        // 创建初始快照
        if (event.nodeId != null) {
          _snapshots.set(
            event.nodeId!,
            NodeSnapshot(
              nodeId: event.nodeId!,
              nodeTypeId: event.nodeTypeId ?? 'unknown',
              nodeName: event.nodeName,
              status: NodeExecutionStatus.running,
              inputData: event.inputData ?? {},
              config: event.config ?? {},
              startTime: event.timestamp,
            ),
          );
        }
        break;
      case ExecutionEventType.nodeCompleted:
        _appendLog('[INFO] 节点完成: ${event.nodeName ?? event.nodeTypeId} -> ${event.port}');
        // 更新快照为完成状态
        if (event.nodeId != null) {
          final existing = _snapshots.get(event.nodeId!);
          if (existing != null) {
            _snapshots.set(
              event.nodeId!,
              existing.copyWith(
                status: NodeExecutionStatus.completed,
                output: NodeOutput(
                  port: event.port ?? 'success',
                  data: event.data ?? {},
                  isSuccess: true,
                ),
                endTime: event.timestamp,
              ),
            );
          }
        }
        break;
      case ExecutionEventType.nodeFailed:
        _appendLog('[ERROR] 节点失败: ${event.nodeName ?? event.nodeTypeId} - ${event.error}');
        // 更新快照为失败状态
        if (event.nodeId != null) {
          final existing = _snapshots.get(event.nodeId!);
          if (existing != null) {
            _snapshots.set(
              event.nodeId!,
              existing.copyWith(
                status: NodeExecutionStatus.failed,
                output: event.port != null
                    ? NodeOutput(
                        port: event.port!,
                        data: event.data ?? {},
                        isSuccess: false,
                        message: event.error,
                      )
                    : null,
                error: event.error,
                endTime: event.timestamp,
              ),
            );
          }
        }
        break;
      case ExecutionEventType.nodeSkipped:
        _appendLog('[WARN] 节点跳过: ${event.nodeName ?? event.nodeTypeId} - ${event.error}');
        if (event.nodeId != null) {
          _snapshots.set(
            event.nodeId!,
            NodeSnapshot(
              nodeId: event.nodeId!,
              nodeTypeId: event.nodeTypeId ?? 'unknown',
              nodeName: event.nodeName,
              status: NodeExecutionStatus.skipped,
              inputData: {},
              config: {},
              error: event.error,
              startTime: event.timestamp,
              endTime: event.timestamp,
            ),
          );
        }
        break;
      case ExecutionEventType.inputRequired:
        _status = ExecutorStatus.paused;
        break;
      case ExecutionEventType.flowCancelled:
        _status = ExecutorStatus.cancelled;
        break;
      case ExecutionEventType.flowStarted:
        // 清空之前的快照
        _snapshots.clear();
        // 设置全局上下文信息
        if (_context != null) {
          final job = _context!.job;
          _snapshots.setGlobalContext({
            'job': {
              'jobId': job.jobId,
              'sourceUrl': job.sourceUrl,
              'targetWc': job.targetWc,
              'currentRevision': job.currentRevision,
              'revisions': job.revisions,
              'completedIndex': job.completedIndex,
            },
            'workDir': _context!.workDir,
          });
        }
        break;
      default:
        break;
    }

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
    _engine?.dispose();
    super.dispose();
  }
}
