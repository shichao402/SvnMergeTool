/// 日志列表面板
///
/// 显示 SVN 日志列表，支持过滤、分页和选择

import 'package:flutter/material.dart';
import '../../models/log_entry.dart';

/// 日志列表面板
class LogListPanel extends StatelessWidget {
  // 数据
  final List<LogEntry> entries;
  final Set<int> selectedRevisions;
  final Set<int> pendingRevisions;
  final Set<int> mergedRevisions;
  final bool isLoading;

  // 过滤
  final TextEditingController authorController;
  final TextEditingController titleController;
  final bool stopOnCopy;
  final void Function(bool) onStopOnCopyChanged;
  final VoidCallback onApplyFilter;
  final VoidCallback onRefresh;

  // 分页
  final int currentPage;
  final int totalPages;
  final bool hasMore;
  final int cachedCount;
  final void Function(int) onPageChanged;

  // 选择
  final void Function(int revision, bool selected) onSelectionChanged;

  const LogListPanel({
    super.key,
    required this.entries,
    required this.selectedRevisions,
    required this.pendingRevisions,
    required this.mergedRevisions,
    required this.isLoading,
    required this.authorController,
    required this.titleController,
    required this.stopOnCopy,
    required this.onStopOnCopyChanged,
    required this.onApplyFilter,
    required this.onRefresh,
    required this.currentPage,
    required this.totalPages,
    required this.hasMore,
    required this.cachedCount,
    required this.onPageChanged,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 过滤栏
        _FilterBar(
          authorController: authorController,
          titleController: titleController,
          stopOnCopy: stopOnCopy,
          isLoading: isLoading,
          onStopOnCopyChanged: onStopOnCopyChanged,
          onApplyFilter: onApplyFilter,
          onRefresh: onRefresh,
        ),
        // 日志列表
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            cacheExtent: 500,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isSelected = selectedRevisions.contains(entry.revision);
              final isPending = pendingRevisions.contains(entry.revision);
              final isMerged = mergedRevisions.contains(entry.revision);

              return _LogEntryTile(
                entry: entry,
                index: index,
                isSelected: isSelected,
                isPending: isPending,
                isMerged: isMerged,
                isLoading: isLoading,
                onSelectionChanged: onSelectionChanged,
              );
            },
          ),
        ),
        // 分页栏
        _PaginationBar(
          currentPage: currentPage,
          totalPages: totalPages,
          hasMore: hasMore,
          cachedCount: cachedCount,
          isLoading: isLoading,
          onPageChanged: onPageChanged,
        ),
      ],
    );
  }
}

/// 过滤栏
class _FilterBar extends StatelessWidget {
  final TextEditingController authorController;
  final TextEditingController titleController;
  final bool stopOnCopy;
  final bool isLoading;
  final void Function(bool) onStopOnCopyChanged;
  final VoidCallback onApplyFilter;
  final VoidCallback onRefresh;

  const _FilterBar({
    required this.authorController,
    required this.titleController,
    required this.stopOnCopy,
    required this.isLoading,
    required this.onStopOnCopyChanged,
    required this.onApplyFilter,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          // 提交者过滤
          SizedBox(
            width: 120,
            child: TextField(
              controller: authorController,
              decoration: const InputDecoration(
                labelText: '提交者',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          // 标题过滤
          SizedBox(
            width: 150,
            child: TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          // 排除分支前记录
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: stopOnCopy,
                onChanged: isLoading ? null : (value) => onStopOnCopyChanged(value ?? false),
              ),
              const Text('排除分支前', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(width: 8),
          // 过滤按钮
          ElevatedButton(
            onPressed: isLoading ? null : onApplyFilter,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('过滤'),
          ),
          const Spacer(),
          // 刷新按钮
          IconButton(
            icon: isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: isLoading ? null : onRefresh,
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }
}

/// 日志条目组件
class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final int index;
  final bool isSelected;
  final bool isPending;
  final bool isMerged;
  final bool isLoading;
  final void Function(int revision, bool selected) onSelectionChanged;

  const _LogEntryTile({
    required this.entry,
    required this.index,
    required this.isSelected,
    required this.isPending,
    required this.isMerged,
    required this.isLoading,
    required this.onSelectionChanged,
  });

  bool get _canSelect => !isMerged && !isPending && !isLoading;

  @override
  Widget build(BuildContext context) {
    Color? tileColor;
    if (isPending) {
      tileColor = Colors.green.shade100;
    } else if (isMerged) {
      tileColor = Colors.grey.shade200;
    } else if (index % 2 == 0) {
      tileColor = Colors.grey.shade50;
    }

    return InkWell(
      onTap: _canSelect ? () => onSelectionChanged(entry.revision, !isSelected) : null,
      child: Container(
        color: isSelected ? Colors.blue.shade50 : tileColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: _canSelect
                  ? (value) => onSelectionChanged(entry.revision, value ?? false)
                  : null,
            ),
            // Revision
            SizedBox(
              width: 60,
              child: Text(
                'r${entry.revision}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isMerged ? Colors.grey : null,
                ),
              ),
            ),
            // 作者
            SizedBox(
              width: 80,
              child: Text(
                entry.author,
                style: TextStyle(
                  fontSize: 12,
                  color: isMerged ? Colors.grey : Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 日期
            SizedBox(
              width: 80,
              child: Text(
                entry.date.substring(0, 10),
                style: TextStyle(
                  fontSize: 11,
                  color: isMerged ? Colors.grey : Colors.grey.shade500,
                ),
              ),
            ),
            // 标题
            Expanded(
              child: Text(
                entry.title,
                style: TextStyle(
                  fontSize: 12,
                  color: isMerged ? Colors.grey : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 状态标签
            if (isMerged) _buildStatusTag('已合并', Colors.grey.shade400),
            if (isPending) _buildStatusTag('待合并', Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }
}

/// 分页栏
class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final bool hasMore;
  final int cachedCount;
  final bool isLoading;
  final void Function(int) onPageChanged;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.hasMore,
    required this.cachedCount,
    required this.isLoading,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page, size: 20),
            onPressed: (currentPage > 0 && !isLoading) ? () => onPageChanged(0) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: (currentPage > 0 && !isLoading) ? () => onPageChanged(currentPage - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${currentPage + 1} / ${totalPages > 0 ? totalPages : "?"}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: (hasMore && !isLoading) ? () => onPageChanged(currentPage + 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 20),
            onPressed: (totalPages > 0 && currentPage < totalPages - 1 && !isLoading)
                ? () => onPageChanged(totalPages - 1)
                : null,
          ),
          const SizedBox(width: 16),
          // 预加载状态
          if (cachedCount > 0)
            Text(
              '已缓存 $cachedCount 条',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }
}
