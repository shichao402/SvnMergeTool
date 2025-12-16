import 'package:flutter/material.dart';

import '../models/models.dart';

/// Pipeline 阶段列表组件
/// 
/// 垂直显示所有阶段的详细状态
class PipelineStageList extends StatelessWidget {
  /// Pipeline 状态
  final PipelineState state;

  /// 是否可展开
  final bool expandable;

  /// 初始是否展开
  final bool initiallyExpanded;

  const PipelineStageList({
    super.key,
    required this.state,
    this.expandable = true,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final stages = state.config.enabledStages;

    if (stages.isEmpty) {
      return const Center(child: Text('没有阶段'));
    }

    final content = ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stages.length,
      itemBuilder: (context, index) {
        final stage = stages[index];
        final result = state.stageResults[stage.id];
        final isLast = index == stages.length - 1;

        return _StageListItem(
          stage: stage,
          result: result,
          isCurrentStage: state.currentStageIndex == index,
          isLast: isLast,
        );
      },
    );

    if (expandable) {
      return ExpansionTile(
        title: const Text('阶段详情'),
        initiallyExpanded: initiallyExpanded,
        children: [content],
      );
    }

    return content;
  }
}

/// 阶段列表项
class _StageListItem extends StatelessWidget {
  final StageConfig stage;
  final StageResult? result;
  final bool isCurrentStage;
  final bool isLast;

  const _StageListItem({
    required this.stage,
    required this.result,
    required this.isCurrentStage,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = result?.status ?? StageStatus.pending;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间线
          SizedBox(
            width: 40,
            child: Column(
              children: [
                _buildStatusIcon(status, isCurrentStage),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: status.isSuccess ? Colors.green : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          // 右侧内容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 阶段名称和状态
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stage.name,
                          style: TextStyle(
                            fontWeight: isCurrentStage ? FontWeight.bold : FontWeight.normal,
                            color: _getStatusColor(status, theme),
                          ),
                        ),
                      ),
                      _buildStatusBadge(status),
                    ],
                  ),
                  // 阶段描述或脚本路径
                  if (stage.script != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      stage.script!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  // 耗时
                  if (result != null && result!.duration.inMilliseconds > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDuration(result!.duration),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                  // 错误信息
                  if (result?.error != null && result!.error!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        result!.error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(StageStatus status, bool isCurrent) {
    IconData icon;
    Color color;

    switch (status) {
      case StageStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case StageStatus.running:
        icon = Icons.play_circle;
        color = Colors.blue;
        break;
      case StageStatus.paused:
        icon = Icons.pause_circle;
        color = Colors.orange;
        break;
      case StageStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case StageStatus.skipped:
        icon = Icons.skip_next;
        color = Colors.grey;
        break;
      case StageStatus.pending:
        icon = Icons.circle_outlined;
        color = Colors.grey.shade400;
    }

    return Container(
      width: 24,
      height: 24,
      decoration: isCurrent
          ? BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
            )
          : null,
      child: Icon(icon, size: 20, color: color),
    );
  }

  Widget _buildStatusBadge(StageStatus status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case StageStatus.completed:
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade700;
        break;
      case StageStatus.running:
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade700;
        break;
      case StageStatus.paused:
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade700;
        break;
      case StageStatus.failed:
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade700;
        break;
      case StageStatus.skipped:
        bgColor = Colors.grey.shade200;
        textColor = Colors.grey.shade600;
        break;
      case StageStatus.pending:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade500;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getStatusColor(StageStatus status, ThemeData theme) {
    switch (status) {
      case StageStatus.completed:
        return Colors.green.shade700;
      case StageStatus.running:
        return theme.colorScheme.primary;
      case StageStatus.paused:
        return Colors.orange.shade700;
      case StageStatus.failed:
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 1) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
  }
}
