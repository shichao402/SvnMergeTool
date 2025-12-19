/// 日志查看对话框
///
/// 显示 Pipeline 执行过程中的操作日志

import 'package:flutter/material.dart';

/// 日志查看对话框
class LogDialog extends StatelessWidget {
  final String log;
  final VoidCallback onClear;

  const LogDialog({
    super.key,
    required this.log,
    required this.onClear,
  });

  /// 显示日志对话框
  static Future<void> show({
    required BuildContext context,
    required String log,
    required VoidCallback onClear,
  }) {
    return showDialog(
      context: context,
      builder: (context) => LogDialog(
        log: log,
        onClear: onClear,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.terminal, size: 20),
          const SizedBox(width: 8),
          const Text('操作日志', style: TextStyle(fontSize: 16)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.clear_all, size: 18),
            onPressed: () {
              onClear();
              Navigator.of(context).pop();
            },
            tooltip: '清空',
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              log.isEmpty ? '暂无日志' : log,
              style: const TextStyle(
                color: Colors.white70,
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    );
  }
}
