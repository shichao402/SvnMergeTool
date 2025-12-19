import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../graph/stage_data.dart';
import '../models/stage_status.dart';

/// 基于 Graph 的流程图组件
///
/// 使用 vyuh_node_flow 的 NodeFlowViewer 显示流程图
class GraphFlowChart extends StatelessWidget {
  /// 流程控制器
  final NodeFlowController<StageData> controller;

  /// 组件高度
  final double height;

  /// 当前执行的节点 ID
  final String? currentNodeId;

  /// 节点点击回调
  final void Function(String nodeId)? onNodeTap;

  const GraphFlowChart({
    super.key,
    required this.controller,
    this.height = 200,
    this.currentNodeId,
    this.onNodeTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: NodeFlowViewer<StageData>(
        controller: controller,
        nodeBuilder: (context, node) => _buildNode(context, node),
        theme: NodeFlowTheme.light,
        onNodeTap: onNodeTap != null ? (node) => onNodeTap!(node?.id ?? '') : null,
      ),
    );
  }

  /// 构建节点
  Widget _buildNode(BuildContext context, Node<StageData> node) {
    final data = node.data;
    if (data == null) {
      return _buildEmptyNode(node.id);
    }

    final isCurrentNode = node.id == currentNodeId;
    final status = data.status;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _getNodeColor(status, isCurrentNode),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getNodeBorderColor(status, isCurrentNode),
          width: isCurrentNode ? 2 : 1,
        ),
        boxShadow: isCurrentNode
            ? [
                BoxShadow(
                  color: _getNodeBorderColor(status, isCurrentNode)
                      .withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 状态图标
          _buildStatusIcon(status, isCurrentNode),
          const SizedBox(height: 4),
          // 节点名称
          Text(
            data.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isCurrentNode ? FontWeight.bold : FontWeight.normal,
              color: _getTextColor(status),
            ),
          ),
          // 进度条（运行中时显示）
          if (status == StageStatus.running) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: 60,
              child: LinearProgressIndicator(
                value: data.progress > 0 ? data.progress : null,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建空节点
  Widget _buildEmptyNode(String id) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Text(
        id,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  /// 构建状态图标
  Widget _buildStatusIcon(StageStatus status, bool isCurrentNode) {
    IconData icon;
    Color color;

    switch (status) {
      case StageStatus.pending:
        icon = Icons.circle_outlined;
        color = Colors.grey.shade400;
        break;
      case StageStatus.running:
        icon = Icons.play_circle_filled;
        color = Colors.white;
        break;
      case StageStatus.completed:
        icon = Icons.check_circle;
        color = Colors.white;
        break;
      case StageStatus.failed:
        icon = Icons.error;
        color = Colors.white;
        break;
      case StageStatus.skipped:
        icon = Icons.skip_next;
        color = Colors.white70;
        break;
      case StageStatus.paused:
        icon = Icons.pause_circle_filled;
        color = Colors.white;
        break;
    }

    return Icon(
      icon,
      size: isCurrentNode ? 20 : 16,
      color: color,
    );
  }

  /// 获取节点背景色
  Color _getNodeColor(StageStatus status, bool isCurrentNode) {
    switch (status) {
      case StageStatus.pending:
        return Colors.grey.shade100;
      case StageStatus.running:
        return Colors.blue;
      case StageStatus.completed:
        return Colors.green;
      case StageStatus.failed:
        return Colors.red;
      case StageStatus.skipped:
        return Colors.grey;
      case StageStatus.paused:
        return Colors.orange;
    }
  }

  /// 获取节点边框色
  Color _getNodeBorderColor(StageStatus status, bool isCurrentNode) {
    if (isCurrentNode) {
      return Colors.blue.shade700;
    }

    switch (status) {
      case StageStatus.pending:
        return Colors.grey.shade400;
      case StageStatus.running:
        return Colors.blue.shade700;
      case StageStatus.completed:
        return Colors.green.shade700;
      case StageStatus.failed:
        return Colors.red.shade700;
      case StageStatus.skipped:
        return Colors.grey.shade600;
      case StageStatus.paused:
        return Colors.orange.shade700;
    }
  }

  /// 获取文字颜色
  Color _getTextColor(StageStatus status) {
    switch (status) {
      case StageStatus.pending:
        return Colors.grey.shade700;
      default:
        return Colors.white;
    }
  }
}

/// 紧凑版流程图（用于列表显示）
class CompactGraphFlowChart extends StatelessWidget {
  /// 流程控制器
  final NodeFlowController<StageData> controller;

  /// 当前执行的节点 ID
  final String? currentNodeId;

  const CompactGraphFlowChart({
    super.key,
    required this.controller,
    this.currentNodeId,
  });

  @override
  Widget build(BuildContext context) {
    // 获取所有节点并按位置排序
    final nodes = controller.nodes.values.toList()
      ..sort((a, b) => a.position.value.dx.compareTo(b.position.value.dx));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < nodes.length; i++) ...[
            _buildCompactNode(nodes[i]),
            if (i < nodes.length - 1) _buildArrow(),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactNode(Node<StageData> node) {
    final data = node.data!;
    final status = data.status;
    final isCurrentNode = node.id == currentNodeId;

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: _getNodeColor(status),
        shape: BoxShape.circle,
        border: isCurrentNode
            ? Border.all(color: Colors.blue.shade700, width: 2)
            : null,
      ),
      child: Center(
        child: Icon(
          _getStatusIcon(status),
          size: 14,
          color: status == StageStatus.pending
              ? Colors.grey.shade600
              : Colors.white,
        ),
      ),
    );
  }

  Widget _buildArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(
        Icons.arrow_forward,
        size: 12,
        color: Colors.grey.shade400,
      ),
    );
  }

  Color _getNodeColor(StageStatus status) {
    switch (status) {
      case StageStatus.pending:
        return Colors.grey.shade200;
      case StageStatus.running:
        return Colors.blue;
      case StageStatus.completed:
        return Colors.green;
      case StageStatus.failed:
        return Colors.red;
      case StageStatus.skipped:
        return Colors.grey;
      case StageStatus.paused:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(StageStatus status) {
    switch (status) {
      case StageStatus.pending:
        return Icons.circle_outlined;
      case StageStatus.running:
        return Icons.play_arrow;
      case StageStatus.completed:
        return Icons.check;
      case StageStatus.failed:
        return Icons.close;
      case StageStatus.skipped:
        return Icons.skip_next;
      case StageStatus.paused:
        return Icons.pause;
    }
  }
}
