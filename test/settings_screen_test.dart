import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/models/app_config.dart';
import 'package:svn_auto_merge/screens/settings_screen.dart';
import 'package:svn_auto_merge/utils/open_directory.dart';

void main() {
  group('formatPositiveIntForField', () {
    test('正整数 → toString', () {
      expect(formatPositiveIntForField(1), '1');
      expect(formatPositiveIntForField(90), '90');
      expect(formatPositiveIntForField(123456), '123456');
    });

    test('0 → 空串（"0 表示不限制" 在表单里显示为空）', () {
      expect(formatPositiveIntForField(0), '');
    });

    test('负数 → 空串（防御性，理论上不会传入但行为同 0）', () {
      expect(formatPositiveIntForField(-1), '');
      expect(formatPositiveIntForField(-100), '');
    });
  });

  group('formatStopDate', () {
    test('普通日期 → yyyy-MM-dd', () {
      expect(formatStopDate(DateTime(2026, 5, 27)), '2026-05-27');
    });

    test('个位数月份/日期补零', () {
      expect(formatStopDate(DateTime(2024, 1, 5)), '2024-01-05');
      expect(formatStopDate(DateTime(2024, 9, 9)), '2024-09-09');
    });

    test('带时分秒也只保留日期段', () {
      expect(
        formatStopDate(DateTime(2026, 12, 31, 23, 59, 59)),
        '2026-12-31',
      );
    });
  });

  group('resolveStopDatePickerInitialDate', () {
    final now = DateTime(2026, 5, 27, 10, 30);

    test('stopDate=null → now - 90 天', () {
      expect(
        resolveStopDatePickerInitialDate(stopDate: null, now: now),
        now.subtract(const Duration(days: 90)),
      );
    });

    test('stopDate 是合法 ISO 字符串 → 用 parse 出的日期', () {
      expect(
        resolveStopDatePickerInitialDate(
          stopDate: '2025-12-01',
          now: now,
        ),
        DateTime.parse('2025-12-01'),
      );
    });

    test('stopDate 无法 parse（损坏字符串）→ 回落到 now - 90 天', () {
      expect(
        resolveStopDatePickerInitialDate(
          stopDate: 'not-a-date',
          now: now,
        ),
        now.subtract(const Duration(days: 90)),
      );
    });

    test('stopDate 为空串 → tryParse 返回 null → 回落', () {
      // DateTime.tryParse('') 返回 null
      expect(
        resolveStopDatePickerInitialDate(stopDate: '', now: now),
        now.subtract(const Duration(days: 90)),
      );
    });
  });

  group('parseSettingsFormInputs', () {
    SettingsResult parse({
      String maxDaysText = '',
      String maxCountText = '',
      String stopRevisionText = '',
      String stopDateText = '',
      String maxRetriesText = '',
      bool preloadEnabled = true,
      bool stopOnBranchPoint = true,
    }) {
      return parseSettingsFormInputs(
        maxDaysText: maxDaysText,
        maxCountText: maxCountText,
        stopRevisionText: stopRevisionText,
        stopDateText: stopDateText,
        maxRetriesText: maxRetriesText,
        preloadEnabled: preloadEnabled,
        stopOnBranchPoint: stopOnBranchPoint,
      );
    }

    test('全部为空 → 数字字段全 0、stopDate=null、maxRetries=5（默认）', () {
      final r = parse();
      expect(r.preloadSettings.maxDays, 0);
      expect(r.preloadSettings.maxCount, 0);
      expect(r.preloadSettings.stopRevision, 0);
      expect(r.preloadSettings.stopDate, isNull);
      expect(r.maxRetries, 5);
    });

    test('正常数字串 → trim 后 parse', () {
      final r = parse(
        maxDaysText: ' 30 ',
        maxCountText: ' 500 ',
        stopRevisionText: ' 12345 ',
        maxRetriesText: ' 10 ',
      );
      expect(r.preloadSettings.maxDays, 30);
      expect(r.preloadSettings.maxCount, 500);
      expect(r.preloadSettings.stopRevision, 12345);
      expect(r.maxRetries, 10);
    });

    test('非法数字串 → 数字字段回落 0，maxRetries 回落 5', () {
      final r = parse(
        maxDaysText: 'abc',
        maxCountText: '12.5',
        stopRevisionText: '--',
        maxRetriesText: 'NaN',
      );
      expect(r.preloadSettings.maxDays, 0);
      expect(r.preloadSettings.maxCount, 0);
      expect(r.preloadSettings.stopRevision, 0);
      expect(r.maxRetries, 5);
    });

    test('maxRetries 默认值是 5（不是 0），与其它字段不同——显式覆盖', () {
      final r = parse(maxRetriesText: '');
      expect(r.maxRetries, 5);
    });

    test('stopDate 仅空白 → null', () {
      final r = parse(stopDateText: '   ');
      expect(r.preloadSettings.stopDate, isNull);
    });

    test('stopDate 非空 → trim 后保留，不做格式校验', () {
      final r = parse(stopDateText: '  2026-01-15  ');
      expect(r.preloadSettings.stopDate, '2026-01-15');
    });

    test('stopDate 即使是非法日期串也原样保留（与原 _save 行为一致）', () {
      // 原代码不做合法性校验，由调用方保证；测试锁定这条以防有人随手加校验
      final r = parse(stopDateText: 'not-a-date');
      expect(r.preloadSettings.stopDate, 'not-a-date');
    });

    test('布尔字段直出', () {
      final r = parse(preloadEnabled: false, stopOnBranchPoint: false);
      expect(r.preloadSettings.enabled, isFalse);
      expect(r.preloadSettings.stopOnBranchPoint, isFalse);

      final r2 = parse(preloadEnabled: true, stopOnBranchPoint: true);
      expect(r2.preloadSettings.enabled, isTrue);
      expect(r2.preloadSettings.stopOnBranchPoint, isTrue);
    });

    test('返回值是 SettingsResult，包含 PreloadSettings 字段', () {
      final r = parse(
        maxDaysText: '7',
        maxCountText: '100',
        stopRevisionText: '999',
        stopDateText: '2026-06-01',
        maxRetriesText: '3',
        preloadEnabled: true,
        stopOnBranchPoint: false,
      );
      expect(r, isA<SettingsResult>());
      expect(r.preloadSettings, isA<PreloadSettings>());
      expect(r.preloadSettings.maxDays, 7);
      expect(r.preloadSettings.maxCount, 100);
      expect(r.preloadSettings.stopRevision, 999);
      expect(r.preloadSettings.stopDate, '2026-06-01');
      expect(r.preloadSettings.enabled, isTrue);
      expect(r.preloadSettings.stopOnBranchPoint, isFalse);
      expect(r.maxRetries, 3);
    });

    test('整型负数串 → tryParse 解析成负数（不做夹紧——锁定原行为）', () {
      // 原代码用 int.tryParse 不做正数校验。即便 UI 用 digitsOnly 输入 formatter
      // 实际 controller.text 永远不会出现负号，此处仍把"无校验"行为作为契约锁住，
      // 防止有人偷偷加 .clamp(0, ...) 改变默认数据流。
      final r = parse(maxDaysText: '-5');
      expect(r.preloadSettings.maxDays, -5);
    });
  });

  group('resolveOpenDirectoryCommand', () {
    test('macos → open <path>', () {
      final cmd = resolveOpenDirectoryCommand(
        platform: 'macos',
        path: '/Users/foo/logs',
      );
      expect(cmd, isNotNull);
      expect(cmd!.executable, 'open');
      expect(cmd.args, ['/Users/foo/logs']);
    });

    test('windows → explorer <path>', () {
      final cmd = resolveOpenDirectoryCommand(
        platform: 'windows',
        path: r'C:\Users\foo\logs',
      );
      expect(cmd, isNotNull);
      expect(cmd!.executable, 'explorer');
      // 反斜杠路径原样透传，不做归一化
      expect(cmd.args, [r'C:\Users\foo\logs']);
    });

    test('linux → xdg-open <path>', () {
      final cmd = resolveOpenDirectoryCommand(
        platform: 'linux',
        path: '/home/foo/logs',
      );
      expect(cmd, isNotNull);
      expect(cmd!.executable, 'xdg-open');
      expect(cmd.args, ['/home/foo/logs']);
    });

    test('android / ios / fuchsia / 未知 → null', () {
      // 与原代码"if/else if 三段命中后兜底 SnackBar"语义对齐
      expect(
        resolveOpenDirectoryCommand(platform: 'android', path: '/x'),
        isNull,
      );
      expect(
        resolveOpenDirectoryCommand(platform: 'ios', path: '/x'),
        isNull,
      );
      expect(
        resolveOpenDirectoryCommand(platform: 'fuchsia', path: '/x'),
        isNull,
      );
      expect(
        resolveOpenDirectoryCommand(platform: 'plan9', path: '/x'),
        isNull,
      );
    });

    test('platform 大小写敏感（macOS / MACOS / Linux 等大写形式不命中）', () {
      // Platform.operatingSystem 文档保证返回小写，这里 lock 此前提：
      // 万一未来 Dart 改了语义（不会，但万一），test 会先红
      expect(
        resolveOpenDirectoryCommand(platform: 'macOS', path: '/x'),
        isNull,
      );
      expect(
        resolveOpenDirectoryCommand(platform: 'Linux', path: '/x'),
        isNull,
      );
      expect(
        resolveOpenDirectoryCommand(platform: 'WINDOWS', path: '/x'),
        isNull,
      );
    });

    test('path 含空格 → 原样透传到 args（不加引号）', () {
      // 引号 / 转义交给 Process.run，不在本函数职责
      final cmd = resolveOpenDirectoryCommand(
        platform: 'macos',
        path: '/Users/foo/with space/logs',
      );
      expect(cmd!.args, ['/Users/foo/with space/logs']);
    });

    test('OpenDirectoryCommand 值相等性（executable + args 逐项）', () {
      const a =
          OpenDirectoryCommand(executable: 'open', args: ['/x']);
      const b =
          OpenDirectoryCommand(executable: 'open', args: ['/x']);
      const c =
          OpenDirectoryCommand(executable: 'open', args: ['/y']);
      const d =
          OpenDirectoryCommand(executable: 'explorer', args: ['/x']);
      const e = OpenDirectoryCommand(
        executable: 'open',
        args: ['/x', '/y'],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
      expect(a, isNot(equals(e)));
    });

    test('OpenDirectoryCommand Set 去重（R103 补漏：4 个互不相等元素）', () {
      // 4 case 全互不相等 → Set 大小应为 4
      const a = OpenDirectoryCommand(executable: 'open', args: ['/x']);
      const c = OpenDirectoryCommand(executable: 'open', args: ['/y']);
      const d = OpenDirectoryCommand(executable: 'explorer', args: ['/x']);
      const e =
          OpenDirectoryCommand(executable: 'open', args: ['/x', '/y']);
      final s = <OpenDirectoryCommand>{a, c, d, e};
      expect(s.length, 4,
          reason: 'executable / args 内容 / args 长度 各维度都参与 ==');
    });

    test('OpenDirectoryCommand args List 同内容不同实例视为相等（R103 实测契约 doc 化）', () {
      // 锁定 lib 内 args 逐项比较实现——而不是 List 引用比较。
      // 防御未来误改成 `other.args == args`（List 默认引用比较一定 fail）。
      final a = OpenDirectoryCommand(executable: 'open', args: ['/x', '/y']);
      final b = OpenDirectoryCommand(executable: 'open', args: ['/x', '/y']);
      expect(identical(a.args, b.args), isFalse,
          reason: '前置：a.args 与 b.args 是不同 List 实例');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('resolveOpenFileCommand', () {
    test("macos → 'open <path>'（同 resolveOpenDirectoryCommand）", () {
      final cmd = resolveOpenFileCommand(
        platform: 'macos',
        path: '/Users/dev/wc/foo.dart',
      );
      expect(cmd, isNotNull);
      expect(cmd!.executable, 'open');
      expect(cmd.args, ['/Users/dev/wc/foo.dart']);
    });

    test("windows → 'cmd /c start \"\" <path>'（不走 explorer 防 select-only）", () {
      // explorer <file> 在 Win 会"在文件管理器中选中"而不是"打开"，
      // 故走 cmd /c start ""（"" 为窗口标题占位）调系统关联程序。
      final cmd = resolveOpenFileCommand(
        platform: 'windows',
        path: r'C:\dev\wc\foo.dart',
      );
      expect(cmd, isNotNull);
      expect(cmd!.executable, 'cmd');
      expect(cmd.args, ['/c', 'start', '', r'C:\dev\wc\foo.dart']);
    });

    test("linux → 'xdg-open <path>'（同 resolveOpenDirectoryCommand）", () {
      final cmd = resolveOpenFileCommand(
        platform: 'linux',
        path: '/home/dev/wc/foo.dart',
      );
      expect(cmd, isNotNull);
      expect(cmd!.executable, 'xdg-open');
      expect(cmd.args, ['/home/dev/wc/foo.dart']);
    });

    test('未知平台 → null（android / ios / fuchsia / 任意未知）', () {
      expect(resolveOpenFileCommand(platform: 'android', path: '/x'), isNull);
      expect(resolveOpenFileCommand(platform: 'ios', path: '/x'), isNull);
      expect(resolveOpenFileCommand(platform: 'fuchsia', path: '/x'), isNull);
      expect(resolveOpenFileCommand(platform: 'plan9', path: '/x'), isNull);
      expect(resolveOpenFileCommand(platform: '', path: '/x'), isNull);
    });

    test('大小写敏感 → 大小写错误的平台名也判 null（与 resolveOpenDirectoryCommand 一致）', () {
      expect(resolveOpenFileCommand(platform: 'macOS', path: '/x'), isNull);
      expect(resolveOpenFileCommand(platform: 'Linux', path: '/x'), isNull);
      expect(resolveOpenFileCommand(platform: 'WINDOWS', path: '/x'), isNull);
    });

    test('path 含空格原样透传，不做引号 / 转义', () {
      final cmd = resolveOpenFileCommand(
        platform: 'macos',
        path: '/Users/foo/with space/foo.dart',
      );
      expect(cmd!.args, ['/Users/foo/with space/foo.dart']);
    });

    test('与 resolveOpenDirectoryCommand 在 macOS / Linux 等价（相同 executable）', () {
      // 两个 helper 在 mac / linux 用同一个可执行文件——OS 自身根据 path 类型决定行为
      final fileMac = resolveOpenFileCommand(platform: 'macos', path: '/x');
      final dirMac = resolveOpenDirectoryCommand(platform: 'macos', path: '/x');
      expect(fileMac!.executable, dirMac!.executable);

      final fileLinux = resolveOpenFileCommand(platform: 'linux', path: '/x');
      final dirLinux =
          resolveOpenDirectoryCommand(platform: 'linux', path: '/x');
      expect(fileLinux!.executable, dirLinux!.executable);
    });

    test('Windows 上 file 与 directory 解析结果不同（cmd vs explorer）', () {
      // 锁定 Windows 分支差异：文件用 cmd /c start，目录用 explorer
      final file = resolveOpenFileCommand(platform: 'windows', path: r'C:\x');
      final dir = resolveOpenDirectoryCommand(platform: 'windows', path: r'C:\x');
      expect(file!.executable, 'cmd');
      expect(dir!.executable, 'explorer');
      expect(file, isNot(equals(dir)));
    });
  });

  group('kDefaultMaxRetries', () {
    test('值固定为 5——锁定字面值', () {
      // 这是一个面向用户的"业务默认值"。改这条值意味着：
      // - 老用户重启后默认重试次数会变（如果没显式存过）
      // - 新用户第一次打开默认重试次数会变
      // 单测显式比较字面值，让任何想改这条值的人必须**主动**修改测试，
      // 不能因为"代码里改了一处看起来没爆"就静默修改。
      expect(kDefaultMaxRetries, 5);
    });

    test('parseSettingsFormInputs 在 maxRetries 解析失败时回退到 kDefaultMaxRetries', () {
      // 锁定"兜底来源"——禁止有人把这里的 ?? 默认值改成另一个数字而不同步常量
      final result = parseSettingsFormInputs(
        maxDaysText: '0',
        maxCountText: '0',
        stopRevisionText: '0',
        stopDateText: '',
        maxRetriesText: 'not-a-number',
        preloadEnabled: false,
        stopOnBranchPoint: false,
      );
      expect(result.maxRetries, kDefaultMaxRetries);
    });

    test('parseSettingsFormInputs 在 maxRetries 为空字符串时回退到 kDefaultMaxRetries', () {
      // 空字符串走和"无法 parse"同一兜底分支
      final result = parseSettingsFormInputs(
        maxDaysText: '',
        maxCountText: '',
        stopRevisionText: '',
        stopDateText: '',
        maxRetriesText: '',
        preloadEnabled: true,
        stopOnBranchPoint: true,
      );
      expect(result.maxRetries, kDefaultMaxRetries);
    });

    test('parseSettingsFormInputs 在 maxRetries 为合法值时不走兜底（防止 ?? 顺序错）', () {
      // 锁住"用户输入合法时优先使用用户值"——防御 `int.tryParse(...) ?? kDefaultMaxRetries`
      // 被改成 `kDefaultMaxRetries ?? int.tryParse(...)`（语法上合法，但 ?? 永远会取常量）
      final result = parseSettingsFormInputs(
        maxDaysText: '0',
        maxCountText: '0',
        stopRevisionText: '0',
        stopDateText: '',
        maxRetriesText: '7',
        preloadEnabled: false,
        stopOnBranchPoint: false,
      );
      expect(result.maxRetries, 7);
      expect(result.maxRetries, isNot(kDefaultMaxRetries));
    });

    test('kDefaultMaxRetries 与其它"0 默认值字段"语义不同：必须 > 0', () {
      // PreloadSettings 里的 maxDays/maxCount/stopRevision 默认值是 0 ("不限制")，
      // 但 maxRetries 默认值是 kDefaultMaxRetries（一个有意义的非零数）。
      // 这条测试锁住"重试次数 0 是非法语义"——禁止把常量改成 0。
      expect(kDefaultMaxRetries, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  // R114 OpenDirectoryCommand.toString 格式锁
  //
  // lib/screens/settings_screen.dart:133 输出
  // 'OpenDirectoryCommand($executable ${args.join(' ')})'。
  // 此格式在错误诊断弹窗中直接展示——若改成 'open /path' 风格（去掉类名包装）
  // 与"打开失败：$cmd"日志中的格式约定冲突。
  // -------------------------------------------------------------------------

  group('R114 OpenDirectoryCommand.toString 格式锁', () {
    test('toString 形如 "OpenDirectoryCommand(executable arg1 arg2 ...)"', () {
      // R114 实测契约 doc 化：lib :133 输出"类名 + 圆括号 + executable + 空格 + args"。
      const cmd = OpenDirectoryCommand(
        executable: 'open',
        args: ['/Users/x/Logs'],
      );
      expect(cmd.toString(), 'OpenDirectoryCommand(open /Users/x/Logs)');
    });

    test('多 args 用空格分隔（args.join(\' \')）', () {
      // 锁住"args 用空格分隔"约定——若有人改成逗号分隔，错误日志中
      // 'OpenDirectoryCommand(explorer, /select,, C:\\path)' 会让用户误以为多了
      // 一个逗号 arg。
      const cmd = OpenDirectoryCommand(
        executable: 'explorer',
        args: ['/select,', r'C:\path\to\file'],
      );
      expect(cmd.toString(),
          r'OpenDirectoryCommand(explorer /select, C:\path\to\file)');
    });

    test('空 args → 输出尾部多一个空格但不省略括号', () {
      // R104 类型 doc-via-test：args.join('') 在 args=[] 时返回 ''——
      // 输出形如 'OpenDirectoryCommand(open )' 末尾有空格。
      // 这是 args.join 的固有行为、非 lib bug——锁住此现状避免未来"美化"。
      const cmd = OpenDirectoryCommand(
        executable: 'open',
        args: [],
      );
      expect(cmd.toString(), 'OpenDirectoryCommand(open )');
    });
  });

  group('_save 持久化失败的 SnackBar 反馈契约（doc-as-test）', () {
    // 用户场景：磁盘满 / 权限拒绝 / SharedPreferences 写入失败时，
    // _save 的 try/catch 原本只写日志却仍 pop(result)，UI 显示"保存成功"
    // 实际未持久化，下次启动配置丢失。现改为：catch 分支弹 SnackBar 显示
    // 具体错误 + 提前 return（不 pop），让用户感知失败可重试或手动取消。
    final src =
        File('lib/screens/settings_screen.dart').readAsStringSync();

    test('catch 分支弹 SnackBar 显示具体错误', () {
      expect(
        src.contains("Text('保存设置失败：\$e')"),
        isTrue,
        reason: 'catch 分支必须 SnackBar 显示具体错误（含 \$e）',
      );
      expect(
        src.contains('backgroundColor: Colors.red'),
        isTrue,
        reason: 'catch 分支 SnackBar 必须用红色背景，与成功路径区分',
      );
    });

    test('catch 分支必须 return 不 pop（拒绝静默成功 bug）', () {
      // 锁定 catch 块以 `return;` 结束，且整个 _save 内 Navigator.pop
      // 仅出现一次（即成功路径那次）。
      final saveStart = src.indexOf('Future<void> _save() async {');
      expect(saveStart, greaterThan(0), reason: '_save 方法必须存在');
      // 找出 _save 方法体的边界（找下一个 Future / void / 顶层方法定义）
      final pickDateStart = src.indexOf('Future<void> _pickDate()', saveStart);
      expect(pickDateStart, greaterThan(saveStart),
          reason: '_save 后应紧接 _pickDate 方法');
      final saveBody = src.substring(saveStart, pickDateStart);

      // _save 内 Navigator.of(context).pop(result) 仅出现一次（成功路径）
      final popMatches = 'Navigator.of(context).pop(result)'
          .allMatches(saveBody)
          .length;
      // 注意 String.allMatches 不支持，改 RegExp
      final popCount = RegExp(r'Navigator\.of\(context\)\.pop\(result\)')
          .allMatches(saveBody)
          .length;
      expect(popCount, 1,
          reason: '_save 中 Navigator.pop(result) 只允许成功路径出现 1 次，'
              'catch 分支不得 pop（避免静默成功）');
      expect(popMatches, anyOf(0, 1)); // 占位避免变量未用警告

      // catch 块必须以 return; 结尾（防止 fallthrough 到 pop）
      expect(
        saveBody.contains('return;'),
        isTrue,
        reason: 'catch 分支必须显式 return; 防止 fallthrough 到 pop(result)',
      );
    });

    test('成功路径 pop(result) 仍存在', () {
      expect(
        src.contains('Navigator.of(context).pop(result);'),
        isTrue,
        reason: '保存成功后必须 pop(result) 关闭设置页并把结果返给调用方',
      );
    });
  });

  group('isSettingsFormDirty 字段级 dirty 检测', () {
    const baselinePreload = PreloadSettings(
      enabled: true,
      stopOnBranchPoint: true,
      maxDays: 90,
      maxCount: 1000,
      stopRevision: 0,
      stopDate: null,
    );
    const baselineMaxRetries = 3;

    SettingsResult mk({
      bool enabled = true,
      bool stopOnBranchPoint = true,
      int maxDays = 90,
      int maxCount = 1000,
      int stopRevision = 0,
      String? stopDate,
      int maxRetries = 3,
    }) =>
        SettingsResult(
          preloadSettings: PreloadSettings(
            enabled: enabled,
            stopOnBranchPoint: stopOnBranchPoint,
            maxDays: maxDays,
            maxCount: maxCount,
            stopRevision: stopRevision,
            stopDate: stopDate,
          ),
          maxRetries: maxRetries,
        );

    test('全字段同基线 → false', () {
      expect(
        isSettingsFormDirty(
          current: mk(),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isFalse,
      );
    });

    test('enabled 改了 → true', () {
      expect(
        isSettingsFormDirty(
          current: mk(enabled: false),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isTrue,
      );
    });

    test('stopOnBranchPoint 改了 → true', () {
      expect(
        isSettingsFormDirty(
          current: mk(stopOnBranchPoint: false),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isTrue,
      );
    });

    test('maxDays 改了 → true', () {
      expect(
        isSettingsFormDirty(
          current: mk(maxDays: 30),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isTrue,
      );
    });

    test('maxCount 改了 → true', () {
      expect(
        isSettingsFormDirty(
          current: mk(maxCount: 500),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isTrue,
      );
    });

    test('stopRevision 改了 → true', () {
      expect(
        isSettingsFormDirty(
          current: mk(stopRevision: 12345),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isTrue,
      );
    });

    test('stopDate null→非 null → true', () {
      expect(
        isSettingsFormDirty(
          current: mk(stopDate: '2026-01-01'),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isTrue,
      );
    });

    test('maxRetries 改了 → true', () {
      expect(
        isSettingsFormDirty(
          current: mk(maxRetries: 5),
          baselinePreload: baselinePreload,
          baselineMaxRetries: baselineMaxRetries,
        ),
        isTrue,
      );
    });
  });

  group('设置页 X 关闭按钮 dirty-check 接线契约（doc-as-test）', () {
    // 用户场景：用户在设置页改了若干字段后误点 AppBar 左上 X，
    // 原 onPressed 直连 `Navigator.of(context).pop()` 静默丢弃所有未保存输入。
    // 现改为：调 _onClosePressed → dirty 时弹"丢弃未保存的修改？"确认 dialog。
    final src =
        File('lib/screens/settings_screen.dart').readAsStringSync();

    test('AppBar leading IconButton 接到 _onClosePressed 而非直连 pop', () {
      expect(
        src.contains('onPressed: _onClosePressed,'),
        isTrue,
        reason: 'X 按钮必须接 _onClosePressed 才能做 dirty 检测',
      );
      expect(
        src.contains('onPressed: () => Navigator.of(context).pop(),\n          tooltip: \'取消\','),
        isFalse,
        reason: 'X 按钮不得再直连 Navigator.pop()（静默丢弃 bug）',
      );
    });

    test('_onClosePressed 调用 isSettingsFormDirty 做字段级对比', () {
      expect(
        src.contains('Future<void> _onClosePressed() async {'),
        isTrue,
      );
      expect(
        src.contains('isSettingsFormDirty('),
        isTrue,
        reason: '关闭前必须用 isSettingsFormDirty 做 dirty 检测',
      );
    });

    test('dirty 时弹确认 dialog 含规定文案', () {
      expect(
        src.contains("Text('丢弃未保存的修改？')"),
        isTrue,
      );
      expect(
        src.contains("Text('设置页有未保存的修改，关闭后将丢失。是否继续？')"),
        isTrue,
      );
      expect(
        src.contains("Text('取消')"),
        isTrue,
        reason: 'dialog 必须有 取消 按钮（保留在设置页）',
      );
      expect(
        src.contains("Text('丢弃')"),
        isTrue,
        reason: 'dialog 必须有 丢弃 按钮（确认丢弃修改）',
      );
    });

    test('非 dirty 时直接 pop 不弹 dialog', () {
      // _onClosePressed 内 if (!dirty) → Navigator.pop() 早退路径
      final closeStart = src.indexOf('Future<void> _onClosePressed() async {');
      expect(closeStart, greaterThan(0));
      // 取从 _onClosePressed 开始到下一个方法 _pickDate 之间的方法体
      final pickDateStart = src.indexOf('Future<void> _pickDate()', closeStart);
      expect(pickDateStart, greaterThan(closeStart));
      final closeBody = src.substring(closeStart, pickDateStart);
      expect(
        closeBody.contains('if (!dirty)'),
        isTrue,
        reason: '必须显式判断 !dirty 早退',
      );
    });
  });

  group('设置页保存按钮对比度契约（doc-as-test）', () {
    final src =
        File('lib/screens/settings_screen.dart').readAsStringSync();

    test('build 内先取得 ColorScheme，按钮颜色走主题高对比色对', () {
      expect(
        src.contains('final colorScheme = Theme.of(context).colorScheme;'),
        isTrue,
        reason: '保存按钮应复用 Material ColorScheme，避免手写低对比颜色',
      );
      expect(
        src.contains('backgroundColor: colorScheme.primary,'),
        isTrue,
        reason: '保存按钮背景应使用 primary',
      );
      expect(
        src.contains('foregroundColor: colorScheme.onPrimary,'),
        isTrue,
        reason: '保存按钮文字/图标应使用 onPrimary 保证与 primary 对比',
      );
    });

    test('保存按钮不得回退为白底 + primaryColor 前景', () {
      final buttonStart = src.indexOf('FilledButton.icon(');
      expect(buttonStart, greaterThan(0), reason: '设置页必须存在保存 FilledButton');
      final buttonEnd = src.indexOf('const SizedBox(width: 8)', buttonStart);
      expect(buttonEnd, greaterThan(buttonStart));
      final buttonBlock = src.substring(buttonStart, buttonEnd);

      expect(buttonBlock.contains('backgroundColor: Colors.white'), isFalse);
      expect(
        buttonBlock.contains('foregroundColor: Theme.of(context).primaryColor'),
        isFalse,
      );
    });
  });
}
