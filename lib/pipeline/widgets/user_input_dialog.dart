import 'package:flutter/material.dart';

import '../models/models.dart';

/// 用户输入对话框
/// 
/// 用于 Review 阶段等待用户输入
class UserInputDialog extends StatefulWidget {
  /// 阶段名称
  final String stageName;

  /// 输入配置
  final ReviewInputConfig inputConfig;

  /// 提交回调
  final void Function(String value) onSubmit;

  /// 取消回调
  final VoidCallback onCancel;

  /// 跳过回调
  final VoidCallback? onSkip;

  const UserInputDialog({
    super.key,
    required this.stageName,
    required this.inputConfig,
    required this.onSubmit,
    required this.onCancel,
    this.onSkip,
  });

  @override
  State<UserInputDialog> createState() => _UserInputDialogState();
}

class _UserInputDialogState extends State<UserInputDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.input, color: Colors.blue),
          const SizedBox(width: 8),
          Text(widget.stageName),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.inputConfig.label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.inputConfig.hint,
                errorText: _errorText,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (widget.inputConfig.required && (value == null || value.isEmpty)) {
                  return '此字段为必填项';
                }
                if (widget.inputConfig.validationRegex != null && value != null) {
                  final regex = RegExp(widget.inputConfig.validationRegex!);
                  if (!regex.hasMatch(value)) {
                    return '格式不正确';
                  }
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        // 取消按钮
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消'),
        ),
        // 跳过按钮
        if (widget.onSkip != null && !widget.inputConfig.required)
          TextButton(
            onPressed: widget.onSkip,
            child: const Text('跳过'),
          ),
        // 提交按钮
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      widget.onSubmit(_controller.text);
    }
  }
}

/// 显示用户输入对话框
Future<String?> showUserInputDialog({
  required BuildContext context,
  required String stageName,
  required ReviewInputConfig inputConfig,
  bool canSkip = false,
}) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UserInputDialog(
      stageName: stageName,
      inputConfig: inputConfig,
      onSubmit: (value) => Navigator.of(context).pop(value),
      onCancel: () => Navigator.of(context).pop(null),
      onSkip: canSkip ? () => Navigator.of(context).pop('') : null,
    ),
  );
}
