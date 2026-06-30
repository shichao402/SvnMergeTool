/// 日志列表面板
///
/// 显示 SVN 日志列表，支持过滤、分页和选择

import 'package:flutter/material.dart';

import '../../models/log_entry.dart';

/// 日志条目是否可被勾选/点选。
///
/// 已合并、已加入待合并队列或正在加载时禁用交互；其它情况均可选。
@visibleForTesting
bool canSelectLogEntry({
  required bool isMerged,
  required bool isPending,
  required bool isLoading,
}) =>
    !isMerged && !isPending && !isLoading;

/// 日志条目行 commit 标题（[LogEntry.title]）的 hover tooltip。
///
/// **进度披露第十五层（Step 5→6→7→8→9→10→11→12→13→14→15→16→17→18→19）**：本轮把
/// hover dual-encode 模式**首次扩到 `log_list_panel.dart` 维度**——SVN 合并选择阶段
/// 的核心交互面板。
///
/// **截断现状**：[LogEntry.title] 由 [extractMessageFirstLine] 取自 [LogEntry.message]
/// 的第一行（`message.split('\n').first`），而 [_LogEntryTile] 把 title 渲染在
/// `Expanded` 列里 + `TextOverflow.ellipsis` —— 如果 commit message 是多行（典型形态：
/// 标题行 + 空行 + 段落正文），用户在列表里**永远看不到正文段落**，必须勾选后再到
/// 别处看 `entry.message`。这是合并 revision 决策时的关键信号丢失。
///
/// **本 tooltip 仅在多行 message 档位触发**（`message.contains('\n')`），返回完整
/// `message`（不 trim、不截断、不附加前缀）；其它档位（单行 message：title == message
/// 字面相等 → 列表已完整渲染）返回 `''`，由 caller `isEmpty` 检查决定是否包 [Tooltip]。
///
/// **为什么是 message 而非 title**：title 是 message 第一行的派生量；列表里看到的就是
/// 第一行字面，再 hover 显示同样的第一行没有 added value（与 Step 8/13 single-line dedup
/// 同源："helper 已渲染等价信息 → tooltip 不重复"）。tooltip 的价值在于**还原 helper
/// 截断前的原始正文**，与 Step 11 [formatJobErrorTooltip] 还原原始 stderr 同型。
///
/// **为什么不展开 author / date / revision**：那三段都是固定宽度 SizedBox 渲染、列表
/// 本身已完整可见（最多被 author 列 80px 的 ellipsis 截掉，但中文 commit 作者名通常 ≤4 字
/// 即 ≤48px，触发 ellipsis 的概率极低，且与 message 多行截断不在一个量级）—— **聚焦
/// 单点信号丢失**（与 Step 13/15/16/17/18 单点聚焦同源决策）。
///
/// **空 message 防御性 → ''**：理论上 [LogEntry] 由 SVN log 解析得到、message 永远非空，
/// 但本 helper 不依赖该不变量；空 message 直接返回 `''`，与 Step 8/9/10/11/12/13/14/15/
/// 16/17/18 的"无附加信息 → ''"契约同源（caller 不渲染 Tooltip）。
///
/// **不带"完整 commit message:"前缀**：tooltip 浮出的就是裸 message 文本——用户视觉上
/// 已经从"列表 ellipsis 一行"切换到"浮层多行"，前缀反而是噪音；与 Step 11 的
/// `'<status>: <error>'` 前缀有 status 维度不同（那里需要叠加状态名 dual-encode），
/// 本 helper 仅做"截断还原"单一维度。
@visibleForTesting
String formatLogEntryTitleTooltip(LogEntry entry) {
  final message = entry.message;
  if (message.isEmpty) return '';
  if (!message.contains('\n')) return '';
  return message;
}

/// 日志条目行的背景色。
///
/// 优先级：选中 > 待合并 > 已合并 > 偶数行斑马底色 > null（透明）。
/// 与 `_LogEntryTile.build` 中原始三层 `if/else if` 分支严格等价。
@visibleForTesting
Color? logEntryTileColor({
  required bool isSelected,
  required bool isPending,
  required bool isMerged,
  required int index,
}) {
  if (isSelected) return Colors.blue.shade50;
  if (isPending) return Colors.green.shade100;
  if (isMerged) return Colors.grey.shade200;
  if (index % 2 == 0) return Colors.grey.shade50;
  return null;
}

/// 「首页」按钮启用条件——`canGoPrevPage` 的语义别名。
///
/// **R91 收敛**：原本 `canGoFirstPage` 与 [canGoPrevPage] 的实现逐字相同
/// （`currentPage > 0 && !isLoading`），且 `canGoPrevPage` 的 doc 显式说明
/// "与「首页」一致"——这是早期抽 helper 时为 callsite 自描述而保留的同义双
/// helper。R91 改为 delegate：`canGoPrevPage` 是唯一逻辑源，本 helper 仅作语义
/// 别名供 line 812 「首页」按钮的 callsite 使用。
///
/// **为什么保留本 helper 而不是直接调 [canGoPrevPage]**：line 812 的 callsite
/// 是「首页」按钮的 onPressed 守卫，写 `canGoPrevPage(...)` 会让 reviewer 困惑
///（"为什么首页按钮调 canGoPrev"）。语义别名让 callsite 保留自描述能力，
/// 同时通过 delegate 显式编码"首页 ⇔ 上一页"的等价。这是项目内首次用"语义
/// 别名 + delegate"模式收敛同义双 helper。
///
/// **真值表与 [canGoPrevPage] 完全一致**——配套 `test/log_list_panel_test.dart`
/// 的 3 条 `canGoFirstPage / canGoPrevPage are ...` 配对断言保证两者永远等价。
@visibleForTesting
bool canGoFirstPage({required int currentPage, required bool isLoading}) =>
    canGoPrevPage(currentPage: currentPage, isLoading: isLoading);

/// 「上一页」按钮启用条件，**也是「首页」按钮的等价条件**（见 [canGoFirstPage]）。
///
/// **唯一逻辑源**：`currentPage > 0 && !isLoading`。「首页」按钮通过 [canGoFirstPage]
/// delegate 到本 helper（R91 收敛），让两个按钮的启用条件永远等价。
@visibleForTesting
bool canGoPrevPage({required int currentPage, required bool isLoading}) =>
    currentPage > 0 && !isLoading;

/// 「下一页」按钮启用条件：`hasMore` 才允许（与是否已知总页数无关）。
@visibleForTesting
bool canGoNextPage({required bool hasMore, required bool isLoading}) =>
    hasMore && !isLoading;

/// 「末页」按钮启用条件：必须知道总页数且当前未在末页。
@visibleForTesting
bool canGoLastPage({
  required int currentPage,
  required int totalPages,
  required bool isLoading,
}) =>
    totalPages > 0 && currentPage < totalPages - 1 && !isLoading;

/// 分页栏中央的页码文案。
///
/// `currentPage` 是 0-based，展示时 +1；`totalPages <= 0` 时分母用 `?`。
@visibleForTesting
String formatPageLabel({required int currentPage, required int totalPages}) {
  final total = totalPages > 0 ? '$totalPages' : '?';
  return '${currentPage + 1} / $total';
}

/// 「过滤栏汇总 chip」的渲染描述。
///
/// 把"是否显示某 chip / 文案 / 配色"从 widget 树里剥离出来：装配阶段产出
/// 一组 [LogSummaryChipSpec]，渲染阶段简单 `map` 到 `_StatusChip` 即可。
///
/// 默认色与 `_StatusChip` 的默认值保持一致（中性灰底 + 中性灰字），调用方
/// 显式传入背景/前景色时覆盖默认。
class LogSummaryChipSpec {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  /// 可选 hover tooltip。`null` 表示该 chip 的 [label] 已自描述完整语义，
  /// hover 时不需要追加额外说明（去重契约：避免 tooltip == label 形成噪音）。
  ///
  /// **Step 27 - 第二十三层 hover**：仅"缓存 / 区间 / 分支点"三类 chip 提供 tooltip——
  /// - **缓存**：`label` 只给数字（"缓存 N 条" / "未缓存日志"），tooltip 解释
  ///   "本地数据库的缓存条数，下次打开仍可用，无需重新从 SVN 拉取"语义；
  /// - **区间**：`label` 给原始 `r{latest} -> r{earliest}`，tooltip 用自然语言解释
  ///   "缓存中最新 → 最早" 与"再老的需点加载更多"；
  /// - **分支点**：`label` 只给 `r{branchPoint}` 数字，tooltip 解释"此 revision 之前
  ///   的日志属于父分支，无法合并到当前分支"——这是用户最容易误解的语义。
  ///
  /// 预加载状态 / 边界提示两类 chip 的 `label` 已是完整文案（来自上游 service 拼好），
  /// 再加 tooltip 反而会形成 tooltip == label 的噪音——故 [tooltip] = `null`。
  final String? tooltip;

  const LogSummaryChipSpec({
    required this.label,
    this.backgroundColor = const Color(0xFFF3F4F6),
    this.textColor = const Color(0xFF4B5563),
    this.tooltip,
  });

  @override
  bool operator ==(Object other) =>
      other is LogSummaryChipSpec &&
      other.label == label &&
      other.backgroundColor.toARGB32() == backgroundColor.toARGB32() &&
      other.textColor.toARGB32() == textColor.toARGB32() &&
      other.tooltip == tooltip;

  @override
  int get hashCode => Object.hash(
        label,
        backgroundColor.toARGB32(),
        textColor.toARGB32(),
        tooltip,
      );

  @override
  String toString() =>
      'LogSummaryChipSpec(label: $label, bg: ${backgroundColor.toARGB32().toRadixString(16)}, fg: ${textColor.toARGB32().toRadixString(16)}, tooltip: $tooltip)';
}

/// 判断 [label] 是否「值得作为 chip label 渲染」。
///
/// **核心契约**：仅当 [label] 非 null **且** 非空字符串时返回 true。
/// 与 R79-R81 的四谓词 `String? -> bool` 矩阵
/// （`isUsableSourceUrl` / `isUsableSvnCredential` /
///  `isUsableWorkingDirectory` / `isUsableSqlStringFilter`）形态完全相同——
/// 实现一字不差，但**callsite 语境不同**：
/// - `isUsableChipLabel`（本谓词）：是否值得在 UI chip 列表中渲染一项
///   （null/空 → 该位置不渲染 chip——视觉上消失，不占布局）；
/// - `isUsableSourceUrl`：是否值得调 `refreshLogEntries`；
/// - `isUsableSvnCredential`：是否值得加到 svn CLI args；
/// - `isUsableWorkingDirectory`：是否值得用作 SVN 缓存键；
/// - `isUsableSqlStringFilter`：是否值得拼到 SQL WHERE 字符串过滤段。
///
/// **为什么这个谓词单独抽**：原 [chipSpecsForLogSummary] 内部
/// `preloadStatusText`（line 153）与 `boundaryText`（line 163）两处各内联
/// 一句 `text != null && text.isNotEmpty`——两者共享同一份"空串视作未启用
/// chip"决策。任何一处把 `&&` 误改成 `||` 会让空串/null 走 OR 短路成 true，
/// 让 chip 列表里出现 `LogSummaryChipSpec(label: '')` 或 `label: null`
/// 的占位项——UI 上是一个**没有文字但仍占空间的色块**，破坏汇总条的视觉秩序。
///
/// **故意不做 trim**：与 R81 `isUsableSqlStringFilter` 一致——单空格 chip
/// label（`' '`）虽然视觉退化为色块，但仍是有意义的"用户已传入"信号，
/// 调用方负责 UI 层去白。本谓词只锁判定。
///
/// **本轮把 `String? -> bool` 矩阵从四谓词扩到五谓词**：R79（双谓词）
/// → R80（三谓词）→ R81（四谓词）→ R83（五谓词）。模式从"个例"
/// 升级为"项目惯例"已稳定 5 轮。设计模式 #9：实现等价但 callsite 语义
/// 自描述能力不同，强行合并为通名 `isUsableNonEmptyString` 会让 review
/// 时多读一次注释。
@visibleForTesting
bool isUsableChipLabel(String? label) => label != null && label.isNotEmpty;

/// 缓存 chip hover 文案——把 label 上"只有数字"的语义补上"本地缓存"维度。
///
/// **Step 27 - 第二十三层 hover**：日志面板汇总条第一个 chip 永远存在，但 label
/// 只显示 `"缓存 N 条"` / `"未缓存日志"`——"N 条"指的是**本地 SQLite 缓存**还是
/// **当前分支总量**？两者用户混淆度很高（已有过反馈）。tooltip 锁定为
/// "本地缓存"语义，并解释"下次打开仍可用，无需从 SVN 拉取"。
///
/// **为什么和 [chipSpecsForLogSummary] 内联 ternary 拆开**：与 R26 status_bar
/// 的 [statusBarStatusTooltip] / [statusBarLogButtonTooltip] 同形态——hover 文案
/// 是 UI 契约，单测要能直接断言 keyword（"本地"/"未缓存"），而不是穿过整个
/// chipSpecsForLogSummary 的 5-chip 装配再去 firstWhere。
@visibleForTesting
String tooltipForCacheChip(int cachedCount) {
  if (cachedCount <= 0) {
    return '本地尚未缓存任何日志 · 点同步可从 SVN 拉取最新提交';
  }
  return '本地已缓存 $cachedCount 条日志 · 下次打开仍可用，无需重新从 SVN 拉取';
}

/// 区间 chip hover 文案——把 label 的 `r{latest} -> r{earliest}` 形式
/// 用自然语言解释为"缓存中最新 → 最早"。
///
/// **关键语义**：箭头方向（latest → earliest）和 SVN log 出参顺序一致
/// （新到旧），但用户看到 `r200 -> r100` 时常会误读为"从 r200 合并到 r100"。
/// tooltip 用"最新 → 最早"明确这是**缓存覆盖区间**，不是合并方向；
/// 顺带提示"再老的需点加载更多"——这是用户继续向下翻页的入口。
@visibleForTesting
String tooltipForRangeChip({
  required int latestCachedRevision,
  required int earliestCachedRevision,
}) =>
    '缓存中最新 r$latestCachedRevision，最早 r$earliestCachedRevision · '
    '更老的 revision 需点「加载更多」逐步拉取';

/// 分支点 chip hover 文案——解释"此 revision 之前的日志无法合并到当前分支"。
///
/// **核心语义**：`branchPoint` 是 SVN 仓库中分支创建点的 revision，
/// 在此之前的所有提交都属于父分支。即使日志面板显示了它们，**也不能选作合并源**——
/// 这是 SvnAutoMerge 早期一直让用户困惑的语义。tooltip 把这个隐式规则显式化。
@visibleForTesting
String tooltipForBranchPointChip(int branchPoint) =>
    '当前分支创建于 r$branchPoint · 此 revision 之前的提交属于父分支，无法合并到当前分支';

/// 装配过滤栏底部的汇总 chip 列表。
///
/// 顺序固定为：**缓存 → 区间 → 分支点 → 预加载状态 → 边界提示**。任何 chip
/// 都可能不出现：
/// - 缓存 chip：始终出现，`cachedCount > 0` → `"缓存 N 条"`，否则 `"未缓存日志"`
/// - 区间 chip：仅当 `latestCachedRevision` 与 `earliestCachedRevision` **都**非 null 时
/// - 分支点 chip：仅当 `branchPoint != null`
/// - 预加载状态 chip：[isUsableChipLabel] (`preloadStatusText`) → true 时
/// - 边界提示 chip：[isUsableChipLabel] (`boundaryText`) → true 时
///
/// 配色与 widget 历史值严格一致：
/// - 分支点：浅蓝底 0xFFE8F4FD / 深蓝字 0xFF0F5A94
/// - 预加载：蓝紫底 0xFFEEF4FF / 蓝紫字 0xFF335C99
/// - 边界：暖橙底 0xFFFFF4E5 / 棕橙字 0xFF9A5D00
/// - 其它（缓存、区间）：默认中性灰
@visibleForTesting
List<LogSummaryChipSpec> chipSpecsForLogSummary({
  required int cachedCount,
  required int? latestCachedRevision,
  required int? earliestCachedRevision,
  required int? branchPoint,
  required String? preloadStatusText,
  required String? boundaryText,
}) {
  final specs = <LogSummaryChipSpec>[
    LogSummaryChipSpec(
      label: cachedCount > 0 ? '缓存 $cachedCount 条' : '未缓存日志',
      tooltip: tooltipForCacheChip(cachedCount),
    ),
  ];

  if (latestCachedRevision != null && earliestCachedRevision != null) {
    specs.add(
      LogSummaryChipSpec(
        label: '区间 r$latestCachedRevision -> r$earliestCachedRevision',
        tooltip: tooltipForRangeChip(
          latestCachedRevision: latestCachedRevision,
          earliestCachedRevision: earliestCachedRevision,
        ),
      ),
    );
  }

  if (branchPoint != null) {
    specs.add(
      LogSummaryChipSpec(
        label: '分支点 r$branchPoint',
        backgroundColor: const Color(0xFFE8F4FD),
        textColor: const Color(0xFF0F5A94),
        tooltip: tooltipForBranchPointChip(branchPoint),
      ),
    );
  }

  if (isUsableChipLabel(preloadStatusText)) {
    specs.add(
      LogSummaryChipSpec(
        label: preloadStatusText!,
        backgroundColor: const Color(0xFFEEF4FF),
        textColor: const Color(0xFF335C99),
      ),
    );
  }

  if (isUsableChipLabel(boundaryText)) {
    specs.add(
      LogSummaryChipSpec(
        label: boundaryText!,
        backgroundColor: const Color(0xFFFFF4E5),
        textColor: const Color(0xFF9A5D00),
      ),
    );
  }

  return specs;
}

/// 日志条目行右侧"状态标签"的渲染描述（紧贴 [LogSummaryChipSpec] 的同形态命名）。
///
/// 把"是否显示某 tag / 文案 / 配色"从 widget 树里剥离：装配阶段产出
/// 一组 [LogStatusTagSpec]，渲染阶段简单 `map` 到 `_buildStatusTag` 即可。
///
/// **配色与 widget 历史值严格一致**：
/// - 已合并：浅灰底 `Colors.grey.shade400`
/// - 待合并：纯绿底 `Colors.green`
/// - 文字色由渲染层统一为白色（与 `_buildStatusTag` 内 `Colors.white` 一致），
///   因此本 spec 不需要 textColor 字段——若日后需要差异化文字色，再加。
///
/// **`tooltip` 字段（Step 28 hover dual-encode 第二十四层）**：
/// - 非空 → 渲染层（`_LogEntryTile._buildStatusTag`）将 tag 用 `Tooltip` 包裹，hover 显示扩展语义；
/// - `null` → 渲染层不包 Tooltip（避免无信息量的悬浮气泡，与 Step 27 `LogSummaryChipSpec.tooltip`
///   的 `null` 去重契约同源）。
/// - 当前两个 tag 都补 tooltip：`已合并` 解释 mergeinfo 语义，`待合并` 解释 pending 队列语义。
///   保留 `null` 可空类型，便于将来加新 tag（如 `重试中` 等）继续按语义判断。
class LogStatusTagSpec {
  final String label;
  final Color backgroundColor;
  final String? tooltip;

  const LogStatusTagSpec({
    required this.label,
    required this.backgroundColor,
    this.tooltip,
  });

  @override
  bool operator ==(Object other) =>
      other is LogStatusTagSpec &&
      other.label == label &&
      other.backgroundColor.toARGB32() == backgroundColor.toARGB32() &&
      other.tooltip == tooltip;

  @override
  int get hashCode => Object.hash(label, backgroundColor.toARGB32(), tooltip);

  @override
  String toString() =>
      'LogStatusTagSpec(label: $label, bg: ${backgroundColor.toARGB32().toRadixString(16)}, tooltip: $tooltip)';
}

/// `已合并` tag 的 hover tooltip（Step 28 hover dual-encode 第二十四层）。
///
/// **为什么需要**：列表里 `已合并` 二字过于浓缩——用户常常分不清"已合并"是
/// 「该 revision 在源分支已存在」还是「已合并到目标分支」。本 tooltip 显式说明：
/// 这里的"已合并"指 **mergeinfo 中已记录该 revision 合并到目标分支**（svn:mergeinfo 维度），
/// 与 R97~R104 一系列审计中 `mergeinfo` / `getAllMergedRevisions` 的语义对齐。
///
/// **行为契约**：返回固定文案，不带参数（无歧义维度，无需根据上下文切换）。
@visibleForTesting
String tooltipForMergedTag() => '已合并 · 该 revision 已被合并到目标分支（mergeinfo 中可查）';

/// `待合并` tag 的 hover tooltip（Step 28 hover dual-encode 第二十四层）。
///
/// **为什么需要**：`待合并` 二字浓缩，用户常困惑"待"是"我还没勾选"还是"已加入但未执行"。
/// 本 tooltip 显式说明：这里指 **该 revision 已加入当前合并队列**（pending list 维度），
/// 等待下一次执行——与 PendingPanel / job_queue_panel 的 pending 语义对齐。
///
/// **行为契约**：返回固定文案，不带参数。
@visibleForTesting
String tooltipForPendingTag() => '待合并 · 该 revision 在当前合并队列中，等待执行';

/// 装配日志条目右侧的"状态标签"列表。
///
/// **顺序固定为：已合并 → 待合并**（与 `_LogEntryTile.build` 行 630-631 原始
/// 顺序完全一致；上层拉平后按列表顺序追加 widget）。
///
/// **行为契约**（**两个 flag 是独立维度**——可同时为 true、可同时为 false，
/// 均按字面解析为"该 tag 是否出现"，**不**做优先级互斥）：
/// - `isMerged && !isPending` → `[已合并]`
/// - `!isMerged && isPending` → `[待合并]`
/// - `isMerged && isPending` → `[已合并, 待合并]`（**两个都渲染**——这是有意行为，
///   "该 revision 已合并过"且"再次出现在 pending 列表"是合法状态：用户可能选择重合并；
///   同时显示两个 tag 反而更利于用户察觉这种少见情况，不做"已合并就吃掉 pending tag"的偷换）。
/// - 都为 false → 空列表（widget 层用 `if` 渲染时不会添加任何 tag）。
///
/// **配色契约**：背景色用 `Colors.grey.shade400` / `Colors.green`，与原 inline 字面量等价
/// （单测用 `LogStatusTagSpec.toARGB32()` 锁定，避免 Color 类内部表示变化时静默漂移）。
@visibleForTesting
List<LogStatusTagSpec> statusTagSpecsForLogEntry({
  required bool isMerged,
  required bool isPending,
}) {
  final tags = <LogStatusTagSpec>[];
  if (isMerged) {
    tags.add(LogStatusTagSpec(
      label: '已合并',
      backgroundColor: Colors.grey.shade400,
      tooltip: tooltipForMergedTag(),
    ));
  }
  if (isPending) {
    tags.add(LogStatusTagSpec(
      label: '待合并',
      backgroundColor: Colors.green,
      tooltip: tooltipForPendingTag(),
    ));
  }
  return tags;
}

/// 把 SVN 日志条目的 date 字段（形如 `'2024-01-01 10:00:00 +0800 (Mon, 01 Jan 2024)'`）
/// 截到展示用的"年-月-日 时:分:秒"前 19 个字符。
///
/// **行为契约**：
/// - 长度 ≥ 19 → `date.substring(0, 19)`；
/// - 长度 < 19 → **整段返回**，**不抛异常**——`String.substring` 越界会抛 `RangeError`，
///   但 LogListPanel 是降级展示路径，不能因为一条异常 date（测试 fixture / 上游 bug /
///   数据迁移残留）让整个列表崩溃。短串原样返回作为"显眼的展示异常"信号。
/// - 空字符串 → 空字符串（同上 fallback）。
/// - **不**做日期合法性校验：传入 `'XX-YY-ZZabc...'` 会照样截前 19 字符——本函数职责
///   只是裁切，"是不是合法 ISO 日期"由上游 SVN 客户端保证。
/// - **不**做 trim：前置/末尾空白被保留进展示，作为上游格式异常的信号。
///
/// **为什么提到顶层**：inline `substring` 有崩溃风险的越界写法；
/// SVN 实际输出通常足够长，但测试 fixture / 错误数据可能不是。提到顶层后用单测
/// 锁定 fallback 行为，且日期格式调整时只改一个函数。
@visibleForTesting
String formatLogEntryDate(String date) {
  if (date.length < 19) return date;
  return date.substring(0, 19);
}

/// 日志列表中 message 列的展示文本。
///
/// 只在列表展示层把内部换行压成空格，保持 [LogEntry.message] 原始内容不变。
@visibleForTesting
String formatLogEntryMessageForList(LogEntry entry) {
  return entry.message.replaceAll(RegExp(r'[\r\n]+'), ' ');
}

/// 日志条目行 date 列的 hover tooltip。
///
/// **进度披露第十六层（Step 5→...→19→20）**：[log_list_panel.dart] 维度连续第二轮收口
/// （Step 19 commit message 标题 / Step 20 date 列），与 step_execution_view.dart 维度的
/// Step 13/14/15 三轮收口同型——同一文件的多个信息渠道全部补齐 hover 入口。
///
/// **截断现状**：[formatLogEntryDate] 把 SVN log 的 timestamp（形如
/// `'2024-01-15 10:30:45 +0800 (Mon, 15 Jan 2024)'`）截到前 19 字符保留到秒，
/// 但时区/星期信息仍不直接显示。本 tooltip 把原始 [LogEntry.date]
/// 完整字符串（不裁切、不解析）还原到 hover 浮层。
///
/// **行为契约**：
/// - 截断分支（`date.length > 19`）→ 返回完整 `date`（让 hover 看到时区+星期）；
/// - 非截断分支（`date.length <= 19`）→ 返回 `''`（caller 不渲染 Tooltip）。
///   理由：长度 ≤ 19 时 [formatLogEntryDate] 是"原样返回"分支，列表 date 列已完整显示，
///   tooltip 重复同一字符串无 added value（与 Step 8/13/19 single-line dedup 同源）。
/// - 空字符串 → 返回 `''`（防御性，caller 不渲染 Tooltip）。
/// - **不**做 trim、不做 ISO 校验、不做时区转换——上游 SVN 客户端的原始格式忠实展示，
///   与 [formatLogEntryDate] 的"职责单一"约定同源（解析/校验是上游 SVN 的事）。
///
/// **为什么不附加"完整时间:"前缀**：与 Step 19 单一职责"截断还原"同源——hover 浮层
/// 已经从"截断 19 字符"切换到"完整字符串"，前缀反而稀释信号；用户看到的就是裸时间戳。
///
/// **为什么不展开 revision/author/message**：那三段在列表上各自有独立列展示，截断不在
/// 同一量级（revision 60px 数字 / author 80px ellipsis / message 由 Step 19 hover 还原）；
/// 单点聚焦 date 维度的截断还原，与 Step 13/15/16/17/18/19 单点聚焦同源决策。
@visibleForTesting
String formatLogEntryDateTooltip(String date) {
  if (date.length <= 19) return '';
  return date;
}

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
  final TextEditingController messageController;
  final bool stopOnCopy;
  final void Function(bool) onStopOnCopyChanged;
  final VoidCallback onApplyFilter;

  /// "清空筛选"按钮回调。null 时**不**渲染按钮（用于禁用整个能力）；
  /// 非 null 时按钮始终 enabled——空文本点击等价于"应用空过滤"，无害。
  ///
  /// **架构选择**：曾经引入 `canClearFilter` 实时探测谓词驱动 disabled 态，但
  /// 那需要在 main_screen_v3 的 initState 加 `controller.addListener` 强行让
  /// keystroke 触发 setState，这违反 R130 档 4 (lib 内 0 处 ChangeNotifier
  /// .addListener)；权衡之下：UX 上"对一个本就空的过滤再点一次"成本极低，
  /// 不值得为此破坏命令式订阅 = 0 不变量。
  final VoidCallback? onClearFilter;

  final VoidCallback onRefresh;
  final bool canSyncLatest;
  final VoidCallback onSyncLatest;
  final bool canLoadMore;
  final VoidCallback onLoadMore;
  final bool canStopPreload;
  final VoidCallback onStopPreload;

  /// 是否允许"导出 CSV"按钮被点击：通常 caller 在
  /// `cachedCount > 0 && sourceUrl 非空 && !isLoading` 时传 true。
  /// 字段独立于 [isLoading] —— 即使 isLoading == false，cachedCount == 0
  /// 时也不应该让用户点击（只能导出表头，无意义）。
  final bool canExportCsv;

  /// 用户点击"导出 CSV"按钮的回调。caller 负责：
  /// 1. 通过 `AppState.getAllFilteredEntries` 拿到当前过滤后的全部条目；
  /// 2. 用 `formatLogEntriesAsCsv` 渲染为字符串；
  /// 3. 调 `FilePicker.platform.saveFile` 让用户选保存路径；
  /// 4. 写文件 + SnackBar 反馈。
  final VoidCallback onExportCsv;

  // 状态摘要
  final int cachedCount;
  final int? latestCachedRevision;
  final int? earliestCachedRevision;
  final int? branchPoint;
  final String? preloadStatusText;
  final String? boundaryText;

  // 分页
  final int currentPage;
  final int totalPages;
  final bool hasMore;
  final void Function(int) onPageChanged;

  // 选择
  final int selectableEntryCount;
  final VoidCallback onSelectAllSelectable;
  final VoidCallback onClearSelection;
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
    required this.messageController,
    required this.stopOnCopy,
    required this.onStopOnCopyChanged,
    required this.onApplyFilter,
    this.onClearFilter,
    required this.onRefresh,
    required this.canSyncLatest,
    required this.onSyncLatest,
    required this.canLoadMore,
    required this.onLoadMore,
    required this.canStopPreload,
    required this.onStopPreload,
    required this.canExportCsv,
    required this.onExportCsv,
    required this.cachedCount,
    required this.latestCachedRevision,
    required this.earliestCachedRevision,
    required this.branchPoint,
    required this.preloadStatusText,
    required this.boundaryText,
    required this.currentPage,
    required this.totalPages,
    required this.hasMore,
    required this.onPageChanged,
    required this.selectableEntryCount,
    required this.onSelectAllSelectable,
    required this.onClearSelection,
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
          messageController: messageController,
          stopOnCopy: stopOnCopy,
          isLoading: isLoading,
          canSyncLatest: canSyncLatest,
          canLoadMore: canLoadMore,
          cachedCount: cachedCount,
          latestCachedRevision: latestCachedRevision,
          earliestCachedRevision: earliestCachedRevision,
          branchPoint: branchPoint,
          preloadStatusText: preloadStatusText,
          boundaryText: boundaryText,
          onStopOnCopyChanged: onStopOnCopyChanged,
          onApplyFilter: onApplyFilter,
          onClearFilter: onClearFilter,
          onRefresh: onRefresh,
          onSyncLatest: onSyncLatest,
          onLoadMore: onLoadMore,
          canStopPreload: canStopPreload,
          onStopPreload: onStopPreload,
          canExportCsv: canExportCsv,
          onExportCsv: onExportCsv,
          selectedCount: selectedRevisions.length,
          selectableEntryCount: selectableEntryCount,
          onSelectAllSelectable: onSelectAllSelectable,
          onClearSelection: onClearSelection,
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
  final TextEditingController messageController;
  final bool stopOnCopy;
  final bool isLoading;
  final bool canSyncLatest;
  final bool canLoadMore;
  final int cachedCount;
  final int? latestCachedRevision;
  final int? earliestCachedRevision;
  final int? branchPoint;
  final String? preloadStatusText;
  final String? boundaryText;
  final void Function(bool) onStopOnCopyChanged;
  final VoidCallback onApplyFilter;
  final VoidCallback? onClearFilter;
  final VoidCallback onRefresh;
  final VoidCallback onSyncLatest;
  final VoidCallback onLoadMore;
  final bool canStopPreload;
  final VoidCallback onStopPreload;
  final bool canExportCsv;
  final VoidCallback onExportCsv;
  final int selectedCount;
  final int selectableEntryCount;
  final VoidCallback onSelectAllSelectable;
  final VoidCallback onClearSelection;

  const _FilterBar({
    required this.authorController,
    required this.titleController,
    required this.messageController,
    required this.stopOnCopy,
    required this.isLoading,
    required this.canSyncLatest,
    required this.canLoadMore,
    required this.cachedCount,
    required this.latestCachedRevision,
    required this.earliestCachedRevision,
    required this.branchPoint,
    required this.preloadStatusText,
    required this.boundaryText,
    required this.onStopOnCopyChanged,
    required this.onApplyFilter,
    this.onClearFilter,
    required this.onRefresh,
    required this.onSyncLatest,
    required this.onLoadMore,
    required this.canStopPreload,
    required this.onStopPreload,
    required this.canExportCsv,
    required this.onExportCsv,
    required this.selectedCount,
    required this.selectableEntryCount,
    required this.onSelectAllSelectable,
    required this.onClearSelection,
  });

  List<Widget> _buildSummaryChips() {
    return chipSpecsForLogSummary(
      cachedCount: cachedCount,
      latestCachedRevision: latestCachedRevision,
      earliestCachedRevision: earliestCachedRevision,
      branchPoint: branchPoint,
      preloadStatusText: preloadStatusText,
      boundaryText: boundaryText,
    )
        .map(
          (spec) => _StatusChip(
            label: spec.label,
            backgroundColor: spec.backgroundColor,
            textColor: spec.textColor,
            tooltip: spec.tooltip,
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final summaryChips = _buildSummaryChips();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              // 标题过滤
              SizedBox(
                width: 150,
                child: TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              // 内容全文搜索（commit message 全文，对 message 列做 LOWER LIKE）
              SizedBox(
                width: 180,
                child: TextField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: '搜索内容',
                    hintText: 'commit 正文关键词',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              // 排除分支前记录
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: stopOnCopy,
                    onChanged: isLoading
                        ? null
                        : (value) => onStopOnCopyChanged(value ?? false),
                  ),
                  const Text('排除分支前', style: TextStyle(fontSize: 12)),
                ],
              ),
              // 过滤按钮
              ElevatedButton.icon(
                onPressed: isLoading ? null : onApplyFilter,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.filter_alt, size: 16),
                label: const Text('过滤'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              if (onClearFilter != null)
                OutlinedButton.icon(
                  onPressed: isLoading ? null : onClearFilter,
                  icon: const Icon(Icons.filter_alt_off, size: 16),
                  label: const Text('清空筛选'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8B6914),
                  ),
                ),
              FilledButton.icon(
                onPressed: canSyncLatest && !isLoading ? onSyncLatest : null,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 16),
                label: const Text('同步最新'),
              ),
              OutlinedButton.icon(
                onPressed: canLoadMore && !isLoading ? onLoadMore : null,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.unfold_more, size: 16),
                label: const Text('加载更多'),
              ),
              OutlinedButton.icon(
                onPressed: canStopPreload ? onStopPreload : null,
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('停止预加载'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF335C99),
                ),
              ),
              OutlinedButton.icon(
                onPressed: canExportCsv && !isLoading ? onExportCsv : null,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('导出 CSV'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                ),
              ),
              OutlinedButton.icon(
                onPressed: selectableEntryCount > 0 && !isLoading
                    ? onSelectAllSelectable
                    : null,
                icon: const Icon(Icons.done_all, size: 16),
                label: Text('全选可选 ($selectableEntryCount)'),
              ),
              TextButton.icon(
                onPressed:
                    selectedCount > 0 && !isLoading ? onClearSelection : null,
                icon: const Icon(Icons.deselect, size: 16),
                label: Text('清空选择 ($selectedCount)'),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: isLoading ? null : onRefresh,
                tooltip: '刷新列表',
              ),
            ],
          ),
          if (summaryChips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: summaryChips,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final String? tooltip;

  const _StatusChip({
    required this.label,
    this.backgroundColor = const Color(0xFFF3F4F6),
    this.textColor = const Color(0xFF4B5563),
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    final t = tooltip;
    if (t == null || t.isEmpty) {
      return chip;
    }
    return Tooltip(message: t, child: chip);
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

  bool get _canSelect => canSelectLogEntry(
        isMerged: isMerged,
        isPending: isPending,
        isLoading: isLoading,
      );

  @override
  Widget build(BuildContext context) {
    final tileColor = logEntryTileColor(
      isSelected: isSelected,
      isPending: isPending,
      isMerged: isMerged,
      index: index,
    );

    return InkWell(
      onTap: _canSelect
          ? () => onSelectionChanged(entry.revision, !isSelected)
          : null,
      child: Container(
        color: tileColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: _canSelect
                  ? (value) =>
                      onSelectionChanged(entry.revision, value ?? false)
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
              width: 140,
              child: Builder(
                builder: (_) {
                  final dateTooltip = formatLogEntryDateTooltip(entry.date);
                  final text = Text(
                    formatLogEntryDate(entry.date),
                    style: TextStyle(
                      fontSize: 11,
                      color: isMerged ? Colors.grey : Colors.grey.shade500,
                    ),
                  );
                  if (dateTooltip.isEmpty) return text;
                  return Tooltip(message: dateTooltip, child: text);
                },
              ),
            ),
            // 消息
            Expanded(
              child: Builder(
                builder: (_) {
                  final tooltip = formatLogEntryTitleTooltip(entry);
                  final messageText = formatLogEntryMessageForList(entry);
                  final text = Text(
                    messageText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isMerged ? Colors.grey : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  );
                  if (tooltip.isEmpty) return text;
                  return Tooltip(message: tooltip, child: text);
                },
              ),
            ),
            // 状态标签
            ...statusTagSpecsForLogEntry(
              isMerged: isMerged,
              isPending: isPending,
            ).map((spec) => _buildStatusTag(
                spec.label, spec.backgroundColor, spec.tooltip)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTag(String text, Color color, String? tooltip) {
    final tag = Container(
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
    if (tooltip == null || tooltip.isEmpty) return tag;
    return Tooltip(message: tooltip, child: tag);
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
            onPressed:
                canGoFirstPage(currentPage: currentPage, isLoading: isLoading)
                    ? () => onPageChanged(0)
                    : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed:
                canGoPrevPage(currentPage: currentPage, isLoading: isLoading)
                    ? () => onPageChanged(currentPage - 1)
                    : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatPageLabel(currentPage: currentPage, totalPages: totalPages),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: canGoNextPage(hasMore: hasMore, isLoading: isLoading)
                ? () => onPageChanged(currentPage + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 20),
            onPressed: canGoLastPage(
              currentPage: currentPage,
              totalPages: totalPages,
              isLoading: isLoading,
            )
                ? () => onPageChanged(totalPages - 1)
                : null,
          ),
          const SizedBox(width: 16),
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
