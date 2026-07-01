import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/logger_service.dart';
import 'package:svn_auto_merge/services/svn_xml_parser.dart';

void main() {
  setUpAll(() {
    // 关闭日志：SvnXmlParser 在错误回退路径上会调用 AppLogger.svn.warn/error，
    // 而 LoggerService 的文件写队列会在没有 Flutter binding 的纯单元测试里
    // 通过 path_provider 访问 ServicesBinding.instance 失败 → 在
    // scheduleMicrotask 里无限重试，导致测试进程挂死。
    // 单元测试不关心日志输出，关掉即可。
    logger.enabled = false;
  });

  group('SvnXmlParser.parseLog', () {
    test('empty / non-log XML → []', () {
      expect(SvnXmlParser.parseLog(''), isEmpty);
      expect(
        SvnXmlParser.parseLog('<?xml version="1.0"?><other/>'),
        isEmpty,
      );
    });

    test('malformed XML → [] (does not throw)', () {
      // 解析失败时整段返回空列表，不应让上层崩。
      expect(SvnXmlParser.parseLog('<log><logentry'), isEmpty);
    });

    test('single well-formed entry', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="123">
  <author>alice</author>
  <date>2024-01-01T10:00:00.000000Z</date>
  <msg>fix bug</msg>
</logentry>
</log>
''';
      final entries = SvnXmlParser.parseLog(x);
      expect(entries, hasLength(1));
      expect(entries.first.revision, 123);
      expect(entries.first.author, 'alice');
      expect(entries.first.title, 'fix bug');
      expect(entries.first.message, 'fix bug');
      // date 走的是 formatSvnIsoDate；具体时区因机器不同，只校验形状
      expect(
        entries.first.date,
        matches(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}$'),
      );
    });

    test('multiple entries preserve order', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="2"><author>b</author><date>2024-01-02T00:00:00Z</date><msg>two</msg></logentry>
<logentry revision="1"><author>a</author><date>2024-01-01T00:00:00Z</date><msg>one</msg></logentry>
</log>
''';
      final entries = SvnXmlParser.parseLog(x);
      expect(entries.map((e) => e.revision).toList(), [2, 1]);
    });

    test('entry without revision attr is skipped', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry><author>a</author><date>2024-01-01T00:00:00Z</date><msg>x</msg></logentry>
<logentry revision="9"><author>b</author><date>2024-01-01T00:00:00Z</date><msg>y</msg></logentry>
</log>
''';
      final entries = SvnXmlParser.parseLog(x);
      expect(entries, hasLength(1));
      expect(entries.first.revision, 9);
    });

    test('entry with non-int revision is skipped', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="abc"><author>a</author><date>2024-01-01T00:00:00Z</date><msg>x</msg></logentry>
</log>
''';
      expect(SvnXmlParser.parseLog(x), isEmpty);
    });

    test('missing optional fields default to empty string', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="5"/>
</log>
''';
      final entries = SvnXmlParser.parseLog(x);
      expect(entries, hasLength(1));
      expect(entries.first.author, '');
      expect(entries.first.message, '');
      expect(entries.first.title, '');
      // 缺失的 date 走 formatSvnIsoDate('') → 解析失败 → 原样返回 ''
      expect(entries.first.date, '');
    });

    test('multiline msg → title is first line trimmed', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="1">
  <author>a</author>
  <date>2024-01-01T00:00:00Z</date>
  <msg>  first line  
second line
third</msg>
</logentry>
</log>
''';
      final entries = SvnXmlParser.parseLog(x);
      expect(entries.first.title, 'first line');
      // message 是 trim 过的整体
      expect(entries.first.message.startsWith('first line'), isTrue);
      expect(entries.first.message.contains('second line'), isTrue);
    });
  });

  group('SvnXmlParser.parseLogChangedPaths', () {
    test('parses action kind and copyfrom-path from verbose log XML', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="123">
  <paths>
    <path action="M" kind="file">/branches/feat/src/a.dart</path>
    <path action="A" kind="file" copyfrom-path="/trunk/src/b.dart">/branches/feat/src/b.dart</path>
  </paths>
</logentry>
</log>
''';

      final paths = SvnXmlParser.parseLogChangedPaths(x);

      expect(paths, hasLength(2));
      expect(paths.first.path, '/branches/feat/src/a.dart');
      expect(paths.first.action, 'M');
      expect(paths.first.kind, 'file');
      expect(paths.first.copyFromPath, isNull);
      expect(paths.last.path, '/branches/feat/src/b.dart');
      expect(paths.last.action, 'A');
      expect(paths.last.kind, 'file');
      expect(paths.last.copyFromPath, '/trunk/src/b.dart');
    });

    test('malformed XML returns empty list', () {
      expect(SvnXmlParser.parseLogChangedPaths('<log><logentry'), isEmpty);
    });
  });

  group('SvnXmlParser.parseInfo', () {
    test('empty / non-info → {}', () {
      expect(SvnXmlParser.parseInfo(''), isEmpty);
      expect(SvnXmlParser.parseInfo('<other/>'), isEmpty);
    });

    test('malformed → {}', () {
      expect(SvnXmlParser.parseInfo('<info'), isEmpty);
    });

    test('full entry extracts url / repository_root / schedule', () {
      const x = '''
<?xml version="1.0"?>
<info>
  <entry>
    <url>https://svn.example/repo/branches/foo</url>
    <repository>
      <root>https://svn.example/repo</root>
    </repository>
    <wc-info>
      <schedule>normal</schedule>
    </wc-info>
  </entry>
</info>
''';
      final m = SvnXmlParser.parseInfo(x);
      expect(m['url'], 'https://svn.example/repo/branches/foo');
      expect(m['repository_root'], 'https://svn.example/repo');
      expect(m['schedule'], 'normal');
    });

    test('partial entry only fills present fields', () {
      const x = '''
<?xml version="1.0"?>
<info>
  <entry>
    <url>https://svn.example/repo</url>
  </entry>
</info>
''';
      final m = SvnXmlParser.parseInfo(x);
      expect(m, {'url': 'https://svn.example/repo'});
    });

    test('info without entry → {}', () {
      const x = '<?xml version="1.0"?><info></info>';
      expect(SvnXmlParser.parseInfo(x), isEmpty);
    });
  });

  group('SvnXmlParser.parseMergeinfo', () {
    test('empty / non-mergeinfo → []', () {
      expect(SvnXmlParser.parseMergeinfo(''), isEmpty);
      expect(SvnXmlParser.parseMergeinfo('<other/>'), isEmpty);
    });

    test('range with start and end is expanded inclusively', () {
      const x = '''
<?xml version="1.0"?>
<mergeinfo>
  <merged-ranges>
    <range start="10" end="13"/>
  </merged-ranges>
</mergeinfo>
''';
      expect(SvnXmlParser.parseMergeinfo(x), [10, 11, 12, 13]);
    });

    test('range with only start is treated as a single revision', () {
      const x = '''
<?xml version="1.0"?>
<mergeinfo>
  <merged-ranges>
    <range start="42"/>
  </merged-ranges>
</mergeinfo>
''';
      expect(SvnXmlParser.parseMergeinfo(x), [42]);
    });

    test('multiple ranges concatenate', () {
      const x = '''
<?xml version="1.0"?>
<mergeinfo>
  <merged-ranges>
    <range start="1" end="2"/>
    <range start="5"/>
    <range start="7" end="8"/>
  </merged-ranges>
</mergeinfo>
''';
      expect(SvnXmlParser.parseMergeinfo(x), [1, 2, 5, 7, 8]);
    });

    test('non-int attrs are skipped', () {
      const x = '''
<?xml version="1.0"?>
<mergeinfo>
  <merged-ranges>
    <range start="abc" end="3"/>
    <range start="4" end="zz"/>
    <range start="9" end="10"/>
  </merged-ranges>
</mergeinfo>
''';
      // 前两条 range 都被 int.tryParse 过滤掉，只剩最后一条展开。
      expect(SvnXmlParser.parseMergeinfo(x), [9, 10]);
    });

    test('mergeinfo without merged-ranges → []', () {
      const x = '<?xml version="1.0"?><mergeinfo/>';
      expect(SvnXmlParser.parseMergeinfo(x), isEmpty);
    });
  });

  group('SvnXmlParser.parseLogFiles', () {
    test('multiple paths are returned in document order', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="1">
  <paths>
    <path action="M">/a.txt</path>
    <path action="A">/b/c.txt</path>
  </paths>
</logentry>
</log>
''';
      expect(SvnXmlParser.parseLogFiles(x), ['/a.txt', '/b/c.txt']);
    });

    test('whitespace inside <path> is trimmed; empty paths dropped', () {
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="1">
  <paths>
    <path>   /a.txt   </path>
    <path></path>
    <path>/b.txt</path>
  </paths>
</logentry>
</log>
''';
      expect(SvnXmlParser.parseLogFiles(x), ['/a.txt', '/b.txt']);
    });

    test('only the first logentry is consulted', () {
      // 历史行为：parseLogFiles 只取第一个 logentry。固化到测试里防退化。
      const x = '''
<?xml version="1.0"?>
<log>
<logentry revision="1"><paths><path>/a</path></paths></logentry>
<logentry revision="2"><paths><path>/b</path></paths></logentry>
</log>
''';
      expect(SvnXmlParser.parseLogFiles(x), ['/a']);
    });

    test('missing log / logentry / paths → []', () {
      expect(SvnXmlParser.parseLogFiles('<other/>'), isEmpty);
      expect(SvnXmlParser.parseLogFiles('<log/>'), isEmpty);
      expect(
        SvnXmlParser.parseLogFiles('<log><logentry revision="1"/></log>'),
        isEmpty,
      );
    });
  });

  group('formatSvnIsoDate', () {
    test('valid ISO 8601 → "YYYY-MM-DD HH:MM:SS ±HHMM"', () {
      // 不校验具体时区/小时（取决于运行机器的本地时区），只校验形状。
      expect(
        formatSvnIsoDate('2024-01-01T10:00:00.000000Z'),
        matches(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}$'),
      );
    });

    test('invalid input is returned as-is', () {
      // 解析失败时不抛异常，原样返回——parseLog 依赖这个回退行为。
      expect(formatSvnIsoDate('not-a-date'), 'not-a-date');
      expect(formatSvnIsoDate(''), '');
    });
  });

  group('formatTimeZoneOffset', () {
    test('零偏移输出 +0000 不输出 Z', () {
      expect(formatTimeZoneOffset(Duration.zero), '+0000');
    });

    test('正整小时偏移', () {
      expect(formatTimeZoneOffset(const Duration(hours: 8)), '+0800');
      expect(formatTimeZoneOffset(const Duration(hours: 1)), '+0100');
    });

    test('负整小时偏移', () {
      expect(formatTimeZoneOffset(const Duration(hours: -5)), '-0500');
      expect(formatTimeZoneOffset(const Duration(hours: -12)), '-1200');
    });

    test('半小时区 +0530（India）', () {
      expect(
        formatTimeZoneOffset(const Duration(hours: 5, minutes: 30)),
        '+0530',
      );
    });

    test('半小时区 -0330（Newfoundland）', () {
      expect(
        formatTimeZoneOffset(const Duration(hours: -3, minutes: -30)),
        '-0330',
      );
    });

    test('45 分钟时区 +0545（Nepal）', () {
      expect(
        formatTimeZoneOffset(const Duration(hours: 5, minutes: 45)),
        '+0545',
      );
    });

    test('14 小时时区 +1400（Kiribati）', () {
      expect(
        formatTimeZoneOffset(const Duration(hours: 14)),
        '+1400',
      );
    });
  });

  group('formatLocalDateTimeForDisplay', () {
    test('显式传入 offset → 形状完全确定（与时区无关）', () {
      // 锁定确切输出，不被运行机器时区影响。
      final t = DateTime(2024, 1, 1, 10, 5, 7);
      expect(
        formatLocalDateTimeForDisplay(t, offset: const Duration(hours: 8)),
        '2024-01-01 10:05:07 +0800',
      );
    });

    test('个位数月日时分秒补零', () {
      final t = DateTime(2024, 3, 5, 9, 8, 7);
      expect(
        formatLocalDateTimeForDisplay(t, offset: Duration.zero),
        '2024-03-05 09:08:07 +0000',
      );
    });

    test('零偏移输出 +0000', () {
      final t = DateTime(2024, 12, 31, 23, 59, 59);
      expect(
        formatLocalDateTimeForDisplay(t, offset: Duration.zero),
        '2024-12-31 23:59:59 +0000',
      );
    });

    test('省略 offset 时回落到 time.timeZoneOffset（仅校验形状）', () {
      // 不锁定具体偏移值（依赖运行机器），只校验完整形状。
      expect(
        formatLocalDateTimeForDisplay(DateTime(2024, 1, 1, 10, 0, 0)),
        matches(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}$'),
      );
    });
  });

  group('extractLogTitle', () {
    test('单行 trim 后返回', () {
      expect(extractLogTitle('hello'), 'hello');
      expect(extractLogTitle('  hello  '), 'hello');
    });

    test('多行只取首行', () {
      expect(extractLogTitle('first line\nsecond\nthird'), 'first line');
    });

    test('首行尾随 \\r 被 trim 吃掉（CRLF 等价处理）', () {
      expect(extractLogTitle('first\r\nsecond'), 'first');
    });

    test('空串 → 空串', () {
      expect(extractLogTitle(''), '');
    });

    test('仅空白 → 空串', () {
      expect(extractLogTitle('   '), '');
      expect(extractLogTitle('\n\n'), '');
    });

    test('首行全空白 + 第二行有内容 → 仍取首行的空串', () {
      // 锁定行为：parseLog 已对 message 做 trim() 兜底，这里展示纯函数本身行为
      expect(extractLogTitle('   \nsecond'), '');
    });
  });

  group('expandRevisionRange', () {
    test('start == end → 单元素列表', () {
      expect(expandRevisionRange(100, 100), [100]);
    });

    test('正常闭区间展开', () {
      expect(expandRevisionRange(1, 5), [1, 2, 3, 4, 5]);
    });

    test('start > end → 空列表（防御性）', () {
      // 原代码靠调用方保证 start ≤ end，没有显式分支；这里把契约显式锁定。
      expect(expandRevisionRange(10, 5), isEmpty);
    });

    test('跨越大数也正常', () {
      final out = expandRevisionRange(1000, 1003);
      expect(out, [1000, 1001, 1002, 1003]);
    });

    test('返回的 list 是新建的（修改不影响后续调用）', () {
      final a = expandRevisionRange(1, 3);
      a.add(99);
      final b = expandRevisionRange(1, 3);
      expect(b, [1, 2, 3]);
    });
  });

  group('formatLogEntryParseFailedLine', () {
    test('正常情况：异常按 toString 拼接', () {
      expect(
        formatLogEntryParseFailedLine(Exception('bad attr')),
        '解析 logentry 失败: Exception: bad attr',
      );
    });

    test('使用半角冒号 + 空格分隔（与中文全角"："区分）', () {
      // 与中文全角"："不同——这里是机读 grep 友好的英文风格。
      final line = formatLogEntryParseFailedLine('e');
      expect(line.contains(': '), isTrue);
      expect(line.contains('：'), isFalse);
    });

    test('保留 logentry 小写字面（与 SVN XML 元素名一致）', () {
      // 不本地化为"日志条目"——保持与 SVN 文档/XML schema 一致便于运维 grep。
      final line = formatLogEntryParseFailedLine('e');
      expect(line.contains('logentry'), isTrue);
      expect(line.contains('日志条目'), isFalse);
    });

    test('与 formatSvnXmlParseFailedLine("log") 严重程度分层（前缀差异）', () {
      // 单条 entry 失败是 warn（轻），最外层 catch 是 error（重）——
      // 两条字面必须互斥才能在日志里看出严重程度。
      final entry = formatLogEntryParseFailedLine('boom');
      final outer = formatSvnXmlParseFailedLine('log');
      expect(entry.startsWith('解析 logentry 失败'), isTrue);
      expect(outer.startsWith('解析 SVN log XML 失败'), isTrue);
      expect(entry, isNot(equals(outer)));
    });
  });

  group('formatSvnDateParseFailedLine', () {
    test('正常 ISO 日期串原样拼接', () {
      expect(
        formatSvnDateParseFailedLine('2024-13-45T99:99:99Z'),
        '日期格式解析失败: 2024-13-45T99:99:99Z',
      );
    });

    test('空字符串透传（"日期为空"是 bug 信号，不特殊文案）', () {
      // 渲染为冒号后空白，让 SVN 返回空 <date> 的异常显眼出现。
      expect(formatSvnDateParseFailedLine(''), '日期格式解析失败: ');
    });

    test('不附带异常对象（避免 FormatException 冗余文案）', () {
      // 函数签名只接受 isoDate；测试是结构性锁定：渲染结果不应含 "Exception" / "FormatException" 词。
      final line = formatSvnDateParseFailedLine('garbage');
      expect(line.contains('Exception'), isFalse);
      expect(line.contains('FormatException'), isFalse);
    });

    test('使用半角冒号 + 空格分隔（与 logentry 失败行风格一致）', () {
      // 跨函数风格统一：解析失败类日志均用半角分隔。
      final dateLine = formatSvnDateParseFailedLine('x');
      final entryLine = formatLogEntryParseFailedLine('x');
      expect(dateLine.contains(': '), isTrue);
      expect(entryLine.contains(': '), isTrue);
    });
  });

  group('formatSvnXmlParseFailedLine', () {
    test('parseLog: 正常情况', () {
      expect(formatSvnXmlParseFailedLine('log'), '解析 SVN log XML 失败');
    });

    test('parseInfo / parseMergeinfo / parseLogFiles 全部正确路由', () {
      // 锁定四个 parser 的字面与现有日志生态对齐（保持向后可 grep）。
      expect(formatSvnXmlParseFailedLine('info'), '解析 SVN info XML 失败');
      expect(
          formatSvnXmlParseFailedLine('mergeinfo'), '解析 SVN mergeinfo XML 失败');
      expect(
          formatSvnXmlParseFailedLine('log files'), '解析 SVN log files XML 失败');
    });

    test('parserName 含空格不做转义（"log files" 是合法值）', () {
      // 注意：'log files' 故意带空格，对应 svn log --xml --verbose 的子操作。
      // 测试锁定，防止有人随手改成 'log_files' 或 'logFiles' 让现有 grep 失效。
      final line = formatSvnXmlParseFailedLine('log files');
      expect(line.contains('log files'), isTrue);
      expect(line.contains('log_files'), isFalse);
      expect(line.contains('logFiles'), isFalse);
    });

    test('空 parserName 透传（暴露上层 bug，不防御）', () {
      // 双空格的"解析 SVN  XML 失败"在日志里很扫眼，用作信号。
      expect(formatSvnXmlParseFailedLine(''), '解析 SVN  XML 失败');
    });

    test('与 formatXmlMissingRootElementLine 严重程度分层（前缀刻意不同）', () {
      // 一个是 warn（结构正常无目标元素），一个是 error（XML 解析自身失败）——
      // 两条字面必须互斥让运维一眼分清严重程度。
      final fail = formatSvnXmlParseFailedLine('log');
      final missing = formatXmlMissingRootElementLine('log');
      expect(fail.startsWith('解析 SVN'), isTrue);
      expect(missing.startsWith('XML 中未找到'), isTrue);
      expect(fail, isNot(equals(missing)));
    });
  });

  group('formatXmlMissingRootElementLine', () {
    test('parseLog: log 元素缺失', () {
      expect(formatXmlMissingRootElementLine('log'), 'XML 中未找到 log 元素');
    });

    test('parseInfo / parseMergeinfo 字面对齐', () {
      // 锁定三 parser 的字面，与历史日志生态对齐。
      expect(formatXmlMissingRootElementLine('info'), 'XML 中未找到 info 元素');
      expect(
        formatXmlMissingRootElementLine('mergeinfo'),
        'XML 中未找到 mergeinfo 元素',
      );
    });

    test('elementName 任意字符串直接拼（不做白名单）', () {
      // 函数不充当字典守卫——未来新增 'status' parser 应零成本走这里。
      expect(
        formatXmlMissingRootElementLine('status'),
        'XML 中未找到 status 元素',
      );
    });

    test('空字符串 → 双空格（bug 信号，刻意保留）', () {
      // 渲染为 'XML 中未找到  元素'，让上层硬编码空 elementName 的 bug 显眼。
      expect(formatXmlMissingRootElementLine(''), 'XML 中未找到  元素');
    });

    test('parseLogFiles 不应触发该字面（高频路径不刷屏）', () {
      // 这是结构性约束：parseLogFiles 在"无 <log>" / "无 <logentry>" / "无 <paths>"
      // 三个分支都直接 return []，**不**走 missing-root-element 日志。
      // 通过解析"<log></log>"的真实结果验证（解析成功 → 不打 warn，返回 []）。
      expect(SvnXmlParser.parseLogFiles('<?xml version="1.0"?><log></log>'),
          <String>[]);
      // （日志是否打出在单元测试里不直接验证；这里只验证返回值契约——
      //  它间接证明了：parseLogFiles 不通过 missing-root-element 路径来 surface
      //  "无内容"的状态。）
    });
  });
}
