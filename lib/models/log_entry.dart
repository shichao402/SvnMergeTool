/// SVN 日志条目模型
///
/// 表示一条 SVN 日志记录，包含版本号、作者、日期、标题和完整消息

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';

part 'log_entry.g.dart';

/// 渲染 [LogEntry.toString] 使用的紧凑单行展示：`'r$rev | $author | $date | $title'`。
///
/// **行为契约**：
/// - 固定结构 **4 段**，**3 个 `' | '` 分隔符**；段顺序 revision → author → date → title
///   是 LogEntry 调试日志生态的核心，**任意调换都会破坏 grep 切片**——单测显式
///   通过 `indexOf` 比较锁定段顺序。
/// - 与 Round 44 的 `formatJobDescription` 共用风格（半角竖线两侧加空格、半角分隔符），
///   但**刻意保留两个独立函数**：MergeJob 描述行有 5 段结构 + 进度装饰，LogEntry
///   描述行只有 4 段且无装饰；语义不同的渲染不应共用渲染器。
/// - 任意字段为空字符串都直接拼，不做"占位文案"——空 author 渲染成 `'r1 |  | ...'`
///   （双空格）作为 bug 信号显眼出现。
/// - revision 负数透传不防御（SVN revision >= 1，传负数 = 上游 bug 应当暴露）。
@visibleForTesting
String formatLogEntryShort({
  required int revision,
  required String author,
  required String date,
  required String title,
}) =>
    'r$revision | $author | $date | $title';

/// 判断一行是否是 SVN 文本日志格式中的分隔线 / 空行（应被 [SvnLogParser.parse] 跳过）。
///
/// **行为契约**：
/// - 空字符串 → `true`（trim 后的空行）；
/// - 以 `'--------'`（8 个连字符）开头 → `true`。**注意**：SVN 实际输出 72 个连字符，
///   这里**故意用 8 而非 72** 作为最小可识别阈值——SVN 不同版本/语言环境的分隔
///   长度可能略有差异，宽松匹配避免假阴性。**永远不会**因为业务行恰好以 8 个连字符
///   开头而误判：业务消息行经过 trim 后若以 `'--------'` 开头，作者本来就不应该用
///   它（见过的真实日志里没出现过），即使误判也只是少解析一条记录，不会数据损坏。
/// - **入参约定为已 trim 过的字符串**——`SvnLogParser.parse` 在调用前 `lines[i].trim()`，
///   本函数**不**重复 trim（保持纯函数职责单一，trim 由调用方控制）。
@visibleForTesting
bool isSvnLogSeparatorLine(String trimmedLine) =>
    trimmedLine.isEmpty || trimmedLine.startsWith('--------');

/// 判断一行是否"看起来像" SVN 文本日志的 entry 头（`'r12345 | author | date | N lines'`）。
///
/// **行为契约**：
/// - 同时满足 `startsWith('r')` 与 `contains(' | ')` → `true`；
/// - **故意宽松**：不在此校验 revision 是否数字、是否恰好 4 段——那是
///   [parseSvnLogHeaderRevision] 的职责。本函数只负责"快速过滤掉不可能的行"，
///   让真正解析的代价只对候选行付出。
/// - 大小写敏感：`'R12345 | ...'` → `false`。SVN 总是输出小写 `r`，按字面匹配
///   即可，不做大小写归一化。
/// - **入参约定为已 trim 过的字符串**（同 [isSvnLogSeparatorLine]）。
/// - 空字符串 → `false`（不会满足 `startsWith('r')`）。
@visibleForTesting
bool isSvnLogHeaderLine(String trimmedLine) =>
    trimmedLine.startsWith('r') && trimmedLine.contains(' | ');

/// 从 SVN 文本日志的 entry 头中解析 revision 数字；任何失败一律返回 `null`。
///
/// **行为契约**（**所有失败路径都是 `null`，不抛异常**——文本解析是降级路径，
/// 不能因为一条坏记录让整个 [SvnLogParser.parse] 崩溃）：
/// - 按 `' | '` 切分后段数 < 4 → `null`（SVN 头至少 4 段：rev / author / date / `'N lines'`）；
/// - 第一段不是以 `'r'` 起始 → `null`（实际上调用前会过 [isSvnLogHeaderLine]，
///   这条防线只是冗余兜底）；
/// - `'r'` 后的字符串 `int.tryParse` 失败 → `null`；
/// - 入参不是合法头（如 `'random text'` / `''` / `'r | a'`）→ `null`；
/// - 成功 → 返回正整数 revision。
/// - **不**接受可选 `prefix` 参数：`'r'` 前缀是 SVN 协议固定字面，没有"自定义前缀"
///   的合理用例。
@visibleForTesting
int? parseSvnLogHeaderRevision(String trimmedLine) {
  final parts = trimmedLine.split(' | ');
  if (parts.length < 4) return null;
  final first = parts[0];
  if (!first.startsWith('r')) return null;
  return int.tryParse(first.substring(1));
}

/// 判断"原始（**未** trim）行"是否是 SVN 文本日志中一条消息体的结束分隔线。
///
/// **行为契约**（**与 [isSvnLogSeparatorLine] 刻意不同**）：
/// - 入参约定为**未** trim 的原始行（来自 `lines.split('\n')` 直出）；
/// - 仅判断 `startsWith('--------')`，**不** 接受空字符串、**不** trim；
/// - `'   --------'` → `false`（前置空白破坏 startsWith）；
/// - `''` → `false`（空字符串不能作为消息结束信号——空行属于消息体的一部分）。
///
/// **为什么和 [isSvnLogSeparatorLine] 不能合并**：
/// - [isSvnLogSeparatorLine] 用在解析头部前的"跳空行 / 跳分隔线"阶段，入参是 trim 过的；
/// - 本函数用在收集消息体的 inner-while 中，入参是**原始**行——若提前 trim，
///   消息体内本意保留的"前置空白"会丢失（例如代码块缩进）。
/// - 若误把空行当作消息结束信号，会过早截断消息体；当前 SvnLogParser 流程依赖这个差异。
@visibleForTesting
bool isSvnLogMessageEndLine(String rawLine) => rawLine.startsWith('--------');

/// 解析 SVN 文本日志的 entry 头，一次性抽出 (revision, author, date) 三元组。
///
/// **行为契约**（合并 [isSvnLogHeaderLine] + [parseSvnLogHeaderRevision] + 段截取）：
/// - 入参约定为**已 trim** 的字符串（同 [isSvnLogHeaderLine]）；
/// - 任何失败一律返回 `null`，**不抛异常**——文本解析是降级路径，
///   不能因为一条坏记录让整个 [SvnLogParser.parse] 崩溃。
/// - 失败路径：
///   - 不以 `'r'` 起始 → `null`；
///   - `' | '` 切分后段数 < 4 → `null`；
///   - `'r'` 后字符串 `int.tryParse` 失败 → `null`。
/// - 成功路径：返回 `(revision: int, author: String, date: String)` record；
///   author / date 段已 `trim()`，与 SvnLogParser 原 inline 行为一致；
///   revision 与 [parseSvnLogHeaderRevision] 完全一致。
///
/// **设计目的**：消除 SvnLogParser.parse 内三次 `split(' | ')` 的重复
/// （isSvnLogHeaderLine 检查、parts.length 检查、parseSvnLogHeaderRevision 内部）。
/// 保留独立的 [isSvnLogHeaderLine] / [parseSvnLogHeaderRevision] 单测做契约
/// 防御——它们各自描述了更小粒度的语义边界，不能被本函数取代。
@visibleForTesting
({int revision, String author, String date})? parseSvnLogHeader(
  String trimmedLine,
) {
  if (!trimmedLine.startsWith('r')) return null;
  final parts = trimmedLine.split(' | ');
  if (parts.length < 4) return null;
  final revision = int.tryParse(parts[0].substring(1));
  if (revision == null) return null;
  return (
    revision: revision,
    author: parts[1].trim(),
    date: parts[2].trim(),
  );
}

/// 从多行消息中取首行作为标题。
///
/// **行为契约**：
/// - `message.split('\n').first`——仅按 `\n` 切分，**不**做 trim（与
///   [SvnLogParser.parse] 行 113-114 的原 inline 行为完全一致：`message` 在外层
///   已经 `join('\n').trim()` 过，首行内部仍可能有空白但**整体**已 trim）；
/// - 单行（无 `\n`）→ 整段返回；
/// - 空字符串 → 空字符串；
/// - **与 `svn_xml_parser.dart` 的 `extractLogTitle` 刻意分两份**：那个函数是
///   `split('\n').first.trim()`（额外做单行 trim），用于 XML 路径的 `<msg>` 内容
///   （末尾可能有 SVN XML 注入的空白）；本函数用于文本路径，外层已经做过整段 trim，
///   再 trim 一次会把"首行末尾本意保留的空格"也去掉。两个函数的职责边界由各自调用
///   栈决定，**不**抽象成共用函数。单测显式断言"首行末尾空格保留"来锁定差异。
@visibleForTesting
String extractMessageFirstLine(String message) => message.split('\n').first;

@JsonSerializable()
class LogEntry {
  final int revision;
  final String author;
  final String date;
  final String title;
  final String message;

  const LogEntry({
    required this.revision,
    required this.author,
    required this.date,
    required this.title,
    required this.message,
  });

  /// 从 JSON 创建
  factory LogEntry.fromJson(Map<String, dynamic> json) =>
      _$LogEntryFromJson(json);

  /// 转换为 JSON
  Map<String, dynamic> toJson() => _$LogEntryToJson(this);

  /// 复制并修改部分字段
  LogEntry copyWith({
    int? revision,
    String? author,
    String? date,
    String? title,
    String? message,
  }) {
    return LogEntry(
      revision: revision ?? this.revision,
      author: author ?? this.author,
      date: date ?? this.date,
      title: title ?? this.title,
      message: message ?? this.message,
    );
  }

  @override
  String toString() => formatLogEntryShort(
        revision: revision,
        author: author,
        date: date,
        title: title,
      );
}

/// SVN 日志解析器
class SvnLogParser {
  /// 解析 svn log 默认输出格式
  /// 
  /// 格式示例：
  /// ```
  /// ------------------------------------------------------------------------
  /// r12345 | username | 2024-01-01 10:00:00 +0800 (Mon, 01 Jan 2024) | 2 lines
  /// 
  /// Commit message title
  /// Commit message body
  /// ------------------------------------------------------------------------
  /// ```
  static List<LogEntry> parse(String raw) {
    final entries = <LogEntry>[];
    final lines = raw.split('\n');
    
    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      
      // 跳过空行和分隔线
      if (isSvnLogSeparatorLine(line)) {
        i++;
        continue;
      }
      
      // 解析头部：r12345 | username | 2024-01-01 10:00:00 +0800 | 2 lines
      if (isSvnLogHeaderLine(line)) {
        // 一次性抽 revision / author / date —— 任何失败跳过整条记录（不崩）。
        final header = parseSvnLogHeader(line);
        if (header == null) {
          i++;
          continue;
        }
        
        // 跳过空行
        i++;
        while (i < lines.length && lines[i].trim().isEmpty) {
          i++;
        }
        
        // 收集消息内容（按**原始**行匹配 '--------'，不 trim——保留消息体内缩进）
        final msgLines = <String>[];
        while (i < lines.length && !isSvnLogMessageEndLine(lines[i])) {
          msgLines.add(lines[i]);
          i++;
        }
        
        final message = msgLines.join('\n').trim();
        final title = extractMessageFirstLine(message);
        
        entries.add(LogEntry(
          revision: header.revision,
          author: header.author,
          date: header.date,
          title: title,
          message: message,
        ));
      } else {
        i++;
      }
    }
    
    return entries;
  }
}

