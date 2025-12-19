/// 用户输入对话框
///
/// 用于 Pipeline 执行过程中需要用户输入的场景（如 CRID）

import 'package:flutter/material.dart';
import '../../../pipeline/pipeline.dart';

/// 用户输入对话框
class InputDialog extends StatefulWidget {
  final ReviewInputConfig inputConfig;
  final void Function(String value) onSubmit;
  final VoidCallback onSkip;

  const InputDialog({
    super.key,
    required this.inputConfig,
    required this.onSubmit,
    required this.onSkip,
  });

  /// 显示输入对话框
  static Future<void> show({
    required BuildContext context,
    required ReviewInputConfig inputConfig,
    required void Function(String value) onSubmit,
    required VoidCallback onSkip,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => InputDialog(
        inputConfig: inputConfig,
        onSubmit: onSubmit,
        onSkip: onSkip,
      ),
    );
  }

  @override
  State<InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<InputDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();

    // 验证必填
    if (widget.inputConfig.required && value.isEmpty) {
      setState(() => _error = '此项为必填');
      return;
    }

    // 验证格式
    if (widget.inputConfig.validationRegex != null && value.isNotEmpty) {
      try {
        final regex = RegExp(widget.inputConfig.validationRegex!);
        if (!regex.hasMatch(value)) {
          setState(() => _error = '格式不正确');
          return;
        }
      } catch (_) {}
    }

    Navigator.of(context).pop();
    widget.onSubmit(value);
  }

  void _skip() {
    Navigator.of(context).pop();
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_note, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.inputConfig.label,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.inputConfig.hint != null) ...[
              Text(
                widget.inputConfig.hint!,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '请输入${widget.inputConfig.label}',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _skip,
          child: const Text('跳过'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
