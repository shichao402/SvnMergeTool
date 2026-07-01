/// 配置对话框
///
/// 用于编辑源 URL、目标工作副本和目标 SVN URL。

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

/// 源 URL 配置对话框。
///
/// 源只需要仓库 URL，不需要工作目录。不要在这个弹窗里加入工作副本选择器，否则会让
/// 用户误以为源侧也需要本地 checkout。
class SourceUrlDialog extends StatelessWidget {
  final TextEditingController sourceUrlController;
  final List<String> sourceUrlHistory;
  final VoidCallback onConfirm;

  const SourceUrlDialog({
    super.key,
    required this.sourceUrlController,
    required this.sourceUrlHistory,
    required this.onConfirm,
  });

  static Future<bool?> show({
    required BuildContext context,
    required TextEditingController sourceUrlController,
    required List<String> sourceUrlHistory,
    required VoidCallback onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => SourceUrlDialog(
        sourceUrlController: sourceUrlController,
        sourceUrlHistory: sourceUrlHistory,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置源 URL'),
      content: SizedBox(
        width: 500,
        child: TextField(
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
                              child: Text(url,
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                  )
                : null,
          ),
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

/// 目标 SVN URL 配置对话框。
///
/// 用于临时精简工作副本模式：目标工作副本会在系统临时目录自动创建，因此这里仅配置
/// checkout 的目标分支 URL，不要求用户准备完整本地工作副本。
class TargetSvnUrlDialog extends StatelessWidget {
  final TextEditingController targetUrlController;
  final List<String> targetUrlHistory;
  final VoidCallback onConfirm;

  const TargetSvnUrlDialog({
    super.key,
    required this.targetUrlController,
    required this.targetUrlHistory,
    required this.onConfirm,
  });

  static Future<bool?> show({
    required BuildContext context,
    required TextEditingController targetUrlController,
    required List<String> targetUrlHistory,
    required VoidCallback onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => TargetSvnUrlDialog(
        targetUrlController: targetUrlController,
        targetUrlHistory: targetUrlHistory,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置目标 SVN URL'),
      content: SizedBox(
        width: 500,
        child: TextField(
          controller: targetUrlController,
          inputFormatters: const [UrlInputFormatter()],
          decoration: InputDecoration(
            labelText: '目标 SVN URL',
            helperText: '精简模式会在系统临时目录自动创建临时工作副本',
            border: const OutlineInputBorder(),
            suffixIcon: targetUrlHistory.isNotEmpty
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: (value) {
                      targetUrlController.text = stripUrlWhitespace(value);
                    },
                    itemBuilder: (context) => targetUrlHistory
                        .map((url) => PopupMenuItem(
                              value: url,
                              child: Text(url,
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                  )
                : null,
          ),
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

/// 目标工作副本配置对话框。
///
/// 目标只选择本地工作副本目录。目标 URL 由 `svn info` 从工作副本元数据获取，不能在
/// UI 中单独填写，避免 URL 与工作目录不一致。
class TargetWorkingCopyDialog extends StatelessWidget {
  final TextEditingController targetWcController;
  final List<String> targetWcHistory;
  final VoidCallback onConfirm;

  const TargetWorkingCopyDialog({
    super.key,
    required this.targetWcController,
    required this.targetWcHistory,
    required this.onConfirm,
  });

  static Future<bool?> show({
    required BuildContext context,
    required TextEditingController targetWcController,
    required List<String> targetWcHistory,
    required VoidCallback onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => TargetWorkingCopyDialog(
        targetWcController: targetWcController,
        targetWcHistory: targetWcHistory,
        onConfirm: onConfirm,
      ),
    );
  }

  /// await 后写 borrowed controller 前必须检查 `context.mounted`。
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
      title: const Text('配置目标工作副本'),
      content: SizedBox(
        width: 500,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: targetWcController,
                decoration: InputDecoration(
                  labelText: '目标工作副本',
                  helperText: '目标 URL 将从该工作副本自动读取',
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
                                    child: Text(wc,
                                        style: const TextStyle(fontSize: 12)),
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
