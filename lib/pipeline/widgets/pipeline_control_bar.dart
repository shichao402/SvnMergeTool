import 'package:flutter/material.dart';

import '../models/models.dart';

/// Pipeline 控制栏组件
/// 
/// 显示回滚、暂停、跳过、取消等操作按钮
class PipelineControlBar extends StatelessWidget {
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

  const PipelineControlBar({
    super.key,
    required this.state,
    this.canResume = false,
    this.canCancel = false,
    this.canRollback = false,
    this.onResume,
    this.onSkip,
    this.onCancel,
    this.onRollback,
  });

  @override
  Widget build(BuildContext context) {
    final status = state.status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _getBackgroundColor(status),
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          // 状态信息
          Expanded(
            child: _buildStatusInfo(context, status),
          ),
          // 操作按钮
          ..._buildActionButtons(context, status),
        ],
      ),
    );
  }

  Color _getBackgroundColor(PipelineStatus status) {
    switch (status) {
      case PipelineStatus.paused:
        return Colors.orange.shade50;
      case PipelineStatus.failed:
        return Colors.red.shade50;
      case PipelineStatus.completed:
        return Colors.green.shade50;
      default:
        return Colors.grey.shade50;
    }
  }

  Widget _buildStatusInfo(BuildContext context, PipelineStatus status) {
    IconData icon;
    Color color;
    String text;

    switch (status) {
      case PipelineStatus.running:
        icon = Icons.play_circle;
        color = Colors.blue;
        text = '正在执行...';
        break;
      case PipelineStatus.paused:
        icon = Icons.pause_circle;
        color = Colors.orange;
        text = state.pauseReason ?? '已暂停';
        break;
      case PipelineStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        text = '执行完成';
        break;
      case PipelineStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        text = state.error ?? '执行失败';
        break;
      case PipelineStatus.cancelled:
        icon = Icons.cancel;
        color = Colors.grey;
        text = '已取消';
        break;
      case PipelineStatus.rollingBack:
        icon = Icons.refresh;
        color = Colors.orange;
        text = '正在回滚...';
        break;
      default:
        icon = Icons.circle_outlined;
        color = Colors.grey;
        text = '空闲';
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 进度
        if (status == PipelineStatus.running) ...[
          const SizedBox(width: 8),
          Text(
            '${(state.progress * 100).toInt()}%',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
        // 耗时
        if (state.totalDuration.inSeconds > 0) ...[
          const SizedBox(width: 8),
          Text(
            _formatDuration(state.totalDuration),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActionButtons(BuildContext context, PipelineStatus status) {
    final buttons = <Widget>[];

    // 回滚按钮
    if (canRollback && onRollback != null) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onRollback,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('回滚'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
          ),
        ),
      );
      buttons.add(const SizedBox(width: 8));
    }

    // 暂停状态下的按钮
    if (status == PipelineStatus.paused) {
      // 跳过按钮
      if (onSkip != null) {
        buttons.add(
          OutlinedButton.icon(
            onPressed: onSkip,
            icon: const Icon(Icons.skip_next, size: 18),
            label: const Text('跳过'),
          ),
        );
        buttons.add(const SizedBox(width: 8));
      }

      // 继续按钮
      if (canResume && onResume != null) {
        buttons.add(
          ElevatedButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('继续'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        );
        buttons.add(const SizedBox(width: 8));
      }
    }

    // 取消按钮
    if (canCancel && onCancel != null) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('取消'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
          ),
        ),
      );
    }

    return buttons;
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    }
  }
}
