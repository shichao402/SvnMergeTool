import 'package:flutter/material.dart';

import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 审核/输入阶段执行器
///
/// 等待用户输入（如 Review ID、CRID 等）。
class ReviewExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final prompt = config['prompt'] as String? ?? '请输入';
    final label = config['label'] as String? ?? '输入';
    final defaultValue = config['defaultValue'] as String?;
    final validationPattern = config['validationPattern'] as String?;
    final validationMessage = config['validationMessage'] as String?;
    final variableName = config['variableName'] as String? ?? 'userInput';

    context.info('等待用户输入: $label');

    try {
      final userInput = await context.requestUserInput(
        prompt: prompt,
        label: label,
        defaultValue: defaultValue,
        validationPattern: validationPattern,
        validationMessage: validationMessage,
      );

      if (userInput == null || userInput.isEmpty) {
        context.warning('用户取消输入');
        return NodeOutput.cancelled(message: '用户取消输入');
      }

      // 保存到上下文变量
      context.setVariable(variableName, userInput);

      context.info('用户输入: $userInput');
      return NodeOutput.success(
        data: {variableName: userInput, 'input': userInput},
        message: '输入完成',
      );
    } catch (e) {
      context.error('获取用户输入失败: $e');
      return NodeOutput.failure(message: e.toString());
    }
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'review',
        name: '用户输入',
        description: '等待用户输入（如 Review ID、CRID 等）',
        icon: Icons.input,
        color: Colors.teal,
        category: '交互',
        inputs: const [PortSpec.defaultInput],
        outputs: const [
          PortSpec.success,
          PortSpec(id: 'cancelled', name: '取消'),
        ],
        params: const [
          ParamSpec(
            key: 'prompt',
            label: '提示文字',
            type: ParamType.string,
            required: true,
            defaultValue: '请输入',
          ),
          ParamSpec(
            key: 'label',
            label: '输入框标签',
            type: ParamType.string,
            defaultValue: '输入',
          ),
          ParamSpec(
            key: 'defaultValue',
            label: '默认值',
            type: ParamType.string,
          ),
          ParamSpec(
            key: 'validationPattern',
            label: '验证正则',
            type: ParamType.string,
            description: '用于验证输入格式的正则表达式',
          ),
          ParamSpec(
            key: 'validationMessage',
            label: '验证失败提示',
            type: ParamType.string,
          ),
          ParamSpec(
            key: 'variableName',
            label: '变量名',
            type: ParamType.string,
            defaultValue: 'userInput',
            description: '保存输入值的变量名，可在后续节点中使用',
          ),
        ],
        executor: execute,
      );
}
