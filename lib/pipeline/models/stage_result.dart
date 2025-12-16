import 'stage_status.dart';

/// 阶段执行结果
class StageResult {
  /// 阶段 ID
  final String stageId;

  /// 执行状态
  final StageStatus status;

  /// 执行耗时
  final Duration duration;

  /// 错误信息（失败时）
  final String? error;

  /// 用户输入（review 阶段）
  final String? userInput;

  /// 脚本退出码
  final int? exitCode;

  /// 标准输出
  final String? stdout;

  /// 标准错误
  final String? stderr;

  /// 解析后的输出（captureMode 为 json 时）
  final dynamic parsedOutput;

  /// 开始时间
  final DateTime? startTime;

  /// 结束时间
  final DateTime? endTime;

  /// 重试次数
  final int retryCount;

  const StageResult({
    required this.stageId,
    required this.status,
    this.duration = Duration.zero,
    this.error,
    this.userInput,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.parsedOutput,
    this.startTime,
    this.endTime,
    this.retryCount = 0,
  });

  /// 创建等待中的结果
  factory StageResult.pending(String stageId) {
    return StageResult(
      stageId: stageId,
      status: StageStatus.pending,
    );
  }

  /// 创建运行中的结果
  factory StageResult.running(String stageId) {
    return StageResult(
      stageId: stageId,
      status: StageStatus.running,
      startTime: DateTime.now(),
    );
  }

  /// 创建完成的结果
  factory StageResult.completed({
    required String stageId,
    required Duration duration,
    int? exitCode,
    String? stdout,
    String? stderr,
    dynamic parsedOutput,
    DateTime? startTime,
  }) {
    final now = DateTime.now();
    return StageResult(
      stageId: stageId,
      status: StageStatus.completed,
      duration: duration,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      parsedOutput: parsedOutput,
      startTime: startTime,
      endTime: now,
    );
  }

  /// 创建失败的结果
  factory StageResult.failed({
    required String stageId,
    required String error,
    Duration duration = Duration.zero,
    int? exitCode,
    String? stdout,
    String? stderr,
    DateTime? startTime,
    int retryCount = 0,
  }) {
    final now = DateTime.now();
    return StageResult(
      stageId: stageId,
      status: StageStatus.failed,
      duration: duration,
      error: error,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      startTime: startTime,
      endTime: now,
      retryCount: retryCount,
    );
  }

  /// 创建暂停的结果
  factory StageResult.paused({
    required String stageId,
    String? error,
    DateTime? startTime,
  }) {
    return StageResult(
      stageId: stageId,
      status: StageStatus.paused,
      error: error,
      startTime: startTime,
    );
  }

  /// 创建跳过的结果
  factory StageResult.skipped(String stageId) {
    return StageResult(
      stageId: stageId,
      status: StageStatus.skipped,
    );
  }

  /// 创建带用户输入的结果（review 阶段）
  factory StageResult.withInput({
    required String stageId,
    required String userInput,
    Duration duration = Duration.zero,
  }) {
    return StageResult(
      stageId: stageId,
      status: StageStatus.completed,
      duration: duration,
      userInput: userInput,
      endTime: DateTime.now(),
    );
  }

  /// 复制并修改
  StageResult copyWith({
    String? stageId,
    StageStatus? status,
    Duration? duration,
    String? error,
    String? userInput,
    int? exitCode,
    String? stdout,
    String? stderr,
    dynamic parsedOutput,
    DateTime? startTime,
    DateTime? endTime,
    int? retryCount,
  }) {
    return StageResult(
      stageId: stageId ?? this.stageId,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      error: error ?? this.error,
      userInput: userInput ?? this.userInput,
      exitCode: exitCode ?? this.exitCode,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      parsedOutput: parsedOutput ?? this.parsedOutput,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  /// 获取输出值（用于变量引用）
  /// 如果有 parsedOutput 返回它，否则返回 stdout
  dynamic get output {
    if (parsedOutput != null) return parsedOutput;
    return stdout?.trim();
  }

  /// 从 JSON 创建
  factory StageResult.fromJson(Map<String, dynamic> json) {
    return StageResult(
      stageId: json['stageId'] as String,
      status: StageStatusExtension.fromString(json['status'] as String),
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      error: json['error'] as String?,
      userInput: json['userInput'] as String?,
      exitCode: json['exitCode'] as int?,
      stdout: json['stdout'] as String?,
      stderr: json['stderr'] as String?,
      parsedOutput: json['parsedOutput'],
      startTime: json['startTime'] != null
          ? DateTime.parse(json['startTime'] as String)
          : null,
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'stageId': stageId,
      'status': status.name,
      'durationMs': duration.inMilliseconds,
      if (error != null) 'error': error,
      if (userInput != null) 'userInput': userInput,
      if (exitCode != null) 'exitCode': exitCode,
      if (stdout != null) 'stdout': stdout,
      if (stderr != null) 'stderr': stderr,
      if (parsedOutput != null) 'parsedOutput': parsedOutput,
      if (startTime != null) 'startTime': startTime!.toIso8601String(),
      if (endTime != null) 'endTime': endTime!.toIso8601String(),
      if (retryCount > 0) 'retryCount': retryCount,
    };
  }
}
