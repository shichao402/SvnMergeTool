/// 日志查看对话框
///
/// 显示合并执行过程中的操作日志
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/process_output_decoder.dart';
import '../../../utils/app_banner.dart';

/// 渲染"复制到剪贴板"按钮要写入剪贴板的文本。
///
/// **核心契约**：
/// - 日志非空 → 直接返回原日志字符串（**不**做修剪、转义或截断——剪贴板要的就是
///   原始数据的逐字副本）；
/// - 日志为空 → 返回占位符 `'暂无日志'`，**与** [formatLogDialogBodyText] 的占位符
///   **完全相同**（**故意复用同一字面量**——单测显式断言这两个函数对空日志的输出
///   字面相等）。
/// - **为什么空日志写入占位符而不是空串**：如果剪贴板被设置成空串，用户粘贴时
///   会以为剪贴板没操作成功（macOS / Windows 的"粘贴"在空剪贴板会变成 no-op），
///   产生"我点了复制但没反应"的体验 bug。占位符虽然不能直接当日志用，但至少给出
///   "操作成功了，但当时没日志"的信号。
/// - **不**追加时间戳 / 元信息：caller 期望"所见即所粘"——粘贴出来的内容应该和
///   对话框里看到的内容一致；任何额外修饰会破坏这个等价。
@visibleForTesting
String formatLogDialogClipboardText(String log) =>
    log.isEmpty ? '暂无日志' : log;

/// 渲染对话框正文区显示的日志文本。
///
/// **核心契约**：
/// - 日志非空 → 直接返回原日志（`SelectableText` 自己做换行/滚动，本函数不参与）；
/// - 日志为空 → 返回 `'暂无日志'`（**与** [formatLogDialogClipboardText] 一致——
///   单测显式锁定"所见即所粘"等价：用户在对话框看到 `'暂无日志'`，按下复制粘贴
///   出来也是 `'暂无日志'`，没有歧义）。
/// - **与** [formatLogDialogHeaderText] 的占位符 `'暂无执行日志'` **故意不同**：
///   - 正文 `'暂无日志'` 是**数据槽**——它替代了"日志内容"本身的位置；
///   - 头部 `'暂无执行日志'` 是**描述性散文**——它向用户解释"为什么这个槽是空的"。
///   两者职责不同，单测显式断言 `formatLogDialogBodyText('') != formatLogDialogHeaderText(log: '', lineCount: 0)`。
@visibleForTesting
String formatLogDialogBodyText(String log) => log.isEmpty ? '暂无日志' : log;

/// 渲染对话框标题下方的"X 行"摘要文本。
///
/// **核心契约**：
/// - 日志非空 + query 空 → `'当前显示 $lineCount 行最近日志'`（**注意**：函数**不**做行数与
///   日志内容的一致性校验——如果 caller 传入了一个非空 log 但 `lineCount == 0`，
///   依然会渲染 `'当前显示 0 行最近日志'`。这是上游 bug 不在本层兜底；过度防御
///   反而会掩盖问题）；
/// - 日志非空 + query 非空 → `'匹配 $matchedCount / 共 $lineCount 行（关键字: $query）'`
///   （在原行为之外**单独**新增的搜索分支，单测显式锁定 query 为 null/'' 时退化到
///   原 `'当前显示 X 行最近日志'`，不破坏既有契约）；
/// - 日志为空 → `'暂无执行日志'`（**与** [formatLogDialogBodyText]/Clipboard 的
///   `'暂无日志'` **故意不同**——见 [formatLogDialogBodyText] 文档）；query 是否
///   非空都不影响——空日志没法匹配，仍走占位符；
/// - **不**对 `lineCount` / `matchedCount` 做格式化（千分位、上限截断）：日志一般
///   不会超过 600 行（`MergeExecutor` 已经限制），三位数直接插值即可；
/// - **不**根据 `lineCount` 是否为 0 切换到 `'暂无执行日志'`：判定基准是 `log` 是否
///   为空字符串，**不是** `lineCount == 0`。原因：caller 可能在过滤后得到 `lineCount == 0`
///   但 `log != ''`（含空白行），此时仍然要显示行数版本而不是占位符。锁定"判定凭 log 不凭 lineCount"。
@visibleForTesting
String formatLogDialogHeaderText({
  required String log,
  required int lineCount,
  String? query,
  int? matchedCount,
}) {
  if (log.isEmpty) {
    return '暂无执行日志';
  }
  final q = query ?? '';
  if (q.isEmpty) {
    return '当前显示 $lineCount 行最近日志';
  }
  return '匹配 ${matchedCount ?? 0} / 共 $lineCount 行（关键字: $q）';
}

/// 渲染"清空日志"二次确认对话框的正文文本。
///
/// **核心契约**：
/// - `lineCount <= 0` → `'当前没有日志可清空。'`（理论分支——UI 调用前已 isEmpty
///   早退跳过 dialog，但顶层 helper 仍要可独立测试，且极端竞态下 lineCount 翻
///   零时 dialog 已弹出也能给出合理文案）；
/// - `lineCount > 0` → `'将清空当前 $lineCount 行日志，操作不可恢复。'`（与
///   `_clearPendingRevisions` 第三十五轮"将移除 \$count 个待合并 revision，操作
///   不可恢复。"句式同型——破坏性操作 confirm 家族文案统一）。
///
/// **不**对 lineCount 做千分位 / 上限截断（与 [formatLogDialogHeaderText] 同口径，
/// MergeExecutor 已限 600 行，三位数直接插值即可）。
@visibleForTesting
String buildClearLogConfirmMessage({required int lineCount}) {
  if (lineCount <= 0) {
    return '当前没有日志可清空。';
  }
  return '将清空当前 $lineCount 行日志，操作不可恢复。';
}

/// 按 case-insensitive substring 匹配过滤日志行。
///
/// **核心契约**：
/// - `query` 为空（包括 `''`）→ 直接返回原 `log` 字符串（**不** split / **不**重组，避免
///   "原来空白行被合并 / trailing newline 丢失"的副作用）；
/// - `query` 非空 → `log.split('\n')` → 每行做 `toLowerCase().contains(query.toLowerCase())`
///   判断 → 用 `'\n'` join。**保持原有行序**（不排序、不去重）；
/// - 无任何行匹配 → 返回空串 `''`（caller 决定怎么显示——上层用 [formatLogDialogBodyText]
///   会把空串再翻译成 `'暂无日志'` 占位）；
/// - **不** trim query / 也**不** trim 行：用户搜 `'  ERROR'`（含前导空格）应能匹配带缩进的
///   error 行，trim 会破坏这个语义；
/// - **case-insensitive**：用户搜 `'error'` 要能匹配 `'ERROR'` / `'Error'`，与 IDE/编辑器
///   的"忽略大小写搜索"默认一致。
@visibleForTesting
String filterLogLinesByQuery(String log, String query) {
  if (query.isEmpty) {
    return log;
  }
  final needle = query.toLowerCase();
  return log
      .split('\n')
      .where((line) => line.toLowerCase().contains(needle))
      .join('\n');
}

/// 日志查看对话框
///
/// **R131 setState 站点**：本 widget 是 lib/ 内**第三个**含 `setState` 的 State 类
/// （前两个：`main_screen_v3.dart` / `settings_screen.dart`），在 R131 setState
/// 锁的"扩展白名单"内。仅一个站点：`_onQueryChanged` —— 同步事件回调内紧跟
/// `setState(() => _query = v)`，无 await，无 mounted check，**档 1 sync 直接
/// setState**。`mounted` 仅出现在原有 `_copyLog` 的 `context.mounted` 处（与
/// `config_dialog` 同款），不引入新 mounted 站点。
class LogDialog extends StatefulWidget {
  final String log;
  final int lineCount;
  final VoidCallback onClear;

  const LogDialog({
    super.key,
    required this.log,
    required this.lineCount,
    required this.onClear,
  });

  /// 显示日志对话框
  static Future<void> show({
    required BuildContext context,
    required String log,
    required int lineCount,
    required VoidCallback onClear,
  }) {
    return showDialog(
      context: context,
      builder: (context) => LogDialog(
        log: log,
        lineCount: lineCount,
        onClear: onClear,
      ),
    );
  }

  @override
  State<LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends State<LogDialog> {
  /// 关键字搜索：空串表示无过滤（与 [filterLogLinesByQuery] 入参等价）。
  String _query = '';

  /// **R131 档 1**（sync 直接 setState）：onChanged 回调同步收到新值，无 await，
  /// 无 mounted check 必要——闭包内只做赋值。
  void _onQueryChanged(String value) {
    setState(() => _query = value);
  }

  /// 按当前 [_query] 过滤后的日志正文（"所见即所粘"——和正文区显示的内容一致）。
  String get _filteredLog =>
      filterLogLinesByQuery(decodeUnicodeEscapes(widget.log), _query);

  /// 过滤后剩多少行——只在 query 非空时有意义；空时与 widget.lineCount 一致。
  int get _filteredLineCount {
    if (_query.isEmpty) return widget.lineCount;
    final f = _filteredLog;
    if (f.isEmpty) return 0;
    return f.split('\n').length;
  }

  Future<void> _copyLog(BuildContext context) async {
    // 复制过滤后的内容——保持"所见即所粘"协议（用户搜索后期望粘贴出的就是
    // 当前看到的过滤结果，而不是原始全量日志）。
    final text = formatLogDialogClipboardText(_filteredLog);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppBanner.showContext(context, message: '日志已复制到剪贴板');
  }

  /// 弹"清空日志"二次确认 AlertDialog。
  ///
  /// **为什么补这个 confirm**：日志对话框标题区"清空" IconButton 原本直连
  /// `widget.onClear()` + `Navigator.pop()`，紧邻"复制"按钮极易误点，且日志
  /// 通常含上百行排查信息（最近 600 行 by `MergeExecutor` 限制），误清不可恢复
  /// 与项目其它破坏性 confirm 家族（清空待合并 / 清空待执行 / 清理历史 / 删除单条
  /// / 终止任务）形成对称漏洞。
  ///
  /// **流程**：
  /// 1. `widget.log.isEmpty` → 直接 `Navigator.pop()` 不弹 confirm（与
  ///    `_clearPendingRevisions` isEmpty 早退对偶；空日志清空是 no-op，弹 dialog
  ///    反而打扰）；
  /// 2. 否则弹 AlertDialog "清空日志？" + `buildClearLogConfirmMessage(...)`
  ///    + 取消（默认）/ 清空双 TextButton；用户取消 → return 不动作；
  /// 3. 确认 → `widget.onClear()` + 跨 await 边界 `if (!context.mounted) return;`
  ///    守护后 `Navigator.pop()`。
  Future<void> _confirmClearLog(BuildContext context) async {
    if (widget.log.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空日志？'),
        content: Text(
          buildClearLogConfirmMessage(lineCount: widget.lineCount),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    widget.onClear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, size: 20),
              const SizedBox(width: 8),
              const Text('操作日志', style: TextStyle(fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                onPressed: () => _copyLog(context),
                tooltip: '复制日志',
              ),
              IconButton(
                icon: const Icon(Icons.clear_all, size: 18),
                onPressed: () => _confirmClearLog(context),
                tooltip: '清空',
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatLogDialogHeaderText(
              log: widget.log,
              lineCount: widget.lineCount,
              query: _query,
              matchedCount: _filteredLineCount,
            ),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          if (widget.log.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: TextField(
                onChanged: _onQueryChanged,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  hintText: '按关键字过滤（不区分大小写）',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide:
                        BorderSide(color: Colors.grey.shade400, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide:
                        BorderSide(color: Colors.grey.shade400, width: 1),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      content: SizedBox(
        width: 680,
        height: 420,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: SelectableText(
                formatLogDialogBodyText(_filteredLog),
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    );
  }
}
