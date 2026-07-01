/// SVN XML 解析工具
///
/// 用于解析 SVN 命令的 XML 输出
/// SVN 支持 --xml 参数，输出结构化的 XML 数据，比文本解析更可靠

import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart' as xml;
import '../models/log_entry.dart';
import 'logger_service.dart';

/// `svn log --xml --verbose` 中单条 `<path>` 的结构化表示。
class SvnLogChangedPath {
  final String path;
  final String action;
  final String? kind;
  final String? copyFromPath;

  const SvnLogChangedPath({
    required this.path,
    required this.action,
    this.kind,
    this.copyFromPath,
  });
}

/// 把时区偏移格式化为 SVN 日志展示风格 `+HHMM` / `-HHMM`。
///
/// 例：`Duration(hours: 8)` → `+0800`；`Duration(hours: -5, minutes: -30)` → `-0530`。
///
/// **契约**：
/// - 偏移为 0 → `+0000`（不输出 `Z`）；
/// - 半小时区（India `+0530`、Newfoundland `-0330`）能正确处理——分钟部分独立 padLeft；
/// - 仅以 [Duration] 入参，**不**依赖 `DateTime.timeZoneOffset`，让函数完全脱离系统时区，
///   方便在 CI / 不同机器上跑出确定结果。原 [formatSvnIsoDate] 中拼装时区段
///   `'$offsetSign$offsetHours$offsetMinutes'` 的 5 行散逻辑全部内化到这里。
@visibleForTesting
String formatTimeZoneOffset(Duration offset) {
  final totalMinutes = offset.inMinutes;
  final sign = totalMinutes >= 0 ? '+' : '-';
  final absMinutes = totalMinutes.abs();
  final hours = (absMinutes ~/ 60).toString().padLeft(2, '0');
  final minutes = (absMinutes % 60).toString().padLeft(2, '0');
  return '$sign$hours$minutes';
}

/// 把 [DateTime] 格式化为 SVN 日志展示风格 `YYYY-MM-DD HH:MM:SS ±HHMM`。
///
/// 用 [formatTimeZoneOffset] 处理时区段；其它字段全部 padLeft 补零。
/// **不调用** `toLocal()`——由调用方决定是否本地化（[formatSvnIsoDate] 在调用前先 `toLocal()`），
/// 让纯函数本身保持时区无关。
@visibleForTesting
String formatLocalDateTimeForDisplay(DateTime time, {Duration? offset}) {
  final year = time.year.toString();
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final second = time.second.toString().padLeft(2, '0');
  final offsetStr = formatTimeZoneOffset(offset ?? time.timeZoneOffset);
  return '$year-$month-$day $hour:$minute:$second $offsetStr';
}

/// 把 SVN 输出的 ISO-8601 时间串格式化为本地时区可读字符串。
///
/// 例：`2024-01-01T10:00:00.000000Z` → `2024-01-01 18:00:00 +0800`（依本机时区而定）。
///
/// 解析失败时直接回退原始字符串，不抛异常——这一点被 [SvnXmlParser.parseLog]
/// 依赖：日志解析永远不应因为单条记录的日期格式异常而整段失败。
@visibleForTesting
String formatSvnIsoDate(String isoDate) {
  try {
    final localDateTime = DateTime.parse(isoDate).toLocal();
    return formatLocalDateTimeForDisplay(localDateTime);
  } catch (_) {
    AppLogger.svn.warn(formatSvnDateParseFailedLine(isoDate));
    return isoDate;
  }
}

/// 从 SVN logentry 的 message 字段提取「标题」段。
///
/// 取首个换行前的内容并 trim。**契约**：
/// - 空输入 → 空串；
/// - 不含换行 → trim 后整段返回；
/// - 多行 → 仅首行；
/// - `\r\n` 与 `\n` 等价处理（先 split `\n` 再 trim 自然吃掉首行尾随的 `\r`）。
@visibleForTesting
String extractLogTitle(String message) {
  return message.split('\n').first.trim();
}

/// 把 `[start, end]` 闭区间展开成全部 revision 的列表（升序）。
///
/// **契约**：
/// - `start == end` → 单元素列表 `[start]`（与原 `for (i = start; i <= end; i++)` 一致）；
/// - `start > end` → **返回空列表**（防御性，原代码靠调用方保证 start ≤ end，没有显式分支）；
/// - `start < 0` 或 `end < 0` 不做特殊处理——SVN 不会产生负 revision，调用方责任。
@visibleForTesting
List<int> expandRevisionRange(int start, int end) {
  if (start > end) return const [];
  final result = <int>[];
  for (var i = start; i <= end; i++) {
    result.add(i);
  }
  return result;
}

/// 渲染"XML 中未找到 X 元素"的 warn 日志行——用于三个 parser 的"根元素缺失"分支。
///
/// **统一三处调用站**：[SvnXmlParser.parseLog]（`'log'`）、[SvnXmlParser.parseInfo]
/// （`'info'`）、[SvnXmlParser.parseMergeinfo]（`'mergeinfo'`）。**注意**
/// [SvnXmlParser.parseLogFiles] 的根元素缺失分支**不**走这条日志——它直接静默
/// 返回 `[]`（行 268），原因是 `parseLogFiles` 在"全量预加载"高频路径上被调用，
/// 单条 entry 没有 `<paths>` 是合法状态（无文件改动的提交），打 warn 会刷屏。
/// 这条契约在测试里通过 `parseLogFiles` 不触发该字面来锁定。
///
/// **行为契约**：
/// - 固定模板 `'XML 中未找到 $elementName 元素'`；
/// - `elementName` 原样拼接，不做白名单校验——任意字符串直接进。理由：未来若新增
///   第四个 parser（如 `svn status --xml`），新增 `'status'` 即可零成本走这里；
/// - 空字符串 `elementName` → `'XML 中未找到  元素'`（双空格），不做防御。这是上
///   层硬编码 bug 信号，应该在日志里显眼出现而非被吞成 `'XML 中未找到元素'`。
@visibleForTesting
String formatXmlMissingRootElementLine(String elementName) =>
    'XML 中未找到 $elementName 元素';

/// 渲染"解析 SVN X XML 失败"的 error 日志行——用于四个 parser 的最外层 catch。
///
/// **统一四处调用站**：parseLog（`'log'`）、parseInfo（`'info'`）、
/// parseMergeinfo（`'mergeinfo'`）、parseLogFiles（`'log files'`）。
///
/// **行为契约**：
/// - 固定模板 `'解析 SVN $parserName XML 失败'`；
/// - `parserName` **不**强制为单词（注意 `'log files'` 含空格——保留 SVN 命令
///   `svn log --xml --verbose` 的子操作语义）；
/// - **与 [formatXmlMissingRootElementLine] 区分**：那条是 warn（XML 结构正常，
///   只是没目标元素），这条是 error（XML 解析自身抛异常 / 严重 bug）。两条
///   日志严重程度不同、所在分支不同，不能共用——单测通过前缀差异锁定这点。
@visibleForTesting
String formatSvnXmlParseFailedLine(String parserName) =>
    '解析 SVN $parserName XML 失败';

/// 渲染"解析 logentry 失败: $error"的 warn 日志行——用于 parseLog 单条 entry 解析。
///
/// **行为契约**：
/// - 固定模板 `'解析 logentry 失败: $error'`，半角冒号 + 空格分隔；
/// - 与 [formatSvnXmlParseFailedLine] 在严重程度上**刻意分层**：单条 entry 失败
///   只 warn 不 error，因为 parseLog 的 try-catch 设计就是"跳过坏 entry、继续
///   解析剩余 entry"——单条失败不应让整次解析降级；
/// - 错误对象按 `Object.toString()`，`null` → `'null'` 字面，不做防御；
/// - **`logentry`** 是 SVN XML 的元素名（小写），**不**改成中文"日志条目"：保持
///   与 SVN 文档一致，方便运维 grep XML 字段。
@visibleForTesting
String formatLogEntryParseFailedLine(Object error) => '解析 logentry 失败: $error';

/// 渲染"日期格式解析失败: $isoDate"的 warn 日志行——用于 [formatSvnIsoDate] 兜底。
///
/// **行为契约**：
/// - 固定模板 `'日期格式解析失败: $isoDate'`，半角冒号 + 空格分隔；
/// - **不**对空字符串做特殊文案（不会渲染成"日期为空"——空串本身就是 bug 信号，
///   渲染为 `'日期格式解析失败: '`（冒号后空白）让 SVN 返回空 `<date>` 的异常
///   显眼出现）；
/// - 仅渲染原始 isoDate 字符串，**不**附带异常对象——异常本身就是"解析失败"，
///   附加 `e.toString()` 多数是 `FormatException` 的冗余文案，对运维定位无价值。
@visibleForTesting
String formatSvnDateParseFailedLine(String isoDate) => '日期格式解析失败: $isoDate';

class SvnXmlParser {
  /// 解析 svn log --xml 输出
  ///
  /// XML 格式示例：
  /// ```xml
  /// <?xml version="1.0"?>
  /// <log>
  /// <logentry revision="12345">
  ///   <author>username</author>
  ///   <date>2024-01-01T10:00:00.000000Z</date>
  ///   <msg>Commit message</msg>
  ///   <paths>
  ///     <path action="M">/path/to/file</path>
  ///   </paths>
  /// </logentry>
  /// </log>
  /// ```
  static List<LogEntry> parseLog(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      final logElement = document.findElements('log').firstOrNull;
      if (logElement == null) {
        AppLogger.svn.warn(formatXmlMissingRootElementLine('log'));
        return [];
      }

      final entries = <LogEntry>[];
      final logEntries = logElement.findElements('logentry');

      for (final entryElement in logEntries) {
        try {
          // 解析 revision
          final revisionAttr = entryElement.getAttribute('revision');
          if (revisionAttr == null) continue;
          final revision = int.tryParse(revisionAttr);
          if (revision == null) continue;

          // 解析 author
          final authorElement = entryElement.findElements('author').firstOrNull;
          final author = authorElement?.innerText.trim() ?? '';

          // 解析 date
          final dateElement = entryElement.findElements('date').firstOrNull;
          final dateStr = dateElement?.innerText.trim() ?? '';
          // 将 ISO 8601 格式转换为可读格式
          final date = formatSvnIsoDate(dateStr);

          // 解析 msg
          final msgElement = entryElement.findElements('msg').firstOrNull;
          final message = msgElement?.innerText.trim() ?? '';
          final title = extractLogTitle(message);

          entries.add(LogEntry(
            revision: revision,
            author: author,
            date: date,
            title: title,
            message: message,
          ));
        } catch (e, stackTrace) {
          AppLogger.svn.warn(formatLogEntryParseFailedLine(e));
          AppLogger.svn.debug('解析 logentry 异常详情', stackTrace);
          continue;
        }
      }

      // 已解析日志，不记录详细信息
      return entries;
    } catch (e, stackTrace) {
      AppLogger.svn.error(formatSvnXmlParseFailedLine('log'), e, stackTrace);
      return [];
    }
  }

  /// 解析 svn info --xml 输出
  ///
  /// 返回 info 信息 Map
  static Map<String, String> parseInfo(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      final infoElement = document.findElements('info').firstOrNull;
      if (infoElement == null) {
        AppLogger.svn.warn(formatXmlMissingRootElementLine('info'));
        return {};
      }

      final result = <String, String>{};

      // 解析 entry
      final entryElement = infoElement.findElements('entry').firstOrNull;
      if (entryElement != null) {
        final urlElement = entryElement.findElements('url').firstOrNull;
        if (urlElement != null) {
          result['url'] = urlElement.innerText.trim();
        }

        final repositoryElement =
            entryElement.findElements('repository').firstOrNull;
        if (repositoryElement != null) {
          final rootElement =
              repositoryElement.findElements('root').firstOrNull;
          if (rootElement != null) {
            result['repository_root'] = rootElement.innerText.trim();
          }
        }

        final wcInfoElement = entryElement.findElements('wc-info').firstOrNull;
        if (wcInfoElement != null) {
          final scheduleElement =
              wcInfoElement.findElements('schedule').firstOrNull;
          if (scheduleElement != null) {
            result['schedule'] = scheduleElement.innerText.trim();
          }
        }
      }

      return result;
    } catch (e, stackTrace) {
      AppLogger.svn.error(formatSvnXmlParseFailedLine('info'), e, stackTrace);
      return {};
    }
  }

  /// 解析 svn mergeinfo --xml 输出
  ///
  /// 返回已合并的 revision 列表
  static List<int> parseMergeinfo(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      final mergeinfoElement = document.findElements('mergeinfo').firstOrNull;
      if (mergeinfoElement == null) {
        AppLogger.svn.warn(formatXmlMissingRootElementLine('mergeinfo'));
        return [];
      }

      final revisions = <int>[];

      // 查找 merged-ranges
      final mergedRangesElement =
          mergeinfoElement.findElements('merged-ranges').firstOrNull;
      if (mergedRangesElement != null) {
        final rangeElements = mergedRangesElement.findElements('range');
        for (final rangeElement in rangeElements) {
          final startAttr = rangeElement.getAttribute('start');
          final endAttr = rangeElement.getAttribute('end');

          if (startAttr != null && endAttr != null) {
            final start = int.tryParse(startAttr);
            final end = int.tryParse(endAttr);
            if (start != null && end != null) {
              // 添加范围内的所有 revision（闭区间展开）
              revisions.addAll(expandRevisionRange(start, end));
            }
          } else if (startAttr != null) {
            // 单个 revision
            final rev = int.tryParse(startAttr);
            if (rev != null) {
              revisions.add(rev);
            }
          }
        }
      }

      // 已解析合并信息，不记录详细信息
      return revisions;
    } catch (e, stackTrace) {
      AppLogger.svn
          .error(formatSvnXmlParseFailedLine('mergeinfo'), e, stackTrace);
      return [];
    }
  }

  /// 解析 svn log --xml --verbose 输出中的文件列表
  ///
  /// 返回文件路径列表
  static List<String> parseLogFiles(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      final logElement = document.findElements('log').firstOrNull;
      if (logElement == null) {
        return [];
      }

      final files = <String>[];
      final logEntryElement = logElement.findElements('logentry').firstOrNull;
      if (logEntryElement == null) {
        return [];
      }

      final pathsElement = logEntryElement.findElements('paths').firstOrNull;
      if (pathsElement == null) {
        return [];
      }

      final pathElements = pathsElement.findElements('path');
      for (final pathElement in pathElements) {
        final filePath = pathElement.innerText.trim();
        if (filePath.isNotEmpty) {
          files.add(filePath);
        }
      }

      return files;
    } catch (e, stackTrace) {
      AppLogger.svn
          .error(formatSvnXmlParseFailedLine('log files'), e, stackTrace);
      return [];
    }
  }

  /// 解析 svn log --xml --verbose 输出中的变更路径（包含 action / kind 等属性）。
  static List<SvnLogChangedPath> parseLogChangedPaths(String xmlString) {
    try {
      final document = xml.XmlDocument.parse(xmlString);
      final logElement = document.findElements('log').firstOrNull;
      if (logElement == null) {
        return [];
      }

      final paths = <SvnLogChangedPath>[];
      final logEntryElement = logElement.findElements('logentry').firstOrNull;
      if (logEntryElement == null) {
        return [];
      }

      final pathsElement = logEntryElement.findElements('paths').firstOrNull;
      if (pathsElement == null) {
        return [];
      }

      for (final pathElement in pathsElement.findElements('path')) {
        final filePath = pathElement.innerText.trim();
        if (filePath.isEmpty) {
          continue;
        }
        paths.add(SvnLogChangedPath(
          path: filePath,
          action: pathElement.getAttribute('action') ?? '',
          kind: pathElement.getAttribute('kind'),
          copyFromPath: pathElement.getAttribute('copyfrom-path'),
        ));
      }

      return paths;
    } catch (e, stackTrace) {
      AppLogger.svn
          .error(formatSvnXmlParseFailedLine('log files'), e, stackTrace);
      return [];
    }
  }
}
