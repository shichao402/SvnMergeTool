import '../../services/working_copy_manager.dart';
import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../models/models.dart';

/// 准备阶段执行器
/// 执行 revert + cleanup，确保工作副本处于干净状态
class PrepareExecutor extends StageExecutor {
  final WorkingCopyManager _wcManager;

  PrepareExecutor({WorkingCopyManager? wcManager})
      : _wcManager = wcManager ?? WorkingCopyManager();

  @override
  Future<ExecutionResult> execute(
    StageConfig config,
    PipelineContext context, {
    void Function(String message)? onLog,
  }) async {
    final targetWc = context.jobParams['targetWc'] as String?;
    if (targetWc == null || targetWc.isEmpty) {
      return ExecutionResult.failure('缺少目标工作副本路径');
    }

    try {
      onLog?.call('[INFO] 开始还原工作副本到干净状态...');

      // 执行 revert
      onLog?.call('[INFO] 执行 svn revert...');
      await _wcManager.revert(targetWc, recursive: true, refreshMergeInfo: false);

      // 执行 cleanup
      onLog?.call('[INFO] 执行 svn cleanup...');
      await _wcManager.cleanup(targetWc);

      onLog?.call('[INFO] 工作副本已还原到干净状态');

      return ExecutionResult.success();
    } catch (e) {
      onLog?.call('[ERROR] 准备阶段失败: $e');
      return ExecutionResult.failure(e.toString());
    }
  }
}
