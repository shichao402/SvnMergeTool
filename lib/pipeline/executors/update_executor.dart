import '../../services/working_copy_manager.dart';
import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../models/models.dart';

/// 更新阶段执行器
/// 执行 svn update，更新工作副本到最新版本
class UpdateExecutor extends StageExecutor {
  final WorkingCopyManager _wcManager;

  UpdateExecutor({WorkingCopyManager? wcManager})
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
      onLog?.call('[INFO] 开始更新工作副本...');

      final result = await _wcManager.update(targetWc);

      if (result.isSuccess) {
        onLog?.call('[INFO] 工作副本已更新到最新版本');
        return ExecutionResult.success(
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode,
        );
      } else {
        onLog?.call('[ERROR] 更新失败: ${result.stderr}');
        return ExecutionResult.failure(
          result.stderr.isNotEmpty ? result.stderr : '更新失败',
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr,
        );
      }
    } catch (e) {
      onLog?.call('[ERROR] 更新阶段失败: $e');
      return ExecutionResult.failure(e.toString());
    }
  }
}
