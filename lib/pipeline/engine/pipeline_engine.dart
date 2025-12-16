import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'pipeline_context.dart';
import 'stage_executor.dart';

/// Pipeline 引擎事件类型
enum PipelineEventType {
  /// Pipeline 开始
  started,

  /// 阶段开始
  stageStarted,

  /// 阶段完成
  stageCompleted,

  /// 阶段失败
  stageFailed,

  /// 阶段跳过
  stageSkipped,

  /// Pipeline 暂停
  paused,

  /// Pipeline 恢复
  resumed,

  /// Pipeline 完成
  completed,

  /// Pipeline 失败
  failed,

  /// Pipeline 取消
  cancelled,

  /// 回滚开始
  rollbackStarted,

  /// 回滚完成
  rollbackCompleted,

  /// 日志
  log,
}

/// Pipeline 事件
class PipelineEvent {
  final PipelineEventType type;
  final String? stageId;
  final String? message;
  final dynamic data;
  final DateTime timestamp;

  PipelineEvent({
    required this.type,
    this.stageId,
    this.message,
    this.data,
  }) : timestamp = DateTime.now();
}

/// 用户输入请求
class UserInputRequest {
  final String stageId;
  final String stageName;
  final ReviewInputConfig inputConfig;
  final Completer<String?> completer;

  UserInputRequest({
    required this.stageId,
    required this.stageName,
    required this.inputConfig,
  }) : completer = Completer<String?>();

  /// 提交输入
  void submit(String value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  /// 取消输入
  void cancel() {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }
}

/// Pipeline 引擎
/// 负责调度阶段执行、管理状态、处理失败
class PipelineEngine extends ChangeNotifier {
  /// 执行器注册表
  final StageExecutorRegistry _registry;

  /// 当前状态
  PipelineState? _state;

  /// 执行上下文
  PipelineContext? _context;

  /// 事件流控制器
  final _eventController = StreamController<PipelineEvent>.broadcast();

  /// 当前用户输入请求
  UserInputRequest? _currentInputRequest;

  /// 是否已取消
  bool _isCancelled = false;

  /// 当前执行的阶段执行器
  StageExecutor? _currentExecutor;

  PipelineEngine(this._registry);

  /// 当前状态
  PipelineState? get state => _state;

  /// 执行上下文
  PipelineContext? get context => _context;

  /// 事件流
  Stream<PipelineEvent> get events => _eventController.stream;

  /// 当前用户输入请求
  UserInputRequest? get currentInputRequest => _currentInputRequest;

  /// 是否正在运行
  bool get isRunning => _state?.status == PipelineStatus.running;

  /// 是否暂停
  bool get isPaused => _state?.status == PipelineStatus.paused;

  /// 是否可以继续
  bool get canResume => _state?.status.canResume ?? false;

  /// 是否可以取消
  bool get canCancel => _state?.status.canCancel ?? false;

  /// 是否可以回滚
  bool get canRollback => _state?.status.canRollback ?? false;

  /// 启动 Pipeline
  Future<void> start(
    PipelineConfig config, {
    Map<String, dynamic>? jobParams,
    Map<String, String>? env,
  }) async {
    if (isRunning) {
      throw StateError('Pipeline is already running');
    }

    // 验证配置
    final errors = config.validate();
    if (errors.isNotEmpty) {
      throw ArgumentError('Invalid pipeline config: ${errors.join(', ')}');
    }

    // 初始化状态
    _state = PipelineState.initial(config).copyWith(
      status: PipelineStatus.running,
      startTime: DateTime.now(),
    );

    // 初始化上下文
    _context = PipelineContext(
      jobParams: jobParams,
      env: env,
    );

    _isCancelled = false;

    _emit(PipelineEvent(type: PipelineEventType.started));
    notifyListeners();

    // 开始执行
    await _executeStages();
  }

  /// 执行所有阶段
  Future<void> _executeStages() async {
    final enabledStages = _state!.config.enabledStages;

    for (int i = _state!.currentStageIndex + 1; i < enabledStages.length; i++) {
      if (_isCancelled) {
        _state = _state!.copyWith(
          status: PipelineStatus.cancelled,
          endTime: DateTime.now(),
        );
        _emit(PipelineEvent(type: PipelineEventType.cancelled));
        notifyListeners();
        return;
      }

      final stage = enabledStages[i];
      _state = _state!.copyWith(currentStageIndex: i);
      notifyListeners();

      final shouldContinue = await _executeStage(stage);
      if (!shouldContinue) {
        return; // 暂停或失败，停止执行
      }
    }

    // 所有阶段完成
    _state = _state!.copyWith(
      status: PipelineStatus.completed,
      endTime: DateTime.now(),
    );
    _emit(PipelineEvent(type: PipelineEventType.completed));
    notifyListeners();
  }

  /// 执行单个阶段
  /// 返回 true 表示继续执行下一阶段，false 表示停止
  Future<bool> _executeStage(StageConfig stage) async {
    final executor = _registry.get(stage.type);
    if (executor == null) {
      _log('[ERROR] 未找到阶段执行器: ${stage.type}');
      return _handleFailure(stage, '未找到阶段执行器: ${stage.type}');
    }

    _currentExecutor = executor;

    // 更新状态为运行中
    final startTime = DateTime.now();
    _state = _state!.updateStageResult(StageResult.running(stage.id));
    _emit(PipelineEvent(
      type: PipelineEventType.stageStarted,
      stageId: stage.id,
      message: '开始执行: ${stage.name}',
    ));
    notifyListeners();

    // 执行阶段（带重试）
    ExecutionResult? result;
    int retryCount = 0;

    while (retryCount <= stage.maxRetries) {
      if (_isCancelled) {
        return false;
      }

      try {
        result = await executor.execute(
          stage,
          _context!,
          onLog: _log,
        );

        if (result.success) {
          break;
        }

        // 失败且策略为重试
        if (stage.onFail == FailureAction.retry &&
            retryCount < stage.maxRetries) {
          retryCount++;
          _log('[WARN] 阶段 "${stage.name}" 执行失败，正在重试 ($retryCount/${stage.maxRetries})...');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        break;
      } catch (e) {
        result = ExecutionResult.failure(e.toString());
        if (stage.onFail != FailureAction.retry ||
            retryCount >= stage.maxRetries) {
          break;
        }
        retryCount++;
        _log('[WARN] 阶段 "${stage.name}" 执行异常，正在重试 ($retryCount/${stage.maxRetries})...');
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    _currentExecutor = null;
    final duration = DateTime.now().difference(startTime);

    if (result == null) {
      return _handleFailure(stage, '执行结果为空');
    }

    // 处理需要暂停的情况（如 review 阶段）
    if (result.needsPause) {
      return await _handlePause(stage, result.pauseReason ?? '需要用户输入');
    }

    if (result.success) {
      // 更新上下文
      final stageResult = StageResult.completed(
        stageId: stage.id,
        duration: duration,
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        parsedOutput: result.parsedOutput,
        startTime: startTime,
      ).copyWith(userInput: result.userInput);

      _context!.updateStageResult(stageResult);
      _state = _state!.updateStageResult(stageResult);

      _emit(PipelineEvent(
        type: PipelineEventType.stageCompleted,
        stageId: stage.id,
        message: '完成: ${stage.name}',
      ));
      notifyListeners();

      return true;
    } else {
      return _handleFailure(
        stage,
        result.error ?? '未知错误',
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        retryCount: retryCount,
      );
    }
  }

  /// 处理阶段失败
  Future<bool> _handleFailure(
    StageConfig stage,
    String error, {
    int? exitCode,
    String? stdout,
    String? stderr,
    int retryCount = 0,
  }) async {
    final stageResult = StageResult.failed(
      stageId: stage.id,
      error: error,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      retryCount: retryCount,
    );

    _state = _state!.updateStageResult(stageResult);
    _context?.updateStageResult(stageResult);

    _emit(PipelineEvent(
      type: PipelineEventType.stageFailed,
      stageId: stage.id,
      message: '失败: ${stage.name} - $error',
    ));

    switch (stage.onFail) {
      case FailureAction.pause:
        return await _handlePause(stage, error);

      case FailureAction.skip:
        _state = _state!.updateStageResult(StageResult.skipped(stage.id));
        _emit(PipelineEvent(
          type: PipelineEventType.stageSkipped,
          stageId: stage.id,
          message: '跳过: ${stage.name}',
        ));
        notifyListeners();
        return true;

      case FailureAction.fail:
        _state = _state!.copyWith(
          status: PipelineStatus.failed,
          error: error,
          endTime: DateTime.now(),
        );
        _emit(PipelineEvent(
          type: PipelineEventType.failed,
          message: 'Pipeline 失败: $error',
        ));
        notifyListeners();
        return false;

      case FailureAction.rollback:
        await rollback();
        return false;

      case FailureAction.abort:
        _state = _state!.copyWith(
          status: PipelineStatus.cancelled,
          error: error,
          endTime: DateTime.now(),
        );
        _emit(PipelineEvent(type: PipelineEventType.cancelled));
        notifyListeners();
        await rollback();
        return false;

      case FailureAction.retry:
        // 已在循环中处理，这里不应该到达
        return false;
    }
  }

  /// 处理暂停
  Future<bool> _handlePause(StageConfig stage, String reason) async {
    _state = _state!.copyWith(
      status: PipelineStatus.paused,
      pauseReason: reason,
    ).updateStageResult(StageResult.paused(
      stageId: stage.id,
      error: reason,
    ));

    _emit(PipelineEvent(
      type: PipelineEventType.paused,
      stageId: stage.id,
      message: '暂停: $reason',
    ));
    notifyListeners();

    return false;
  }

  /// 恢复执行
  Future<void> resume({String? userInput}) async {
    if (!canResume) {
      throw StateError('Cannot resume: current status is ${_state?.status}');
    }

    final currentStage = _state!.currentStage;
    if (currentStage == null) {
      throw StateError('No current stage to resume');
    }

    // 如果是 review 阶段，需要用户输入
    if (currentStage.type == StageType.review && userInput != null) {
      final stageResult = StageResult.withInput(
        stageId: currentStage.id,
        userInput: userInput,
      );
      _context!.updateStageResult(stageResult);
      _state = _state!.updateStageResult(stageResult);
    }

    _state = _state!.copyWith(
      status: PipelineStatus.running,
      pauseReason: null,
    );

    _emit(PipelineEvent(type: PipelineEventType.resumed));
    notifyListeners();

    // 继续执行后续阶段
    await _executeStages();
  }

  /// 跳过当前阶段
  Future<void> skipCurrentStage() async {
    if (!isPaused) {
      throw StateError('Cannot skip: pipeline is not paused');
    }

    final currentStage = _state!.currentStage;
    if (currentStage == null) {
      throw StateError('No current stage to skip');
    }

    _state = _state!.updateStageResult(StageResult.skipped(currentStage.id));
    _state = _state!.copyWith(
      status: PipelineStatus.running,
      pauseReason: null,
    );

    _emit(PipelineEvent(
      type: PipelineEventType.stageSkipped,
      stageId: currentStage.id,
      message: '跳过: ${currentStage.name}',
    ));
    notifyListeners();

    // 继续执行后续阶段
    await _executeStages();
  }

  /// 取消执行
  Future<void> cancel() async {
    if (!canCancel) {
      return;
    }

    _isCancelled = true;

    // 取消当前执行器
    if (_currentExecutor?.supportsCancellation ?? false) {
      await _currentExecutor!.cancel();
    }

    // 取消用户输入请求
    _currentInputRequest?.cancel();
    _currentInputRequest = null;

    _state = _state!.copyWith(
      status: PipelineStatus.cancelled,
      endTime: DateTime.now(),
    );

    _emit(PipelineEvent(type: PipelineEventType.cancelled));
    notifyListeners();
  }

  /// 回滚
  /// 回滚逻辑由外部提供（通过注册 rollback 回调）
  Future<void> rollback() async {
    if (!canRollback) {
      return;
    }

    _state = _state!.copyWith(status: PipelineStatus.rollingBack);
    _emit(PipelineEvent(type: PipelineEventType.rollbackStarted));
    notifyListeners();

    // 回滚逻辑由 prepare 执行器实现
    final prepareExecutor = _registry.get(StageType.prepare);
    if (prepareExecutor != null) {
      try {
        await prepareExecutor.execute(
          StageConfig.prepare(),
          _context!,
          onLog: _log,
        );
        _log('[INFO] 回滚完成');
      } catch (e) {
        _log('[ERROR] 回滚失败: $e');
      }
    }

    _state = _state!.copyWith(
      status: PipelineStatus.cancelled,
      endTime: DateTime.now(),
    );

    _emit(PipelineEvent(type: PipelineEventType.rollbackCompleted));
    notifyListeners();
  }

  /// 请求用户输入
  Future<String?> requestUserInput(
    String stageId,
    String stageName,
    ReviewInputConfig inputConfig,
  ) async {
    _currentInputRequest = UserInputRequest(
      stageId: stageId,
      stageName: stageName,
      inputConfig: inputConfig,
    );
    notifyListeners();

    final result = await _currentInputRequest!.completer.future;
    _currentInputRequest = null;
    notifyListeners();

    return result;
  }

  /// 提交用户输入
  void submitUserInput(String value) {
    _currentInputRequest?.submit(value);
  }

  /// 取消用户输入
  void cancelUserInput() {
    _currentInputRequest?.cancel();
  }

  /// 发送事件
  void _emit(PipelineEvent event) {
    _eventController.add(event);
  }

  /// 记录日志
  void _log(String message) {
    _emit(PipelineEvent(
      type: PipelineEventType.log,
      message: message,
    ));
  }

  /// 重置引擎
  void reset() {
    _state = null;
    _context = null;
    _isCancelled = false;
    _currentExecutor = null;
    _currentInputRequest = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventController.close();
    super.dispose();
  }
}
