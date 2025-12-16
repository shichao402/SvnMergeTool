import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../models/models.dart';

/// Review 阶段执行器
/// 等待用户输入（如 Review ID）
/// 
/// 注意：此执行器返回 needsPause=true，由引擎处理暂停和用户输入
class ReviewExecutor extends StageExecutor {
  @override
  Future<ExecutionResult> execute(
    StageConfig config,
    PipelineContext context, {
    void Function(String message)? onLog,
  }) async {
    final reviewInput = config.reviewInput;
    if (reviewInput == null) {
      return ExecutionResult.failure('缺少 Review 输入配置');
    }

    onLog?.call('[INFO] 等待用户输入: ${reviewInput.label}');

    // 返回暂停结果，由引擎处理用户输入
    return ExecutionResult.pause('等待输入: ${reviewInput.label}');
  }
}
