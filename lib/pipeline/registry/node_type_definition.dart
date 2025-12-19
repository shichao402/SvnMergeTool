import 'package:flutter/material.dart';

import '../engine/execution_context.dart';
import '../engine/node_output.dart';
import 'param_spec.dart';
import 'port_spec.dart';

/// 节点执行器类型
///
/// 执行节点逻辑，返回 NodeOutput 指定触发哪个输出端口。
typedef NodeExecutor = Future<NodeOutput> Function({
  required Map<String, dynamic> input,
  required Map<String, dynamic> config,
  required ExecutionContext context,
});

/// 节点类型定义
///
/// 定义节点的元信息：名称、图标、端口、参数、执行器。
/// 注册到 NodeTypeRegistry 后，可通过 typeId 查找。
class NodeTypeDefinition {
  /// 类型 ID（唯一标识）
  final String typeId;

  /// 显示名称
  final String name;

  /// 描述
  final String? description;

  /// 图标
  final IconData icon;

  /// 颜色
  final Color color;

  /// 分类（用于节点面板分组）
  final String? category;

  /// 输入端口列表
  final List<PortSpec> inputs;

  /// 输出端口列表
  final List<PortSpec> outputs;

  /// 可配置参数列表
  final List<ParamSpec> params;

  /// 执行器
  final NodeExecutor executor;

  /// 是否为用户自定义节点
  final bool isUserDefined;

  /// 是否隐藏（不在节点面板显示）
  final bool isHidden;

  /// 用户自定义节点的原始配置（JSON）
  final Map<String, dynamic>? rawConfig;

  const NodeTypeDefinition({
    required this.typeId,
    required this.name,
    this.description,
    this.icon = Icons.play_arrow,
    this.color = Colors.blue,
    this.category,
    this.inputs = const [PortSpec.defaultInput],
    this.outputs = const [PortSpec.success, PortSpec.failure],
    this.params = const [],
    required this.executor,
    this.isUserDefined = false,
    this.isHidden = false,
    this.rawConfig,
  });

  /// 获取输入端口
  PortSpec? getInputPort(String portId) {
    try {
      return inputs.firstWhere((p) => p.id == portId);
    } catch (_) {
      return null;
    }
  }

  /// 获取输出端口
  PortSpec? getOutputPort(String portId) {
    try {
      return outputs.firstWhere((p) => p.id == portId);
    } catch (_) {
      return null;
    }
  }

  /// 验证节点配置
  List<ParamValidationResult> validateConfig(Map<String, dynamic> config) {
    final results = <ParamValidationResult>[];
    for (final param in params) {
      final value = config[param.key];
      final result = param.validate(value);
      if (!result.isValid) {
        results.add(result);
      }
    }
    return results;
  }

  /// 获取带默认值的配置
  Map<String, dynamic> getEffectiveConfig(Map<String, dynamic> config) {
    final result = <String, dynamic>{};
    for (final param in params) {
      result[param.key] = param.getEffectiveValue(config[param.key]);
    }
    return result;
  }

  @override
  String toString() => 'NodeTypeDefinition(typeId: $typeId, name: $name)';
}
