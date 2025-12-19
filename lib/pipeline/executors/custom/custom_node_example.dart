/// 自定义节点示例
///
/// 演示如何在代码中创建用户自定义节点。

import 'dart:io';
import 'package:flutter/material.dart';

import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 示例：文件存在检查节点
///
/// 检查指定路径的文件是否存在，根据结果触发不同的输出端口。
class FileExistsExecutor {
  /// 执行器函数
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    // 获取配置参数
    final filePath = config['filePath'] as String? ?? '';

    if (filePath.isEmpty) {
      context.error('未指定文件路径');
      return NodeOutput.failure(message: '未指定文件路径');
    }

    context.info('检查文件: $filePath');

    try {
      final file = File(filePath);
      final exists = await file.exists();

      if (exists) {
        final stat = await file.stat();
        context.info('文件存在，大小: ${stat.size} 字节');

        return NodeOutput(
          port: 'exists',
          data: {
            'filePath': filePath,
            'size': stat.size,
            'modified': stat.modified.toIso8601String(),
          },
          message: '文件存在',
          isSuccess: true,
        );
      } else {
        context.info('文件不存在');

        return NodeOutput(
          port: 'not_exists',
          data: {'filePath': filePath},
          message: '文件不存在',
          isSuccess: true, // 不存在也是正常结果
        );
      }
    } catch (e) {
      context.error('检查文件失败: $e');
      return NodeOutput.failure(message: e.toString());
    }
  }

  /// 节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'file_exists',
        name: '文件存在检查',
        description: '检查指定路径的文件是否存在',
        icon: Icons.insert_drive_file,
        color: Colors.indigo,
        category: '工具',
        inputs: const [PortSpec.defaultInput],
        outputs: const [
          PortSpec(id: 'exists', name: '存在', description: '文件存在时触发'),
          PortSpec(id: 'not_exists', name: '不存在', description: '文件不存在时触发'),
          PortSpec.failure,
        ],
        params: const [
          ParamSpec(
            key: 'filePath',
            label: '文件路径',
            type: ParamType.string,
            required: true,
            description: '要检查的文件完整路径',
          ),
        ],
        executor: execute,
        isUserDefined: true,
      );
}

/// 示例：延迟节点
///
/// 等待指定的秒数后继续执行。
class DelayExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final seconds = (config['seconds'] as num?)?.toInt() ?? 5;

    context.info('等待 $seconds 秒...');

    for (var i = 0; i < seconds; i++) {
      // 检查是否被取消
      if (context.isCancelled) {
        return NodeOutput.cancelled();
      }

      // 检查是否被暂停
      await context.checkPause();

      await Future.delayed(const Duration(seconds: 1));

      // 每秒输出进度
      if ((i + 1) % 5 == 0 || i == seconds - 1) {
        context.debug('已等待 ${i + 1}/$seconds 秒');
      }
    }

    context.info('等待完成');

    return NodeOutput.success(
      data: {'waitedSeconds': seconds},
      message: '等待 $seconds 秒完成',
    );
  }

  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'delay',
        name: '延迟',
        description: '等待指定的秒数后继续执行',
        icon: Icons.timer,
        color: Colors.amber,
        category: '工具',
        inputs: const [PortSpec.defaultInput],
        outputs: const [PortSpec.success, PortSpec.failure],
        params: const [
          ParamSpec(
            key: 'seconds',
            label: '等待秒数',
            type: ParamType.int,
            defaultValue: 5,
            description: '等待的秒数',
          ),
        ],
        executor: execute,
        isUserDefined: true,
      );
}

/// 示例：条件分支节点
///
/// 根据上游输入的值决定走哪个分支。
class ConditionalExecutor {
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final fieldName = config['fieldName'] as String? ?? 'value';
    final expectedValue = config['expectedValue'] as String? ?? '';
    final operator = config['operator'] as String? ?? 'equals';

    final actualValue = input[fieldName]?.toString() ?? '';

    context.info('条件检查: $fieldName $operator "$expectedValue"');
    context.debug('实际值: "$actualValue"');

    bool matches;
    switch (operator) {
      case 'equals':
        matches = actualValue == expectedValue;
        break;
      case 'not_equals':
        matches = actualValue != expectedValue;
        break;
      case 'contains':
        matches = actualValue.contains(expectedValue);
        break;
      case 'starts_with':
        matches = actualValue.startsWith(expectedValue);
        break;
      case 'ends_with':
        matches = actualValue.endsWith(expectedValue);
        break;
      case 'is_empty':
        matches = actualValue.isEmpty;
        break;
      case 'is_not_empty':
        matches = actualValue.isNotEmpty;
        break;
      default:
        matches = actualValue == expectedValue;
    }

    final port = matches ? 'true' : 'false';
    context.info('条件结果: $port');

    return NodeOutput(
      port: port,
      data: {
        'fieldName': fieldName,
        'actualValue': actualValue,
        'expectedValue': expectedValue,
        'operator': operator,
        'matches': matches,
      },
      message: matches ? '条件满足' : '条件不满足',
      isSuccess: true,
    );
  }

  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'conditional',
        name: '条件分支',
        description: '根据输入值决定执行分支',
        icon: Icons.call_split,
        color: Colors.deepPurple,
        category: '流程控制',
        inputs: const [PortSpec.defaultInput],
        outputs: const [
          PortSpec(id: 'true', name: '是', description: '条件满足时触发'),
          PortSpec(id: 'false', name: '否', description: '条件不满足时触发'),
        ],
        params: [
          const ParamSpec(
            key: 'fieldName',
            label: '字段名',
            type: ParamType.string,
            defaultValue: 'value',
            description: '要检查的输入字段名',
          ),
          ParamSpec(
            key: 'operator',
            label: '比较方式',
            type: ParamType.select,
            defaultValue: 'equals',
            options: [
              SelectOption(value: 'equals', label: '等于'),
              SelectOption(value: 'not_equals', label: '不等于'),
              SelectOption(value: 'contains', label: '包含'),
              SelectOption(value: 'starts_with', label: '开头是'),
              SelectOption(value: 'ends_with', label: '结尾是'),
              SelectOption(value: 'is_empty', label: '为空'),
              SelectOption(value: 'is_not_empty', label: '不为空'),
            ],
            description: '比较操作符',
          ),
          const ParamSpec(
            key: 'expectedValue',
            label: '期望值',
            type: ParamType.string,
            defaultValue: '',
            description: '期望的值（is_empty/is_not_empty 时忽略）',
          ),
        ],
        executor: execute,
        isUserDefined: true,
      );
}

/// 注册所有示例节点
void registerExampleNodes() {
  final registry = NodeTypeRegistry.instance;

  registry.register(FileExistsExecutor.definition);
  registry.register(DelayExecutor.definition);
  registry.register(ConditionalExecutor.definition);
}
