/// 底部状态栏
///
/// 显示当前状态和日志查看入口

import 'package:flutter/material.dart';
import '../../pipeline/pipeline.dart';

/// 底部状态栏
class StatusBar extends StatelessWidget {
  final GraphExecutorStatus status;
  final bool hasLog;
  final VoidCallback onViewLog;

  const StatusBar({
    super.key,
    required this.status,
    required this.hasLog,
    required this.onViewLog,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          // 状态信息
          Icon(
            status == GraphExecutorStatus.running ? Icons.sync : Icons.info_outline,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 6),
          Text(
            _statusText,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const Spacer(),
          // 查看日志按钮
          TextButton.icon(
            onPressed: hasLog ? onViewLog : null,
            icon: Icon(
              Icons.terminal,
              size: 16,
              color: hasLog ? Colors.grey.shade700 : Colors.grey.shade400,
            ),
            label: Text(
              '日志',
              style: TextStyle(
                fontSize: 12,
                color: hasLog ? Colors.grey.shade700 : Colors.grey.shade400,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  String get _statusText {
    switch (status) {
      case GraphExecutorStatus.idle:
        return '就绪';
      case GraphExecutorStatus.running:
        return '运行中';
      case GraphExecutorStatus.paused:
        return '已暂停';
      case GraphExecutorStatus.completed:
        return '已完成';
      case GraphExecutorStatus.failed:
        return '失败';
      case GraphExecutorStatus.cancelled:
        return '已取消';
    }
  }
}
