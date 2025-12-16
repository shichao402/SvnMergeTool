import '../../services/working_copy_manager.dart';
import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../models/models.dart';

/// 合并阶段执行器
/// 执行 svn merge，合并指定的 revision
class MergeExecutor extends StageExecutor {
  final WorkingCopyManager _wcManager;

  MergeExecutor({WorkingCopyManager? wcManager})
      : _wcManager = wcManager ?? WorkingCopyManager();

  @override
  Future<ExecutionResult> execute(
    StageConfig config,
    PipelineContext context, {
    void Function(String message)? onLog,
  }) async {
    final targetWc = context.jobParams['targetWc'] as String?;
    final sourceUrl = context.jobParams['sourceUrl'] as String?;
    final revision = context.jobParams['currentRevision'] as int?;

    if (targetWc == null || targetWc.isEmpty) {
      return ExecutionResult.failure('缺少目标工作副本路径');
    }
    if (sourceUrl == null || sourceUrl.isEmpty) {
      return ExecutionResult.failure('缺少源 URL');
    }
    if (revision == null) {
      return ExecutionResult.failure('缺少要合并的 revision');
    }

    try {
      onLog?.call('[INFO] 开始合并 r$revision...');

      // merge 方法返回 void，成功则无异常
      await _wcManager.merge(
        sourceUrl,
        revision,
        targetWc,
      );

      // merge 成功（没有抛出异常）
      onLog?.call('[INFO] r$revision 合并成功');
      return ExecutionResult.success();
    } catch (e) {
      final errorStr = e.toString();
      onLog?.call('[ERROR] 合并阶段失败: $errorStr');

      // 检查是否是冲突错误
      if (_hasConflict(errorStr)) {
        return ExecutionResult.pause('合并冲突，需要手动解决');
      }

      return ExecutionResult.failure(errorStr);
    }
  }

  /// 检查是否存在冲突
  bool _hasConflict(String output) {
    final lowerOutput = output.toLowerCase();
    return lowerOutput.contains('conflict') ||
        lowerOutput.contains('冲突') ||
        lowerOutput.contains('tree conflict');
  }
}
