import 'package:flutter/material.dart';

import '../data/data.dart';
import '../registry/registry.dart';

/// 流图编辑器适配器接口
///
/// 隔离 UI 组件依赖，使得可以替换不同的流图编辑器组件。
abstract class IFlowEditorAdapter<TController, TNode> {
  /// 创建控制器
  TController createController();

  /// 将业务节点数据转换为 UI 节点
  TNode createViewNode(NodeTypeDefinition typeDef, NodeData data);

  /// 从 UI 节点提取节点数据
  NodeData extractNodeData(TNode viewNode);

  /// 添加节点到控制器
  void addNode(TController controller, TNode node);

  /// 移除节点
  void removeNode(TController controller, String nodeId);

  /// 添加连接
  void addConnection(TController controller, ConnectionData connection);

  /// 移除连接
  void removeConnection(TController controller, String connectionId);

  /// 更新节点位置
  void updateNodePosition(TController controller, String nodeId, double x, double y);

  /// 导出为通用格式
  FlowGraphData exportGraph(TController controller);

  /// 从通用格式导入
  void importGraph(TController controller, FlowGraphData graph);

  /// 清空图
  void clearGraph(TController controller);

  /// 构建编辑器 Widget
  Widget buildEditor({
    required TController controller,
    required Widget Function(BuildContext context, TNode node) nodeBuilder,
    void Function(ConnectionData connection)? onConnectionCreated,
    void Function(String connectionId)? onConnectionRemoved,
    void Function(String nodeId)? onNodeSelected,
    void Function(String nodeId, double x, double y)? onNodeMoved,
  });

  /// 释放控制器资源
  void disposeController(TController controller);
}
