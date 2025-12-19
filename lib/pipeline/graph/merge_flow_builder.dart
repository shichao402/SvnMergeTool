/// 合并流程构建器
/// 
/// 用于构建标准的 SVN 合并流程图。
/// 
/// 现在基于 FlowDefinition 和 FlowGenerator，
/// 确保 UI 表现和执行逻辑使用相同的节点和连接定义。

import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../models/stage_status.dart';
import '../models/stage_type.dart';
import 'flow_generator.dart';
import 'stage_data.dart';
import 'stage_definition.dart';

/// 合并流程构建器
class MergeFlowBuilder {
  /// 构建标准合并流程
  /// 
  /// 流程：prepare → update → merge → commit
  ///                                    ↓ (失败)
  ///                               crid_input
  ///                                    ↓ (成功)
  ///                                  commit
  static NodeFlowController<StageData> buildStandardFlow({
    String? commitMessageTemplate,
  }) {
    final flow = FlowDefinition.standardMergeFlow(
      commitMessageTemplate: commitMessageTemplate,
    );
    return FlowGenerator.generate(flow);
  }

  /// 构建简单线性流程（无分支）
  static NodeFlowController<StageData> buildSimpleFlow() {
    final flow = FlowDefinition.simpleFlow();
    return FlowGenerator.generate(flow);
  }

  /// 从 FlowDefinition 构建
  static NodeFlowController<StageData> buildFromDefinition(FlowDefinition flow) {
    return FlowGenerator.generate(flow);
  }

  /// 从 JSON 加载流程
  static NodeFlowController<StageData> fromJson(Map<String, dynamic> json) {
    final graph = NodeGraph<StageData>.fromJson(
      json,
      (data) => StageData.fromJson(data as Map<String, dynamic>),
    );

    final controller = NodeFlowController<StageData>();

    for (final node in graph.nodes) {
      controller.addNode(node);
    }

    for (final connection in graph.connections) {
      controller.addConnection(connection);
    }

    return controller;
  }

  /// 导出为 JSON
  static Map<String, dynamic> toJson(NodeFlowController<StageData> controller) {
    final nodes = controller.nodes.values.toList();
    final connections = controller.connections.toList();
    final graph = NodeGraph<StageData>(
      nodes: nodes,
      connections: connections,
    );
    return graph.toJson((data) => data.toJson());
  }
}

/// 节点类型对应的颜色
Color getNodeColorByType(StageType type) {
  switch (type) {
    case StageType.prepare:
      return Colors.blue;
    case StageType.update:
      return Colors.cyan;
    case StageType.merge:
      return Colors.orange;
    case StageType.commit:
      return Colors.green;
    case StageType.review:
      return Colors.purple;
    case StageType.script:
    case StageType.check:
    case StageType.postScript:
      return Colors.grey;
  }
}

/// 节点状态对应的颜色
Color getNodeColorByStatus(StageStatus status) {
  switch (status) {
    case StageStatus.pending:
      return Colors.grey;
    case StageStatus.running:
      return Colors.blue;
    case StageStatus.paused:
      return Colors.orange;
    case StageStatus.completed:
      return Colors.green;
    case StageStatus.skipped:
      return Colors.grey.shade400;
    case StageStatus.failed:
      return Colors.red;
  }
}
