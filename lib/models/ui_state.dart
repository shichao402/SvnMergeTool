/// UI 状态模型
///
/// 设计原则：
/// 1. 单一数据源：所有 UI 决策都基于这个状态
/// 2. 状态与 UI 解耦：这是纯数据模型，不依赖任何 UI 组件
/// 3. 不可变：状态变化通过创建新实例实现
/// 4. 可预测：状态转换有明确的规则
library;

import 'package:flutter/foundation.dart';
import '../pipeline/engine/engine.dart';
import '../providers/pipeline_merge_state.dart';

/// UI 阶段
/// 
/// 这是 UI 层面的阶段划分，与业务逻辑解耦
enum UIPhase {
  /// 选择阶段：浏览日志、选择 revision
  selecting,
  
  /// 执行阶段：Pipeline 正在执行
  executing,
  
  /// 等待输入：需要用户输入（如 CRID）
  waitingInput,
  
  /// 已完成：所有任务完成
  completed,
  
  /// 已失败：任务失败，需要用户处理
  failed,
}

/// 对话框类型
enum DialogType {
  /// 无对话框
  none,
  
  /// 用户输入对话框（如 CRID）
  userInput,
  
  /// 日志查看对话框
  logViewer,
  
  /// 配置对话框
  config,
  
  /// 确认对话框
  confirm,
}

/// 用户输入请求（UI 层面）
@immutable
class UIInputRequest {
  final String id;
  final String title;
  final String? hint;
  final String? validationRegex;
  final bool required;
  
  const UIInputRequest({
    required this.id,
    required this.title,
    this.hint,
    this.validationRegex,
    this.required = true,
  });
  
  /// 从 UserInputConfig 创建
  factory UIInputRequest.fromConfig(String nodeId, UserInputConfig config) {
    return UIInputRequest(
      id: nodeId,
      title: config.label,
      hint: config.hint,
      validationRegex: config.validationRegex,
      required: config.required,
    );
  }
}

/// 执行进度信息
@immutable
class UIExecutionProgress {
  /// 当前阶段名称
  final String? currentStageName;
  
  /// 进度百分比 (0.0 - 1.0)
  final double progress;
  
  /// 当前处理的 revision
  final int? currentRevision;
  
  /// 总 revision 数
  final int totalRevisions;
  
  /// 已完成的 revision 数
  final int completedRevisions;
  
  /// 执行器状态
  final ExecutorStatus? executorStatus;
  
  const UIExecutionProgress({
    this.currentStageName,
    this.progress = 0,
    this.currentRevision,
    this.totalRevisions = 0,
    this.completedRevisions = 0,
    this.executorStatus,
  });
  
  static const empty = UIExecutionProgress();
}

/// 暂停信息
@immutable
class UIPauseInfo {
  final String reason;
  final int? currentRevision;
  final int completedCount;
  final int totalCount;
  
  const UIPauseInfo({
    required this.reason,
    this.currentRevision,
    this.completedCount = 0,
    this.totalCount = 0,
  });
}

/// UI 状态快照
/// 
/// 这是一个不可变的状态快照，UI 层只需要读取这个状态来决定显示什么
@immutable
class UIState {
  /// 当前阶段
  final UIPhase phase;
  
  /// 当前显示的对话框类型
  final DialogType activeDialog;
  
  /// 用户输入请求（当 phase == waitingInput 时有值）
  final UIInputRequest? inputRequest;
  
  /// 执行进度（当 phase == executing 时有值）
  final UIExecutionProgress executionProgress;
  
  /// 暂停信息（当任务暂停时有值）
  final UIPauseInfo? pauseInfo;
  
  /// 错误信息（当 phase == failed 时有值）
  final String? errorMessage;
  
  /// 日志内容
  final String log;
  
  /// 是否有日志
  bool get hasLog => log.isNotEmpty;
  
  const UIState({
    this.phase = UIPhase.selecting,
    this.activeDialog = DialogType.none,
    this.inputRequest,
    this.executionProgress = UIExecutionProgress.empty,
    this.pauseInfo,
    this.errorMessage,
    this.log = '',
  });
  
  /// 创建副本
  UIState copyWith({
    UIPhase? phase,
    DialogType? activeDialog,
    UIInputRequest? inputRequest,
    bool clearInputRequest = false,
    UIExecutionProgress? executionProgress,
    UIPauseInfo? pauseInfo,
    bool clearPauseInfo = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? log,
  }) {
    return UIState(
      phase: phase ?? this.phase,
      activeDialog: activeDialog ?? this.activeDialog,
      inputRequest: clearInputRequest ? null : (inputRequest ?? this.inputRequest),
      executionProgress: executionProgress ?? this.executionProgress,
      pauseInfo: clearPauseInfo ? null : (pauseInfo ?? this.pauseInfo),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      log: log ?? this.log,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UIState &&
        other.phase == phase &&
        other.activeDialog == activeDialog &&
        other.inputRequest?.id == inputRequest?.id &&
        other.executionProgress.progress == executionProgress.progress &&
        other.pauseInfo?.reason == pauseInfo?.reason &&
        other.errorMessage == errorMessage &&
        other.log == log;
  }
  
  @override
  int get hashCode => Object.hash(
    phase,
    activeDialog,
    inputRequest?.id,
    executionProgress.progress,
    pauseInfo?.reason,
    errorMessage,
    log,
  );
}

/// UI 状态管理器
/// 
/// 负责：
/// 1. 监听业务状态变化
/// 2. 将业务状态转换为 UI 状态
/// 3. 管理对话框状态
/// 4. 提供统一的状态变化通知
class UIStateManager extends ChangeNotifier {
  UIState _state = const UIState();
  
  /// 当前 UI 状态
  UIState get state => _state;
  
  /// 便捷访问器
  UIPhase get phase => _state.phase;
  DialogType get activeDialog => _state.activeDialog;
  bool get isDialogShowing => _state.activeDialog != DialogType.none;
  UIInputRequest? get inputRequest => _state.inputRequest;
  UIExecutionProgress get executionProgress => _state.executionProgress;
  UIPauseInfo? get pauseInfo => _state.pauseInfo;
  String? get errorMessage => _state.errorMessage;
  String get log => _state.log;
  bool get hasLog => _state.hasLog;
  
  // ==================== 对话框管理 ====================
  
  /// 已处理的输入请求 ID（防止重复弹出）
  String? _lastHandledInputId;
  
  /// 显示用户输入对话框
  void showInputDialog() {
    if (_state.inputRequest != null) {
      _updateState(_state.copyWith(activeDialog: DialogType.userInput));
    }
  }
  
  /// 显示日志对话框
  void showLogDialog() {
    _updateState(_state.copyWith(activeDialog: DialogType.logViewer));
  }
  
  /// 显示配置对话框
  void showConfigDialog() {
    _updateState(_state.copyWith(activeDialog: DialogType.config));
  }
  
  /// 关闭当前对话框
  void closeDialog() {
    _updateState(_state.copyWith(activeDialog: DialogType.none));
  }
  
  // ==================== 状态同步 ====================
  
  /// 从 PipelineMergeState 同步状态
  /// 
  /// 这是核心方法，将业务状态转换为 UI 状态
  void syncFromMergeState(PipelineMergeState mergeState) {
    final newState = _computeUIState(mergeState);
    
    // 检查是否有新的输入请求需要处理
    final hasNewInputRequest = newState.inputRequest != null &&
        newState.inputRequest!.id != _lastHandledInputId &&
        _state.activeDialog != DialogType.userInput;
    
    if (hasNewInputRequest) {
      // 有新的输入请求，自动显示对话框
      _lastHandledInputId = newState.inputRequest!.id;
      _updateState(newState.copyWith(activeDialog: DialogType.userInput));
    } else if (newState.inputRequest == null && _state.activeDialog == DialogType.userInput) {
      // 输入请求已处理，关闭对话框
      _updateState(newState.copyWith(activeDialog: DialogType.none));
    } else {
      // 保持当前对话框状态
      _updateState(newState.copyWith(activeDialog: _state.activeDialog));
    }
  }
  
  /// 计算 UI 状态
  UIState _computeUIState(PipelineMergeState mergeState) {
    final phase = _computePhase(mergeState);
    final inputRequest = _computeInputRequest(mergeState);
    final executionProgress = _computeExecutionProgress(mergeState);
    final pauseInfo = _computePauseInfo(mergeState);
    final errorMessage = _computeErrorMessage(mergeState);
    
    return UIState(
      phase: phase,
      inputRequest: inputRequest,
      executionProgress: executionProgress,
      pauseInfo: pauseInfo,
      errorMessage: errorMessage,
      log: mergeState.log,
    );
  }
  
  /// 计算当前阶段
  UIPhase _computePhase(PipelineMergeState mergeState) {
    // 等待输入优先级最高
    if (mergeState.isWaitingInput) {
      return UIPhase.waitingInput;
    }
    
    // 检查是否有失败的任务
    final pausedJob = mergeState.pausedJob;
    if (pausedJob != null && pausedJob.error.isNotEmpty) {
      return UIPhase.failed;
    }
    
    // 正在执行
    if (mergeState.isProcessing) {
      return UIPhase.executing;
    }
    
    // 有暂停的任务
    if (mergeState.hasPausedJob) {
      return UIPhase.failed; // 暂停通常是因为错误
    }
    
    // 检查是否有活跃任务
    if (mergeState.activeJobs.isNotEmpty) {
      return UIPhase.executing;
    }
    
    // 默认是选择阶段
    return UIPhase.selecting;
  }
  
  /// 计算输入请求
  UIInputRequest? _computeInputRequest(PipelineMergeState mergeState) {
    final inputConfig = mergeState.waitingInputConfig;
    final nodeId = mergeState.currentNodeId;
    if (inputConfig == null || nodeId == null) return null;
    return UIInputRequest.fromConfig(nodeId, inputConfig);
  }
  
  /// 计算执行进度
  UIExecutionProgress _computeExecutionProgress(PipelineMergeState mergeState) {
    final pausedJob = mergeState.pausedJob;
    final status = mergeState.status;
    
    if (pausedJob == null) {
      return UIExecutionProgress(executorStatus: status);
    }
    
    // 计算进度
    double progress = 0.0;
    if (pausedJob.revisions.isNotEmpty) {
      progress = pausedJob.completedIndex / pausedJob.revisions.length;
    }
    
    return UIExecutionProgress(
      currentStageName: mergeState.currentNodeId,
      progress: progress,
      currentRevision: pausedJob.currentRevision,
      totalRevisions: pausedJob.revisions.length,
      completedRevisions: pausedJob.completedIndex,
      executorStatus: status,
    );
  }
  
  /// 计算暂停信息
  UIPauseInfo? _computePauseInfo(PipelineMergeState mergeState) {
    final pausedJob = mergeState.pausedJob;
    if (pausedJob == null) return null;
    
    return UIPauseInfo(
      reason: pausedJob.pauseReason,
      currentRevision: pausedJob.currentRevision,
      completedCount: pausedJob.completedIndex,
      totalCount: pausedJob.revisions.length,
    );
  }
  
  /// 计算错误信息
  String? _computeErrorMessage(PipelineMergeState mergeState) {
    final pausedJob = mergeState.pausedJob;
    if (pausedJob != null && pausedJob.error.isNotEmpty) {
      return pausedJob.error;
    }
    return null;
  }
  
  /// 更新状态
  void _updateState(UIState newState) {
    if (_state != newState) {
      _state = newState;
      notifyListeners();
    }
  }
  
  /// 重置状态
  void reset() {
    _lastHandledInputId = null;
    _updateState(const UIState());
  }
}
