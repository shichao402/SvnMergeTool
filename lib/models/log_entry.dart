/// SVN 日志条目模型
///
/// 表示一条 SVN 日志记录，包含版本号、作者、日期、标题和完整消息

import 'package:json_annotation/json_annotation.dart';

part 'log_entry.g.dart';

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
  String toString() => 'r$revision | $author | $date | $title';
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
      if (line.isEmpty || line.startsWith('--------')) {
        i++;
        continue;
      }
      
      // 解析头部：r12345 | username | 2024-01-01 10:00:00 +0800 | 2 lines
      if (line.startsWith('r') && line.contains(' | ')) {
        final parts = line.split(' | ');
        if (parts.length < 4) {
          i++;
          continue;
        }
        
        // 提取版本号
        final revStr = parts[0].substring(1); // 去掉 'r'
        final revision = int.tryParse(revStr);
        if (revision == null) {
          i++;
          continue;
        }
        
        // 提取作者和日期
        final author = parts[1].trim();
        final dateStr = parts[2].trim();
        
        // 跳过空行
        i++;
        while (i < lines.length && lines[i].trim().isEmpty) {
          i++;
        }
        
        // 收集消息内容
        final msgLines = <String>[];
        while (i < lines.length && !lines[i].startsWith('--------')) {
          msgLines.add(lines[i]);
          i++;
        }
        
        final message = msgLines.join('\n').trim();
        final title = message.split('\n').first;
        
        entries.add(LogEntry(
          revision: revision,
          author: author,
          date: dateStr,
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

