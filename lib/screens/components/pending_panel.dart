/// 待合并面板
///
/// 显示待合并的 revision 列表和操作按钮

import 'package:flutter/material.dart';

/// 是否在标题区显示来源分支文字（仅当传入了非空字符串）。
@visibleForTesting
bool shouldShowSourceLabel(String? sourceLabel) =>
    sourceLabel != null && sourceLabel.isNotEmpty;

/// 是否显示来源分支不一致的橙色警告条。
@visibleForTesting
bool shouldShowSourceWarning(String? sourceWarning) =>
    sourceWarning != null && sourceWarning.isNotEmpty;

/// 是否在标题区显示「清空待合并」按钮。
@visibleForTesting
bool shouldShowClearAction({required List<int> pendingRevisions}) =>
    pendingRevisions.isNotEmpty;

/// 是否显示顶部「添加选中 (N)」按钮（必须有日志列表里被勾选的项）。
@visibleForTesting
bool shouldShowAddButton({required int selectedCount}) => selectedCount > 0;

/// 标题右侧的「N 个」计数文案。
@visibleForTesting
String formatPendingHeaderCount(int count) => '$count 个';

/// 列表中每一项左侧圆形序号的展示文本（基于 0 索引转 1-based）。
@visibleForTesting
String formatPendingItemPosition(int zeroBasedIndex) => '${zeroBasedIndex + 1}';

/// 待合并列表行右侧 close 按钮的 hover tooltip 文案。
///
/// 第十九层 hover 进度披露 / 第二轮回访 pending_panel.dart 维度，
/// 与 Step 22 第二轮回访 config_bar.dart 同源。
///
/// pending 面板每一行右侧有一个 IconButton(Icons.close)，点击会从
/// 待合并列表里移除当前 revision。原本没有 tooltip——用户想知道
/// 即将移除哪一条 revision，得肉眼把 close 图标对齐到行首圆形序号
/// 或行中间的 `r$rev` 标题。当列表较长 / 字号较小时这种对齐成本
/// 不低，是真实的可发现性缺陷。
///
/// 把渲染规格抽到顶层 helper：固定模板 `'从待合并移除 r$revision'`，
/// 让 hover 立刻把"按钮要做什么 + 作用在哪条 revision"两个信息
/// 一起暴露出来，避免视觉对齐成本。
@visibleForTesting
String formatPendingRemoveTooltip(int revision) => '从待合并移除 r$revision';

/// 待合并面板顶部 sourceLabel 的 hover tooltip 文案。
///
/// 第十七层 hover 进度披露，首次扩展到 pending_panel.dart 维度，
/// 与 Step 19 首次扩展到 log_list_panel.dart 同型。
///
/// sourceLabel 由 main_screen_v3.dart 的 `summarizeSourceUrl` 生成：
/// 把完整 SVN URL 切段后，若 segments.length >= 2 则只保留末两段
/// （例：`svn://server/repo/branches/v2` → `branches/v2`），完整路径在
/// `Expanded + TextOverflow.ellipsis` 里被进一步隐藏。Tooltip 在 hover
/// 时把完整 URL 还原出来，方便用户核对来源分支。
///
/// 不在 helper 里调用 `summarizeSourceUrl` 重新计算（违反单点原则），
/// 改由 caller 把 sourceLabel 与 sourceUrl 一起传进来做对照：当
/// summarize 真正裁切了字符（trim 后字面不等）才返回完整 sourceUrl，
/// 其它情形（任一为空、或 trim 后字面相等）一律返回 ''，由调用方判空
/// 决定是否包 Tooltip。
@visibleForTesting
String formatPendingSourceLabelTooltip(String? sourceLabel, String? sourceUrl) {
  if (sourceLabel == null || sourceLabel.isEmpty) return '';
  if (sourceUrl == null) return '';
  final trimmedUrl = sourceUrl.trim();
  if (trimmedUrl.isEmpty) return '';
  if (trimmedUrl == sourceLabel) return '';
  return trimmedUrl;
}

/// 待合并面板
class PendingPanel extends StatelessWidget {
  final List<int> pendingRevisions;
  final int selectedCount;
  final String? sourceLabel;
  final String? sourceUrl;
  final String? sourceWarning;
  final VoidCallback onAddSelected;
  final bool canAddSelected;
  final VoidCallback onClearPending;
  final void Function(int revision) onRemove;
  final VoidCallback onStartMerge;
  final bool canStartMerge;

  /// commit message 附加信息输入框 controller。
  ///
  /// **R133 owner/borrower/disposer 协议**：本 widget 是 **borrower**——只读取
  /// `controller.text` 用于 `TextField` 绑定，**不**调用 `.dispose()`。owner =
  /// `_MainScreenV3State`（创建 + dispose），lifecycle 严格短于 owner。
  ///
  /// **故意不在 onStartMerge 后清空**：批量合并典型场景是同一 CRID 多轮合并，
  /// 每轮清空反而强制用户重输；用户自行判断何时清。
  final TextEditingController? commitSupplementController;

  const PendingPanel({
    super.key,
    required this.pendingRevisions,
    required this.selectedCount,
    this.sourceLabel,
    this.sourceUrl,
    this.sourceWarning,
    required this.onAddSelected,
    required this.canAddSelected,
    required this.onClearPending,
    required this.onRemove,
    required this.onStartMerge,
    required this.canStartMerge,
    this.commitSupplementController,
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
          if (shouldShowSourceWarning(sourceWarning)) _buildWarningBanner(),
          // 添加按钮
          if (shouldShowAddButton(selectedCount: selectedCount))
            _buildAddButton(),
          // 待合并列表
          Expanded(child: _buildList()),
          // commit 附加信息（CRID 等）输入框
          if (commitSupplementController != null) _buildCommitSupplementField(),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('待合并',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (shouldShowSourceLabel(sourceLabel))
                  Builder(
                    builder: (_) {
                      final tooltip = formatPendingSourceLabelTooltip(
                          sourceLabel, sourceUrl);
                      final text = Text(
                        sourceLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                      if (tooltip.isEmpty) return text;
                      return Tooltip(message: tooltip, child: text);
                    },
                  ),
              ],
            ),
          ),
          Text(formatPendingHeaderCount(pendingRevisions.length)),
          if (shouldShowClearAction(pendingRevisions: pendingRevisions)) ...[
            const SizedBox(width: 4),
            IconButton(
              onPressed: onClearPending,
              tooltip: '清空待合并',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.clear_all, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sourceWarning!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ElevatedButton.icon(
        onPressed: canAddSelected ? onAddSelected : null,
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
            Text('选择要合并的 revision',
                style: TextStyle(color: Colors.grey.shade600)),
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
            child: Text(formatPendingItemPosition(index),
                style: const TextStyle(fontSize: 10, color: Colors.white)),
          ),
          title: Text('r$rev',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: formatPendingRemoveTooltip(rev),
            onPressed: () => onRemove(rev),
          ),
        );
      },
    );
  }

  Widget _buildCommitSupplementField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: TextField(
        controller: commitSupplementController,
        minLines: 1,
        maxLines: 3,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          isDense: true,
          labelText: '提交附加信息（可选）',
          hintText: '如 --crid=123456、需求编号等，会拼到 commit message 末尾',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
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
