/// 凭证输入对话框

import 'package:flutter/material.dart';

class CredentialData {
  final String username;
  final String password;

  const CredentialData({
    required this.username,
    required this.password,
  });
}

class CredentialDialog extends StatefulWidget {
  final String svnUrl;

  const CredentialDialog({super.key, required this.svnUrl});

  @override
  State<CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends State<CredentialDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户名不能为空')),
      );
      return;
    }

    Navigator.of(context).pop(
      CredentialData(
        username: username,
        password: password,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 提取服务器地址
    final uri = Uri.tryParse(widget.svnUrl);
    final server = uri?.host ?? widget.svnUrl;

    return AlertDialog(
      title: const Text('SVN 认证'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SVN 服务器需要认证\n服务器: $server'),
            const SizedBox(height: 16),

            // 用户名
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),

            // 密码
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

