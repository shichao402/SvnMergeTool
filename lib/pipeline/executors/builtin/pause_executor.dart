import 'package:flutter/material.dart';

import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 暂停节点执行器
///
/// 暂停流程执行，等待用户手动继续。
/// 用于在流程中插入检查点，让用户确认后再继续。
class PauseExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final message = config['message'] as String? ?? '流程已暂停，点击继续执行';
    
    context.info('暂停: $message');
    
    // 请求用户输入，用户点击继续即可
    final result = await context.requestUserInput(
      prompt: message,
      label: '流程暂停',
    );
    
    // 用户取消
    if (result == null) {
      return NodeOutput.cancelled(message: '用户取消');
    }
    
    context.info('用户确认继续');
    
    // 传递上游数据
    return NodeOutput.success(
      data: Map<String, dynamic>.from(input),
      message: '继续执行',
    );
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'pause',
        name: '暂停',
        description: '暂停流程执行，等待用户手动继续',
        icon: Icons.pause_circle_outline,
        color: Colors.orange,
        category: '流程控制',
        inputs: const [PortSpec.defaultInput],
        outputs: const [PortSpec.success],
        params: const [
          ParamSpec(
            key: 'message',
            label: '提示信息',
            type: ParamType.string,
            defaultValue: '流程已暂停，点击继续执行',
            description: '显示给用户的提示信息',
          ),
        ],
        executor: execute,
      );
}
