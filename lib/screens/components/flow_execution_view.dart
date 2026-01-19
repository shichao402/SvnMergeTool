/// 流程执行视图
///
/// 在执行阶段显示只读流程图，高亮当前执行的节点
/// 支持节点选择以查看快照详情
library;

import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart' as vyuh;

import '../../pipeline/adapter/vyuh_adapter.dart';
import '../../pipeline/data/data.dart';
import '../../pipeline/engine/engine.dart';
import '../../pipeline/registry/registry.dart';

/// 流程执行视图
/// 
/// 显示只读流程图，高亮当前执行的节点
/// 支持点击节点查看快照详情
class FlowExecutionView extends StatefulWidget {
  /// 流程图数据
  final FlowGraphData flowGraph;

  /// 当前执行的节点 ID
  final String? currentNodeId;

  /// 执行状态
  final ExecutorStatus status;

  /// 节点执行快照
  final ExecutionSnapshots snapshots;

  /// 选中的节点 ID
  final String? selectedNodeId;

  /// 节点选择回调
  final void Function(String? nodeId)? onNodeSelected;

  const FlowExecutionView({
    super.key,
    required this.flowGraph,
    this.currentNodeId,
    required this.status,
    required this.snapshots,
    this.selectedNodeId,
    this.onNodeSelected,
  });

  @override
  State<FlowExecutionView> createState() => _FlowExecutionViewState();
}

class _FlowExecutionViewState extends State<FlowExecutionView> {
  late vyuh.NodeFlowController<VyuhNodeData, VyuhConnectionData> _controller;
  final _adapter = VyuhAdapter();

  @override
  void initState() {
    super.initState();
    _controller = _adapter.createController();
    _loadGraph();
  }

  @override
  void didUpdateWidget(FlowExecutionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果流程图变化，重新加载
    if (oldWidget.flowGraph != widget.flowGraph) {
      _loadGraph();
    }
    // 如果当前节点变化，居中显示
    if (oldWidget.currentNodeId != widget.currentNodeId && widget.currentNodeId != null) {
      _centerOnCurrentNode();
    }
  }

  void _loadGraph() {
    _adapter.importGraph(_controller, widget.flowGraph);
    // 加载完成后居中显示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.fitToView();
      if (widget.currentNodeId != null) {
        _centerOnCurrentNode();
      }
    });
  }

  void _centerOnCurrentNode() {
    if (widget.currentNodeId != null) {
      _controller.centerOnNode(widget.currentNodeId!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return vyuh.NodeFlowViewer<VyuhNodeData, VyuhConnectionData>(
      controller: _controller,
      theme: vyuh.NodeFlowTheme.light,
      nodeBuilder: (context, node) => _buildNodeContent(node),
    );
  }

  /// 构建节点内容
  Widget _buildNodeContent(vyuh.Node<VyuhNodeData> node) {
    final data = node.data;
    final isCurrentNode = node.id == widget.currentNodeId;
    final isSelectedNode = node.id == widget.selectedNodeId;
    final typeDef = NodeTypeRegistry.instance.get(data.typeId);
    final snapshot = widget.snapshots.get(node.id);

    // 根据执行状态和快照状态确定节点样式
    Color backgroundColor;
    Color borderColor;
    double borderWidth;

    if (isCurrentNode) {
      // 当前执行节点
      switch (widget.status) {
        case ExecutorStatus.running:
          backgroundColor = Colors.blue.shade50;
          borderColor = Colors.blue;
          borderWidth = 3;
        case ExecutorStatus.paused:
          backgroundColor = Colors.orange.shade50;
          borderColor = Colors.orange;
          borderWidth = 3;
        case ExecutorStatus.failed:
          backgroundColor = Colors.red.shade50;
          borderColor = Colors.red;
          borderWidth = 3;
        default:
          backgroundColor = Colors.grey.shade100;
          borderColor = Colors.grey;
          borderWidth = 2;
      }
    } else if (snapshot != null) {
      // 已执行的节点，根据快照状态显示
      switch (snapshot.status) {
        case NodeExecutionStatus.completed:
          backgroundColor = Colors.green.shade50;
          borderColor = Colors.green;
          borderWidth = 2;
        case NodeExecutionStatus.failed:
          backgroundColor = Colors.red.shade50;
          borderColor = Colors.red;
          borderWidth = 2;
        case NodeExecutionStatus.skipped:
          backgroundColor = Colors.grey.shade100;
          borderColor = Colors.grey;
          borderWidth = 1;
        default:
          backgroundColor = data.color?.withValues(alpha: 0.1) ?? Colors.grey.shade50;
          borderColor = data.color ?? Colors.grey;
          borderWidth = 1;
      }
    } else {
      // 未执行的普通节点
      backgroundColor = data.color?.withValues(alpha: 0.1) ?? Colors.grey.shade50;
      borderColor = data.color ?? Colors.grey;
      borderWidth = 1;
    }

    // 选中状态额外高亮
    if (isSelectedNode && !isCurrentNode) {
      borderColor = Colors.purple;
      borderWidth = 3;
    }

    return GestureDetector(
      onTap: () {
        // 点击节点时触发选择
        if (widget.onNodeSelected != null) {
          if (widget.selectedNodeId == node.id) {
            // 再次点击取消选择
            widget.onNodeSelected!(null);
          } else {
            widget.onNodeSelected!(node.id);
          }
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: isCurrentNode || isSelectedNode
              ? [
                  BoxShadow(
                    color: borderColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: data.color ?? Colors.grey,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 状态图标
                  _buildStatusIcon(isCurrentNode, snapshot),
                  if (data.icon != null) ...[
                    Icon(data.icon, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      data.name ?? typeDef?.name ?? data.typeId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 快照可用指示器
                  if (snapshot != null) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ],
                ],
              ),
            ),
            // 端口区域（简化显示）
            if (typeDef != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 输入端口
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: typeDef.inputs.map((port) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text(
                            port.name,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        );
                      }).toList(),
                    ),
                    // 输出端口
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: typeDef.outputs.map((port) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text(
                            port.name,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建状态图标
  Widget _buildStatusIcon(bool isCurrentNode, NodeSnapshot? snapshot) {
    if (isCurrentNode && widget.status == ExecutorStatus.running) {
      return const Padding(
        padding: EdgeInsets.only(right: 6),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    if (snapshot != null) {
      IconData icon;
      switch (snapshot.status) {
        case NodeExecutionStatus.completed:
          icon = Icons.check_circle;
        case NodeExecutionStatus.failed:
          icon = Icons.error;
        case NodeExecutionStatus.skipped:
          icon = Icons.skip_next;
        default:
          return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Icon(icon, size: 14, color: Colors.white),
      );
    }

    return const SizedBox.shrink();
  }
}
