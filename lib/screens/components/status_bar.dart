/// 底部状态栏
///
/// 显示当前状态和日志查看入口
library;

import 'package:flutter/material.dart';
import '../../execution/executor_status.dart';

/// 底部状态栏左侧的简短状态文案。
///
/// 注意：与 `executorStatusMessage` 是不同的展示文案集（后者用于执行面板顶部，
/// 文案更具引导性），状态栏这里偏向「一目了然」。
@visibleForTesting
String statusBarStatusText(ExecutorStatus status) {
  switch (status) {
    case ExecutorStatus.idle:
      return '就绪';
    case ExecutorStatus.running:
      return '运行中';
    case ExecutorStatus.paused:
      return '等待处理';
    case ExecutorStatus.completed:
      return '已完成';
  }
}

/// 状态栏左侧的图标：执行中显示旋转箭头，其它状态显示通用 info。
@visibleForTesting
IconData statusBarStatusIcon(ExecutorStatus status) =>
    status == ExecutorStatus.running ? Icons.sync : Icons.info_outline;

/// 状态栏左侧 status icon + 文案 hover 时的扩展语义提示。
///
/// 设计目标：`statusBarStatusText` 是一目了然的两到四字短文（如「就绪」「等待处理」），
/// 但用户在「等待处理」语义下常常困惑「我到底要做什么」、在「已完成」时也希望
/// 确认「整批是否真的全部跑完」——hover 给出一句更具引导性的扩展说明，避免与
/// 顶部 `executorStatusMessage` 文案重复（顶部偏行动指引，这里偏状态语义）。
@visibleForTesting
String statusBarStatusTooltip(ExecutorStatus status) {
  switch (status) {
    case ExecutorStatus.idle:
      return '就绪 · 当前无任务运行，可点「开始」启动';
    case ExecutorStatus.running:
      return '运行中 · 正在执行队列任务，请稍候';
    case ExecutorStatus.paused:
      return '等待处理 · 存在暂停或失败任务，处理完后可继续';
    case ExecutorStatus.completed:
      return '已完成 · 队列内任务全部结束';
  }
}

/// 状态栏右侧「日志」按钮 hover 时的提示。
///
/// 当 `hasLog == false` 时按钮被禁用，但用户没有任何反馈——这里用 hover 解释
/// 「为什么按不动」，避免用户反复点击。
@visibleForTesting
String statusBarLogButtonTooltip({required bool hasLog}) {
  if (!hasLog) {
    return '暂无可查看的日志 · 任务执行后将自动产生';
  }
  return '查看最近一次任务的日志输出';
}

/// 底部状态栏
class StatusBar extends StatelessWidget {
  final ExecutorStatus status;
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
          // 状态信息（hover 给出扩展语义）
          Tooltip(
            message: statusBarStatusTooltip(status),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  statusBarStatusIcon(status),
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  statusBarStatusText(status),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const Spacer(),
          // 查看日志按钮（hover 解释 enabled/disabled 原因）
          Tooltip(
            message: statusBarLogButtonTooltip(hasLog: hasLog),
            child: TextButton.icon(
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
          ),
        ],
      ),
    );
  }
}
