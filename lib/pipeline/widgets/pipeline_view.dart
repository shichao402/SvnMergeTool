import 'package:flutter/material.dart';

import '../models/models.dart';
import 'pipeline_control_bar.dart';
import 'pipeline_progress_bar.dart';
import 'pipeline_stage_list.dart';

/// Pipeline 视图组件
/// 
/// 组合进度条、阶段列表和控制栏的完整视图
class PipelineView extends StatelessWidget {
  /// Pipeline 状态
  final PipelineState state;

  /// 是否可以继续
  final bool canResume;

  /// 是否可以取消
  final bool canCancel;

  /// 是否可以回滚
  final bool canRollback;

  /// 继续回调
  final VoidCallback? onResume;

  /// 跳过回调
  final VoidCallback? onSkip;

  /// 取消回调
  final VoidCallback? onCancel;

  /// 回滚回调
  final VoidCallback? onRollback;

  /// 是否显示阶段详情
  final bool showStageDetails;

  /// 是否紧凑模式
  final bool compact;

  const PipelineView({
    super.key,
    required this.state,
    this.canResume = false,
    this.canCancel = false,
    this.canRollback = false,
    this.onResume,
    this.onSkip,
    this.onCancel,
    this.onRollback,
    this.showStageDetails = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 进度条
        Container(
          padding: EdgeInsets.all(compact ? 8 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pipeline: ${state.config.name}',
                      style: TextStyle(
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 进度百分比
                  Text(
                    '${(state.progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 12),
              // 进度条
              PipelineProgressBar(
                state: state,
                showLabels: !compact,
                compact: compact,
              ),
            ],
          ),
        ),
        // 阶段详情
        if (showStageDetails) ...[
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PipelineStageList(
                state: state,
                expandable: false,
              ),
            ),
          ),
        ],
        // 控制栏
        if (!state.status.isTerminal || state.status == PipelineStatus.paused)
          PipelineControlBar(
            state: state,
            canResume: canResume,
            canCancel: canCancel,
            canRollback: canRollback,
            onResume: onResume,
            onSkip: onSkip,
            onCancel: onCancel,
            onRollback: onRollback,
          ),
      ],
    );
  }
}

/// 紧凑的 Pipeline 状态卡片
/// 
/// 用于在列表中显示 Pipeline 状态摘要
class PipelineStatusCard extends StatelessWidget {
  /// Pipeline 状态
  final PipelineState state;

  /// 点击回调
  final VoidCallback? onTap;

  const PipelineStatusCard({
    super.key,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和状态
              Row(
                children: [
                  Expanded(
                    child: Text(
                      state.config.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _buildStatusChip(state.status),
                ],
              ),
              const SizedBox(height: 8),
              // 进度条
              PipelineProgressBar(
                state: state,
                showLabels: false,
                compact: true,
              ),
              const SizedBox(height: 8),
              // 当前阶段
              if (state.currentStage != null)
                Text(
                  '当前: ${state.currentStage!.name}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(PipelineStatus status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case PipelineStatus.running:
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade700;
        break;
      case PipelineStatus.paused:
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade700;
        break;
      case PipelineStatus.completed:
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade700;
        break;
      case PipelineStatus.failed:
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade700;
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade600;
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
}
