/// 顶部配置栏
///
/// 显示当前源 URL 和目标工作副本的紧凑视图

import 'package:flutter/material.dart';

import '../../models/merge_config.dart';

/// SVN 操作类型
enum SvnOperation {
  update,
  switchBranch,
  revert,
  cleanup,
}

/// 把 SVN 源 URL 渲染成 ConfigBar 顶部标签里的"分支名"短串。
///
/// **契约**（与原 `_ConfigBarState._extractBranchName` 完全一致——本函数只是把它从 widget
/// 内私有方法抬到顶层 + 加测试，不改行为）：
/// - 用 `'/'` 切分 URL，取**末两段**用 `/` 重新连接（例如
///   `'svn://host/repo/branches/v1' → 'branches/v1'`）。
/// - 段数不足 2 → 原样返回 `url`（**不 trim**，与现状保持一致）。
/// - **不**过滤空段（与 `main_screen_v3.dart` 中 `summarizeSourceUrl` 的过滤行为不同）。
///   两个函数边界行为故意不一致，是历史遗留——本轮只锁定现状，不做统一。
@visibleForTesting
String extractBranchDisplayName(String url) {
  final parts = url.split('/');
  if (parts.length >= 2) {
    return parts.sublist(parts.length - 2).join('/');
  }
  return url;
}

/// 把目标工作副本路径渲染成 ConfigBar 顶部标签里的"文件夹名"短串。
///
/// **契约**（与原 `_ConfigBarState._extractFolderName` 完全一致）：
/// - 反斜杠 `\` 替换为正斜杠 `/`（兼容 Windows 路径如 `C:\proj\wc`）。
/// - 末尾连续的 `/` 全部去掉（`/a/b/` → `/a/b`）。
/// - 切段后取**最后一段**作为基础名（`/proj/wc` → `wc`）。
/// - 切段结果为空时回落到 normalize 后的整串（理论不可达，因为 split 至少返回单元素 list；
///   保留是因为原实现里有这条兜底）。
@visibleForTesting
String extractFolderDisplayName(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final parts = normalized.split('/');
  return parts.isNotEmpty ? parts.last : normalized;
}

/// ConfigBar 顶部"源"和"目标"字段在**未配置时**的统一占位文案。
///
/// 顶层常量是为了**强制共享**——原 build() 里 L83/L95 各自硬编码 `'未设置'`，
/// 任何一处改文案另一处就静默不一致（先看到的用户会困惑）。提到常量后单点改动。
@visibleForTesting
const String kConfigBarUnsetPlaceholder = '未设置';

/// 把当前 sourceUrl 渲染成 ConfigBar"源"字段的展示文本。
///
/// **契约**：
/// - sourceUrl 为空 → 返回 [kConfigBarUnsetPlaceholder]
/// - 否则委托 [extractBranchDisplayName] 截取分支段
///
/// **注意**：不 trim sourceUrl——和 [extractBranchDisplayName] 的"原样返回（不 trim）"
/// 边界行为对齐，留给 caller 决定要不要预处理。这与 `summarizeSourceUrl`（main_screen_v3）
/// 的"段内 trim"故意不同。
@visibleForTesting
String formatConfigBarSourceLabel(String sourceUrl) {
  if (sourceUrl.isEmpty) return kConfigBarUnsetPlaceholder;
  return extractBranchDisplayName(sourceUrl);
}

/// 把当前 targetWc 渲染成 ConfigBar"目标"字段的展示文本。
///
/// **契约**：
/// - targetWc 为空 → 返回 [kConfigBarUnsetPlaceholder]
/// - 否则委托 [extractFolderDisplayName] 截尾段（Windows / POSIX 路径分隔符统一处理）
@visibleForTesting
String formatConfigBarTargetLabel(String targetWc) {
  if (targetWc.isEmpty) return kConfigBarUnsetPlaceholder;
  return extractFolderDisplayName(targetWc);
}

/// 精简模式下目标区域的临时工作副本文案。
@visibleForTesting
const String kTemporarySparseTargetHint = '将自动创建临时工作副本';

/// ConfigBar 目标字段按当前模式展示不同语义。
@visibleForTesting
String formatConfigBarEffectiveTargetLabel({
  required TargetConfig targetConfig,
}) {
  if (targetConfig.isFullWorkingCopy) {
    return formatConfigBarTargetLabel(targetConfig.workingCopyPath);
  }
  if (targetConfig.svnUrl.isEmpty) return kConfigBarUnsetPlaceholder;
  return extractBranchDisplayName(targetConfig.svnUrl);
}

/// ConfigBar"源"字段 hover tooltip 文案——展开 [formatConfigBarSourceLabel] 隐藏的完整原始 URL。
///
/// **第十八层 hover 渐进披露**（首次扩展到 `config_bar.dart` 维度——全局配置面板）。
/// `_CompactField` 文本被 [formatConfigBarSourceLabel]（`extractBranchDisplayName` 截到末两段）
/// + UI 层 `TextOverflow.ellipsis` 双重截断，完整 URL 在窄面板下完全不可见；
/// 鼠标悬停在"源: …"字段上即展开原始 URL。
///
/// **契约**（与 Step 21 `formatPendingSourceLabelTooltip` 同型——纯函数，不调用上游 helper 重算）：
/// - sourceUrl 为空字符串 → 返回 `''`（caller 用空串短路不挂 Tooltip，避免空气泡）。
/// - sourceUrl trim 后为空 → 返回 `''`（同上）。
/// - sourceUrl trim 后**字面等于** [formatConfigBarSourceLabel] 的结果 → 返回 `''`
///   （label 已展示完整 URL，重复展示是噪音；dedup 是核心契约，单测显式锁定）。
/// - 其它 → 返回 `sourceUrl.trim()`（保持 trim 与现状对齐——caller 已经在更上层 trim 过，
///   本函数 trim 只是边界双保险）。
///
/// **为什么不调用 `summarizeSourceUrl` 重算**：那是 `main_screen_v3.dart` 的私有 helper，
/// 跨文件依赖会破坏单点原则；此处用"caller-passes-original-url + helper-pure-string-compare"
/// 模式，与 Step 21 完全同型。
@visibleForTesting
String formatConfigBarSourceTooltip(String sourceUrl) {
  final trimmed = sourceUrl.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed == formatConfigBarSourceLabel(sourceUrl)) return '';
  return trimmed;
}

/// ConfigBar"目标"字段 hover tooltip 文案——展开 [formatConfigBarTargetLabel] 隐藏的完整原始路径。
///
/// **第十八层 hover 渐进披露**（与 [formatConfigBarSourceTooltip] 同轮 dual-encode——
/// 一次还原源/目标两个字段）。`_CompactField` 文本被 [formatConfigBarTargetLabel]
/// （`extractFolderDisplayName` 截到尾段）+ UI 层 `TextOverflow.ellipsis` 双重截断，
/// 完整路径（特别是 Windows 长路径如 `C:\dev\projects\xxx\branches\v1\wc`）在窄面板下完全不可见。
///
/// **契约**（与 [formatConfigBarSourceTooltip] 同形态）：
/// - targetWc 为空字符串 → 返回 `''`。
/// - targetWc trim 后为空 → 返回 `''`。
/// - targetWc trim 后**字面等于** [formatConfigBarTargetLabel] 的结果 → 返回 `''`（dedup）。
/// - 其它 → 返回 `targetWc.trim()`。
///
/// **dedup 时机举例**：targetWc == `'wc'`（单段路径）时 label 也是 `'wc'`，trim 后字面相等 → 不挂 Tooltip。
@visibleForTesting
String formatConfigBarTargetTooltip(String targetWc) {
  final trimmed = targetWc.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed == formatConfigBarTargetLabel(targetWc)) return '';
  return trimmed;
}

/// ConfigBar 目标字段按当前模式展示 tooltip。
@visibleForTesting
String formatConfigBarEffectiveTargetTooltip({
  required TargetConfig targetConfig,
}) {
  if (targetConfig.isFullWorkingCopy) {
    return formatConfigBarTargetTooltip(targetConfig.workingCopyPath);
  }
  final trimmed = targetConfig.svnUrl.trim();
  if (trimmed.isEmpty) return kTemporarySparseTargetHint;
  return '$trimmed\n$kTemporarySparseTargetHint（系统临时目录）';
}

/// 是否在 ConfigBar 右侧显示 SVN 操作（更新/还原/清理）菜单按钮。
///
/// **行为契约**（**两个 flag 必须同时满足，且语义独立**——不能合并成"`hasCallback || ...`"
/// 等其它运算符；测试显式覆盖了 truth table 4 个分支）：
/// - `hasCallback == false` → `false`（caller 没注入回调时菜单点了也无意义，**静默隐藏**比
///   "灰显但点击无响应"更利于用户认知，与"未配置"文案的处理一致）。
/// - `targetWc.isEmpty` → `false`（SVN 操作都需要工作副本路径，路径为空时菜单按钮即使可点也跑不出
///   有效命令；同样静默隐藏，避免"点了菜单 → 跑命令 → 报错弹窗"的可避免噪音）。
/// - 两者都满足 → `true`。
/// - **入参约定**：[targetWc] 由 caller 传 ConfigBar 的 `targetWc` 字段原值（不在本函数 trim——
///   保持与 `formatConfigBarTargetLabel` 的"不 trim"边界一致；caller 想 trim 由 caller 决定）。
/// - **为什么用 `hasCallback: bool` 而不是直接接 `VoidCallback?`**：保持本函数纯，避免
///   测试时构造 fake callback 的噪音。caller 在调用点用 `onSvnOperation != null` 派生即可。
@visibleForTesting
bool shouldShowSvnOperationMenu({
  required bool hasCallback,
  required TargetConfig targetConfig,
}) =>
    hasCallback &&
    targetConfig.isFullWorkingCopy &&
    targetConfig.workingCopyPath.isNotEmpty;

/// SVN 操作菜单的单条菜单项渲染描述（紧贴 `LogStatusTagSpec` / `LogSummaryChipSpec`
/// 的 Spec-builder 风格——装配阶段产出 spec 列表，渲染阶段 `map` 到 `PopupMenuItem`）。
///
/// **配色契约**：[titleColor] 仅 `revert` 一项设为 `Colors.orange`，标记**破坏性操作**
/// （撤销本地修改不可逆）；其它两项 `null` 用 Material 默认前景色——这是有意契约，
/// 单测显式锁定"只有 revert 用橙色"，防止未来加新破坏性操作时漏配色。
class SvnOperationMenuItemSpec {
  final SvnOperation operation;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final Color? iconColor;

  const SvnOperationMenuItemSpec({
    required this.operation,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.iconColor,
  });

  @override
  bool operator ==(Object other) =>
      other is SvnOperationMenuItemSpec &&
      other.operation == operation &&
      other.icon == icon &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.titleColor?.toARGB32() == titleColor?.toARGB32() &&
      other.iconColor?.toARGB32() == iconColor?.toARGB32();

  @override
  int get hashCode => Object.hash(
        operation,
        icon,
        title,
        subtitle,
        titleColor?.toARGB32(),
        iconColor?.toARGB32(),
      );

  @override
  String toString() =>
      'SvnOperationMenuItemSpec(operation: $operation, title: $title)';
}

/// 装配 SVN 操作菜单的全部菜单项（顺序固定：**更新 → 切换 → 还原 → 清理**）。
///
/// **行为契约**（与原 ConfigBar.build 内 `itemBuilder` 的字面量列表完全等价——
/// 本函数只是把它从 widget 内剥离 + 加测试，不改任何文案/图标/配色）：
/// - 列表恰好与 [SvnOperation] 的值一一对应；新增 enum 值时如果忘了
///   在此添加菜单项，单测 `菜单项数 == SvnOperation.values.length` 会立刻红。
/// - 顺序固定 `[update, switchBranch, revert, cleanup]`——上层 PopupMenu 直接 `map` 到 `PopupMenuItem`
///   按列表顺序渲染，顺序变更就是视觉变更，必须锁定。
/// - **唯一带前景色的项是 revert**（橙色 `Colors.orange`）：标记破坏性操作。其它两项
///   `titleColor` / `iconColor` 都为 `null`（用 Material 默认色）。这是有意契约，
///   单测显式断言"只有 revert 用橙色"，防止未来加新破坏性操作时漏配色。
@visibleForTesting
List<SvnOperationMenuItemSpec> svnOperationMenuSpecs() {
  return const [
    SvnOperationMenuItemSpec(
      operation: SvnOperation.update,
      icon: Icons.download,
      title: '更新',
      subtitle: '更新工作副本到最新版本',
    ),
    SvnOperationMenuItemSpec(
      operation: SvnOperation.switchBranch,
      icon: Icons.swap_horiz,
      title: '切换',
      subtitle: '切换目标工作副本到其他分支',
    ),
    SvnOperationMenuItemSpec(
      operation: SvnOperation.revert,
      icon: Icons.undo,
      title: '还原',
      subtitle: '撤销所有本地修改',
      titleColor: Colors.orange,
      iconColor: Colors.orange,
    ),
    SvnOperationMenuItemSpec(
      operation: SvnOperation.cleanup,
      icon: Icons.cleaning_services,
      title: '清理',
      subtitle: '清理工作副本',
    ),
  ];
}

/// 顶部配置栏
class ConfigBar extends StatelessWidget {
  final String sourceUrl;
  final TargetConfig targetConfig;
  final VoidCallback onSourceTap;
  final VoidCallback onTargetTap;
  final VoidCallback onSettingsTap;
  final void Function(SvnOperation)? onSvnOperation;
  final ValueChanged<bool>? onTemporarySparseWorkingCopyChanged;

  const ConfigBar({
    super.key,
    required this.sourceUrl,
    required this.targetConfig,
    required this.onSourceTap,
    required this.onTargetTap,
    required this.onSettingsTap,
    this.onSvnOperation,
    this.onTemporarySparseWorkingCopyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTargetLabel = formatConfigBarEffectiveTargetLabel(
      targetConfig: targetConfig,
    );
    final effectiveTargetTooltip = formatConfigBarEffectiveTargetTooltip(
      targetConfig: targetConfig,
    );
    final useTemporarySparseWorkingCopy =
        targetConfig.isTemporarySparseWorkingCopy;
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
              value: formatConfigBarSourceLabel(sourceUrl),
              tooltip: formatConfigBarSourceTooltip(sourceUrl),
              onTap: onSourceTap,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          // 目标配置（完整工作副本模式显示路径；精简模式显示目标 URL）
          Expanded(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CompactField(
                  label: useTemporarySparseWorkingCopy ? '目标 URL' : '目标',
                  value: effectiveTargetLabel,
                  tooltip: effectiveTargetTooltip,
                  onTap: onTargetTap,
                ),
                if (useTemporarySparseWorkingCopy) ...[
                  const SizedBox(height: 3),
                  const Text(
                    '$kTemporarySparseTargetHint（系统临时目录）',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                _TemporarySparseWorkingCopyOption(
                  value: useTemporarySparseWorkingCopy,
                  onChanged: onTemporarySparseWorkingCopyChanged,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // SVN 操作菜单（不常用操作）
          if (shouldShowSvnOperationMenu(
            hasCallback: onSvnOperation != null,
            targetConfig: targetConfig,
          ))
            PopupMenuButton<SvnOperation>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'SVN 操作',
              onSelected: onSvnOperation,
              itemBuilder: (context) => svnOperationMenuSpecs()
                  .map((spec) => PopupMenuItem(
                        value: spec.operation,
                        child: ListTile(
                          leading:
                              Icon(spec.icon, size: 20, color: spec.iconColor),
                          title: Text(spec.title,
                              style: TextStyle(color: spec.titleColor)),
                          subtitle: Text(spec.subtitle,
                              style: const TextStyle(fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ))
                  .toList(),
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

class _TemporarySparseWorkingCopyOption extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _TemporarySparseWorkingCopyOption({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged == null
              ? null
              : (checked) => onChanged!(checked ?? false),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const Flexible(
          child: Text(
            '使用临时精简工作副本（仅检出本次合并需要的路径）',
            style: TextStyle(fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Tooltip(
      message: '适合目标 SVN 仓库很大、磁盘空间有限的场景；复杂目录变更会提示改用完整工作副本。',
      child: label,
    );
  }
}

/// 紧凑字段组件
class _CompactField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  /// hover tooltip 文案（第十八层 hover 渐进披露）。
  ///
  /// caller 用 [formatConfigBarSourceTooltip] / [formatConfigBarTargetTooltip] 派生：
  /// - `null` 或空串 → build 内不挂 Tooltip（避免空气泡）
  /// - 非空 → 包 Tooltip 展开完整原始 URL/路径
  ///
  /// 为什么是 `String?` 而不是 `required String`：保持构造器对未来其它 caller 的弹性
  /// （比如未来加"提交者"字段也用 `_CompactField` 但不需要 tooltip 时无需传入）。
  final String? tooltip;

  const _CompactField({
    required this.label,
    required this.value,
    required this.onTap,
    this.tooltip,
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
              child: Builder(
                builder: (_) {
                  final text = Text(
                    value,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  );
                  final tip = tooltip;
                  if (tip == null || tip.isEmpty) return text;
                  return Tooltip(message: tip, child: text);
                },
              ),
            ),
            const Icon(Icons.edit, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
