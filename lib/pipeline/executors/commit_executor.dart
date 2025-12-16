import '../../services/working_copy_manager.dart';
import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../models/models.dart';

/// 提交阶段执行器
/// 执行 svn commit
class CommitExecutor extends StageExecutor {
  final WorkingCopyManager _wcManager;

  CommitExecutor({WorkingCopyManager? wcManager})
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

    // 构建提交信息
    final message = _buildCommitMessage(config, context);

    try {
      onLog?.call('[INFO] 开始提交...');
      onLog?.call('[INFO] 提交信息: $message');

      // commit 方法返回 void，成功则无异常
      await _wcManager.commit(targetWc, message);

      onLog?.call('[INFO] 提交成功');
      return ExecutionResult.success();
    } catch (e) {
      final errorStr = e.toString();
      onLog?.call('[ERROR] 提交失败: $errorStr');

      // 检查是否是 out-of-date 错误
      if (_isOutOfDate(errorStr)) {
        return ExecutionResult.failure('工作副本过期，需要更新');
      }

      return ExecutionResult.failure(errorStr);
    }
  }

  /// 构建提交信息
  String _buildCommitMessage(StageConfig config, PipelineContext context) {
    // 如果有模板，使用模板
    if (config.commitMessageTemplate != null &&
        config.commitMessageTemplate!.isNotEmpty) {
      return context.resolve(config.commitMessageTemplate!);
    }

    // 默认提交信息
    final sourceUrl = context.jobParams['sourceUrl'] as String? ?? '';
    final revision = context.jobParams['currentRevision'];
    final revisions = context.jobParams['revisions'] as List<int>?;

    if (revisions != null && revisions.isNotEmpty) {
      final revStr = revisions.map((r) => 'r$r').join(', ');
      return '[Merge] $revStr from $sourceUrl';
    } else if (revision != null) {
      return '[Merge] r$revision from $sourceUrl';
    } else {
      return '[Merge] from $sourceUrl';
    }
  }

  /// 检查是否是 out-of-date 错误
  bool _isOutOfDate(String output) {
    final lowerOutput = output.toLowerCase();
    return lowerOutput.contains('out-of-date') ||
        lowerOutput.contains('out of date');
  }
}
