import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart' as vyuh;

import '../data/data.dart' as data;
import '../registry/registry.dart';
import 'flow_editor_adapter.dart';
import 'node_layout.dart';

/// Vyuh Node Flow 适配器数据
class VyuhNodeData implements vyuh.NodeData {
  /// 节点类型 ID
  final String typeId;

  /// 节点显示名称
  final String? name;

  /// 节点颜色
  final Color? color;

  /// 节点图标
  final IconData? icon;

  /// 用户配置
  final Map<String, dynamic> config;

  const VyuhNodeData({
    required this.typeId,
    this.name,
    this.color,
    this.icon,
    this.config = const {},
  });

  @override
  vyuh.NodeData clone() => VyuhNodeData(
    typeId: typeId,
    name: name,
    color: color,
    icon: icon,
    config: Map.from(config),
  );
}

/// 连接数据类型别名（我们不需要连接携带额外数据）
typedef VyuhConnectionData = void;

/// Vyuh Node Flow 适配器
///
/// 将 vyuh_node_flow 组件适配到通用接口。
/// 这是创建 vyuh 节点的**唯一入口**，确保节点格式一致。
class VyuhAdapter
    implements IFlowEditorAdapter<vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData>, vyuh.Node<VyuhNodeData>> {
  @override
  vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> createController() {
    return vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData>(
      config: vyuh.NodeFlowConfig(
        snapToGrid: true,
        gridSize: 20,
      ),
    );
  }

  @override
  vyuh.Node<VyuhNodeData> createViewNode(NodeTypeDefinition typeDef, data.NodeData nodeData) {
    final inputNames = typeDef.inputs.map((p) => p.name).toList();
    final outputNames = typeDef.outputs.map((p) => p.name).toList();
    
    final nodeSize = NodeLayout.calculateSize(
      title: typeDef.name,
      inputPortNames: inputNames,
      outputPortNames: outputNames,
    );

    return vyuh.Node<VyuhNodeData>(
      id: nodeData.id,
      type: nodeData.typeId,
      position: Offset(nodeData.x, nodeData.y),
      size: nodeSize,
      data: VyuhNodeData(
        typeId: nodeData.typeId,
        name: typeDef.name,
        color: typeDef.color,
        icon: typeDef.icon,
        config: nodeData.config,
      ),
      inputPorts: _createPorts(typeDef.inputs, typeDef.inputs.length, isInput: true),
      outputPorts: _createPorts(typeDef.outputs, typeDef.outputs.length, isInput: false),
    );
  }

  /// 创建新节点（用于编辑器添加新节点）
  vyuh.Node<VyuhNodeData> createNewNode(NodeTypeDefinition typeDef, {Offset position = const Offset(100, 100)}) {
    final nodeData = data.NodeData(
      id: 'node_${DateTime.now().millisecondsSinceEpoch}',
      typeId: typeDef.typeId,
      x: position.dx,
      y: position.dy,
      config: {},
    );
    return createViewNode(typeDef, nodeData);
  }

  /// 复制节点（用于编辑器复制功能）
  /// 
  /// 创建一个与源节点相同类型和配置的新节点，位置偏移 (30, 30)
  vyuh.Node<VyuhNodeData>? duplicateNode(vyuh.Node<VyuhNodeData> sourceNode) {
    final typeDef = NodeTypeRegistry.instance.get(sourceNode.data.typeId);
    if (typeDef == null) return null;

    final newPosition = Offset(
      sourceNode.position.value.dx + 30,
      sourceNode.position.value.dy + 30,
    );

    final nodeData = data.NodeData(
      id: 'node_${DateTime.now().millisecondsSinceEpoch}',
      typeId: sourceNode.data.typeId,
      x: newPosition.dx,
      y: newPosition.dy,
      config: Map<String, dynamic>.from(sourceNode.data.config),
    );
    return createViewNode(typeDef, nodeData);
  }

  /// 创建端口列表
  List<vyuh.Port> _createPorts(List<PortSpec> specs, int totalPorts, {required bool isInput}) {
    return specs.asMap().entries.map((entry) {
      final index = entry.key;
      final spec = entry.value;
      final offsetY = NodeLayout.calculatePortOffsetY(index, totalPorts);
      
      return vyuh.Port(
        id: spec.id,
        name: spec.name,
        position: isInput ? vyuh.PortPosition.left : vyuh.PortPosition.right,
        type: isInput ? vyuh.PortType.input : vyuh.PortType.output,
        offset: Offset(0, offsetY),
        showLabel: true,  // 启用端口标签
        multiConnections: isInput,  // 输入端口允许多连接，输出端口只能连一个
        shape: spec.role == PortRole.error 
            ? vyuh.MarkerShapes.diamond 
            : vyuh.MarkerShapes.capsuleHalf,
      );
    }).toList();
  }

  @override
  data.NodeData extractNodeData(vyuh.Node<VyuhNodeData> viewNode) {
    return data.NodeData(
      id: viewNode.id,
      typeId: viewNode.data.typeId,
      x: viewNode.position.value.dx,
      y: viewNode.position.value.dy,
      config: viewNode.data.config,
    );
  }

  /// 获取节点数据（用于 UI 显示）
  VyuhNodeData getNodeData(vyuh.Node<VyuhNodeData> node) => node.data;

  @override
  void addNode(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller, vyuh.Node<VyuhNodeData> node) {
    controller.addNode(node);
  }

  @override
  void removeNode(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller, String nodeId) {
    controller.removeNode(nodeId);
  }

  @override
  void addConnection(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller, data.ConnectionData connection) {
    controller.addConnection(vyuh.Connection<VyuhConnectionData>(
      id: connection.id,
      sourceNodeId: connection.sourceNodeId,
      sourcePortId: connection.sourcePortId,
      targetNodeId: connection.targetNodeId,
      targetPortId: connection.targetPortId,
    ));
  }

  @override
  void removeConnection(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller, String connectionId) {
    controller.removeConnection(connectionId);
  }

  @override
  void updateNodePosition(
    vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller,
    String nodeId,
    double x,
    double y,
  ) {
    controller.setNodePosition(nodeId, Offset(x, y));
  }

  @override
  data.FlowGraphData exportGraph(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller) {
    final graph = controller.exportGraph();

    final nodes = graph.nodes.map((n) => data.NodeData(
          id: n.id,
          typeId: n.data.typeId,
          x: n.position.value.dx,
          y: n.position.value.dy,
          config: n.data.config,
        )).toList();

    final connections = graph.connections.map((c) => data.ConnectionData(
          id: c.id,
          sourceNodeId: c.sourceNodeId,
          sourcePortId: c.sourcePortId,
          targetNodeId: c.targetNodeId,
          targetPortId: c.targetPortId,
        )).toList();

    return data.FlowGraphData(
      nodes: nodes,
      connections: connections,
    );
  }

  @override
  void importGraph(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller, data.FlowGraphData graph) {
    controller.clearGraph();

    // 添加节点
    for (final nodeData in graph.nodes) {
      final typeDef = NodeTypeRegistry.instance.get(nodeData.typeId);
      if (typeDef != null) {
        final viewNode = createViewNode(typeDef, nodeData);
        controller.addNode(viewNode);
      }
    }

    // 添加连接
    for (final conn in graph.connections) {
      controller.addConnection(vyuh.Connection<VyuhConnectionData>(
        id: conn.id,
        sourceNodeId: conn.sourceNodeId,
        sourcePortId: conn.sourcePortId,
        targetNodeId: conn.targetNodeId,
        targetPortId: conn.targetPortId,
      ));
    }
  }

  @override
  void clearGraph(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller) {
    controller.clearGraph();
  }

  @override
  Widget buildEditor({
    required vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller,
    required Widget Function(BuildContext context, vyuh.Node<VyuhNodeData> node) nodeBuilder,
    void Function(data.ConnectionData connection)? onConnectionCreated,
    void Function(String connectionId)? onConnectionRemoved,
    void Function(String nodeId)? onNodeSelected,
    void Function(String nodeId, double x, double y)? onNodeMoved,
  }) {
    return vyuh.NodeFlowEditor<VyuhNodeData, VyuhConnectionData>(
      controller: controller,
      behavior: vyuh.NodeFlowBehavior.design,
      theme: vyuh.NodeFlowTheme.light,
      nodeBuilder: (context, node) => nodeBuilder(context, node),
      events: vyuh.NodeFlowEvents(
        connection: vyuh.ConnectionEvents(
          onCreated: onConnectionCreated != null
              ? (conn) {
                  onConnectionCreated(data.ConnectionData(
                    id: conn.id,
                    sourceNodeId: conn.sourceNodeId,
                    sourcePortId: conn.sourcePortId,
                    targetNodeId: conn.targetNodeId,
                    targetPortId: conn.targetPortId,
                  ));
                }
              : null,
        ),
        node: vyuh.NodeEvents(
          onSelected: onNodeSelected != null
              ? (node) {
                  if (node != null) {
                    onNodeSelected(node.id);
                  }
                }
              : null,
          onDragStop: onNodeMoved != null
              ? (node) {
                  onNodeMoved(node.id, node.position.value.dx, node.position.value.dy);
                }
              : null,
        ),
      ),
    );
  }

  @override
  void disposeController(vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> controller) {
    controller.dispose();
  }
}
