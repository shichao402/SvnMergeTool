/// 配置对话框
///
/// 用于编辑源 URL 和目标工作副本

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

/// 把字符串中所有 ASCII / Unicode 空白字符（空格、tab、CR、LF、no-break space 等）剥光。
///
/// **为什么是 sourceUrl 专属**：SVN URL 按 RFC 3986 不允许出现裸空白字符（必须 percent-encode），
/// 用户输入里出现空白几乎一定是粘贴时被聊天/web/工单系统额外添加的（最常见：trailing `\n`、
/// leading 缩进空格、双击选词带的前后空格）。targetWc 是文件路径，**合法含空格**（如
/// `/Users/Name With Space/wc`），所以这个 helper 不应套到目标工作副本字段。
///
/// 行为契约：
/// - null-safe 不接受（caller 保证非 null，与 [TextEditingValue.text] 同款）。
/// - 返回值长度 ≤ 入参长度（永远只删不加）。
/// - 不做 percent-encoding（已编码的 `%20` 之类原样保留）。
/// - 中文字符 / Unicode 表情等 non-whitespace code unit 原样保留。
///
/// 用 `RegExp(r'\s+')` 一次性替换为空串而不是 `trim()`：trim 只清头尾，
/// 内部空白（如 `https://repo /branch`）也要清，否则 `Uri.parse` 会成功
/// 但 svn info 仍然报 404，用户排查更难。
@visibleForTesting
String stripUrlWhitespace(String input) {
  if (input.isEmpty) return input;
  return input.replaceAll(RegExp(r'\s+'), '');
}

/// `TextInputFormatter` 子类，绑到 sourceUrl `TextField.inputFormatters` 上，
/// 在每次输入（含粘贴）时把 [TextEditingValue.text] 经 [stripUrlWhitespace] 净化。
///
/// **为什么走 [TextInputFormatter] 而不是 `onChanged` 里手动改 controller.text**：
/// - `onChanged` 改 controller.text 会触发递归 onChanged + 光标位置跳到末尾，
///   用户中间输入时光标错乱；
/// - `TextInputFormatter` 在 framework 层就改 [TextEditingValue]，光标位置由
///   formatter 自己控制，体验自然；
/// - 还能捕获到首次 paste 的整段（onChanged 看到的已经是 paste 后结果，但中间
///   可能错过 IME composing 状态——formatter 在 composing 之前介入更彻底）。
///
/// 光标策略：净化后字符串长度可能缩短，旧 selection.baseOffset 若超出新长度则
/// clamp 到末尾；否则保留原 baseOffset（粘贴 trailing `\n` 时光标本来就在末尾，
/// clamp 后体验自然）。
@visibleForTesting
class UrlInputFormatter extends TextInputFormatter {
  const UrlInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final stripped = stripUrlWhitespace(newValue.text);
    if (identical(stripped, newValue.text) || stripped == newValue.text) {
      return newValue;
    }
    final clampedOffset =
        newValue.selection.baseOffset.clamp(0, stripped.length);
    return TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: clampedOffset),
    );
  }
}

/// 配置对话框
///
/// **R133 controller 借用者（borrower）—— 流向拓扑契约**：本类是
/// `_MainScreenV3State` 拥有的 `_sourceUrlController` / `_targetWcController`
/// 的 **borrower**：通过构造参数接收引用、可执行 `.text=`（写站点 3 处：
/// `_pickTargetWc:61` 档 3 / `onSelected:84` 档 1 / `onSelected:110` 档 1）
/// + 绑定到 `TextField.controller:`（读站点）；**故意不调用 .dispose()**
/// —— J2 borrower 无 dispose 责任律，否则 dialog dismiss 后 owner 再写
/// disposed controller 会抛 `FlutterError: A TextEditingController was used
/// after being disposed`。
///
/// borrower 子类型 = StatelessWidget → 档 3 写必用 `context.mounted` 守护
/// （J3 子类型分流，与 R132 I3 同律）；本类 `_pickTargetWc:59` 已遵此契约。
class ConfigDialog extends StatelessWidget {
  final TextEditingController sourceUrlController;
  final TextEditingController targetWcController;
  final List<String> sourceUrlHistory;
  final List<String> targetWcHistory;
  final VoidCallback onConfirm;

  const ConfigDialog({
    super.key,
    required this.sourceUrlController,
    required this.targetWcController,
    required this.sourceUrlHistory,
    required this.targetWcHistory,
    required this.onConfirm,
  });

  /// 显示配置对话框
  static Future<bool?> show({
    required BuildContext context,
    required TextEditingController sourceUrlController,
    required TextEditingController targetWcController,
    required List<String> sourceUrlHistory,
    required List<String> targetWcHistory,
    required VoidCallback onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ConfigDialog(
        sourceUrlController: sourceUrlController,
        targetWcController: targetWcController,
        sourceUrlHistory: sourceUrlHistory,
        targetWcHistory: targetWcHistory,
        onConfirm: onConfirm,
      ),
    );
  }

  /// **R132 TextEditingController.text 写时机审计 — 档 3 async-bracket
  /// (跨 await 边界) + StatelessWidget 子型**：本类是 StatelessWidget 不持
  /// 有 owned controller（由 _MainScreenV3State 注入），await 期间父
  /// State 可能被 dispose（用户在 picker dialog 期间关闭整个应用），写 disposed
  /// `targetWcController.text` 会抛 FlutterError。无 `mounted` 字段可用——
  /// 用 `context.mounted` 替代（Flutter 3.7+ 等价契约）。
  ///
  /// 与同 lib R131 修复的 `_syncLatestLogs:1071` / `settings_screen._pickDate`
  /// + R132 修复的 `main_screen_v3:_loadAuthorFilterHistory` 共享同模板——
  /// await 后 .text= 之前必须自检（StatefulWidget 用 `mounted` /
  /// StatelessWidget 用 `context.mounted`）。
  Future<void> _pickTargetWc(BuildContext context) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (!context.mounted) return;
    if (result != null) {
      targetWcController.text = result;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 源 URL
            TextField(
              controller: sourceUrlController,
              inputFormatters: const [UrlInputFormatter()],
              decoration: InputDecoration(
                labelText: '源 URL',
                helperText: '粘贴时自动剥离空白字符',
                border: const OutlineInputBorder(),
                suffixIcon: sourceUrlHistory.isNotEmpty
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (value) {
                          sourceUrlController.text = stripUrlWhitespace(value);
                        },
                        itemBuilder: (context) => sourceUrlHistory
                            .map((url) => PopupMenuItem(
                                  value: url,
                                  child: Text(url, style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            // 目标工作副本
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: targetWcController,
                    decoration: InputDecoration(
                      labelText: '目标工作副本',
                      border: const OutlineInputBorder(),
                      suffixIcon: targetWcHistory.isNotEmpty
                          ? PopupMenuButton<String>(
                              icon: const Icon(Icons.arrow_drop_down),
                              onSelected: (value) {
                                targetWcController.text = value;
                              },
                              itemBuilder: (context) => targetWcHistory
                                  .map((wc) => PopupMenuItem(
                                        value: wc,
                                        child: Text(wc, style: const TextStyle(fontSize: 12)),
                                      ))
                                  .toList(),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _pickTargetWc(context),
                  child: const Text('选择...'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            onConfirm();
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
