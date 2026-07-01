import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/log_entry.dart';
import 'package:svn_auto_merge/services/log_filter_service.dart';

void main() {
  group('computePaginationPlan', () {
    test('totalCount == 0 yields empty plan', () {
      final plan = computePaginationPlan(
        totalCount: 0,
        pageSize: 20,
        requestedPage: 5,
      );
      expect(plan.totalPages, 0);
      expect(plan.adjustedPage, 0);
      expect(plan.offset, 0);
      expect(plan.hasMore, isFalse);
    });

    test('negative totalCount is treated like empty', () {
      // 防御性：如果上游传入异常值不应导致 totalPages 为负数。
      final plan = computePaginationPlan(
        totalCount: -3,
        pageSize: 10,
        requestedPage: 0,
      );
      expect(plan.totalPages, 0);
      expect(plan.adjustedPage, 0);
      expect(plan.offset, 0);
      expect(plan.hasMore, isFalse);
    });

    test('exactly one page', () {
      final plan = computePaginationPlan(
        totalCount: 5,
        pageSize: 20,
        requestedPage: 0,
      );
      expect(plan.totalPages, 1);
      expect(plan.adjustedPage, 0);
      expect(plan.offset, 0);
      expect(plan.hasMore, isFalse);
    });

    test('totalCount equal to pageSize → exactly one full page', () {
      final plan = computePaginationPlan(
        totalCount: 20,
        pageSize: 20,
        requestedPage: 0,
      );
      expect(plan.totalPages, 1);
      expect(plan.hasMore, isFalse);
    });

    test('totalCount one over pageSize → spills into 2nd page', () {
      final plan = computePaginationPlan(
        totalCount: 21,
        pageSize: 20,
        requestedPage: 0,
      );
      expect(plan.totalPages, 2);
      expect(plan.adjustedPage, 0);
      expect(plan.offset, 0);
      expect(plan.hasMore, isTrue);
    });

    test('on last page hasMore is false and offset is correct', () {
      final plan = computePaginationPlan(
        totalCount: 45,
        pageSize: 20,
        requestedPage: 2,
      );
      expect(plan.totalPages, 3); // ceil(45/20) = 3
      expect(plan.adjustedPage, 2);
      expect(plan.offset, 40);
      expect(plan.hasMore, isFalse);
    });

    test('requestedPage beyond last clamps to last', () {
      final plan = computePaginationPlan(
        totalCount: 45,
        pageSize: 20,
        requestedPage: 99,
      );
      expect(plan.adjustedPage, 2);
      expect(plan.offset, 40);
      expect(plan.hasMore, isFalse);
    });

    test('negative requestedPage clamps to 0', () {
      final plan = computePaginationPlan(
        totalCount: 45,
        pageSize: 20,
        requestedPage: -3,
      );
      expect(plan.adjustedPage, 0);
      expect(plan.offset, 0);
      expect(plan.hasMore, isTrue);
    });

    test('pageSize <= 0 throws ArgumentError', () {
      expect(
        () => computePaginationPlan(
          totalCount: 10,
          pageSize: 0,
          requestedPage: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => computePaginationPlan(
          totalCount: 10,
          pageSize: -5,
          requestedPage: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('isUsableWorkingDirectory', () {
    test('null is not usable', () {
      expect(isUsableWorkingDirectory(null), isFalse);
    });

    test('empty string is not usable', () {
      expect(isUsableWorkingDirectory(''), isFalse);
    });

    test('non-empty string is usable', () {
      expect(isUsableWorkingDirectory('/Users/me/wc'), isTrue);
    });
  });

  group('LogFilter.isEmpty', () {
    test('all null is empty', () {
      const f = LogFilter();
      expect(f.isEmpty, isTrue);
    });

    test('empty strings count as empty', () {
      const f = LogFilter(author: '', title: '');
      expect(f.isEmpty, isTrue);
    });

    test('non-empty author makes it non-empty', () {
      const f = LogFilter(author: 'alice');
      expect(f.isEmpty, isFalse);
    });

    test('non-empty title makes it non-empty', () {
      const f = LogFilter(title: 'fix');
      expect(f.isEmpty, isFalse);
    });

    test('minRevision alone makes it non-empty', () {
      const f = LogFilter(minRevision: 100);
      expect(f.isEmpty, isFalse);
    });

    test('non-empty message makes it non-empty', () {
      const f = LogFilter(message: 'fix logging');
      expect(f.isEmpty, isFalse);
    });

    test('empty message stays empty', () {
      const f = LogFilter(author: '', title: '', message: '');
      expect(f.isEmpty, isTrue);
    });
  });

  group('LogFilter.copyWith', () {
    test('replaces individual fields', () {
      const original = LogFilter(author: 'a', title: 't', minRevision: 1);
      final updated = original.copyWith(author: 'b');
      expect(updated.author, 'b');
      expect(updated.title, 't');
      expect(updated.minRevision, 1);
    });

    test('omitting parameters keeps existing values', () {
      const original = LogFilter(author: 'a', title: 't', minRevision: 1);
      final copy = original.copyWith();
      expect(copy.author, 'a');
      expect(copy.title, 't');
      expect(copy.minRevision, 1);
    });

    test('clearMinRevision drops minRevision even if a new one is supplied',
        () {
      // 显式清空优先级最高，避免把「忘了清」误当成「想要保留」。
      const original = LogFilter(minRevision: 100);
      final cleared =
          original.copyWith(minRevision: 200, clearMinRevision: true);
      expect(cleared.minRevision, isNull);
    });

    test('clearMinRevision on a filter without minRevision is a no-op', () {
      const original = LogFilter(author: 'a');
      final cleared = original.copyWith(clearMinRevision: true);
      expect(cleared.minRevision, isNull);
      expect(cleared.author, 'a');
    });

    // R102 LogFilter.copyWith 字段对称性 + 不对称 doc 化（首次明确）：
    // log_filter_service.dart:270 LogFilter.copyWith 3 nullable 字段中，
    //   - minRevision: 通过 `clearMinRevision: true` flag **可以** reset 回 null
    //   - author / title: 用 `?? this.X` 模式，**无法**通过 copyWith reset 回 null
    // 这是**故意不对称设计**——见 lib/providers/app_state.dart:402 setFilter，
    // author/title 的清空路径走"直接 new LogFilter(author: null, title: null, ...)
    // 重建"，而非 copyWith。本测试把这两条契约分别 doc 化。
    test('R102 lib 实测契约 doc 化：copyWith 无法把 author 清回 null', () {
      const original = LogFilter(author: 'alice', title: 'fix');
      final attempt = original.copyWith(author: null);
      expect(attempt.author, 'alice',
          reason: 'copyWith(author: null) 不能清空——`?? this.author` 会回退到原值。'
              '清空 author 走 setFilter (app_state.dart:402) 直接 new LogFilter 路径。');
      expect(attempt.title, 'fix');
    });

    test('R102 lib 实测契约 doc 化：copyWith 无法把 title 清回 null', () {
      const original = LogFilter(author: 'alice', title: 'fix');
      final attempt = original.copyWith(title: null);
      expect(attempt.title, 'fix',
          reason: 'copyWith(title: null) 不能清空——`?? this.title` 会回退到原值。'
              '清空 title 走 setFilter 直接 new LogFilter 路径。');
      expect(attempt.author, 'alice');
    });

    test('R102 全字段独立可改对称性矩阵（3 字段）', () {
      const baseline = LogFilter(author: 'alice', title: 'fix', minRevision: 100);

      final modAuthor = baseline.copyWith(author: 'bob');
      expect(modAuthor.author, 'bob');
      expect(modAuthor.title, baseline.title);
      expect(modAuthor.minRevision, baseline.minRevision);

      final modTitle = baseline.copyWith(title: 'chore');
      expect(modTitle.title, 'chore');
      expect(modTitle.author, baseline.author);
      expect(modTitle.minRevision, baseline.minRevision);

      final modMinRev = baseline.copyWith(minRevision: 200);
      expect(modMinRev.minRevision, 200);
      expect(modMinRev.author, baseline.author);
      expect(modMinRev.title, baseline.title);
    });

    test('copyWith(message:) 替换 message 字段，其他字段保持', () {
      const baseline = LogFilter(author: 'alice', title: 'fix', minRevision: 100);
      final updated = baseline.copyWith(message: 'logging crash');
      expect(updated.message, 'logging crash');
      expect(updated.author, 'alice');
      expect(updated.title, 'fix');
      expect(updated.minRevision, 100);
    });
  });

  group('appLogSeparator', () {
    test('非空字符串', () {
      expect(appLogSeparator, isNotEmpty);
    });

    test('字符锁定为 40 个 U+2501 横线', () {
      // 锁死字符与长度——任何"美化"修改（换 ASCII、加减字符）都要先红再绿。
      // 跨服务共享，迁移自原 log_sync_service 的 syncLogSeparator。
      expect(appLogSeparator.length, 40);
      expect(appLogSeparator, '━' * 40);
    });
  });

  group('formatPaginatedEntriesHeaderLines', () {
    test('完整路径：4 行固定顺序', () {
      final lines = formatPaginatedEntriesHeaderLines(
        sourceUrl: 'svn://repo/trunk',
        page: 2,
        pageSize: 50,
        filter: const LogFilter(author: 'alice', title: 'fix', minRevision: 100),
      );
      expect(lines, [
        '【过滤服务】获取分页数据（只使用最新区间）',
        '  源 URL: svn://repo/trunk',
        '  页码: 2, 每页: 50',
        '  过滤条件: LogFilter(author: alice, title: fix, message: null, minRevision: 100)',
      ]);
    });

    test('空 filter 仍走 toString 渲染', () {
      // 契约：本函数不区分 filter.isEmpty，统一走 toString，避免 dump 多一个分支
      final lines = formatPaginatedEntriesHeaderLines(
        sourceUrl: 'u',
        page: 0,
        pageSize: 20,
        filter: const LogFilter(),
      );
      expect(lines.last,
          '  过滤条件: LogFilter(author: null, title: null, message: null, minRevision: null)');
    });

    test('总是返回 4 行', () {
      expect(
        formatPaginatedEntriesHeaderLines(
          sourceUrl: 'u',
          page: 0,
          pageSize: 1,
          filter: const LogFilter(),
        ).length,
        4,
      );
    });

    test('标题行不带缩进，其它 3 行两空格缩进', () {
      // 视觉契约：标题是段落首行，3 个数据行带 '  ' 前缀
      final lines = formatPaginatedEntriesHeaderLines(
        sourceUrl: 'u',
        page: 0,
        pageSize: 1,
        filter: const LogFilter(),
      );
      expect(lines[0].startsWith(' '), isFalse);
      for (final line in lines.skip(1)) {
        expect(line.startsWith('  '), isTrue, reason: line);
      }
    });
  });

  group('formatPaginatedEntriesResultLine', () {
    test('完整路径：1-based 页码 + hasMore=true', () {
      // adjustedPage=1 → 显示"第 2/5 页"
      final line = formatPaginatedEntriesResultLine(
        entriesCount: 17,
        adjustedPage: 1,
        totalPages: 5,
        hasMore: true,
      );
      expect(line, '  返回: 17 条, 第 2/5 页, hasMore=true');
    });

    test('hasMore=false 时如实显示', () {
      final line = formatPaginatedEntriesResultLine(
        entriesCount: 3,
        adjustedPage: 4,
        totalPages: 5,
        hasMore: false,
      );
      expect(line, '  返回: 3 条, 第 5/5 页, hasMore=false');
    });

    test('adjustedPage=0 → 显示"第 1/N 页"（1-based 转换）', () {
      // 锁定 adjustedPage+1 而非 adjustedPage，防止有人"统一改成 0-based"
      final line = formatPaginatedEntriesResultLine(
        entriesCount: 0,
        adjustedPage: 0,
        totalPages: 1,
        hasMore: false,
      );
      expect(line, '  返回: 0 条, 第 1/1 页, hasMore=false');
    });

    test('行首两空格缩进', () {
      final line = formatPaginatedEntriesResultLine(
        entriesCount: 0,
        adjustedPage: 0,
        totalPages: 0,
        hasMore: false,
      );
      expect(line.startsWith('  '), isTrue);
    });
  });

  group('formatBranchPointCacheClearLine', () {
    test('null wd → "已清除所有分支点缓存"', () {
      expect(formatBranchPointCacheClearLine(null), '已清除所有分支点缓存');
    });

    test('空串 wd → "已清除所有分支点缓存"（与 isUsableWorkingDirectory 一致）', () {
      expect(formatBranchPointCacheClearLine(''), '已清除所有分支点缓存');
    });

    test('非空 wd → "已清除分支点缓存: <wd>"', () {
      expect(
        formatBranchPointCacheClearLine('/tmp/wc'),
        '已清除分支点缓存: /tmp/wc',
      );
    });

    test('单个空格 wd 视作 usable（与 isUsableWorkingDirectory 同源决策）', () {
      // 决策锁定：isUsableWorkingDirectory 不做 trim，单空格视作 usable，
      // 本函数必须保持同步——否则两处对"空白字符串"的判定会分裂。
      expect(formatBranchPointCacheClearLine(' '), '已清除分支点缓存:  ');
    });

    test('两条文案的固定前缀互斥（不会同时出现）', () {
      final all = formatBranchPointCacheClearLine(null);
      final one = formatBranchPointCacheClearLine('/wc');
      expect(all.contains('已清除所有'), isTrue);
      expect(all.contains('已清除分支点缓存:'), isFalse);
      expect(one.contains('已清除分支点缓存:'), isTrue);
      expect(one.contains('已清除所有'), isFalse);
    });
  });

  group('formatBranchPointCacheSetLine', () {
    test('正常路径：wd + 非 null branchPoint', () {
      expect(
        formatBranchPointCacheSetLine(
          workingDirectory: '/tmp/wc',
          branchPoint: 12345,
        ),
        '已缓存分支点: /tmp/wc -> r12345',
      );
    });

    test('branchPoint == null 时输出 "-> rnull"（不要美化成"未知"）', () {
      // 决策锁定：null 路径必须显式输出 "-> rnull"，让"上层把 null
      // 当 branchPoint 写进缓存"这种异常调用在日志里可见。
      expect(
        formatBranchPointCacheSetLine(
          workingDirectory: '/wc',
          branchPoint: null,
        ),
        '已缓存分支点: /wc -> rnull',
      );
    });

    test('branchPoint == 1 边界（最小合法 SVN revision）', () {
      expect(
        formatBranchPointCacheSetLine(
          workingDirectory: '/wc',
          branchPoint: 1,
        ),
        '已缓存分支点: /wc -> r1',
      );
    });

    test('不带前导缩进（独立事件日志，不属于段落）', () {
      final line = formatBranchPointCacheSetLine(
        workingDirectory: '/wc',
        branchPoint: 1,
      );
      expect(line.startsWith(' '), isFalse);
    });
  });

  group('formatPageAdjustmentLine', () {
    test('超界向上 clamp：requestedPage > totalPages-1', () {
      expect(
        formatPageAdjustmentLine(
          requestedPage: 99,
          adjustedPage: 4,
          totalPages: 5,
        ),
        '  页码调整: 99 -> 4 (总页数: 5)',
      );
    });

    test('超界向下 clamp：负数 → 0', () {
      expect(
        formatPageAdjustmentLine(
          requestedPage: -3,
          adjustedPage: 0,
          totalPages: 5,
        ),
        '  页码调整: -3 -> 0 (总页数: 5)',
      );
    });

    test('totalPages == 1 边界（仅 1 页）', () {
      expect(
        formatPageAdjustmentLine(
          requestedPage: 5,
          adjustedPage: 0,
          totalPages: 1,
        ),
        '  页码调整: 5 -> 0 (总页数: 1)',
      );
    });

    test('行首 2 空格缩进', () {
      final line = formatPageAdjustmentLine(
        requestedPage: 0,
        adjustedPage: 0,
        totalPages: 1,
      );
      expect(line.startsWith('  '), isTrue);
    });
  });

  group('formatPaginatedEntriesTotalCountLine', () {
    test('正常路径：totalCount > 0', () {
      expect(
        formatPaginatedEntriesTotalCountLine(42),
        '  最新区间内符合条件的总数: 42',
      );
    });

    test('totalCount == 0 仍合法输出', () {
      // 决策锁定：getEntryCountInLatestRange 可能返回 0（无数据 / 过滤
      // 后无命中），此时 "总数: 0" 是有效诊断信息，不静默吞掉。
      expect(
        formatPaginatedEntriesTotalCountLine(0),
        '  最新区间内符合条件的总数: 0',
      );
    });

    test('totalCount < 0 防御性透传（不掩盖 SQL 异常）', () {
      // 决策锁定：COUNT(*) by contract >= 0；负数应在日志里暴露而非
      // 被静默修正。
      expect(
        formatPaginatedEntriesTotalCountLine(-1),
        '  最新区间内符合条件的总数: -1',
      );
    });

    test('行首 2 空格缩进', () {
      expect(
        formatPaginatedEntriesTotalCountLine(0).startsWith('  '),
        isTrue,
      );
    });
  });

  group('isStringFilterEmpty', () {
    test('null → true', () {
      expect(isStringFilterEmpty(null), isTrue);
    });

    test('空串 → true', () {
      expect(isStringFilterEmpty(''), isTrue);
    });

    test('单空格 → false（不做 trim，与 isMergeInfoArgsValid 同源决策）', () {
      // 决策锁定：仅 null / 空串视作未设置；含空白的字符串视作"已设置"，
      // 把净化责任留在 UI 层。
      expect(isStringFilterEmpty(' '), isFalse);
    });

    test('非空字符串 → false', () {
      expect(isStringFilterEmpty('alice'), isFalse);
    });

    test('LogFilter.isEmpty 委托此函数：空 author + 空 title + null minRev', () {
      // 锁定 LogFilter.isEmpty 的实现走本函数，避免后续有人把
      // (a == null || a.isEmpty) 重新写回去。
      const f = LogFilter(author: '', title: null, minRevision: null);
      expect(f.isEmpty, isTrue);
    });

    test('LogFilter.isEmpty：单空格 author 视作"已设置"→ isEmpty=false', () {
      const f = LogFilter(author: ' ', title: null, minRevision: null);
      expect(f.isEmpty, isFalse);
    });
  });

  group('escapeCsvField', () {
    test('纯文本（无特殊字符）原样返回，不加引号', () {
      // 契约：不需要包裹时不强加 `"`，避免输出体积膨胀。
      expect(escapeCsvField('hello world'), 'hello world');
    });

    test('含逗号 → 包双引号', () {
      // 字段含 `,` 必须包裹否则破坏 CSV 列结构。
      expect(escapeCsvField('a,b'), '"a,b"');
    });

    test('含双引号 → 包双引号且内部 " → ""', () {
      // RFC 4180：内部引号转义为 `""`，外层再包一对 `"`。
      expect(escapeCsvField('say "hi"'), '"say ""hi"""');
    });

    test('含 \\n 换行 → 包双引号（保留换行字符本身）', () {
      // CSV 行内换行靠 `"..."` 包裹，换行本身不替换。
      expect(escapeCsvField('line1\nline2'), '"line1\nline2"');
    });

    test('含 \\r 回车 → 包双引号', () {
      // CRLF 数据保留原字符。
      expect(escapeCsvField('a\rb'), '"a\rb"');
    });

    test('引号 + 逗号同时出现 → 包双引号且引号转义', () {
      // 两种触发条件叠加，引号仍 escape，外层只包一次。
      expect(escapeCsvField('a,"b"'), '"a,""b"""');
    });

    test('空字符串 → 原样空串（不加引号）', () {
      // 与 "无字段值" 语义一致；下游 `,,` 表示空字段。
      expect(escapeCsvField(''), '');
    });

    test('保留前后空格（不 trim）', () {
      // 锁定契约：用户日志里前后空白可能有意义（缩进示例），
      // escapeCsvField 不做 trim。
      expect(escapeCsvField('  spaced  '), '  spaced  ');
    });
  });

  group('formatLogEntriesAsCsv', () {
    test('空列表 → 仅表头行 + 末尾 \\r\\n', () {
      // 契约：空 entries 不返回空串——下游写空文件让用户误以为"导出失败"。
      // 输出"只有表头"明确表明"过滤后 0 条"。
      expect(
        formatLogEntriesAsCsv(const []),
        'revision,author,date,title,message\r\n',
      );
    });

    test('单条标准条目 → 表头 + 1 行数据', () {
      const entry = LogEntry(
        revision: 12345,
        author: 'alice',
        date: '2026-06-01 10:00:00 +0800',
        title: 'Fix bug',
        message: 'Fix bug',
      );
      expect(
        formatLogEntriesAsCsv([entry]),
        'revision,author,date,title,message\r\n'
        '12345,alice,2026-06-01 10:00:00 +0800,Fix bug,Fix bug\r\n',
      );
    });

    test('多条数据顺序与入参一致（不重排）', () {
      // 契约：调用方负责排序（缓存层已 revision 降序），本函数保留入参顺序。
      const entries = [
        LogEntry(
          revision: 10,
          author: 'a',
          date: 'd1',
          title: 't1',
          message: 'm1',
        ),
        LogEntry(
          revision: 20,
          author: 'b',
          date: 'd2',
          title: 't2',
          message: 'm2',
        ),
        LogEntry(
          revision: 5,
          author: 'c',
          date: 'd3',
          title: 't3',
          message: 'm3',
        ),
      ];
      final csv = formatLogEntriesAsCsv(entries);
      // 第 1 条 r10 出现在第 2 条 r20 之前，第 3 条 r5 在最后——逆序入参也保留顺序。
      final r10Idx = csv.indexOf('10,a');
      final r20Idx = csv.indexOf('20,b');
      final r5Idx = csv.indexOf('5,c');
      expect(r10Idx >= 0 && r20Idx >= 0 && r5Idx >= 0, isTrue);
      expect(r10Idx < r20Idx, isTrue);
      expect(r20Idx < r5Idx, isTrue);
    });

    test('message 含 CSV 特殊字符 → 各自正确 escape', () {
      const entry = LogEntry(
        revision: 1,
        author: 'a',
        date: 'd',
        title: 'has, comma',
        message: 'multi\nline "quoted"',
      );
      final csv = formatLogEntriesAsCsv([entry]);
      // title 含逗号 → "has, comma"
      // message 含换行+引号 → "multi\nline ""quoted"""
      expect(
        csv,
        'revision,author,date,title,message\r\n'
        '1,a,d,"has, comma","multi\nline ""quoted"""\r\n',
      );
    });

    test('表头格式固定为 5 列', () {
      // 锁定契约：列名顺序 revision,author,date,title,message。
      // 任何调换都会破坏下游消费方（Excel 模板 / 脚本）。
      final csv = formatLogEntriesAsCsv(const []);
      expect(csv.startsWith('revision,author,date,title,message\r\n'), isTrue);
    });
  });

  group('formatCsvExportFileName', () {
    test('标准时间生成 svn-log-yyyyMMdd-HHmmss.csv', () {
      final t = DateTime(2026, 6, 1, 14, 30, 45);
      expect(formatCsvExportFileName(t), 'svn-log-20260601-143045.csv');
    });

    test('单数月日时分秒零填充至 2 位', () {
      // 锁定契约：1 月 5 日 9:08:07 → 01 / 05 / 09 / 08 / 07，避免错位。
      final t = DateTime(2026, 1, 5, 9, 8, 7);
      expect(formatCsvExportFileName(t), 'svn-log-20260105-090807.csv');
    });

    test('元旦零点 → 全零填充', () {
      // 边界：所有字段都需 padLeft。
      final t = DateTime(2026, 1, 1, 0, 0, 0);
      expect(formatCsvExportFileName(t), 'svn-log-20260101-000000.csv');
    });
  });
}
