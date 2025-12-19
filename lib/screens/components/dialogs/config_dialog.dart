/// 配置对话框
///
/// 用于编辑源 URL 和目标工作副本

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

/// 配置对话框
class ConfigDialog extends StatelessWidget {
  final TextEditingController sourceUrlController;
  final TextEditingController targetWcController;
  final List<String> sourceUrlHistory;
  final List<String> targetWcHistory;
  final VoidCallback onConfirm;

  const ConfigDialog({
    super.key,
    required this.sourceUrlController,
    required this.targetWcController,
    required this.sourceUrlHistory,
    required this.targetWcHistory,
    required this.onConfirm,
  });

  /// 显示配置对话框
  static Future<bool?> show({
    required BuildContext context,
    required TextEditingController sourceUrlController,
    required TextEditingController targetWcController,
    required List<String> sourceUrlHistory,
    required List<String> targetWcHistory,
    required VoidCallback onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ConfigDialog(
        sourceUrlController: sourceUrlController,
        targetWcController: targetWcController,
        sourceUrlHistory: sourceUrlHistory,
        targetWcHistory: targetWcHistory,
        onConfirm: onConfirm,
      ),
    );
  }

  Future<void> _pickTargetWc(BuildContext context) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      targetWcController.text = result;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 源 URL
            TextField(
              controller: sourceUrlController,
              decoration: InputDecoration(
                labelText: '源 URL',
                border: const OutlineInputBorder(),
                suffixIcon: sourceUrlHistory.isNotEmpty
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (value) {
                          sourceUrlController.text = value;
                        },
                        itemBuilder: (context) => sourceUrlHistory
                            .map((url) => PopupMenuItem(
                                  value: url,
                                  child: Text(url, style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            // 目标工作副本
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: targetWcController,
                    decoration: InputDecoration(
                      labelText: '目标工作副本',
                      border: const OutlineInputBorder(),
                      suffixIcon: targetWcHistory.isNotEmpty
                          ? PopupMenuButton<String>(
                              icon: const Icon(Icons.arrow_drop_down),
                              onSelected: (value) {
                                targetWcController.text = value;
                              },
                              itemBuilder: (context) => targetWcHistory
                                  .map((wc) => PopupMenuItem(
                                        value: wc,
                                        child: Text(wc, style: const TextStyle(fontSize: 12)),
                                      ))
                                  .toList(),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _pickTargetWc(context),
                  child: const Text('选择...'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            onConfirm();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
