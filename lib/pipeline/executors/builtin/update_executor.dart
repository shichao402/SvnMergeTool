import 'package:flutter/material.dart';

import '../../../services/working_copy_manager.dart';
import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 更新阶段执行器
///
/// 执行 svn update，更新工作副本到最新版本。
class UpdateExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final wcManager = WorkingCopyManager();
    final targetWc = context.job.targetWc;

    if (targetWc.isEmpty) {
      return NodeOutput.failure(message: '缺少目标工作副本路径');
    }

    try {
      context.info('开始更新工作副本...');

      final result = await wcManager.update(targetWc);

      if (result.isSuccess) {
        context.info('工作副本已更新到最新版本');
        return NodeOutput.success(
          data: {
            'stdout': result.stdout,
            'exitCode': result.exitCode,
          },
          message: '更新完成',
        );
      } else {
        context.error('更新失败: ${result.stderr}');
        return NodeOutput.failure(
          message: result.stderr.isNotEmpty ? result.stderr : '更新失败',
          data: {
            'exitCode': result.exitCode,
            'stderr': result.stderr,
          },
        );
      }
    } catch (e) {
      context.error('更新阶段失败: $e');
      return NodeOutput.failure(message: e.toString());
    }
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'update',
        name: '更新',
        description: '更新工作副本到最新版本',
        icon: Icons.refresh,
        color: Colors.green,
        category: 'SVN 操作',
        inputs: const [PortSpec.defaultInput],
        outputs: const [PortSpec.success, PortSpec.failure],
        params: const [],
        executor: execute,
      );
}
