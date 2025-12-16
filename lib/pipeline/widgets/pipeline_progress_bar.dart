import 'package:flutter/material.dart';

import '../models/models.dart';

/// Pipeline 进度条组件
/// 
/// 显示横向的阶段进度条，类似安装向导
class PipelineProgressBar extends StatelessWidget {
  /// Pipeline 状态
  final PipelineState state;

  /// 是否显示阶段名称
  final bool showLabels;

  /// 是否紧凑模式
  final bool compact;

  const PipelineProgressBar({
    super.key,
    required this.state,
    this.showLabels = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final stages = state.config.enabledStages;

    if (stages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 进度条
        Row(
          children: [
            for (int i = 0; i < stages.length; i++) ...[
              _buildStageIndicator(context, stages[i], i),
              if (i < stages.length - 1) _buildConnector(context, stages[i]),
            ],
          ],
        ),
        // 标签
        if (showLabels && !compact) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              for (int i = 0; i < stages.length; i++) ...[
                _buildStageLabel(context, stages[i]),
                if (i < stages.length - 1) const Expanded(child: SizedBox()),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// 构建阶段指示器
  Widget _buildStageIndicator(BuildContext context, StageConfig stage, int index) {
    final theme = Theme.of(context);
    final result = state.stageResults[stage.id];
    final status = result?.status ?? StageStatus.pending;
    final isCurrentStage = state.currentStageIndex == index;

    Color color;
    IconData icon;

    switch (status) {
      case StageStatus.completed:
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case StageStatus.running:
        color = theme.colorScheme.primary;
        icon = Icons.play_circle;
        break;
      case StageStatus.paused:
        color = Colors.orange;
        icon = Icons.pause_circle;
        break;
      case StageStatus.failed:
        color = Colors.red;
        icon = Icons.error;
        break;
      case StageStatus.skipped:
        color = Colors.grey;
        icon = Icons.skip_next;
        break;
      case StageStatus.pending:
        color = Colors.grey.shade400;
        icon = Icons.circle_outlined;
    }

    final size = compact ? 20.0 : 28.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrentStage ? color.withOpacity(0.2) : null,
        border: isCurrentStage
            ? Border.all(color: color, width: 2)
            : null,
      ),
      child: Icon(
        icon,
        size: size - 4,
        color: color,
      ),
    );
  }

  /// 构建连接线
  Widget _buildConnector(BuildContext context, StageConfig stage) {
    final result = state.stageResults[stage.id];
    final status = result?.status ?? StageStatus.pending;
    final isCompleted = status == StageStatus.completed || status == StageStatus.skipped;

    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: isCompleted ? Colors.green : Colors.grey.shade300,
      ),
    );
  }

  /// 构建阶段标签
  Widget _buildStageLabel(BuildContext context, StageConfig stage) {
    final theme = Theme.of(context);
    final result = state.stageResults[stage.id];
    final status = result?.status ?? StageStatus.pending;
    final isCurrentStage = state.currentStage?.id == stage.id;

    Color textColor;
    switch (status) {
      case StageStatus.completed:
        textColor = Colors.green;
        break;
      case StageStatus.running:
        textColor = theme.colorScheme.primary;
        break;
      case StageStatus.paused:
        textColor = Colors.orange;
        break;
      case StageStatus.failed:
        textColor = Colors.red;
        break;
      default:
        textColor = Colors.grey;
    }

    return SizedBox(
      width: 60,
      child: Text(
        stage.name,
        style: TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: isCurrentStage ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
