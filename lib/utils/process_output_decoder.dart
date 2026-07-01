/// 子进程输出解码工具。
///
/// SVN / shell 等外部命令在 Windows（GBK）与 Unix（UTF-8）上的编码不一致，
/// 且历史版本可能把非 ASCII 字符转成 `{U+xxxx}` 字面量。本模块统一处理这两种情况。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 解码 `{U+XXXX}` 格式的 Unicode 转义字符。
///
/// 部分子进程输出或历史快照会把非 ASCII 字符以 `{U+xxxx}` 形式保留，
/// 展示前需要还原成实际字符。
@visibleForTesting
String decodeUnicodeEscapes(String input) {
  return input.replaceAllMapped(
    RegExp(r'\{U\+([0-9A-Fa-f]{4,6})\}'),
    (match) {
      final hex = match.group(1)!;
      final codePoint = int.parse(hex, radix: 16);
      return String.fromCharCode(codePoint);
    },
  );
}

/// 判断字符串是否包含 `{U+xxxx}` 转义序列。
@visibleForTesting
bool containsUnicodeEscapes(String input) {
  return RegExp(r'\{U\+[0-9A-Fa-f]{4,6}\}').hasMatch(input);
}

/// 判断 UTF-8 解码结果是否像乱码（应尝试 systemEncoding）。
@visibleForTesting
bool looksLikeMojibake(String decoded) {
  if (decoded.isEmpty) return false;
  var replacementCount = 0;
  var latinSupplementCount = 0;
  for (final codePoint in decoded.runes) {
    if (codePoint == 0xFFFD) {
      replacementCount++;
    } else if (codePoint >= 0x80 && codePoint <= 0xFF) {
      latinSupplementCount++;
    }
  }
  if (replacementCount > 0) return true;
  return latinSupplementCount > decoded.runes.length * 0.3;
}

/// 把 [Process.run] 以 `latin1` 读回的 stdout/stderr 字符串解码为可读文本。
///
/// **流程**：
/// 1. `latin1.encode` 还原原始字节；
/// 2. 优先 UTF-8 解码（macOS / Linux / 新版 Windows SVN）；
/// 3. 若结果像乱码，回退 `systemEncoding`（Windows 中文环境常为 GBK）；
/// 4. 最后对 `{U+xxxx}` 转义做还原（兼容历史输出格式）。
String decodeProcessOutput(
  String latin1MappedOutput, {
  Encoding? fallbackEncoding,
}) {
  if (latin1MappedOutput.isEmpty) {
    return latin1MappedOutput;
  }

  if (containsUnicodeEscapes(latin1MappedOutput)) {
    return decodeUnicodeEscapes(latin1MappedOutput);
  }

  final bytes = latin1.encode(latin1MappedOutput);
  final utf8Decoded = utf8.decode(bytes, allowMalformed: true);

  String decoded = utf8Decoded;
  if (looksLikeMojibake(utf8Decoded)) {
    final fallback = fallbackEncoding ?? systemEncoding;
    try {
      decoded = fallback.decode(bytes);
    } catch (_) {
      decoded = utf8Decoded;
    }
  }

  return decodeUnicodeEscapes(decoded);
}

/// 解码 [ProcessResult] 的 stdout / stderr（已按 latin1 读入时）。
@visibleForTesting
String decodeProcessStream(String latin1MappedOutput) =>
    decodeProcessOutput(latin1MappedOutput);
