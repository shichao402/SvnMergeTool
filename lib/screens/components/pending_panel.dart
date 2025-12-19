/// 待合并面板
///
/// 显示待合并的 revision 列表和操作按钮

import 'package:flutter/material.dart';

/// 待合并面板
class PendingPanel extends StatelessWidget {
  final List<int> pendingRevisions;
  final int selectedCount;
  final VoidCallback onAddSelected;
  final void Function(int revision) onRemove;
  final VoidCallback onStartMerge;
  final bool canStartMerge;

  const PendingPanel({
    super.key,
    required this.pendingRevisions,
    required this.selectedCount,
    required this.onAddSelected,
    required this.onRemove,
    required this.onStartMerge,
    required this.canStartMerge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border(left: BorderSide(color: Colors.green.shade200)),
      ),
      child: Column(
        children: [
          // 标题
          _buildHeader(),
          // 添加按钮
          if (selectedCount > 0) _buildAddButton(),
          // 待合并列表
          Expanded(child: _buildList()),
          // 开始合并按钮
          _buildStartButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.green.shade100,
      child: Row(
        children: [
          const Icon(Icons.merge_type, color: Colors.green),
          const SizedBox(width: 8),
          const Text('待合并', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${pendingRevisions.length} 个'),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ElevatedButton.icon(
        onPressed: onAddSelected,
        icon: const Icon(Icons.add, size: 18),
        label: Text('添加选中 ($selectedCount)'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 36),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (pendingRevisions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('选择要合并的 revision', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: pendingRevisions.length,
      itemBuilder: (context, index) {
        final rev = pendingRevisions[index];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 12,
            backgroundColor: Colors.green,
            child: Text('${index + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
          ),
          title: Text('r$rev', style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => onRemove(rev),
          ),
        );
      },
    );
  }

  Widget _buildStartButton() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ElevatedButton.icon(
        onPressed: canStartMerge ? onStartMerge : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('开始合并'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 44),
        ),
      ),
    );
  }
}
