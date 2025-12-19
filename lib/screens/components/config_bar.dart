/// 顶部配置栏
///
/// 显示当前源 URL 和目标工作副本的紧凑视图

import 'package:flutter/material.dart';

/// SVN 操作类型
enum SvnOperation {
  update,
  revert,
  cleanup,
}

/// 顶部配置栏
class ConfigBar extends StatelessWidget {
  final String sourceUrl;
  final String targetWc;
  final VoidCallback onConfigTap;
  final VoidCallback onSettingsTap;
  final void Function(SvnOperation)? onSvnOperation;

  const ConfigBar({
    super.key,
    required this.sourceUrl,
    required this.targetWc,
    required this.onConfigTap,
    required this.onSettingsTap,
    this.onSvnOperation,
  });

  String _extractBranchName(String url) {
    final parts = url.split('/');
    if (parts.length >= 2) {
      return parts.sublist(parts.length - 2).join('/');
    }
    return url;
  }

  String _extractFolderName(String path) {
    final parts = path.split('/');
    return parts.isNotEmpty ? parts.last : path;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          // 源 URL（紧凑显示）
          Expanded(
            flex: 2,
            child: _CompactField(
              label: '源',
              value: sourceUrl.isEmpty ? '未设置' : _extractBranchName(sourceUrl),
              onTap: onConfigTap,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          // 目标工作副本（紧凑显示）
          Expanded(
            flex: 2,
            child: _CompactField(
              label: '目标',
              value: targetWc.isEmpty ? '未设置' : _extractFolderName(targetWc),
              onTap: onConfigTap,
            ),
          ),
          const SizedBox(width: 8),
          // SVN 操作菜单（不常用操作）
          if (onSvnOperation != null && targetWc.isNotEmpty)
            PopupMenuButton<SvnOperation>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'SVN 操作',
              onSelected: onSvnOperation,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: SvnOperation.update,
                  child: ListTile(
                    leading: Icon(Icons.download, size: 20),
                    title: Text('Update'),
                    subtitle: Text('更新工作副本到最新版本', style: TextStyle(fontSize: 11)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: SvnOperation.revert,
                  child: ListTile(
                    leading: Icon(Icons.undo, size: 20, color: Colors.orange),
                    title: Text('Revert', style: TextStyle(color: Colors.orange)),
                    subtitle: Text('撤销所有本地修改', style: TextStyle(fontSize: 11)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: SvnOperation.cleanup,
                  child: ListTile(
                    leading: Icon(Icons.cleaning_services, size: 20),
                    title: Text('Cleanup'),
                    subtitle: Text('清理工作副本', style: TextStyle(fontSize: 11)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            onPressed: onSettingsTap,
            tooltip: '设置',
          ),
        ],
      ),
    );
  }
}

/// 紧凑字段组件
class _CompactField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _CompactField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Text(
              '$label: ',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.edit, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
