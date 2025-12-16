import 'pipeline_config.dart';
import 'pipeline_status.dart';
import 'stage_config.dart';
import 'stage_result.dart';
import 'stage_status.dart';

/// Pipeline 运行时状态
class PipelineState {
  /// 使用的 Pipeline 配置
  final PipelineConfig config;

  /// 整体状态
  final PipelineStatus status;

  /// 当前执行的阶段索引（-1 表示未开始）
  final int currentStageIndex;

  /// 各阶段的执行结果
  final Map<String, StageResult> stageResults;

  /// 开始时间
  final DateTime? startTime;

  /// 结束时间
  final DateTime? endTime;

  /// 暂停原因
  final String? pauseReason;

  /// 错误信息
  final String? error;

  const PipelineState({
    required this.config,
    this.status = PipelineStatus.idle,
    this.currentStageIndex = -1,
    this.stageResults = const {},
    this.startTime,
    this.endTime,
    this.pauseReason,
    this.error,
  });

  /// 创建初始状态
  factory PipelineState.initial(PipelineConfig config) {
    final results = <String, StageResult>{};
    for (final stage in config.stages) {
      results[stage.id] = StageResult.pending(stage.id);
    }
    return PipelineState(
      config: config,
      stageResults: results,
    );
  }

  /// 获取当前阶段配置
  StageConfig? get currentStage {
    if (currentStageIndex < 0 ||
        currentStageIndex >= config.enabledStages.length) {
      return null;
    }
    return config.enabledStages[currentStageIndex];
  }

  /// 获取当前阶段结果
  StageResult? get currentStageResult {
    final stage = currentStage;
    if (stage == null) return null;
    return stageResults[stage.id];
  }

  /// 获取指定阶段的结果
  StageResult? getStageResult(String stageId) {
    return stageResults[stageId];
  }

  /// 计算总耗时
  Duration get totalDuration {
    if (startTime == null) return Duration.zero;
    final end = endTime ?? DateTime.now();
    return end.difference(startTime!);
  }

  /// 计算进度百分比
  double get progress {
    final enabledStages = config.enabledStages;
    if (enabledStages.isEmpty) return 0;

    int completed = 0;
    for (final stage in enabledStages) {
      final result = stageResults[stage.id];
      if (result != null && result.status.isTerminal) {
        completed++;
      }
    }
    return completed / enabledStages.length;
  }

  /// 是否所有阶段都已完成
  bool get isAllStagesCompleted {
    for (final stage in config.enabledStages) {
      final result = stageResults[stage.id];
      if (result == null || !result.status.isSuccess) {
        return false;
      }
    }
    return true;
  }

  /// 复制并修改
  PipelineState copyWith({
    PipelineConfig? config,
    PipelineStatus? status,
    int? currentStageIndex,
    Map<String, StageResult>? stageResults,
    DateTime? startTime,
    DateTime? endTime,
    String? pauseReason,
    String? error,
  }) {
    return PipelineState(
      config: config ?? this.config,
      status: status ?? this.status,
      currentStageIndex: currentStageIndex ?? this.currentStageIndex,
      stageResults: stageResults ?? this.stageResults,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      pauseReason: pauseReason ?? this.pauseReason,
      error: error ?? this.error,
    );
  }

  /// 更新阶段结果
  PipelineState updateStageResult(StageResult result) {
    final newResults = Map<String, StageResult>.from(stageResults);
    newResults[result.stageId] = result;
    return copyWith(stageResults: newResults);
  }

  /// 从 JSON 创建
  factory PipelineState.fromJson(
    Map<String, dynamic> json,
    PipelineConfig config,
  ) {
    final resultsJson = json['stageResults'] as Map<String, dynamic>? ?? {};
    final results = <String, StageResult>{};
    for (final entry in resultsJson.entries) {
      results[entry.key] =
          StageResult.fromJson(entry.value as Map<String, dynamic>);
    }

    return PipelineState(
      config: config,
      status: PipelineStatusExtension.fromString(
          json['status'] as String? ?? 'idle'),
      currentStageIndex: json['currentStageIndex'] as int? ?? -1,
      stageResults: results,
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      pauseReason: json['pauseReason'] as String?,
      error: json['error'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'configId': config.id,
      'status': status.name,
      'currentStageIndex': currentStageIndex,
      'stageResults':
          stageResults.map((key, value) => MapEntry(key, value.toJson())),
      if (startTime != null) 'startTime': startTime!.toIso8601String(),
      if (endTime != null) 'endTime': endTime!.toIso8601String(),
      if (pauseReason != null) 'pauseReason': pauseReason,
      if (error != null) 'error': error,
    };
  }
}
