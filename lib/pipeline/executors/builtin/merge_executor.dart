import 'package:flutter/material.dart';

import '../../../services/working_copy_manager.dart';
import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 合并阶段执行器
///
/// 执行 svn merge，合并指定的 revision。
class MergeExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final wcManager = WorkingCopyManager();
    final targetWc = context.job.targetWc;
    final sourceUrl = context.job.sourceUrl;
    final revision = context.job.currentRevision;

    if (targetWc.isEmpty) {
      return NodeOutput.failure(message: '缺少目标工作副本路径');
    }
    if (sourceUrl.isEmpty) {
      return NodeOutput.failure(message: '缺少源 URL');
    }
    if (revision == null || revision <= 0) {
      return NodeOutput.failure(message: '缺少要合并的 revision');
    }

    try {
      context.info('开始合并 r$revision...');

      await wcManager.merge(sourceUrl, revision, targetWc);

      context.info('r$revision 合并成功');
      return NodeOutput.success(
        data: {
          'revision': revision,
          'sourceUrl': sourceUrl,
        },
        message: '合并成功',
      );
    } catch (e) {
      final errorStr = e.toString();
      context.error('合并阶段失败: $errorStr');

      // 检查是否是冲突错误
      if (_hasConflict(errorStr)) {
        return NodeOutput.port(
          'conflict',
          data: {'error': errorStr, 'revision': revision},
          message: '合并冲突，需要手动解决',
          isSuccess: false,
        );
      }

      return NodeOutput.failure(message: errorStr);
    }
  }

  /// 检查是否存在冲突
  static bool _hasConflict(String output) {
    final lowerOutput = output.toLowerCase();
    return lowerOutput.contains('conflict') ||
        lowerOutput.contains('冲突') ||
        lowerOutput.contains('tree conflict');
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'merge',
        name: '合并',
        description: '合并指定的 revision 到工作副本',
        icon: Icons.merge,
        color: Colors.orange,
        category: 'SVN 操作',
        inputs: const [PortSpec.defaultInput],
        outputs: const [
          PortSpec.success,
          PortSpec(id: 'conflict', name: '冲突', role: PortRole.error),
          PortSpec.failure,
        ],
        params: const [],
        executor: execute,
      );
}
