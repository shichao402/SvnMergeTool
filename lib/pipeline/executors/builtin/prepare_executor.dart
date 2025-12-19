import 'package:flutter/material.dart';

import '../../../services/working_copy_manager.dart';
import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 准备阶段执行器
///
/// 执行 revert + cleanup，确保工作副本处于干净状态。
class PrepareExecutor {
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
      context.info('开始还原工作副本到干净状态...');

      // 执行 revert
      context.info('执行 svn revert...');
      await wcManager.revert(targetWc, recursive: true, refreshMergeInfo: false);

      // 执行 cleanup
      context.info('执行 svn cleanup...');
      await wcManager.cleanup(targetWc);

      context.info('工作副本已还原到干净状态');

      return NodeOutput.success(
        data: {'targetWc': targetWc},
        message: '准备完成',
      );
    } catch (e) {
      context.error('准备阶段失败: $e');
      return NodeOutput.failure(message: e.toString());
    }
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'prepare',
        name: '准备',
        description: '还原工作副本到干净状态（revert + cleanup）',
        icon: Icons.cleaning_services,
        color: Colors.blue,
        category: 'SVN 操作',
        inputs: const [],
        outputs: const [PortSpec.success, PortSpec.failure],
        params: const [],
        executor: execute,
      );
}
