/// SVN 分支切换对话框
///
/// 支持从历史分支 URL 选择，也支持在线浏览仓库目录后选择目标分支。

import 'package:flutter/material.dart';

import 'config_dialog.dart' show UrlInputFormatter, stripUrlWhitespace;

String trimSvnUrlTrailingSlash(String url) {
  return url.trim().replaceAll(RegExp(r'/+$'), '');
}

String joinSvnUrl(String baseUrl, String childName) {
  final base = trimSvnUrlTrailingSlash(baseUrl);
  final child = childName.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  if (base.isEmpty) return child;
  if (child.isEmpty) return base;
  return '$base/$child';
}

String? parentSvnUrl(String url) {
  final normalized = trimSvnUrlTrailingSlash(url);
  if (normalized.isEmpty) return null;

  final schemeIndex = normalized.indexOf('://');
  final firstPathSlash = schemeIndex >= 0
      ? normalized.indexOf('/', schemeIndex + 3)
      : normalized.indexOf('/');
  final lastSlash = normalized.lastIndexOf('/');
  if (lastSlash <= 0) return null;
  if (firstPathSlash >= 0 && lastSlash <= firstPathSlash) return null;
  return normalized.substring(0, lastSlash);
}

typedef RepositoryListLoader = Future<List<String>> Function(String url);

class SwitchBranchDialog extends StatefulWidget {
  final String currentTargetUrl;
  final String initialBrowseUrl;
  final List<String> branchHistory;
  final RepositoryListLoader onLoadRepository;

  const SwitchBranchDialog({
    super.key,
    required this.currentTargetUrl,
    required this.initialBrowseUrl,
    required this.branchHistory,
    required this.onLoadRepository,
  });

  static Future<String?> show({
    required BuildContext context,
    required String currentTargetUrl,
    required String initialBrowseUrl,
    required List<String> branchHistory,
    required RepositoryListLoader onLoadRepository,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SwitchBranchDialog(
        currentTargetUrl: currentTargetUrl,
        initialBrowseUrl: initialBrowseUrl,
        branchHistory: branchHistory,
        onLoadRepository: onLoadRepository,
      ),
    );
  }

  @override
  State<SwitchBranchDialog> createState() => _SwitchBranchDialogState();
}

class _SwitchBranchDialogState extends State<SwitchBranchDialog> {
  late final TextEditingController _targetUrlController;
  late final TextEditingController _browseUrlController;
  List<String> _entries = const [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetUrlController = TextEditingController(
      text: stripUrlWhitespace(widget.currentTargetUrl),
    );
    _browseUrlController = TextEditingController(
      text: stripUrlWhitespace(widget.initialBrowseUrl),
    );

    final initialBrowseUrl = _browseUrlController.text.trim();
    if (initialBrowseUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRepository(initialBrowseUrl);
        }
      });
    }
  }

  @override
  void dispose() {
    _targetUrlController.dispose();
    _browseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadRepository(String url) async {
    final normalized = stripUrlWhitespace(url);
    if (normalized.isEmpty) {
      setState(() {
        _entries = const [];
        _error = '请输入仓库目录 URL';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _browseUrlController.text = normalized;
    });

    try {
      final entries = await widget.onLoadRepository(normalized);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = '读取仓库目录失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openChild(String entry) async {
    final childUrl = joinSvnUrl(_browseUrlController.text, entry);
    _targetUrlController.text = childUrl;
    if (entry.endsWith('/')) {
      await _loadRepository(childUrl);
    }
  }

  Future<void> _openParent() async {
    final parent = parentSvnUrl(_browseUrlController.text);
    if (parent != null) {
      await _loadRepository(parent);
    }
  }

  void _useCurrentBrowseUrl() {
    _targetUrlController.text =
        trimSvnUrlTrailingSlash(_browseUrlController.text);
  }

  void _confirm() {
    final targetUrl = stripUrlWhitespace(_targetUrlController.text);
    if (targetUrl.isEmpty) {
      setState(() => _error = '请选择或输入要切换到的分支 URL');
      return;
    }
    Navigator.of(context).pop(targetUrl);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('切换目标分支'),
      content: SizedBox(
        width: 760,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _targetUrlController,
              inputFormatters: const [UrlInputFormatter()],
              decoration: InputDecoration(
                labelText: '切换到 URL',
                helperText: '可手动输入、选择历史分支，或从下方在线仓库浏览中选择',
                border: const OutlineInputBorder(),
                suffixIcon: widget.branchHistory.isNotEmpty
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.history),
                        onSelected: (value) {
                          _targetUrlController.text = stripUrlWhitespace(value);
                        },
                        itemBuilder: (context) => widget.branchHistory
                            .map((url) => PopupMenuItem(
                                  value: url,
                                  child: Text(
                                    url,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ))
                            .toList(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _browseUrlController,
                    inputFormatters: const [UrlInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: '在线仓库浏览路径',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _loadRepository,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _loadRepository(_browseUrlController.text),
                  child: const Text('加载'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isLoading ? null : _openParent,
                  child: const Text('上一级'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _useCurrentBrowseUrl,
                  child: const Text('使用当前目录'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _entries.isEmpty
                        ? const Center(child: Text('暂无目录项'))
                        : ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = _entries[index];
                              final isDirectory = entry.endsWith('/');
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isDirectory
                                      ? Icons.folder
                                      : Icons.insert_drive_file,
                                  color: isDirectory ? Colors.amber : null,
                                ),
                                title: Text(entry),
                                subtitle: Text(
                                  joinSvnUrl(_browseUrlController.text, entry),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: isDirectory
                                    ? const Text('进入')
                                    : const Text('选择'),
                                onTap: () => _openChild(entry),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _confirm,
          child: const Text('确定切换'),
        ),
      ],
    );
  }
}
