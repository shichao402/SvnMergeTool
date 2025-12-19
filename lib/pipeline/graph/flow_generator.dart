/// 流程生成器
/// 
/// 从 FlowDefinition 生成：
/// 1. UI 表现层的 NodeFlowController（用于流程图显示）
/// 2. 执行器可用的节点映射
/// 
/// 设计原则：
/// - 单一数据源：所有生成都基于 FlowDefinition
/// - 一致性保证：UI 和执行使用相同的端口 ID 和连接关系

import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../adapter/node_layout.dart';
import 'stage_data.dart';
import 'stage_definition.dart';

/// 流程生成器
/// 
/// 负责从 FlowDefinition 生成 vyuh_node_flow 需要的数据结构
class FlowGenerator {
  /// 从 FlowDefinition 生成 NodeFlowController
  /// 
  /// 返回的 controller 可以直接用于 NodeFlowWidget 显示，
  /// 也可以传给 GraphExecutor 执行
  static NodeFlowController<StageData> generate(FlowDefinition flow) {
    final controller = NodeFlowController<StageData>();
    
    // 计算节点位置
    final positions = _calculateNodePositions(flow);
    
    // 创建节点
    for (final stage in flow.stages) {
      final node = _createNode(stage, positions[stage.id]!);
      controller.addNode(node);
    }
    
    // 创建连接
    for (final conn in flow.connections) {
      controller.addConnection(Connection(
        id: conn.id,
        sourceNodeId: conn.sourceStageId,
        sourcePortId: conn.sourcePortId,
        targetNodeId: conn.targetStageId,
        targetPortId: conn.targetPortId,
      ));
    }
    
    return controller;
  }
  
  /// 计算节点位置
  /// 
  /// 使用简单的拓扑排序布局：
  /// - 主流程从左到右
  /// - 分支流程在下方
  static Map<String, Offset> _calculateNodePositions(FlowDefinition flow) {
    final positions = <String, Offset>{};
    final visited = <String>{};
    
    // 找到起始节点
    final startStage = flow.startStage;
    if (startStage == null) return positions;
    
    // BFS 布局主流程
    int column = 0;
    final queue = <String>[startStage.id];
    final branchNodes = <String>[];  // 分支节点稍后处理
    
    while (queue.isNotEmpty) {
      final stageId = queue.removeAt(0);
      if (visited.contains(stageId)) continue;
      visited.add(stageId);
      
      // 设置位置
      positions[stageId] = Offset(
        50 + column * NodeLayout.nodeHSpacing,
        100,
      );
      column++;
      
      // 找下一个节点
      final stage = flow.stages.firstWhere((s) => s.id == stageId);
      for (final conn in flow.connections) {
        if (conn.sourceStageId == stageId) {
          if (conn.sourcePortId == 'success') {
            // 成功分支加入主队列
            if (!visited.contains(conn.targetStageId)) {
              queue.add(conn.targetStageId);
            }
          } else {
            // 其他分支稍后处理
            if (!visited.contains(conn.targetStageId)) {
              branchNodes.add(conn.targetStageId);
            }
          }
        }
      }
    }
    
    // 处理分支节点
    int branchRow = 1;
    for (final stageId in branchNodes) {
      if (visited.contains(stageId)) continue;
      visited.add(stageId);
      
      // 找到连接到这个节点的源节点，放在其下方
      Offset? sourcePos;
      for (final conn in flow.connections) {
        if (conn.targetStageId == stageId && positions.containsKey(conn.sourceStageId)) {
          sourcePos = positions[conn.sourceStageId];
          break;
        }
      }
      
      positions[stageId] = Offset(
        sourcePos?.dx ?? 50,
        100 + branchRow * NodeLayout.nodeVSpacing,
      );
      branchRow++;
    }
    
    return positions;
  }
  
  /// 从 StageDefinition 创建 Node
  static Node<StageData> _createNode(StageDefinition stage, Offset position) {
    // 计算节点尺寸
    final inputNames = stage.inputPorts.map((p) => p.name).toList();
    final outputNames = stage.outputPorts.map((p) => p.name).toList();
    final nodeSize = NodeLayout.calculateSize(
      title: stage.name,
      inputPortNames: inputNames,
      outputPortNames: outputNames,
    );
    
    // 创建输入端口
    final inputPorts = <Port>[];
    for (int i = 0; i < stage.inputPorts.length; i++) {
      final portDef = stage.inputPorts[i];
      final yOffset = NodeLayout.calculatePortOffsetY(i, stage.inputPorts.length);
      inputPorts.add(Port(
        id: portDef.id,
        name: portDef.name,
        position: PortPosition.left,
        offset: Offset(0, yOffset),
        type: PortType.input,
        showLabel: true,
        multiConnections: true,  // 输入端口允许多连接
      ));
    }
    
    // 创建输出端口
    final outputPorts = <Port>[];
    for (int i = 0; i < stage.outputPorts.length; i++) {
      final portDef = stage.outputPorts[i];
      final yOffset = NodeLayout.calculatePortOffsetY(i, stage.outputPorts.length);
      outputPorts.add(Port(
        id: portDef.id,
        name: portDef.name,
        position: PortPosition.right,
        offset: Offset(0, yOffset),
        type: PortType.output,
        showLabel: true,
        multiConnections: false,  // 输出端口只能连一个
      ));
    }
    
    return Node<StageData>(
      id: stage.id,
      type: stage.type.name,
      position: position,
      data: stage.toStageData(),
      size: nodeSize,
      inputPorts: inputPorts,
      outputPorts: outputPorts,
    );
  }
}
