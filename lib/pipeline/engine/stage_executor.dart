import '../models/models.dart';
import 'pipeline_context.dart';

/// 阶段执行结果
class ExecutionResult {
  /// 是否成功
  final bool success;

  /// 是否需要暂停（等待用户输入）
  final bool needsPause;

  /// 暂停原因
  final String? pauseReason;

  /// 错误信息
  final String? error;

  /// 退出码
  final int? exitCode;

  /// 标准输出
  final String? stdout;

  /// 标准错误
  final String? stderr;

  /// 解析后的输出
  final dynamic parsedOutput;

  /// 用户输入（review 阶段）
  final String? userInput;

  const ExecutionResult({
    required this.success,
    this.needsPause = false,
    this.pauseReason,
    this.error,
    this.exitCode,
    this.stdout,
    this.stderr,
    this.parsedOutput,
    this.userInput,
  });

  /// 创建成功结果
  factory ExecutionResult.success({
    int? exitCode,
    String? stdout,
    String? stderr,
    dynamic parsedOutput,
  }) {
    return ExecutionResult(
      success: true,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      parsedOutput: parsedOutput,
    );
  }

  /// 创建失败结果
  factory ExecutionResult.failure(String error, {
    int? exitCode,
    String? stdout,
    String? stderr,
  }) {
    return ExecutionResult(
      success: false,
      error: error,
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
    );
  }

  /// 创建暂停结果
  factory ExecutionResult.pause(String reason) {
    return ExecutionResult(
      success: false,
      needsPause: true,
      pauseReason: reason,
    );
  }

  /// 创建带用户输入的成功结果
  factory ExecutionResult.withInput(String userInput) {
    return ExecutionResult(
      success: true,
      userInput: userInput,
    );
  }
}

/// 阶段执行器抽象接口
/// 采用策略模式，每种阶段类型对应一个执行器实现
abstract class StageExecutor {
  /// 执行阶段
  /// [config] 阶段配置
  /// [context] Pipeline 上下文
  /// [onLog] 日志回调
  Future<ExecutionResult> execute(
    StageConfig config,
    PipelineContext context, {
    void Function(String message)? onLog,
  });

  /// 是否支持取消
  bool get supportsCancellation => false;

  /// 取消执行
  Future<void> cancel() async {}
}

/// 阶段执行器注册表
/// 采用注册表模式管理所有执行器
class StageExecutorRegistry {
  final Map<StageType, StageExecutor> _executors = {};

  /// 注册执行器
  void register(StageType type, StageExecutor executor) {
    _executors[type] = executor;
  }

  /// 获取执行器
  StageExecutor? get(StageType type) {
    return _executors[type];
  }

  /// 是否已注册
  bool hasExecutor(StageType type) {
    return _executors.containsKey(type);
  }

  /// 获取所有已注册的类型
  Set<StageType> get registeredTypes => _executors.keys.toSet();
}
