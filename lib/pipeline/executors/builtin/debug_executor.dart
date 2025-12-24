import 'dart:convert';

import 'package:flutter/material.dart';

import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 调试节点执行器
///
/// 用于调试流程，显示上游传入的数据。
/// 可以选择暂停让用户查看，或直接透传数据继续执行。
class DebugExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final pauseAfterLog = config['pauseAfterLog'] as bool? ?? true;
    final logLevel = config['logLevel'] as String? ?? 'info';
    
    // 格式化输入数据
    final inputJson = const JsonEncoder.withIndent('  ').convert(input);
    
    // 记录日志
    final logMessage = '===== 调试信息 =====\n'
        '上游输入数据:\n$inputJson\n'
        '====================';
    
    switch (logLevel) {
      case 'debug':
        context.debug(logMessage);
      case 'warning':
        context.warning(logMessage);
      case 'error':
        context.error(logMessage);
      default:
        context.info(logMessage);
    }
    
    // 如果需要暂停
    if (pauseAfterLog) {
      final result = await context.requestUserInput(
        prompt: '上游数据已记录到日志，点击继续执行\n\n输入数据:\n$inputJson',
        label: '调试信息',
      );
      
      if (result == null) {
        return NodeOutput.cancelled(message: '用户取消');
      }
    }
    
    // 透传上游数据
    return NodeOutput.success(
      data: Map<String, dynamic>.from(input),
      message: '调试完成',
    );
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'debug',
        name: '调试',
        description: '显示上游传入的数据，用于调试流程',
        icon: Icons.bug_report,
        color: Colors.purple,
        category: '流程控制',
        inputs: const [PortSpec.defaultInput],
        outputs: const [PortSpec.success],
        params: const [
          ParamSpec(
            key: 'pauseAfterLog',
            label: '记录后暂停',
            type: ParamType.bool,
            defaultValue: true,
            description: '记录日志后是否暂停等待用户确认',
          ),
          ParamSpec(
            key: 'logLevel',
            label: '日志级别',
            type: ParamType.select,
            defaultValue: 'info',
            options: [
              SelectOption(value: 'debug', label: 'Debug'),
              SelectOption(value: 'info', label: 'Info'),
              SelectOption(value: 'warning', label: 'Warning'),
              SelectOption(value: 'error', label: 'Error'),
            ],
            description: '日志输出级别',
          ),
        ],
        executor: execute,
      );
}
