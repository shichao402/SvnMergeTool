/// SVN XML 解析工具
///
/// 用于解析 SVN 命令的 XML 输出
/// SVN 支持 --xml 参数，输出结构化的 XML 数据，比文本解析更可靠

import 'package:xml/xml.dart' as xml;
import '../models/log_entry.dart';
import 'logger_service.dart';

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
        AppLogger.svn.warn('XML 中未找到 log 元素');
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
          final date = _formatDate(dateStr);

          // 解析 msg
          final msgElement = entryElement.findElements('msg').firstOrNull;
          final message = msgElement?.innerText.trim() ?? '';
          final title = message.split('\n').first.trim();

          entries.add(LogEntry(
            revision: revision,
            author: author,
            date: date,
            title: title,
            message: message,
          ));
        } catch (e, stackTrace) {
          AppLogger.svn.warn('解析 logentry 失败: $e');
          AppLogger.svn.debug('解析 logentry 异常详情', stackTrace);
          continue;
        }
      }

      // 已解析日志，不记录详细信息
      return entries;
    } catch (e, stackTrace) {
      AppLogger.svn.error('解析 SVN log XML 失败', e, stackTrace);
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
        AppLogger.svn.warn('XML 中未找到 info 元素');
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

        final repositoryElement = entryElement.findElements('repository').firstOrNull;
        if (repositoryElement != null) {
          final rootElement = repositoryElement.findElements('root').firstOrNull;
          if (rootElement != null) {
            result['repository_root'] = rootElement.innerText.trim();
          }
        }

        final wcInfoElement = entryElement.findElements('wc-info').firstOrNull;
        if (wcInfoElement != null) {
          final scheduleElement = wcInfoElement.findElements('schedule').firstOrNull;
          if (scheduleElement != null) {
            result['schedule'] = scheduleElement.innerText.trim();
          }
        }
      }

      return result;
    } catch (e, stackTrace) {
      AppLogger.svn.error('解析 SVN info XML 失败', e, stackTrace);
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
        AppLogger.svn.warn('XML 中未找到 mergeinfo 元素');
        return [];
      }

      final revisions = <int>[];

      // 查找 merged-ranges
      final mergedRangesElement = mergeinfoElement.findElements('merged-ranges').firstOrNull;
      if (mergedRangesElement != null) {
        final rangeElements = mergedRangesElement.findElements('range');
        for (final rangeElement in rangeElements) {
          final startAttr = rangeElement.getAttribute('start');
          final endAttr = rangeElement.getAttribute('end');
          
          if (startAttr != null && endAttr != null) {
            final start = int.tryParse(startAttr);
            final end = int.tryParse(endAttr);
            if (start != null && end != null) {
              // 添加范围内的所有 revision
              for (int i = start; i <= end; i++) {
                revisions.add(i);
              }
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
      AppLogger.svn.error('解析 SVN mergeinfo XML 失败', e, stackTrace);
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
      AppLogger.svn.error('解析 SVN log files XML 失败', e, stackTrace);
      return [];
    }
  }

  /// 格式化日期字符串
  /// 
  /// 将 ISO 8601 格式转换为可读格式
  /// 例如：2024-01-01T10:00:00.000000Z -> 2024-01-01 10:00:00 +0800
  static String _formatDate(String isoDate) {
    try {
      // 尝试解析 ISO 8601 格式
      final dateTime = DateTime.parse(isoDate);
      // 转换为本地时区
      final localDateTime = dateTime.toLocal();
      // 格式化为可读格式
      final year = localDateTime.year.toString();
      final month = localDateTime.month.toString().padLeft(2, '0');
      final day = localDateTime.day.toString().padLeft(2, '0');
      final hour = localDateTime.hour.toString().padLeft(2, '0');
      final minute = localDateTime.minute.toString().padLeft(2, '0');
      final second = localDateTime.second.toString().padLeft(2, '0');
      
      // 计算时区偏移
      final offset = localDateTime.timeZoneOffset;
      final offsetHours = offset.inHours;
      final offsetMinutes = (offset.inMinutes % 60).abs();
      final offsetSign = offsetHours >= 0 ? '+' : '-';
      final offsetStr = '$offsetSign${offsetHours.abs().toString().padLeft(2, '0')}${offsetMinutes.toString().padLeft(2, '0')}';
      
      return '$year-$month-$day $hour:$minute:$second $offsetStr';
    } catch (e, stackTrace) {
      // 如果解析失败，返回原始字符串
      AppLogger.svn.warn('日期格式解析失败: $isoDate');
      return isoDate;
    }
  }
}

