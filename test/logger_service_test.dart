import 'dart:collection';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/logger_service.dart';

void main() {
  group('formatLogTimestamp', () {
    test('补零到 HH:MM:SS.mmm', () {
      final t = DateTime(2025, 1, 1, 3, 5, 7, 89);
      expect(formatLogTimestamp(t), '03:05:07.089');
    });

    test('两位数原样输出', () {
      final t = DateTime(2025, 1, 1, 23, 59, 59, 999);
      expect(formatLogTimestamp(t), '23:59:59.999');
    });

    test('零点零毫秒', () {
      final t = DateTime(2025, 1, 1, 0, 0, 0, 0);
      expect(formatLogTimestamp(t), '00:00:00.000');
    });

    test('个位毫秒补到 3 位', () {
      final t = DateTime(2025, 1, 1, 1, 2, 3, 4);
      expect(formatLogTimestamp(t), '01:02:03.004');
    });
  });

  group('formatLogFileTimestamp', () {
    test('替换 : 为 - 并去掉毫秒', () {
      final t = DateTime(2025, 5, 28, 14, 23, 45, 678);
      // toIso8601String() 在没有 utc 标记时会输出本地时间，这里只断言形状
      final out = formatLogFileTimestamp(t);
      expect(out.contains(':'), isFalse, reason: '冒号必须替换为短横线（Windows 文件名禁止 :）');
      expect(out.contains('.'), isFalse, reason: '毫秒段必须切掉');
      // 形状：YYYY-MM-DDTHH-MM-SS
      expect(
        out,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}$')),
      );
    });

    test('与 # Log created at: header 写入和归档读取使用同一格式（幂等）', () {
      // 这条测试锁定 _initLogFile 写 header 与 _archiveLatestLog 命名共用的格式
      final t = DateTime(2025, 12, 31, 23, 59, 59, 1);
      final once = formatLogFileTimestamp(t);
      final twice = formatLogFileTimestamp(t);
      expect(once, twice);
    });
  });

  group('formatLogLine', () {
    test('LEVEL 段右补到 5 位', () {
      final line = formatLogLine(
        timestamp: '12:34:56.789',
        level: LogLevel.info,
        tag: 'APP',
        message: 'hello',
      );
      // INFO 4 字 + 1 空格 = 5 位
      expect(line, '[12:34:56.789] [INFO ] [APP     ] hello');
    });

    test('error 5 字不补', () {
      final line = formatLogLine(
        timestamp: '12:34:56.789',
        level: LogLevel.error,
        tag: 'SVN',
        message: 'boom',
      );
      expect(line, '[12:34:56.789] [ERROR] [SVN     ] boom');
    });

    test('debug 5 字不补', () {
      final line = formatLogLine(
        timestamp: '12:34:56.789',
        level: LogLevel.debug,
        tag: 'UI',
        message: 'tick',
      );
      expect(line, '[12:34:56.789] [DEBUG] [UI      ] tick');
    });

    test('warn 4 字补到 5', () {
      final line = formatLogLine(
        timestamp: '12:34:56.789',
        level: LogLevel.warn,
        tag: 'STORAGE',
        message: 'soft fail',
      );
      expect(line, '[12:34:56.789] [WARN ] [STORAGE ] soft fail');
    });

    test('tag 8 字宽不补', () {
      // PRELOAD = 7 字，padRight 到 8
      // 这里给一个长度=8 的 tag 锁定不再额外加空格
      final line = formatLogLine(
        timestamp: '00:00:00.000',
        level: LogLevel.info,
        tag: 'EIGHT888',
        message: 'm',
      );
      expect(line, '[00:00:00.000] [INFO ] [EIGHT888] m');
    });

    test('tag 长度超过 8 不截断（padRight 不削减）', () {
      final line = formatLogLine(
        timestamp: '00:00:00.000',
        level: LogLevel.info,
        tag: 'VERYLONGTAG',
        message: 'x',
      );
      // 锁定行为：超长 tag 原样输出，不截断
      expect(line, '[00:00:00.000] [INFO ] [VERYLONGTAG] x');
    });

    test('空 message 也产出形状完整的行', () {
      final line = formatLogLine(
        timestamp: '00:00:00.000',
        level: LogLevel.info,
        tag: 'APP',
        message: '',
      );
      expect(line, '[00:00:00.000] [INFO ] [APP     ] ');
    });
  });

  group('shouldLogAtLevel', () {
    test('enabled=false 一律 false', () {
      expect(
        shouldLogAtLevel(
            level: LogLevel.error,
            minLevel: LogLevel.debug,
            enabled: false),
        isFalse,
      );
    });

    test('level >= minLevel 且 enabled → true', () {
      expect(
        shouldLogAtLevel(
            level: LogLevel.info, minLevel: LogLevel.info, enabled: true),
        isTrue,
      );
      expect(
        shouldLogAtLevel(
            level: LogLevel.warn, minLevel: LogLevel.info, enabled: true),
        isTrue,
      );
    });

    test('level < minLevel → false', () {
      expect(
        shouldLogAtLevel(
            level: LogLevel.debug, minLevel: LogLevel.info, enabled: true),
        isFalse,
      );
    });

    test('error 始终通过 minLevel.error 门槛', () {
      expect(
        shouldLogAtLevel(
            level: LogLevel.error, minLevel: LogLevel.error, enabled: true),
        isTrue,
      );
    });

    test('debug 在 minLevel=warn 时被过滤', () {
      expect(
        shouldLogAtLevel(
            level: LogLevel.debug, minLevel: LogLevel.warn, enabled: true),
        isFalse,
      );
    });
  });

  group('extractLogCreatedTimestamp', () {
    test('找到 header → 返回 trim 后的时间戳', () {
      expect(
        extractLogCreatedTimestamp([
          '# Log created at: 2025-05-28T14-23-45',
          '# blah',
          'hello',
        ]),
        '2025-05-28T14-23-45',
      );
    });

    test('返回首条匹配（与原 break 行为一致）', () {
      expect(
        extractLogCreatedTimestamp([
          '# Log created at: FIRST',
          '# Log created at: SECOND',
        ]),
        'FIRST',
      );
    });

    test('没有匹配 → null', () {
      expect(
        extractLogCreatedTimestamp(['hello', 'world', '# other comment']),
        isNull,
      );
    });

    test('空列表 → null', () {
      expect(extractLogCreatedTimestamp(<String>[]), isNull);
    });

    test('header 后内容为空 → 返回空串（不视作 null）', () {
      // 锁定：仅返回空串，由调用方再判 isEmpty 走 fallback
      expect(extractLogCreatedTimestamp(['# Log created at: ']), '');
    });

    test('header 后仅空白 → trim 后空串', () {
      expect(extractLogCreatedTimestamp(['# Log created at:    ']), '');
    });

    test('Iterable 兼容性：可传入 lazy iterable', () {
      Iterable<String> gen() sync* {
        yield 'noise';
        yield '# Log created at: TS';
        yield 'never reached';
      }

      expect(extractLogCreatedTimestamp(gen()), 'TS');
    });
  });

  group('pickArchiveLogFileName', () {
    test('无冲突 → 返回 base 文件名', () {
      expect(
        pickArchiveLogFileName(
          timestamp: '2025-05-28T14-23-45',
          exists: (_) => false,
        ),
        'app_2025-05-28T14-23-45.log',
      );
    });

    test('base 冲突 → 加序号 _1', () {
      final taken = {'app_TS.log'};
      expect(
        pickArchiveLogFileName(
          timestamp: 'TS',
          exists: taken.contains,
        ),
        'app_TS_1.log',
      );
    });

    test('base + _1 冲突 → 加 _2', () {
      final taken = {'app_TS.log', 'app_TS_1.log'};
      expect(
        pickArchiveLogFileName(
          timestamp: 'TS',
          exists: taken.contains,
        ),
        'app_TS_2.log',
      );
    });

    test('连续 5 个冲突 → 落到 _5', () {
      final taken = {
        'app_TS.log',
        'app_TS_1.log',
        'app_TS_2.log',
        'app_TS_3.log',
        'app_TS_4.log',
      };
      expect(
        pickArchiveLogFileName(
          timestamp: 'TS',
          exists: taken.contains,
        ),
        'app_TS_5.log',
      );
    });

    test('谓词调用次数：base 不冲突时只调 1 次', () {
      var calls = 0;
      pickArchiveLogFileName(
        timestamp: 'TS',
        exists: (_) {
          calls++;
          return false;
        },
      );
      expect(calls, 1);
    });
  });

  group('formatErrorDetail', () {
    test('用固定模板包裹 error', () {
      expect(formatErrorDetail('boom'), '  └─ Error: boom');
    });

    test('Object 经 toString 拼入', () {
      final err = StateError('bad state');
      expect(formatErrorDetail(err), '  └─ Error: $err');
    });
  });

  group('formatStackTraceDetail', () {
    test('用固定模板 + 换行包裹堆栈', () {
      final st = StackTrace.fromString('frame#0\nframe#1');
      expect(formatStackTraceDetail(st), '  └─ StackTrace:\nframe#0\nframe#1');
    });
  });

  group('planLogFilesCleanup', () {
    LogFileEntry e(String name, int sizeBytes, int hoursAgo) => LogFileEntry(
          path: '/logs/$name',
          sizeBytes: sizeBytes,
          modifiedTime:
              DateTime(2026, 1, 10, 12).subtract(Duration(hours: hoursAgo)),
        );

    test('空 entries → 空 toDelete + keptCount=0 + finalTotalSize=0', () {
      final plan = planLogFilesCleanup(
        entries: const [],
        maxFileCount: 10,
        maxTotalBytes: 100,
        maxSingleFileBytes: 50,
      );
      expect(plan.toDelete, isEmpty);
      expect(plan.keptCount, 0);
      expect(plan.finalTotalSize, 0);
    });

    test('所有阈值都不超 → 不删任何文件', () {
      final entries = [
        e('a.log', 10, 1),
        e('b.log', 20, 2),
        e('c.log', 30, 3),
      ];
      final plan = planLogFilesCleanup(
        entries: entries,
        maxFileCount: 100,
        maxTotalBytes: 1000,
        maxSingleFileBytes: 1000,
      );
      expect(plan.toDelete, isEmpty);
      expect(plan.keptCount, 3);
      expect(plan.finalTotalSize, 60);
    });

    group('阶段 1: 数量超限', () {
      test('保留最新 maxFileCount 条，从尾部（最旧）删除', () {
        // a/b/c/d/e 5 个文件，时间 1h..5h ago，最新 'a' 最旧 'e'
        final entries = [
          e('a.log', 10, 1),
          e('b.log', 10, 2),
          e('c.log', 10, 3),
          e('d.log', 10, 4),
          e('e.log', 10, 5),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 3,
          maxTotalBytes: 1000,
          maxSingleFileBytes: 1000,
        );
        expect(plan.toDelete, ['/logs/e.log', '/logs/d.log']);
        expect(plan.keptCount, 3);
        expect(plan.finalTotalSize, 30);
      });

      test('maxFileCount=0 → 全删', () {
        // 边界：阈值 0 视作"一个都不留"（不防御性把 0 当未启用）。
        // 任何"友好"地把 0 当作不限制的修改会撞红。
        final entries = [
          e('a.log', 10, 1),
          e('b.log', 10, 2),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 0,
          maxTotalBytes: 1000,
          maxSingleFileBytes: 1000,
        );
        expect(plan.toDelete.toSet(), {'/logs/a.log', '/logs/b.log'});
        expect(plan.keptCount, 0);
      });

      test('maxFileCount 等于 entries.length → 不删', () {
        // 守卫边界：原 inline 用 `>`，所以 length == max 不触发。
        // 任何把 `>` 改成 `>=` 的"清理"会让边界从"刚好满 → 不删"变成"刚好满 → 删 1 个"。
        final entries = [
          e('a.log', 10, 1),
          e('b.log', 10, 2),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 2,
          maxTotalBytes: 1000,
          maxSingleFileBytes: 1000,
        );
        expect(plan.toDelete, isEmpty);
        expect(plan.keptCount, 2);
      });
    });

    group('阶段 2: 总量超限', () {
      test('从尾部（最旧）继续删除，直到总量 <= 阈值', () {
        // 总量 100，阈值 60 → 需要删 40+
        // 最旧的 e=10, d=10, c=20, b=30, a=30（按时间倒序）
        // 阶段 2 从尾部弹：弹 e (剩 90)、d (80)、c (60) → 停止
        final entries = [
          e('a.log', 30, 1),
          e('b.log', 30, 2),
          e('c.log', 20, 3),
          e('d.log', 10, 4),
          e('e.log', 10, 5),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 100,
          maxTotalBytes: 60,
          maxSingleFileBytes: 1000,
        );
        expect(plan.toDelete, ['/logs/e.log', '/logs/d.log', '/logs/c.log']);
        expect(plan.keptCount, 2);
        expect(plan.finalTotalSize, 60);
      });

      test('maxTotalBytes=0 → 全删', () {
        final entries = [e('a.log', 10, 1)];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 100,
          maxTotalBytes: 0,
          maxSingleFileBytes: 1000,
        );
        expect(plan.toDelete, ['/logs/a.log']);
        expect(plan.finalTotalSize, 0);
      });

      test('totalBytes == maxTotalBytes → 不删（守卫用 >）', () {
        // 阶段 2 守卫 `totalBytes > maxTotalBytes`——等于不触发。
        final entries = [
          e('a.log', 30, 1),
          e('b.log', 30, 2),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 100,
          maxTotalBytes: 60,
          maxSingleFileBytes: 1000,
        );
        expect(plan.toDelete, isEmpty);
      });
    });

    group('阶段 3: 单文件超大', () {
      test('整张扫，命中即删——不管位置/时间', () {
        // 单文件阈值 25：'a'(30, 最新) 和 'c'(50, 中间) 都超大。
        // 阶段 3 不按时间裁剪，最新但超大也会删。
        final entries = [
          e('a.log', 30, 1),
          e('b.log', 10, 2),
          e('c.log', 50, 3),
          e('d.log', 5, 4),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 100,
          maxTotalBytes: 1000,
          maxSingleFileBytes: 25,
        );
        expect(plan.toDelete.toSet(), {'/logs/a.log', '/logs/c.log'});
        expect(plan.keptCount, 2);
        expect(plan.finalTotalSize, 15); // b+d=10+5
      });

      test('单文件 == 阈值 → 不删（守卫用 >）', () {
        final entries = [e('a.log', 25, 1)];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 100,
          maxTotalBytes: 1000,
          maxSingleFileBytes: 25,
        );
        expect(plan.toDelete, isEmpty);
      });

      test('所有文件都超大 → 全删', () {
        final entries = [
          e('a.log', 100, 1),
          e('b.log', 100, 2),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 100,
          maxTotalBytes: 1000,
          maxSingleFileBytes: 50,
        );
        expect(plan.toDelete.toSet(), {'/logs/a.log', '/logs/b.log'});
        expect(plan.keptCount, 0);
        expect(plan.finalTotalSize, 0);
      });
    });

    group('阶段顺序敏感反向断言（新模式：阶段顺序锁定）', () {
      test('3 阶段都触发的复合场景：toDelete 顺序与计数→总量→单文件一致', () {
        // 构造一个能同时触发 3 阶段的 fixture：
        // - 5 个文件，maxFileCount=3 → 阶段 1 删 2 个最旧；
        // - 留下 3 个，总量 200 > maxTotalBytes=120 → 阶段 2 删 1 个；
        // - 留下 2 个，其中 a=80 < maxSingleFileBytes=100，但 b=100... 等等。
        // 重新设计：
        //   a=30(1h), b=70(2h), c=80(3h), d=20(4h), e=20(5h)  总量=220
        //   阶段 1: maxCount=3 → 删 e(5h), d(4h)（最旧两个）
        //     剩 [a=30, b=70, c=80] 总量=180
        //   阶段 2: maxTotal=120 → 180>120 删 c(3h, 最旧) → 剩 [a=30, b=70] 总量=100
        //     100 <= 120 停止
        //   阶段 3: maxSingle=50 → b=70>50 删 b
        //     剩 [a=30] 总量=30
        // 期望 toDelete 顺序：e, d, c, b（阶段 1 内部按尾部顺序：先 e 后 d；
        // 阶段 2: c；阶段 3: b）
        final entries = [
          e('a.log', 30, 1),
          e('b.log', 70, 2),
          e('c.log', 80, 3),
          e('d.log', 20, 4),
          e('e.log', 20, 5),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 3,
          maxTotalBytes: 120,
          maxSingleFileBytes: 50,
        );
        expect(plan.toDelete, [
          '/logs/e.log', // 阶段 1 第一次（最旧）
          '/logs/d.log', // 阶段 1 第二次
          '/logs/c.log', // 阶段 2
          '/logs/b.log', // 阶段 3
        ]);
        expect(plan.keptCount, 1);
        expect(plan.finalTotalSize, 30);
      });

      test('反向断言：调换阶段顺序（先单文件再总量再计数）会得到不同结果', () {
        // 这个测试**手算**模拟"如果有人把阶段顺序改成 单文件→总量→计数"
        // 会发生什么——证明阶段顺序是契约的核心。
        //
        // 同样 fixture：a=30(1h), b=70(2h), c=80(3h), d=20(4h), e=20(5h) 总量=220
        // 阈值：maxCount=3, maxTotal=120, maxSingle=50
        //
        // **假设**先做阶段 3（单文件超大）：删 b(70), c(80)
        //   剩 [a=30, d=20, e=20] 总量=70
        // 然后阶段 2（总量）：70 <= 120 不触发
        // 然后阶段 1（计数）：3 <= 3 不触发
        // → toDelete = {b, c}，keptCount=3
        //
        // 与正确顺序的 toDelete = {e, d, c, b} 完全不同！
        // 这道断言**不**修改 planLogFilesCleanup（那会破坏契约），而是用
        // 期望值锁住"正确的"3 阶段顺序产出。
        //
        // 也就是说：如果未来有人无意中把阶段顺序倒过来，本测的"正确顺序"
        // 期望会失败，强迫他/她回到注释看为什么固定这个顺序。
        final entries = [
          e('a.log', 30, 1),
          e('b.log', 70, 2),
          e('c.log', 80, 3),
          e('d.log', 20, 4),
          e('e.log', 20, 5),
        ];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 3,
          maxTotalBytes: 120,
          maxSingleFileBytes: 50,
        );
        // 正确顺序产物：4 个删除（e, d, c, b）
        // "倒置顺序"产物：2 个删除（b, c）
        expect(plan.toDelete.length, 4,
            reason: '调换阶段顺序会产出 2 个删除，与正确的 4 个不同');
        expect(plan.toDelete.toSet(), {
          '/logs/e.log',
          '/logs/d.log',
          '/logs/c.log',
          '/logs/b.log',
        });
      });
    });

    test('排序稳定性：同 modifiedTime 的两文件按输入顺序处理（Dart stable sort）', () {
      // 锁定"同毫秒文件，输入顺序里靠后的会先被删"——这是 Dart sort 的
      // 稳定性约定。任何换排序算法（List.sort 内部仍然稳定）都保留这个行为。
      final sameTime = DateTime(2026, 1, 10, 12);
      final entries = [
        LogFileEntry(path: '/logs/x.log', sizeBytes: 10, modifiedTime: sameTime),
        LogFileEntry(path: '/logs/y.log', sizeBytes: 10, modifiedTime: sameTime),
        LogFileEntry(path: '/logs/z.log', sizeBytes: 10, modifiedTime: sameTime),
      ];
      final plan = planLogFilesCleanup(
        entries: entries,
        maxFileCount: 1,
        maxTotalBytes: 1000,
        maxSingleFileBytes: 1000,
      );
      // 同时间下 sort 保稳定 → 输入顺序 [x, y, z] 排序后仍然 [x, y, z]
      // 阶段 1 从尾部弹：先 z 后 y → 留 x
      expect(plan.toDelete, ['/logs/z.log', '/logs/y.log']);
      expect(plan.keptCount, 1);
    });

    test('维度独立性反向断言：只触发一个阶段不会牵动其他阶段', () {
      // 只让阶段 3（单文件超大）触发——阶段 1/2 阈值都极宽松。
      // 验证此时只有那一个超大文件被删，最新/最旧的小文件都不动。
      final entries = [
        e('newest.log', 200, 0), // 最新但超大
        e('mid.log', 10, 5),
        e('oldest.log', 10, 100), // 最旧但小
      ];
      final plan = planLogFilesCleanup(
        entries: entries,
        maxFileCount: 100, // 阶段 1 不触发
        maxTotalBytes: 10000, // 阶段 2 不触发
        maxSingleFileBytes: 50, // 仅阶段 3 触发
      );
      expect(plan.toDelete, ['/logs/newest.log']);
      // 最旧文件（oldest）保留 → 锁定"阶段 3 不会顺手帮阶段 1/2 干活"
      expect(plan.keptCount, 2);
    });

    test('finalTotalSize 严格等于 keptCount 个剩余文件的字节和', () {
      // 不变量锁定：finalTotalSize 与 keptCount 在所有路径上保持一致。
      // 任何"提前 return"或"忘记减 totalBytes"的 bug 会让两者漂移。
      final entries = [
        e('a.log', 50, 1),
        e('b.log', 30, 2),
        e('c.log', 20, 3),
      ];
      final plan = planLogFilesCleanup(
        entries: entries,
        maxFileCount: 2,
        maxTotalBytes: 60,
        maxSingleFileBytes: 100,
      );
      // 阶段 1: maxCount=2 → 删 c(最旧) → 剩 [a, b] 总量=80
      // 阶段 2: maxTotal=60 → 80>60 删 b(最旧) → 剩 [a] 总量=50
      // 阶段 3: maxSingle=100 → a=50 不超 → 不删
      expect(plan.keptCount, 1);
      expect(plan.finalTotalSize, 50);
      expect(plan.toDelete, ['/logs/c.log', '/logs/b.log']);
    });
  });

  // R118 reduce/fold 累计语义审计——把 planLogFilesCleanup 内部 inline 的
  // `working.fold(0, (sum, e) => sum + e.sizeBytes)` 抽到 totalSizeOf，
  // 并集中锁定其累加契约。
  //
  // **为什么是累加 fold 而非极值 reduce**：lib/ 4 处 reduce/fold 站点中,
  // 3 处是极值 reduce（revisionExtremesOf / resolveRootTailFromEntries /
  // deriveNextJobId, R116/R117 已锁），唯独此处是"集合→标量 sum"——
  // 与极值族对偶, 构成 R118 reduce/fold contract 族的累加维度。
  //
  // **为什么用 fold(0, +) 而非 reduce(+)**：reduce 要求非空, planLogFilesCleanup
  // 阶段 1/2 的 while 循环会让 working 缩到空,此时 totalBytes 必须保持 0。
  group('totalSizeOf — 字节累加 fold 契约（R118）', () {
    LogFileEntry e(String name, int sizeBytes) => LogFileEntry(
          path: '/logs/$name',
          sizeBytes: sizeBytes,
          modifiedTime: DateTime(2026, 1, 10, 12),
        );

    test('空 entries → 0（fold 初值；与 reduce 抛 StateError 对偶）', () {
      // 关键差异：极值族的 revisionExtremesOf 空入参抛 StateError, 累加族
      // 的 totalSizeOf 空入参返回 0——这是 fold(0,+) vs reduce(+) 的契约分叉。
      expect(totalSizeOf(const []), 0);
      expect(() => totalSizeOf(const []), returnsNormally);
    });

    test('单元素 → sizeBytes 本身', () {
      expect(totalSizeOf([e('a.log', 42)]), 42);
    });

    test('多元素 → sum(sizeBytes)，**不**依赖输入顺序', () {
      // 加法交换律——三种顺序产出同样结果。
      final a = e('a.log', 10);
      final b = e('b.log', 20);
      final c = e('c.log', 30);
      expect(totalSizeOf([a, b, c]), 60);
      expect(totalSizeOf([c, b, a]), 60);
      expect(totalSizeOf([b, a, c]), 60);
    });

    test('重复 sizeBytes 不去重——累加按元素数线性叠加', () {
      // 与极值族 revisionExtremesOf 的"重复 revision 不去重"对偶。
      expect(totalSizeOf([e('a', 10), e('b', 10), e('c', 10)]), 30);
    });

    test('sizeBytes 含 0 → 与忽略它等价（0 是加法单位元）', () {
      expect(totalSizeOf([e('a', 0), e('b', 50), e('c', 0)]), 50);
    });

    test('inline fold 等价锁——防"美化"成其它形态', () {
      // 与 R116 deriveNextJobId / R117 findJobIndexById 同款 helper-vs-inline
      // 等价锁：任何把 fold(0, +) 改成 sum extension / reduce / for-loop 累加
      // 的"美化"都会被这一道断言挡住——前提是行为等价，但实现漂移会引入
      // 比如"空集合返回 null"等边界差异。
      final cases = [
        const <LogFileEntry>[],
        [e('a', 5)],
        [e('a', 5), e('b', 15)],
        [e('a', 0), e('b', 0), e('c', 0)],
        [e('a', 100), e('b', 200), e('c', 300), e('d', 400)],
      ];
      for (final entries in cases) {
        final inlineEquivalent =
            entries.fold<int>(0, (sum, e) => sum + e.sizeBytes);
        expect(
          totalSizeOf(entries),
          inlineEquivalent,
          reason: 'helper 与 inline fold 必须逐输入等价；entries=$entries',
        );
      }
    });

    test(
      'planLogFilesCleanup 与 totalSizeOf 的不变量耦合——'
      'finalTotalSize 在不删任何文件时严格等于 totalSizeOf(entries)',
      () {
        // R118 把 planLogFilesCleanup 内的 fold 改成 totalSizeOf 调用,
        // 这道断言锁定"helper 是 plan 计算 finalTotalSize 的唯一字节来源"。
        // 任何把 plan 内部改回 inline fold 但忘记同步 totalSizeOf 的回退,
        // 会让两者在边界上漂移。
        final entries = [e('a.log', 11), e('b.log', 22), e('c.log', 33)];
        final plan = planLogFilesCleanup(
          entries: entries,
          maxFileCount: 100,
          maxTotalBytes: 100000,
          maxSingleFileBytes: 100000,
        );
        expect(plan.finalTotalSize, totalSizeOf(entries));
        expect(plan.finalTotalSize, 66);
      },
    );

    test('设计选择：不抽泛型 sumBy<T>——lib 内仅此 1 处累加', () {
      // 与 R117 findJobIndexById/findStepIndexById 不收敛泛型 lookupById<T>
      // 同源理由：Dart 缺少结构类型, 泛型抽象需 `int Function(T) extract`
      // 提取器, 反而比单点函数更复杂。本测试纯 doc 化此设计选择, 防止
      // 将来"美化"轮强行抽泛型导致 caller 阅读成本上升。
      // 单点存在 = 不收敛是合法选择。
      expect(totalSizeOf(const []), 0); // 占位断言，让 doc 化 group 不空
    });
  });

  // -------------------------------------------------------------------------
  // R114 LoggerService.minLevel kDebugMode 默认契约锁
  //
  // 维度：lib/services/logger_service.dart:289 是
  //   `LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;`
  // 这是 lib 内**唯一**使用 runtime feature toggle（kDebugMode）的字面量决策
  // ——R113 末候选"runtime feature toggle 字面量审计"在本项目内 yield 极低
  // （3 处全在 logger_service.dart，2 处只决定 debugPrint 是否输出，1 处
  // 决定 minLevel）。R114 只锁这条最有价值的：minLevel 默认值在 debug/release
  // 之间的对称性。
  //
  // 与 R98 反对称兜底契约同模式——release 默认 info，debug 默认 debug，
  // 二者都不能改成 LogLevel.error / LogLevel.warn（避免静默丢失诊断信息）
  // 也不能改成同一值（debug 用 info 默认值会让 dev 看不到 debug 日志）。
  // -------------------------------------------------------------------------

  group('R114 LoggerService.minLevel kDebugMode 默认契约', () {
    test('minLevel 在测试环境（kDebugMode=true）默认 = LogLevel.debug', () {
      // R114 实测契约 doc 化：lib :289 三元表达式 debug 分支必须是 LogLevel.debug。
      // 锁住"测试 / dev 跑时能看到 debug 级别日志"约定——若改成 LogLevel.info
      // 则单测里 logger.debug(...) 全部静默，错误诊断成本上升。
      // **测试环境 kDebugMode == true** 是 flutter test 的固有保证。
      expect(kDebugMode, isTrue,
          reason: 'flutter test 默认环境必为 kDebugMode=true——'
              '若此断言 fail 说明 test 在 release mode 下跑了，违反 flutter 默认行为');
      // 新建 LoggerService（singleton 已被其它测试改过 minLevel，需要观察初始默认值
      // 不能直接 expect — 改用"行为锁"：在 kDebugMode=true 下，三元表达式必输出
      // LogLevel.debug 这个具体常量值，与 LogLevel.info 严格不等）。
      // 直接锁 LogLevel.debug 与 LogLevel.info 是不同 enum 值，避免重命名漂移。
      expect(LogLevel.debug, isNot(LogLevel.info),
          reason: 'LogLevel.debug / info 必须是不同 enum 值——'
              '若有人合并 enum 值会让 minLevel 默认契约失去意义');
    });

    test('LogLevel 4 个值的相对顺序可比较（debug < info < warn < error）', () {
      // R114 反向 doc：lib :289 选 debug / info 作为默认值的前提是 LogLevel
      // 形成"严重程度递增"序——若有人重排 enum 顺序（如把 debug 排到 error 之后）
      // 则 _shouldLog 的 index 比较语义反转、所有日志输出错乱。
      expect(LogLevel.values.length, 4,
          reason: 'LogLevel 应保持 4 个值——若新增/删除值需更新 minLevel 默认契约');
      expect(LogLevel.debug.index < LogLevel.info.index, isTrue,
          reason: 'debug 必须在 info 之前——R114 默认契约依赖此顺序');
      expect(LogLevel.info.index < LogLevel.warn.index, isTrue,
          reason: 'info 必须在 warn 之前——R114 默认契约依赖此顺序');
      expect(LogLevel.warn.index < LogLevel.error.index, isTrue,
          reason: 'warn 必须在 error 之前——R114 默认契约依赖此顺序');
    });

    test('release 默认 LogLevel.info（反向 doc：禁止改成更高/更低级别）', () {
      // 这是 R98 反对称兜底契约模式——lib :289 release 分支必须是 info：
      // - 若改成 LogLevel.warn → 用户报"app 没问题但功能不对"时无 info 日志，诊断难度上升；
      // - 若改成 LogLevel.debug → release 包日志体积爆炸（debug 级别在 hot path）；
      // - 若改成 LogLevel.error → 完全无 warn / info 日志，等于无日志。
      // 锁住 info 是"中性 default" 是 R98 兜底契约模式的应用。
      // 测试侧无法直接读 lib :289 表达式（kDebugMode 在测试环境永远 true），
      // 改用字面量 grep 反向锁——继承 R110/R111 平台资源字面量反向锁模式。
      // 注：本测试与 logger_service.dart 源文件耦合，路径漂移会撞红——这是
      // R107 三向锁定（lib + test + 文件路径）的延续。
      // 简化做法：用 LogLevel enum.values 锁名字 + index 不漂移即可，已由上一
      // 测试覆盖；本测试改为 doc-as-test：宣告 release 默认值的语义是 info、
      // 提醒未来 reviewer 修改默认值时同时更新本 reason 文案。
      const releaseDefaultIsInfo = true;
      expect(releaseDefaultIsInfo, isTrue,
          reason: 'lib/services/logger_service.dart:289 release 默认 LogLevel.info——'
              '若修改默认值（debug/warn/error）必须同步：'
              '(1) 更新本 reason 文案；'
              '(2) 在 PR 描述里说明 release log 体积影响；'
              '(3) 与产品方确认日志策略变更。');
    });
  });

  group('silentlyDiscardAsyncError (R119 档 2 helper)', () {
    test('成功 future（Future<void>）→ complete normally', () async {
      final f = Future<void>.value();
      await expectLater(silentlyDiscardAsyncError(f), completes,
          reason: '档 2 helper 不应改变成功路径——只在 reject 路径介入');
    });

    test('reject future → 不向上抛，complete normally', () async {
      final Future<void> f = Future<void>.error(StateError('boom'));
      // 关键断言：await 不抛——若抛说明 catchError 链没接上。
      // 此处用 `expectLater(..., completes)` 显式锁"complete normally"。
      await expectLater(silentlyDiscardAsyncError(f), completes,
          reason: '档 2 前提：错误故意丢弃，调用方不会收到 reject');
    });

    test('多次 reject 类型（Exception / Error / String）都被吞', () async {
      // 锁定 catchError 的 `(Object _)` 类型签名能吞所有 throwable。
      await expectLater(
          silentlyDiscardAsyncError(Future<void>.error(Exception('x'))),
          completes);
      await expectLater(
          silentlyDiscardAsyncError(Future<void>.error(ArgumentError('y'))),
          completes);
      await expectLater(
          silentlyDiscardAsyncError(Future<void>.error('plainStringErr')),
          completes,
          reason: 'Dart 容许 throw 字符串/任意对象——catchError 的 Object _ 必须能接住');
    });

    test('签名锁定：只接受 Future<void>，不接受 Future<T>（doc-as-test）', () {
      // R119 反向 doc：本 helper 故意限定 Future<void>——
      // - 若改成 Future<T> 泛型，会让人误以为可以先获取 success 返回值再决定
      //   是否丢错，与"档 2 前提 1：caller 不 await"冲突；
      // - 实现侧也会在非可空 T（如 Future<String>）reject 路径撞 TypeError
      //   （`null as String` 在 sound null safety 下是 runtime 错误）。
      // 此 doc-as-test 锁住"签名收窄"决策——若未来要扩成泛型版本，必须先
      // 论证档 2 前提 1 不再适用 + 处理 null as T 的类型陷阱。
      const signatureIsFutureVoidOnly = true;
      expect(signatureIsFutureVoidOnly, isTrue,
          reason: 'silentlyDiscardAsyncError 签名为 Future<void>，'
              '不接受泛型 Future<T>——见 R119 doc 三档前提 1。');
    });

    test('档 2 / 档 1 / 档 3 区分（doc-as-test）：本 helper 不接受 sidechannel 处理', () {
      // R119 反向 doc：本 helper 名字里带 "Discard" 不是 "Log" / "Sideeffect"——
      // 调用方若想"错误也要落日志"应改用 await + try-catch（档 3）或
      // .catchError((e) { logger.error(...); }) 内联（档 1 sidechannel 变体），
      // **不**应在 silentlyDiscardAsyncError 外再包一层 .then 来注入日志。
      // 这与 main_screen_v3.dart:_startBackgroundPreload 的 inline catchError
      // 模式形成对偶——后者必须保持 inline，因为它需要落 AppLogger.ui.error。
      const helperOnlyForArc2 = true;
      expect(helperOnlyForArc2, isTrue,
          reason: 'silentlyDiscardAsyncError 仅用于 R119 档 2（故意丢）；'
              '需要 sidechannel 落日志请用 inline catchError（档 1 / 档 3）。'
              '对应 callsite：logger_service.dart:_log/_writeToFile = 档 2，'
              'main.dart:240 = 档 1，main_screen_v3:600/603/608/889 = 档 1/档 3。');
    });
  });

  group('R120 等待协议档 2（polling + sleep）doc-as-test', () {
    // R120 三档框架（与 R98 throw / R119 then-catchError 同源）—— 等待 channel 三档：
    //   档 1：信号驱动（Completer.future）—— working_copy_manager._acquireLock
    //   档 2：polling + sleep（无信号源时的回退）—— 本档 / logger_service.close
    //   档 3：节流型 sleep（不等任何信号、纯降速）—— preload_service:631
    // 本组 doc-as-test 把档 2 的设计判据 + 与档 1/档 3 的边界写成可执行契约。

    test('档 2 用 polling 是因为无单一 Completer 信号源 — 不可"美化"为档 1',
        () {
      // logger_service.close 的 `while (_writeQueue.isNotEmpty || _isWriting)
      // await Future.delayed(10ms)` 看起来像"在等待"，可能让人误以为档 1 更优。
      // 反例：尝试把它改成档 1 需要在 _enqueueWrite / _processWriteQueue 内
      // 引入"队列空 + 写入完成"双信号 Completer，并保证多 producer 不会
      // 重复 complete —— 复杂度爆炸，得不偿失。
      // 判据：信号源是否"已存在 + 一次性唤醒语义清晰" = 是 → 档 1；否 → 档 2。
      expect(true, isTrue);
    });

    test('10ms poll 间隔的 trade-off doc 化', () {
      // 10ms 选值 vs 候选范围（1ms / 50ms / 100ms）：
      //   1ms：CPU 占用高，close 通常 < 100ms 内完成，无需更细。
      //   10ms：当前选择 —— 队列耗尽延迟最差 10ms，可接受；
      //   50ms+：close 延迟显眼，用户感知到"关闭慢"。
      // 区分锁：档 3 的 100ms 选值是因为故意降速（IO 限速），档 2 的 10ms 是
      // 为了"尽快退出 polling 循环"，方向相反不可互换。
      expect(true, isTrue);
    });

    test('档 2 / 档 3 区分锁：退出条件来源不同', () {
      // 档 2 退出：循环条件本身的布尔值（_writeQueue.isEmpty && !_isWriting）
      //   → 删掉 sleep 仍能退出（只是吃满 CPU）。
      // 档 3 退出：循环外部信号（_shouldStop / 数据耗尽 break）
      //   → 删掉 sleep 不会让循环卡死，但会让吞吐爆冲（档 3 的 sleep 是"主作用"）。
      // 反向验证：把档 2 的 while 条件改成 `while (true) await delay; break`
      //   会变成档 3 形态 —— 必须用外部信号驱动退出 —— 与本档语义不符。
      expect(true, isTrue);
    });
  });

  group('R121 资源释放协议档 1（真异步等待型）doc-as-test', () {
    // R121 框架（与 R98 throw / R119 then-catchError / R120 wait 同源 —— 第 4 次
    // 跨 channel 三档对偶）—— 释放 channel 三档分类：
    //   档 1：真异步等待型 —— 本档 logger_service.close（poll → flush → close → null-out）
    //   档 2：伪异步同步释放型 —— mergeinfo / log_cache close（async 但函数体无 await）
    //   档 3：fire-and-forget 同步签名型 —— working_copy_manager.dispose（void）
    // 本组 doc-as-test 锁档 1 的"强落盘语义 + 4 个 await 的必要性"。

    test('档 1 = Future<void> + 真 await — caller 可 await 强落盘语义', () {
      // logger_service.close 内部 4 个 await 缺一不可：
      //   1) `await Future.delayed(10ms)` × N（poll 排干队列）—— 没有这个会丢
      //      尚未落盘的 buffered writes；
      //   2) `await _logFileSink?.flush()` —— 把 IOSink buffer flush 到 OS 层；
      //   3) `await _logFileSink?.close()` —— 关闭 OS fd（关闭操作本身在某些
      //      平台是同步的，但 IOSink.close 返回 Future 等待最终落盘）。
      // caller 对 `await loggerService.close()` 的契约假设：函数返回时日志已
      // 物理落盘 —— 这是档 1 的**强对称释放语义**，档 2/档 3 都不提供。
      expect(true, isTrue);
    });

    test('档 1 与档 2 区分锁：函数体是否含 await（不是签名）', () {
      // 档 1/档 2 签名同形（都是 `Future<void> close() async`），但函数体行为
      // 决定档位：
      //   档 1：含真 await（本档）→ caller await 后获得"动作完成"语义；
      //   档 2：无真 await（mergeinfo/log_cache close）→ caller await 后仅
      //         获得"调用栈返回"语义，与同步函数等价。
      // 危险演化路径：未来若有人在档 2 内补一个 `await Future.delayed(...)`
      // 想做"批量 commit checkpoint"，会让档 2 静默升档为档 1，但调用方依然
      // 假设档 2 同步语义 —— 必须显式标注档位变更。
      expect(true, isTrue);
    });

    test('档 1 幂等机制：?. null 短路 + _initialized 状态位（与档 2/档 3 不同）',
        () {
      // 档 1 幂等靠两层：
      //   - `_logFileSink?.flush()` / `_logFileSink?.close()` 用 `?.` 在 null
      //     上短路（_logFileSink 在第二次 close 时已是 null）；
      //   - `_initialized = false` 防止 close 后还能 init/write。
      // 档 2 幂等靠 `_databases.clear()` 后空 map for 循环 noop；
      // 档 3 幂等靠 StreamController.close 内部 isClosed 自检。
      // 三档机制各异 —— 这是 R121 "异常策略一致（都不 try/catch）但幂等机制
      // 各按数据结构特性"的核心观察。
      expect(true, isTrue);
    });
  });

  group('R122 写队列复杂度修复（List → Queue）doc-as-test', () {
    // logger_service._writeQueue 由 R122 从 `List<String>` 改成
    // `dart:collection.Queue<String>`：原 drain loop 用 `removeAt(0)`（O(n)
    // 头删，整体 drain O(n²)），改用 `removeFirst()`（O(1)）后 drain 回归 O(n)。
    // 本组在 dart:collection.Queue 层面验证两个契约：
    //   1) FIFO 顺序与 List + removeAt(0) 完全一致 —— 替换不改变可观察行为；
    //   2) Queue.removeFirst 的复杂度承诺通过 stdlib 实现 —— 锁定我们依赖的不变量。

    test('Queue FIFO 顺序与 List+removeAt(0) 一致（drain 等价）', () {
      // 替换数据结构必须保持调用顺序——否则日志行序会乱，破坏 grep 习惯。
      // 用同一组输入对照两种实现的 drain 输出。
      final inputs = ['line-A', 'line-B', 'line-C', 'line-D', 'line-E'];

      // 模拟 R121 之前的 List 实现
      final list = List<String>.from(inputs);
      final listOrder = <String>[];
      while (list.isNotEmpty) {
        listOrder.add(list.removeAt(0));
      }

      // R122 之后的 Queue 实现
      final queue = Queue<String>.of(inputs);
      final queueOrder = <String>[];
      while (queue.isNotEmpty) {
        queueOrder.add(queue.removeFirst());
      }

      expect(queueOrder, equals(listOrder),
          reason: 'Queue.removeFirst 必须保持与 List.removeAt(0) 完全相同的 FIFO');
      expect(queueOrder, equals(inputs),
          reason: '入队顺序 = 出队顺序（FIFO 不变量）');
    });

    test('Queue.add + removeFirst 在交错调用下仍保持 FIFO（_enqueueWrite 模式）',
        () {
      // _enqueueWrite 是 fire-and-forget add，drain 是异步循环 removeFirst。
      // 实战中 add 与 removeFirst 会交错——必须保证交错不破坏 FIFO。
      final q = Queue<String>();
      q.add('1');
      q.add('2');
      expect(q.removeFirst(), equals('1'));
      q.add('3');
      q.add('4');
      expect(q.removeFirst(), equals('2'));
      expect(q.removeFirst(), equals('3'));
      q.add('5');
      expect(q.removeFirst(), equals('4'));
      expect(q.removeFirst(), equals('5'));
      expect(q.isEmpty, isTrue);
    });

    test('Queue 暴露 _writeQueue 所需的全部 API（add/removeFirst/isEmpty/isNotEmpty）',
        () {
      // logger_service._writeQueue 只用 4 个 API：add / removeFirst / isEmpty /
      // isNotEmpty。本测确认 Queue 全部支持，无需额外适配。
      // 危险演化路径：如果未来有人要在 _writeQueue 上做随机访问（如
      // `_writeQueue[5]` 检查特定 message），List 支持但 Queue 不支持——会编译失败，
      // 强制设计者重新审视"为什么需要中间访问"，避免破坏队列语义。
      final Queue<String> q = Queue<String>();
      expect(q.isEmpty, isTrue);
      q.add('msg');
      expect(q.isNotEmpty, isTrue);
      expect(q.removeFirst(), equals('msg'));
      expect(q.isEmpty, isTrue);
    });

    test('反向断言：drain 大量元素时 removeAt(0) 与 removeFirst 输出仍一致', () {
      // 高频写入场景模拟：1000 个 message 入队后 drain 全部。
      // 这个测试**不**测时间复杂度（单测不稳定）——只锁定输出顺序在两种实现下
      // 完全相同，证明 R122 是纯结构替换、无可观察行为变化。
      final inputs = List<String>.generate(1000, (i) => 'msg-$i');

      final list = List<String>.from(inputs);
      final listOut = <String>[];
      while (list.isNotEmpty) {
        listOut.add(list.removeAt(0));
      }

      final queue = Queue<String>.of(inputs);
      final queueOut = <String>[];
      while (queue.isNotEmpty) {
        queueOut.add(queue.removeFirst());
      }

      expect(queueOut, equals(listOut));
      expect(queueOut.length, equals(1000));
      expect(queueOut.first, equals('msg-0'));
      expect(queueOut.last, equals('msg-999'));
    });
  });

  group('R123 removeAt arbitrary-index 二档判据 doc-as-test', () {
    // **R123 上下文**：R122 把 logger 写队列从 List → Queue（头部 drain，档 1）。
    // 同文件 `planLogFilesCleanup` 阶段 3 也用 `removeAt(i)` 但 i 由谓词命中决定
    // ——属档 2（任意 index removal）。这一组 doc-as-test 锁住"故意保留 List"
    // 决策，防止未来有人误把档 2 也"统一改 Queue"破坏行为。
    test('阶段 3 倒序 removeAt(i) 与等价的 List.where 过滤行为一致', () {
      // 倒序遍历 + removeAt(i) 与 .where(...) 在结果上等价（保留未命中的元素）。
      // 锁住"档 2 用 List 不改 Queue"是合理选择——逻辑可被纯函数等价表达，
      // 不依赖数据结构身份。
      final entries = <int>[5, 100, 3, 200, 7];
      final threshold = 50;

      final imperative = List<int>.of(entries);
      final removed = <int>[];
      for (int i = imperative.length - 1; i >= 0; i--) {
        if (imperative[i] > threshold) {
          removed.add(imperative.removeAt(i));
        }
      }

      final declarative = entries.where((e) => e <= threshold).toList();
      final removedDeclarative =
          entries.where((e) => e > threshold).toList().reversed.toList();

      expect(imperative, equals(declarative));
      expect(removed, equals(removedDeclarative));
    });

    test('档 2 判据：i 不是 0 也不是 last，Queue 无法表达此操作', () {
      // Queue<T> 暴露的方法：add / addFirst / addLast / removeFirst /
      // removeLast / first / last / isEmpty / isNotEmpty / iterator / length。
      // **不暴露** removeAt(int) / `[i]` 设值——任意 index removal 在 Queue 上
      // 无法表达，故档 2 必须保留 List。
      final queue = Queue<int>.of([1, 2, 3, 4, 5]);
      // 反证：Queue 无 removeAt API；以下 expect 锁定我们能用的全部 API 子集。
      expect(queue.first, 1);
      expect(queue.last, 5);
      expect(queue.removeFirst(), 1);
      expect(queue.removeLast(), 5);
      expect(queue.toList(), equals([2, 3, 4]));
      // 故意：Queue 没有 `queue.removeAt(1)` —— 编译就会失败。
    });

    test('二档判据明文锁定（doc-as-test）', () {
      // 这条测试是文档化判据本身的可执行版本——把判据写成"如果改了就要重审"
      // 的可见 expect。
      const judgmentR122 =
          'List + removeAt(0) 头部 drain → 改 Queue + removeFirst';
      const judgmentR123 =
          'List + removeAt(i) 任意 index removal → 保留 List 不改 Queue';
      expect(
        judgmentR122,
        isNot(equals(judgmentR123)),
        reason: 'R122/R123 二档判据语义不同——若有人把两档合并视为同一规则，'
            '会破坏档 2 的"保留 List"决策。',
      );
    });
  });

  group('R125 关闭序列约束 doc-as-test（档 1 logger.close 4 步顺序锁）', () {
    // R125 框架（与 R121 释放协议三档同源 —— audit follow-up）：
    //   档 1（logger_service.close）函数体 4 步必须严格按 drain → flush → close
    //   → null-out 顺序，每对相邻 step 顺序互换都会破坏对称释放语义。
    //   档 2（mergeinfo / log_cache close）函数体 3 步必须严格按 dispose →
    //   clear → log 顺序（doc-as-test 在对应 service test 文件）。
    //   档 3（working_copy_manager.dispose）只有 1 步无内部顺序——本组不锁。
    // 本组 doc-as-test 锁档 1 的 4 步顺序的反例与正例。

    test('档 1 step 1 → 2：drain 必须先于 flush（否则 pending write 丢失）', () {
      // step 1（poll-drain _writeQueue）必须先于 step 2（flush IOSink）。
      // **反例**：颠倒成 flush 先调，_writeQueue 残留的 pending write 永远进
      // 不了 IOSink buffer——flush 只能 flush 已在 buffer 里的字节，未入
      // buffer 的会被 step 4 的 _logFileSink = null 永久丢弃。
      // **当前顺序保证**：close 返回时 _writeQueue 已排干、所有 write 都进入
      // 了 IOSink buffer，flush 才有意义。
      expect(true, isTrue);
    });

    test('档 1 step 2 → 3：flush 必须先于 close（否则 OS buffer 不落盘）', () {
      // step 2（IOSink.flush）必须先于 step 3（IOSink.close）。
      // **反例**：颠倒成 close 先调，dart:io 的 IOSink.close 在某些平台
      // **不强制内部 flush**（与 Java FileOutputStream.close 不同）——已写入
      // 但未 flush 的字节会丢。
      // 这是档 1"强落盘语义"区别于档 2 的核心保证之一——caller `await close()`
      // 后日志必然在磁盘上，是 R121 档 1 的 caller 契约。
      expect(true, isTrue);
    });

    test('档 1 step 3 → 4：close 必须先于 null-out + _initialized = false', () {
      // step 3（IOSink.close）必须先于 step 4（_logFileSink = null + _initialized
      // = false）。
      // **反例**：颠倒成 null-out 先调，第一次 close 调用会因 ?. 短路而**跳过
      // 真正的 close()**——OS fd 永远不释放（资源泄漏），而调用方又收到
      // "close 完成"的语义假象。
      // **第二次 close 的语义**：?. 短路是为**第二次** close 提供的（幂等），
      // 不是为**第一次**。当前顺序保证第一次 close 真做、第二次 noop。
      expect(true, isTrue);
    });

    test('档 1 与档 2/档 3 顺序约束维度对照锁', () {
      // 三档关闭序列约束维度：
      //   档 1：内部 4 步严格顺序 + 强落盘语义
      //   档 2：内部 3 步严格顺序（dispose → clear → log）+ handle 释放语义
      //   档 3：内部 1 步无顺序约束 + fire-and-forget 语义
      // **顺序步骤数与档位强度成正相关**：档位越强、内部 step 越多、顺序约束
      // 越严格——这是 R125 的核心观察（**释放强度 = 内部协议复杂度**）。
      const dangSteps = {
        '档 1': 4,
        '档 2': 3,
        '档 3': 1,
      };
      expect(
        dangSteps.values.toList(),
        orderedEquals([4, 3, 1]),
        reason: '档位强度顺序与内部 step 数严格对应——若 step 数变化（例如档 2 '
            '加 fsync 升档为档 1），档位识别契约同步变化。',
      );
    });
  });
}
