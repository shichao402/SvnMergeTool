import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/log_entry.dart';

void main() {
  group('LogEntry.toString (via formatLogEntryShort)', () {
    test('正常情况：4 段 + 3 个 " | " 分隔符', () {
      const entry = LogEntry(
        revision: 12345,
        author: 'alice',
        date: '2024-01-01 10:00:00 +0800',
        title: 'Fix bug',
        message: 'Fix bug\nDetails...',
      );
      expect(
        entry.toString(),
        'r12345 | alice | 2024-01-01 10:00:00 +0800 | Fix bug',
      );
    });

    test('toString 与 formatLogEntryShort 输出等价', () {
      const entry = LogEntry(
        revision: 1,
        author: 'a',
        date: 'd',
        title: 't',
        message: 'm',
      );
      expect(
        entry.toString(),
        formatLogEntryShort(revision: 1, author: 'a', date: 'd', title: 't'),
      );
    });
  });

  group('extractMessageFirstLine', () {
    test('多行：取 \\n 前首段', () {
      expect(extractMessageFirstLine('title\nbody\nmore'), 'title');
    });

    test('单行（无换行）→ 整段返回', () {
      expect(extractMessageFirstLine('only line'), 'only line');
    });

    test('空字符串 → 空字符串', () {
      expect(extractMessageFirstLine(''), '');
    });

    test('刻意不 trim：首行末尾空格保留（与 svn_xml_parser.extractLogTitle 区分）', () {
      // 与 svn_xml_parser 的 extractLogTitle 刻意分两份：那个会额外 trim，
      // 本函数不 trim——外层已 trim 整段，再 trim 首行会去掉首行末尾的合法空白。
      expect(extractMessageFirstLine('hello \nworld'), 'hello ');
    });

    test('首字符就是 \\n → 返回空串', () {
      // 上层 message 已 trim 过整段，正常不会出现这种输入；测试锁定降级行为。
      expect(extractMessageFirstLine('\nbody'), '');
    });

    test('\\r\\n 行尾保留 \\r（不识别 Windows 行尾）', () {
      // 仅按 \n 切分，\r 留在首段末尾。SVN 客户端在 Unix/macOS 平台是主路径，
      // 不为可能存在的 Windows 行尾做特殊处理——保持纯函数职责单一。
      expect(extractMessageFirstLine('hello\r\nworld'), 'hello\r');
    });
  });

  group('formatLogEntryShort', () {
    test('正常情况：固定结构', () {
      expect(
        formatLogEntryShort(
          revision: 100,
          author: 'bob',
          date: '2024-02-02',
          title: 'feat',
        ),
        'r100 | bob | 2024-02-02 | feat',
      );
    });

    test('段顺序锁定：revision → author → date → title', () {
      final line = formatLogEntryShort(
        revision: 99,
        author: 'AUTHOR',
        date: 'DATE',
        title: 'TITLE',
      );
      final iRev = line.indexOf('r99');
      final iAuthor = line.indexOf('AUTHOR');
      final iDate = line.indexOf('DATE');
      final iTitle = line.indexOf('TITLE');
      expect(iRev, 0);
      expect(iRev < iAuthor, isTrue);
      expect(iAuthor < iDate, isTrue);
      expect(iDate < iTitle, isTrue);
    });

    test('恰好 3 个 " | " 分隔符', () {
      // 运维通过 ' | ' 切片做日志分析——分隔符出现次数必须稳定。
      final line = formatLogEntryShort(
        revision: 1,
        author: 'a',
        date: 'd',
        title: 't',
      );
      expect(' | '.allMatches(line).length, 3);
    });

    test('空 author → "r1 |  | ..."（双空格作为 bug 信号）', () {
      final line = formatLogEntryShort(
        revision: 1,
        author: '',
        date: 'd',
        title: 't',
      );
      expect(line.contains('r1 |  | d'), isTrue);
    });

    test('revision 负数透传（暴露上游 bug，不防御）', () {
      // SVN revision 永远 >= 1；负数 = 上游 bug 应当显眼。
      final line = formatLogEntryShort(
        revision: -1,
        author: 'a',
        date: 'd',
        title: 't',
      );
      expect(line.startsWith('r-1 '), isTrue);
    });

    test('与 MergeJob 的 formatJobDescription 风格一致但段数不同（4 vs 5）', () {
      // 两个渲染共用半角竖线 + 两侧空格的风格；但段数与装饰不同，函数刻意分开。
      final line = formatLogEntryShort(
        revision: 1,
        author: 'a',
        date: 'd',
        title: 't',
      );
      // 4 段 → 3 个分隔符（formatJobDescription 是 5 段 → 4 个分隔符之一为可选；
      // 这里只断言 LogEntry 侧的稳定性）。
      expect(' | '.allMatches(line).length, 3);
    });
  });

  group('isSvnLogHeaderLine', () {
    test('合法头行 → true', () {
      expect(
        isSvnLogHeaderLine('r12345 | alice | 2024-01-01 | 2 lines'),
        isTrue,
      );
    });

    test('单字符 r 开头但缺少 " | " → false', () {
      expect(isSvnLogHeaderLine('r12345 alice'), isFalse);
    });

    test('含 " | " 但不以 r 开头 → false', () {
      expect(isSvnLogHeaderLine('alice | something'), isFalse);
    });

    test('空字符串 → false', () {
      expect(isSvnLogHeaderLine(''), isFalse);
    });

    test('大写 R 不识别（按 SVN 字面，不做大小写归一化）', () {
      // SVN 总是输出小写 'r'，按字面匹配。
      expect(
        isSvnLogHeaderLine('R12345 | alice | 2024-01-01 | 2 lines'),
        isFalse,
      );
    });

    test('故意宽松：不校验段数 / revision 数字（那是 parseSvnLogHeaderRevision 的职责）', () {
      // 这个函数只快速过滤，不当字典守卫——具体校验交给 parser。
      expect(isSvnLogHeaderLine('rXYZ | a | b'), isTrue);
      expect(isSvnLogHeaderLine('rXYZ | a'), isTrue);
    });
  });

  group('isSvnLogMessageEndLine', () {
    test('原始 "--------" 起始 → true', () {
      expect(isSvnLogMessageEndLine('--------'), isTrue);
    });

    test('SVN 实际输出的 72 个连字符 → true', () {
      expect(isSvnLogMessageEndLine('-' * 72), isTrue);
    });

    test('空字符串 → false（与 isSvnLogSeparatorLine 刻意不同）', () {
      // 空行是消息体的一部分，不能当作消息结束信号——否则会过早截断消息体。
      expect(isSvnLogMessageEndLine(''), isFalse);
    });

    test('前置空白破坏 startsWith → false（不 trim）', () {
      // 入参是原始行（未 trim），保留消息体内缩进——若提前 trim 会丢失代码块缩进。
      expect(isSvnLogMessageEndLine('   --------'), isFalse);
      expect(isSvnLogMessageEndLine('\t--------'), isFalse);
    });

    test('普通业务行 → false', () {
      expect(isSvnLogMessageEndLine('Commit message'), isFalse);
      expect(isSvnLogMessageEndLine('r12345 | a | b | c'), isFalse);
    });

    test('与 isSvnLogSeparatorLine 在边界上的差异', () {
      // isSvnLogSeparatorLine('') = true；isSvnLogMessageEndLine('') = false。
      // 两个函数刻意不能合并：用途不同（头部前过滤 vs 消息体结束信号）。
      expect(isSvnLogSeparatorLine(''), isTrue);
      expect(isSvnLogMessageEndLine(''), isFalse);
    });

    test('7 个连字符 → false（startsWith 不到阈值）', () {
      expect(isSvnLogMessageEndLine('-------'), isFalse);
    });
  });

  group('isSvnLogSeparatorLine', () {
    test('空字符串 → true（trim 后空行）', () {
      expect(isSvnLogSeparatorLine(''), isTrue);
    });

    test('72 个连字符（SVN 实际输出）→ true', () {
      expect(
        isSvnLogSeparatorLine('-' * 72),
        isTrue,
      );
    });

    test('8 个连字符（最小阈值）→ true', () {
      // 阈值是 8 而非 72：SVN 不同版本/语言环境的分隔长度可能略有差异，宽松匹配避免假阴性。
      expect(isSvnLogSeparatorLine('--------'), isTrue);
    });

    test('7 个连字符 → false（低于阈值）', () {
      expect(isSvnLogSeparatorLine('-------'), isFalse);
    });

    test('连字符开头但前置其它字符 → false', () {
      // startsWith 严格匹配开头。
      expect(isSvnLogSeparatorLine('a--------'), isFalse);
      expect(isSvnLogSeparatorLine(' --------'), isFalse);
    });

    test('普通业务行 → false', () {
      expect(
        isSvnLogSeparatorLine('r12345 | alice | 2024 | 2 lines'),
        isFalse,
      );
      expect(isSvnLogSeparatorLine('Commit message'), isFalse);
    });
  });

  group('parseSvnLogHeader', () {
    test('正常头：返回 (revision, author, date) 三元组', () {
      final header = parseSvnLogHeader(
        'r12345 | alice | 2024-01-01 10:00:00 +0800 (Mon, 01 Jan 2024) | 2 lines',
      );
      expect(header, isNotNull);
      expect(header!.revision, 12345);
      expect(header.author, 'alice');
      expect(header.date, '2024-01-01 10:00:00 +0800 (Mon, 01 Jan 2024)');
    });

    test('author / date 段会被 trim', () {
      // 与 SvnLogParser 原 inline `parts[1].trim()` / `parts[2].trim()` 行为一致。
      final header = parseSvnLogHeader('r1 |   alice   |   2024-01-01   | 1 lines');
      expect(header, isNotNull);
      expect(header!.author, 'alice');
      expect(header.date, '2024-01-01');
    });

    test('不以 r 起始 → null', () {
      expect(parseSvnLogHeader('alice | bob | c | d'), isNull);
    });

    test('段数 < 4 → null', () {
      expect(parseSvnLogHeader('r1 | a | b'), isNull);
      expect(parseSvnLogHeader('r1'), isNull);
      expect(parseSvnLogHeader('r1 | a'), isNull);
    });

    test('r 后非数字 → null（不抛异常）', () {
      // 文本解析是降级路径——所有失败一律 null。
      expect(parseSvnLogHeader('rXYZ | a | b | c'), isNull);
    });

    test('r 后跟空 → null（int.tryParse(\'\') = null）', () {
      expect(parseSvnLogHeader('r | a | b | c'), isNull);
    });

    test('空字符串 → null', () {
      expect(parseSvnLogHeader(''), isNull);
    });

    test('与 parseSvnLogHeaderRevision 的 revision 字段始终一致', () {
      // 双函数共存的契约锁——任何一边修了都不应让 revision 解析行为漂移。
      const cases = [
        'r12345 | alice | 2024-01-01 | 2 lines',
        'r999999 | a | b | c',
        'r1 | a | b | c',
      ];
      for (final c in cases) {
        expect(parseSvnLogHeader(c)?.revision, parseSvnLogHeaderRevision(c));
      }
    });

    test('段数恰好 4 → 成功（边界）', () {
      // 至少 4 段就够（rev / author / date / 'N lines'），不要求 == 4。
      final header = parseSvnLogHeader('r1 | a | b | c');
      expect(header, isNotNull);
      expect(header!.revision, 1);
    });

    test('段数 > 4 → 仍成功（多余段被忽略）', () {
      // SVN 头本应恰好 4 段，多出的段不影响 revision/author/date 抽取。
      final header = parseSvnLogHeader('r1 | a | b | c | d | e');
      expect(header, isNotNull);
      expect(header!.author, 'a');
      expect(header.date, 'b');
    });
  });

  group('parseSvnLogHeaderRevision', () {
    test('正常头：返回 revision 数字', () {
      expect(
        parseSvnLogHeaderRevision('r12345 | alice | 2024-01-01 | 2 lines'),
        12345,
      );
    });

    test('段数 < 4 → null（不抛异常）', () {
      expect(parseSvnLogHeaderRevision('r1 | a | b'), isNull);
      expect(parseSvnLogHeaderRevision('r1'), isNull);
      expect(parseSvnLogHeaderRevision(''), isNull);
    });

    test('第一段不以 r 起始 → null（冗余兜底）', () {
      // 实际调用前会过 isSvnLogHeaderLine，但本函数依然防线冗余。
      expect(
        parseSvnLogHeaderRevision('alice | bob | c | d'),
        isNull,
      );
    });

    test('r 后非数字 → null', () {
      expect(
        parseSvnLogHeaderRevision('rXYZ | a | b | c'),
        isNull,
      );
    });

    test('空字符串 → null（不抛异常）', () {
      // 文本解析是降级路径，**所有失败一律 null**，让上层跳过坏记录继续。
      expect(parseSvnLogHeaderRevision(''), isNull);
    });

    test('r 后跟空 → null（int.tryParse(\'\') = null）', () {
      expect(
        parseSvnLogHeaderRevision('r | a | b | c'),
        isNull,
      );
    });

    test('revision 大数（int 范围内）正常解析', () {
      expect(
        parseSvnLogHeaderRevision('r999999 | a | b | c'),
        999999,
      );
    });
  });

  group('SvnLogParser.parse 端到端（验证抽出的纯函数协同）', () {
    test('完整 SVN 日志格式：解析 1 条 entry', () {
      const raw = '''------------------------------------------------------------------------
r12345 | alice | 2024-01-01 10:00:00 +0800 (Mon, 01 Jan 2024) | 2 lines

Fix authentication bug
Details about the fix
------------------------------------------------------------------------''';
      final entries = SvnLogParser.parse(raw);
      expect(entries.length, 1);
      expect(entries[0].revision, 12345);
      expect(entries[0].author, 'alice');
      expect(entries[0].date, '2024-01-01 10:00:00 +0800 (Mon, 01 Jan 2024)');
      expect(entries[0].title, 'Fix authentication bug');
      expect(entries[0].message, 'Fix authentication bug\nDetails about the fix');
    });

    test('多条 entry：顺序保留', () {
      const raw = '''------------------------------------------------------------------------
r1 | alice | 2024-01-01 | 1 lines

First
------------------------------------------------------------------------
r2 | bob | 2024-01-02 | 1 lines

Second
------------------------------------------------------------------------''';
      final entries = SvnLogParser.parse(raw);
      expect(entries.length, 2);
      expect(entries[0].revision, 1);
      expect(entries[0].title, 'First');
      expect(entries[1].revision, 2);
      expect(entries[1].title, 'Second');
    });

    test('空输入 → 空列表', () {
      expect(SvnLogParser.parse(''), <LogEntry>[]);
    });

    test('坏 revision 头 → 跳过该 entry，不崩溃', () {
      // parseSvnLogHeaderRevision 返回 null 时本应跳过——文本解析是降级路径。
      const raw = '''------------------------------------------------------------------------
rXYZ | alice | 2024-01-01 | 1 lines

Bad
------------------------------------------------------------------------
r2 | bob | 2024-01-02 | 1 lines

Good
------------------------------------------------------------------------''';
      final entries = SvnLogParser.parse(raw);
      expect(entries.length, 1);
      expect(entries[0].revision, 2);
    });
  });

  // R101 LogEntry round-trip 完整性审计：
  // log_entry.dart 内 LogEntry 类 5 字段全 required，无 nullable 字段、无 default。
  // 但 message 字段可能含特殊字符（换行/制表/Unicode）——round-trip 时必须不丢失。
  group('LogEntry round-trip 完整性（R101）', () {
    test('全字段非默认值 round-trip', () {
      const original = LogEntry(
        revision: 12345,
        author: 'alice@example.com',
        date: '2024-01-15T10:30:45+0800',
        title: '修复严重 bug',
        message: '修复严重 bug\n\n详细描述：\n- 问题原因\n- 修复方案',
      );
      final restored = LogEntry.fromJson(original.toJson());
      expect(restored.revision, original.revision);
      expect(restored.author, original.author);
      expect(restored.date, original.date);
      expect(restored.title, original.title);
      expect(restored.message, original.message,
          reason: 'message 字段含 \\n 等特殊字符——round-trip 必须不丢失。');
    });

    test('message 含特殊字符 round-trip：制表符 / Unicode / 引号', () {
      // 防御 JSON 编解码层把特殊字符吞掉的退化——历史 commit message 可能含任意字符。
      const original = LogEntry(
        revision: 1,
        author: 'bob',
        date: '2024-01-01',
        title: 'tab\there',
        message: '中文 emoji\u{1f600} "quoted" \tindented\nline2',
      );
      final restored = LogEntry.fromJson(original.toJson());
      expect(restored.message, original.message,
          reason: 'JSON 编解码层应保留所有特殊字符。');
      expect(restored.title, original.title);
    });

    test('空字符串字段 round-trip（边界）', () {
      // SVN 历史 commit 可能 author/title/message 都为空（异常 commit）——
      // 不能崩，且空串必须保持为空串、不被替换为 null。
      const original = LogEntry(
        revision: 0,
        author: '',
        date: '',
        title: '',
        message: '',
      );
      final restored = LogEntry.fromJson(original.toJson());
      expect(restored.revision, 0);
      expect(restored.author, '');
      expect(restored.date, '');
      expect(restored.title, '');
      expect(restored.message, '');
    });
  });

  // R102 LogEntry.copyWith 全字段对称性审计：
  // log_entry.dart:172 LogEntry copyWith 5 字段全 non-nullable，无 reset-to-null 风险。
  // 原本 0 个 copyWith 测试——本轮补"全字段独立可改"对称性。
  group('LogEntry copyWith 全字段对称性（R102）', () {
    const baseline = LogEntry(
      revision: 100,
      author: 'baseline-author',
      date: '2024-01-01',
      title: 'baseline-title',
      message: 'baseline-message',
    );

    test('修改单个字段时其他 4 字段全部保持原值', () {
      final modRev = baseline.copyWith(revision: 999);
      expect(modRev.revision, 999);
      expect(modRev.author, baseline.author);
      expect(modRev.date, baseline.date);
      expect(modRev.title, baseline.title);
      expect(modRev.message, baseline.message);

      final modAuthor = baseline.copyWith(author: 'new-author');
      expect(modAuthor.author, 'new-author');
      expect(modAuthor.revision, baseline.revision);

      final modDate = baseline.copyWith(date: '2099-12-31');
      expect(modDate.date, '2099-12-31');
      expect(modDate.author, baseline.author);

      final modTitle = baseline.copyWith(title: 'new-title');
      expect(modTitle.title, 'new-title');
      expect(modTitle.message, baseline.message);

      final modMessage = baseline.copyWith(message: 'new-message');
      expect(modMessage.message, 'new-message');
      expect(modMessage.title, baseline.title);
    });

    test('无参 copyWith 等价于副本（保留所有原值）', () {
      final copy = baseline.copyWith();
      expect(copy.revision, baseline.revision);
      expect(copy.author, baseline.author);
      expect(copy.date, baseline.date);
      expect(copy.title, baseline.title);
      expect(copy.message, baseline.message);
    });
  });
}
