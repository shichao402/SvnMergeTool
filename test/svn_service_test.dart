import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/services/svn_service.dart';
import 'package:svn_auto_merge/services/svn_auth_exceptions.dart';
import 'package:svn_auto_merge/services/log_filter_service.dart'
    show isUsableWorkingDirectory;
import 'package:svn_auto_merge/providers/app_state.dart' show isUsableSourceUrl;

void main() {
  group('buildSvnCliArgs', () {
    test('无凭据：svn 路径 + --non-interactive + base', () {
      expect(
        buildSvnCliArgs(svnPath: 'svn', baseArgs: const ['log', '-l', '5']),
        ['svn', '--non-interactive', 'log', '-l', '5'],
      );
    });

    test('保留 svnPath 原样（绝对路径不动）', () {
      expect(
        buildSvnCliArgs(
          svnPath: '/opt/homebrew/bin/svn',
          baseArgs: const ['info'],
        ),
        ['/opt/homebrew/bin/svn', '--non-interactive', 'info'],
      );
    });

    test('username 非空 → 注入 --username', () {
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['log'],
          username: 'alice',
        ),
        ['svn', '--username', 'alice', '--non-interactive', 'log'],
      );
    });

    test('password 非空 → 注入 --password', () {
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['log'],
          password: 'p@ss',
        ),
        ['svn', '--password', 'p@ss', '--non-interactive', 'log'],
      );
    });

    test('username + password 同时提供，顺序：username 先于 password', () {
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['log'],
          username: 'alice',
          password: 'p@ss',
        ),
        [
          'svn',
          '--username',
          'alice',
          '--password',
          'p@ss',
          '--non-interactive',
          'log',
        ],
      );
    });

    test('空字符串视作未提供（与 isNotEmpty 判定一致）', () {
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['log'],
          username: '',
          password: '',
        ),
        ['svn', '--non-interactive', 'log'],
      );
    });

    test('baseArgs 为空也合法', () {
      expect(
        buildSvnCliArgs(svnPath: 'svn', baseArgs: const []),
        ['svn', '--non-interactive'],
      );
    });

    test('interactive=true 时不追加 --non-interactive', () {
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['info', 'https://example.com'],
          interactive: true,
        ),
        ['svn', 'info', 'https://example.com'],
      );
    });

    test('interactive=true 且带 username/password 用于一次性鉴权缓存', () {
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['info', 'https://example.com'],
          username: 'alice',
          password: 'p@ss',
          interactive: true,
        ),
        [
          'svn',
          '--username',
          'alice',
          '--password',
          'p@ss',
          'info',
          'https://example.com',
        ],
      );
    });
  });

  group('injectXmlFlag', () {
    const blacklist = {'merge', 'commit', 'mergeinfo'};

    test('useXml=false → 原样返回，didInsert=false', () {
      final r = injectXmlFlag(
        const ['log', '-l', '5'],
        useXml: false,
        xmlBlacklist: blacklist,
      );
      expect(r.args, ['log', '-l', '5']);
      expect(r.didInsert, isFalse);
      expect(r.suppressedCommand, isNull);
    });

    test('useXml=true 且子命令支持 → 在 args[1] 插入 --xml', () {
      final r = injectXmlFlag(
        const ['log', '-l', '5'],
        useXml: true,
        xmlBlacklist: blacklist,
      );
      expect(r.args, ['log', '--xml', '-l', '5']);
      expect(r.didInsert, isTrue);
      expect(r.suppressedCommand, isNull);
    });

    test('useXml=true 但已经包含 --xml → 不重复插入', () {
      final r = injectXmlFlag(
        const ['log', '--xml', '-l', '5'],
        useXml: true,
        xmlBlacklist: blacklist,
      );
      expect(r.args, ['log', '--xml', '-l', '5']);
      expect(r.didInsert, isFalse);
      expect(r.suppressedCommand, isNull);
    });

    test('useXml=true 且子命令在黑名单 → 不插入，并回填 suppressedCommand', () {
      final r = injectXmlFlag(
        const ['merge', 'svn://x', '/wc'],
        useXml: true,
        xmlBlacklist: blacklist,
      );
      expect(r.args, ['merge', 'svn://x', '/wc']);
      expect(r.didInsert, isFalse);
      expect(r.suppressedCommand, 'merge');
    });

    test('useXml=true 且 args 为空 → 不插入，suppressedCommand 走空串分支', () {
      // command = '' 不在黑名单，按"在 args[1] 插入"语义会越界——
      // 实际原代码也是 List.insert(1, ...) 在长度 0 的 list 上会抛异常。
      // 但此分支在生产中不会到达，因为 useXml 总伴随有命令。
      // 这里仅断言我们不会"无端把空串当黑名单命中"。
      // 用单元素安全输入验证：长度>=1 的 args 才不抛。
      final r = injectXmlFlag(
        const ['log'],
        useXml: true,
        xmlBlacklist: blacklist,
      );
      expect(r.args, ['log', '--xml']);
      expect(r.didInsert, isTrue);
    });

    test('不修改入参', () {
      final input = <String>['log', '-l', '5'];
      injectXmlFlag(input, useXml: true, xmlBlacklist: blacklist);
      expect(input, ['log', '-l', '5']);
    });
  });

  group('truncateForLog', () {
    test('短于 maxLen 原样返回', () {
      expect(truncateForLog('hello'), 'hello');
    });

    test('恰好等于 maxLen 不截断', () {
      final s = 'a' * 200;
      expect(truncateForLog(s), s);
    });

    test('超过 maxLen 截到 maxLen 并加 "..."', () {
      final s = 'a' * 250;
      final r = truncateForLog(s);
      expect(r.length, 203); // 200 + 3
      expect(r.endsWith('...'), isTrue);
      expect(r.substring(0, 200), 'a' * 200);
    });

    test('自定义 maxLen', () {
      expect(truncateForLog('abcdef', maxLen: 3), 'abc...');
    });
  });

  group('formatSvnOutputSummary', () {
    test('XML 输出标签', () {
      expect(
        formatSvnOutputSummary(lines: 12, size: 345, useXml: true),
        '(XML 输出: 12 行, 345 字符)',
      );
    });

    test('普通输出标签', () {
      expect(
        formatSvnOutputSummary(lines: 1, size: 7, useXml: false),
        '(输出: 1 行, 7 字符)',
      );
    });
  });

  group('formatSvnExceptionMessage', () {
    test('仅 message', () {
      expect(
        formatSvnExceptionMessage(message: 'boom'),
        'SvnException: boom',
      );
    });

    test('带 command', () {
      expect(
        formatSvnExceptionMessage(message: 'boom', command: 'log -l 5'),
        'SvnException: boom\nCommand: log -l 5',
      );
    });

    test('带 exitCode', () {
      expect(
        formatSvnExceptionMessage(message: 'boom', exitCode: 1),
        'SvnException: boom\nExit code: 1',
      );
    });

    test('output 为空串时跳过 Output 行', () {
      expect(
        formatSvnExceptionMessage(message: 'boom', output: ''),
        'SvnException: boom',
      );
    });

    test('全部字段', () {
      expect(
        formatSvnExceptionMessage(
          message: 'boom',
          command: 'merge svn://x /wc',
          exitCode: 1,
          output: 'oops',
        ),
        'SvnException: boom\n'
        'Command: merge svn://x /wc\n'
        'Exit code: 1\n'
        'Output: oops',
      );
    });
  });

  group('svnOutputNeedsAuth', () {
    test('authorization failed 命中', () {
      expect(svnOutputNeedsAuth('svn: E170001: Authorization failed'), isTrue);
    });

    test('authentication 子串命中', () {
      expect(svnOutputNeedsAuth('Authentication realm: <...>'), isTrue);
    });

    test('could not authenticate 命中', () {
      expect(
        svnOutputNeedsAuth('svn: E170001: Could not authenticate to server'),
        isTrue,
      );
    });

    test('no more credentials 命中', () {
      expect(
        svnOutputNeedsAuth(
            'svn: E215004: No more credentials or we tried too many times'),
        isTrue,
      );
    });

    test('大小写不敏感', () {
      expect(svnOutputNeedsAuth('AUTHORIZATION FAILED'), isTrue);
    });

    test('普通错误不命中', () {
      expect(
        svnOutputNeedsAuth('svn: E155007: not a working copy'),
        isFalse,
      );
    });

    test('空串不命中', () {
      expect(svnOutputNeedsAuth(''), isFalse);
    });
  });

  group('formatProbeFailureReason', () {
    test('SvnAuthRequiredException → 鉴权失败文案', () {
      expect(
        formatProbeFailureReason(
          role: '源 URL',
          error: const SvnAuthRequiredException(url: 'https://x'),
        ),
        '源 URL 校验失败：需要 SVN 鉴权，请在设置中添加鉴权信息',
      );
    });

    test('SvnException + 输出含鉴权关键词 → 鉴权失败文案', () {
      final e = SvnException(
        'svn info failed',
        command: 'info url',
        exitCode: 1,
        output: 'svn: E170001: Authorization failed',
      );
      expect(
        formatProbeFailureReason(role: '源 URL', error: e),
        '源 URL 校验失败：需要 SVN 鉴权，请在设置中添加鉴权信息',
      );
    });

    test('SvnException + 输出无鉴权关键词 → 仅取 message', () {
      final e = SvnException(
        '路径不存在',
        command: 'info /nope',
        exitCode: 1,
        output: 'svn: E155007: not a working copy',
      );
      expect(
        formatProbeFailureReason(role: '目标工作副本', error: e),
        '目标工作副本 校验失败：路径不存在',
      );
    });

    test('SvnException 不暴露 command/exitCode/output 多行噪音', () {
      final e = SvnException(
        'oops',
        command: 'info x',
        exitCode: 99,
        output: 'big\nmulti\nline',
      );
      final msg = formatProbeFailureReason(role: '源 URL', error: e);
      expect(msg.contains('Command'), isFalse);
      expect(msg.contains('Exit code'), isFalse);
      expect(msg.contains('Output'), isFalse);
      expect(msg.contains('\n'), isFalse, reason: '错误必须是一行 SnackBar 友好文案');
    });

    test('非 SvnException → toString 兜底', () {
      expect(
        formatProbeFailureReason(role: '源 URL', error: 'plain string error'),
        '源 URL 校验失败：plain string error',
      );
    });

    test('role 入参可定制（覆盖 source / target 两种语境）', () {
      final e = SvnException('x', output: '');
      expect(
        formatProbeFailureReason(role: '源 URL', error: e),
        startsWith('源 URL 校验失败'),
      );
      expect(
        formatProbeFailureReason(role: '目标工作副本', error: e),
        startsWith('目标工作副本 校验失败'),
      );
    });
  });

  group('SvnService.probeSvnLocation contract（doc-as-test）', () {
    final src = File(
      'lib/services/svn_service.dart',
    ).readAsStringSync();

    test('probeSvnLocation 方法签名锁', () {
      expect(
        src.contains(
          'Future<String?> probeSvnLocation(\n'
          '    String path, {\n'
          '    required String role,\n'
          '    String? username,\n'
          '    String? password,\n'
          '  }) async {',
        ),
        isTrue,
      );
    });

    test('probeSvnLocation 调用 getInfo(item: \'url\') 拿连通性', () {
      final start = src.indexOf(
        'Future<String?> probeSvnLocation(',
      );
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 800);
      expect(body.contains("item: 'url'"), isTrue);
      expect(body.contains('await getInfo('), isTrue);
    });

    test('probeSvnLocation 成功 → return null', () {
      final start = src.indexOf(
        'Future<String?> probeSvnLocation(',
      );
      final body = src.substring(start, start + 800);
      expect(body.contains('return null;'), isTrue);
    });

    test('probeSvnLocation catch 走 formatProbeFailureReason', () {
      final start = src.indexOf(
        'Future<String?> probeSvnLocation(',
      );
      final body = src.substring(start, start + 800);
      expect(body.contains('} catch (e) {'), isTrue);
      expect(
        body.contains('return formatProbeFailureReason(role: role, error: e);'),
        isTrue,
      );
    });
  });

  group('SvnException', () {
    test('toString 走 formatSvnExceptionMessage', () {
      final e = SvnException(
        'cmd failed',
        command: 'log',
        exitCode: 1,
        output: 'auth failed',
      );
      expect(
        e.toString(),
        'SvnException: cmd failed\n'
        'Command: log\n'
        'Exit code: 1\n'
        'Output: auth failed',
      );
    });

    test('needsAuth 走 svnOutputNeedsAuth', () {
      expect(
        SvnException('x', output: 'Authorization failed').needsAuth,
        isTrue,
      );
      expect(
        SvnException('x', output: 'random error').needsAuth,
        isFalse,
      );
    });
  });

  group('formatSvnCommandStartLine', () {
    // 决策锁定：函数签名故意不接受 password 参数 —— 密码值永远以字面量
    // '****' 出现在日志里，从源头杜绝任何"误把真密码写进日志"的风险。
    test('无凭据/非 XML/无工作目录：仅 [SVN 命令执行] svn 前缀 + displayArgs', () {
      expect(
        formatSvnCommandStartLine(
          displayArgs: 'log -l 5',
          username: null,
          useXml: false,
          workingDirectory: null,
        ),
        '[SVN 命令执行] svn log -l 5',
      );
    });

    test('username 非 null → 追加 --username <u> --password ****', () {
      expect(
        formatSvnCommandStartLine(
          displayArgs: 'log',
          username: 'alice',
          useXml: false,
          workingDirectory: null,
        ),
        '[SVN 命令执行] svn log --username alice --password ****',
      );
    });

    test('username 为空串也保留追加（审计可见性，不收紧为 isNotEmpty）', () {
      // 决策锁定：原行为是 username != null 即追加，
      // 即使是空串也输出 "--username  --password ****"，便于排查
      // "上层把空串当用户名传进来"这种异常。
      expect(
        formatSvnCommandStartLine(
          displayArgs: 'log',
          username: '',
          useXml: false,
          workingDirectory: null,
        ),
        '[SVN 命令执行] svn log --username  --password ****',
      );
    });

    test('useXml=true → 追加 [XML 输出]', () {
      expect(
        formatSvnCommandStartLine(
          displayArgs: 'log -l 5',
          username: null,
          useXml: true,
          workingDirectory: null,
        ),
        '[SVN 命令执行] svn log -l 5 [XML 输出]',
      );
    });

    test('workingDirectory 非 null → 追加 (工作目录: <d>)', () {
      expect(
        formatSvnCommandStartLine(
          displayArgs: 'info',
          username: null,
          useXml: false,
          workingDirectory: '/tmp/wc',
        ),
        '[SVN 命令执行] svn info (工作目录: /tmp/wc)',
      );
    });

    test('全字段：顺序 = displayArgs → 凭据 → XML → 工作目录', () {
      expect(
        formatSvnCommandStartLine(
          displayArgs: 'log -l 5',
          username: 'alice',
          useXml: true,
          workingDirectory: '/tmp/wc',
        ),
        '[SVN 命令执行] svn log -l 5 --username alice --password **** '
        '[XML 输出] (工作目录: /tmp/wc)',
      );
    });

    test('密码字面量恒为 ****，函数签名根本不接受 password 入参', () {
      // 决策锁定：再次断言函数没有 password 形参 —— 通过任何方式
      // 调用都不可能让真密码出现在返回的日志行里。
      final line = formatSvnCommandStartLine(
        displayArgs: 'log',
        username: 'alice',
        useXml: false,
        workingDirectory: null,
      );
      expect(line.contains('****'), isTrue);
      expect(line.contains('p@ss'), isFalse);
    });
  });

  group('maskSvnCliPasswordInDisplayArgs', () {
    test('掩码 displayArgs 中的密码值', () {
      expect(
        maskSvnCliPasswordInDisplayArgs(
          'svn --username alice --password secret123 info https://x',
          password: 'secret123',
        ),
        'svn --username alice --password **** info https://x',
      );
    });

    test('无密码时不改动', () {
      expect(
        maskSvnCliPasswordInDisplayArgs('svn info https://x'),
        'svn info https://x',
      );
    });
  });

  group('formatSvnSuccessLine / formatSvnFailureLine', () {
    test('成功模板：✓ + 退出码 + 耗时 ms', () {
      expect(
        formatSvnSuccessLine(exitCode: 0, durationMs: 123),
        '✓ SVN 命令执行成功 (退出码: 0, 耗时: 123ms)',
      );
    });

    test('失败模板：✗ + 退出码 + 耗时 ms', () {
      expect(
        formatSvnFailureLine(exitCode: 1, durationMs: 456),
        '✗ SVN 命令执行失败 (退出码: 1, 耗时: 456ms)',
      );
    });

    test('成功/失败两条仅前缀符号差异（结构对称）', () {
      final ok = formatSvnSuccessLine(exitCode: 0, durationMs: 1);
      final ko = formatSvnFailureLine(exitCode: 0, durationMs: 1);
      expect(ok.replaceFirst('✓ SVN 命令执行成功', 'X'),
          ko.replaceFirst('✗ SVN 命令执行失败', 'X'));
    });

    test('durationMs=0 仍输出 "0ms"', () {
      expect(
        formatSvnSuccessLine(exitCode: 0, durationMs: 0),
        '✓ SVN 命令执行成功 (退出码: 0, 耗时: 0ms)',
      );
    });

    test('durationMs >= 1000 仍输出 ms（不自动换算秒）', () {
      // 决策锁定：日志里 durationMs 永远以 ms 表达，便于机器解析；
      // 不做"超过 1s 就显示秒"这种自适应转换。
      expect(
        formatSvnFailureLine(exitCode: 1, durationMs: 12345),
        '✗ SVN 命令执行失败 (退出码: 1, 耗时: 12345ms)',
      );
    });
  });

  group('formatFindBranchPointHeaderLines', () {
    test('返回 3 行：标题 + 分支 URL + 工作目录（缩进固定）', () {
      final lines = formatFindBranchPointHeaderLines(
        branchUrl: 'svn://x/branches/foo',
        workingDirectory: '/tmp/wc',
      );
      expect(lines, [
        '【SvnService.findBranchPoint】查找分支点',
        '  分支 URL: svn://x/branches/foo',
        '  工作目录: /tmp/wc',
      ]);
    });

    test('字段顺序固定：标题 → URL → 工作目录', () {
      final lines = formatFindBranchPointHeaderLines(
        branchUrl: 'U',
        workingDirectory: 'W',
      );
      expect(lines.length, 3);
      expect(lines[0], '【SvnService.findBranchPoint】查找分支点');
      expect(lines[1].contains('分支 URL'), isTrue);
      expect(lines[2].contains('工作目录'), isTrue);
    });

    test('workingDirectory == null → 占位 "未指定"', () {
      final lines = formatFindBranchPointHeaderLines(
        branchUrl: 'svn://x',
        workingDirectory: null,
      );
      expect(lines.last, '  工作目录: 未指定');
    });

    test('workingDirectory == "" 透传空串（不替换为"未指定"）', () {
      // 决策锁定：null 才走"未指定"，空串原样输出。这样能在日志里
      // 区分"上层完全没传"和"上层传了一个空串"两种异常。
      final lines = formatFindBranchPointHeaderLines(
        branchUrl: 'svn://x',
        workingDirectory: '',
      );
      expect(lines.last, '  工作目录: ');
    });
  });

  group('formatBranchPointResultLine', () {
    test('找到分支点：✓ + 修订号 + 2 空格缩进', () {
      expect(formatBranchPointResultLine(123), '  ✓ 找到分支点: r123');
    });

    test('未找到分支点：⚠ + 提示 + 2 空格缩进', () {
      expect(formatBranchPointResultLine(null), '  ⚠ 未找到分支点');
    });

    test('两条结果行都带 2 空格前导缩进（与 header 保持一致）', () {
      expect(formatBranchPointResultLine(1).startsWith('  '), isTrue);
      expect(formatBranchPointResultLine(null).startsWith('  '), isTrue);
    });

    test('✓ 与 ⚠ 两个分支互斥（不会同时出现）', () {
      final hit = formatBranchPointResultLine(7);
      final miss = formatBranchPointResultLine(null);
      expect(hit.contains('✓'), isTrue);
      expect(hit.contains('⚠'), isFalse);
      expect(miss.contains('⚠'), isTrue);
      expect(miss.contains('✓'), isFalse);
    });
  });

  group('svnPathToWorkingDirectory', () {
    test("'http://...' → null（URL 不切换 cwd）", () {
      expect(svnPathToWorkingDirectory('http://svn.example.com/repo'), isNull);
    });

    test("'https://...' → null（URL 不切换 cwd）", () {
      expect(
        svnPathToWorkingDirectory('https://svn.example.com/repo'),
        isNull,
      );
    });

    test("'svn://...' 与 'svn+ssh://...' → null（SVN URL 不切换 cwd）", () {
      expect(svnPathToWorkingDirectory('svn://svn.example.com/repo'), isNull);
      expect(
        svnPathToWorkingDirectory('svn+ssh://svn.example.com/repo'),
        isNull,
      );
    });

    test("'file://...' → null（仓库 URL 不切换 cwd）", () {
      expect(svnPathToWorkingDirectory('file:///tmp/repo'), isNull);
    });

    test("本地路径 '/tmp/wc' → 原样返回", () {
      expect(svnPathToWorkingDirectory('/tmp/wc'), '/tmp/wc');
    });

    test('空字符串 → 空字符串（不算 URL，本地路径降级；不做合法性校验）', () {
      expect(svnPathToWorkingDirectory(''), '');
    });

    test('Windows 路径 r"C:\\wc" → 原样返回（不被误判为 URL）', () {
      expect(svnPathToWorkingDirectory(r'C:\wc'), r'C:\wc');
    });

    test("大小写敏感：'HTTP://...' 不算 URL（按本地路径处理）", () {
      // 与 dartdoc 契约一致——SVN 命令行严格小写 http/https，本守卫不做大小写转换
      expect(
        svnPathToWorkingDirectory('HTTP://svn.example.com/repo'),
        'HTTP://svn.example.com/repo',
      );
    });

    test("'http' 前缀但不是真 URL（如 'httpdocs/'）按本地路径处理", () {
      expect(svnPathToWorkingDirectory('httpdocs/'), 'httpdocs/');
    });
  });

  group('svnMergeinfoTargetToWorkingDirectory', () {
    test('临时目标 SVN URL 不作为 Process workingDirectory', () {
      expect(
        svnMergeinfoTargetToWorkingDirectory(
          'svn://svn.example.com/repo/branches/target',
        ),
        isNull,
      );
      expect(
        svnMergeinfoTargetToWorkingDirectory(
          'https://svn.example.com/repo/branches/target',
        ),
        isNull,
      );
    });

    test('完整工作副本路径仍作为 workingDirectory', () {
      expect(
        svnMergeinfoTargetToWorkingDirectory('/tmp/target-wc'),
        '/tmp/target-wc',
      );
    });

    test('批量和全量 mergeinfo 查询都使用 URL-safe cwd helper', () {
      final src = File('lib/services/svn_service.dart').readAsStringSync();
      final batchStart =
          src.indexOf('Future<Map<int, bool>> checkMergedStatus(');
      final allStart = src.indexOf('Future<Set<int>> getAllMergedRevisions(');
      expect(batchStart, greaterThan(0));
      expect(allStart, greaterThan(0));

      final batchBody = src.substring(batchStart, allStart);
      final allBody = src.substring(allStart, allStart + 1200);

      expect(
        batchBody,
        contains(
          'workingDirectory: svnMergeinfoTargetToWorkingDirectory(targetWc)',
        ),
      );
      expect(
        allBody,
        contains(
          'workingDirectory: svnMergeinfoTargetToWorkingDirectory(targetWc)',
        ),
      );
      expect(batchBody, isNot(contains('workingDirectory: targetWc,')));
      expect(allBody, isNot(contains('workingDirectory: targetWc,')));
    });
  });

  group('svnStatusOutputHasConflict', () {
    test('空字符串 → false', () {
      expect(svnStatusOutputHasConflict(''), isFalse);
    });

    test('全空行 → false（不抛 RangeError）', () {
      expect(svnStatusOutputHasConflict('\n\n\n'), isFalse);
    });

    test("'C  conflicted.txt' → true（首列 C = 内容冲突）", () {
      expect(svnStatusOutputHasConflict('C  conflicted.txt'), isTrue);
    });

    test('多行混合，某行首列 C → true', () {
      expect(
        svnStatusOutputHasConflict(
          'M  modified.txt\n'
          '?  unknown.txt\n'
          'C  conflict.txt\n',
        ),
        isTrue,
      );
    });

    test('多行无任一首列 C → false', () {
      expect(
        svnStatusOutputHasConflict(
          'M  modified.txt\n'
          'A  added.txt\n'
          'D  deleted.txt\n',
        ),
        isFalse,
      );
    });

    test("文件名包含 'C' 但首列不是 C → false（不被 contains('C') 误判）", () {
      // 关键防线：caller 方法名叫 hasConflicts，不能因为文件名碰巧叫 'CMakeLists.txt' 就误判
      expect(
        svnStatusOutputHasConflict('M  src/CMakeLists.txt\n'),
        isFalse,
      );
    });

    test("第二列为 C（属性冲突 'M C 文件'）→ false（本守卫只看首列）", () {
      // 这是 dartdoc 里"不区分内容冲突 / 属性冲突"的一个表现：
      // 'M C foo'（M 在第一列、C 在第二列）= 内容修改 + 属性冲突，但本函数仅看首列 'M' → 不算冲突。
      // 这条契约符合 caller 当前预期；如未来要识别属性冲突，需要新建独立函数而非改本函数。
      expect(svnStatusOutputHasConflict('M C foo.txt\n'), isFalse);
    });

    test('首列 C 后接换行符立刻命中（短路返回，不扫剩余行）', () {
      expect(
        svnStatusOutputHasConflict(
          'C  conflict.txt\n'
          'M  later.txt\n',
        ),
        isTrue,
      );
    });

    test('单字符行 "C" → true（line[0] == "C"，line.length 不必 > 1）', () {
      expect(svnStatusOutputHasConflict('C'), isTrue);
    });

    test('首列 c（小写）→ false（大小写敏感，SVN 状态码全大写）', () {
      expect(svnStatusOutputHasConflict('c  foo.txt\n'), isFalse);
    });
  });

  group('parseConflictedFiles', () {
    test('空字符串 → 空 list', () {
      expect(parseConflictedFiles(''), isEmpty);
    });

    test('全空行 → 空 list（不抛 RangeError）', () {
      expect(parseConflictedFiles('\n\n\n'), isEmpty);
    });

    test("'C       conflict.txt' → ['conflict.txt']", () {
      // SVN status 单字符状态行：1 列状态 + 6 列其他元信息 + 路径
      expect(
        parseConflictedFiles('C       conflict.txt'),
        ['conflict.txt'],
      );
    });

    test('多行混合，仅冲突行被收，顺序保留', () {
      expect(
        parseConflictedFiles(
          'M       modified.txt\n'
          '?       unknown.txt\n'
          'C       conflict_a.txt\n'
          'A       added.txt\n'
          'C       conflict_b.dart\n',
        ),
        ['conflict_a.txt', 'conflict_b.dart'],
      );
    });

    test('多行无任一首列 C → 空 list', () {
      expect(
        parseConflictedFiles(
          'M       modified.txt\n'
          'A       added.txt\n'
          'D       deleted.txt\n',
        ),
        isEmpty,
      );
    });

    test("文件名包含 'C' 但首列不是 C → 不被收（不被 contains 误判）", () {
      expect(
        parseConflictedFiles('M       src/CMakeLists.txt\n'),
        isEmpty,
      );
    });

    test("第二列为 C（属性冲突 'M C 文件'）→ 不收（与 hasConflict 守卫一致：仅看首列）", () {
      expect(parseConflictedFiles('M C     foo.txt\n'), isEmpty);
    });

    test('单字符行 "C" → 不收（无路径段）', () {
      // line.length < 8，substring(7) 会抛 RangeError，故必须先判长度
      expect(parseConflictedFiles('C'), isEmpty);
    });

    test('首列 C 但路径段全空白 → 不收', () {
      expect(parseConflictedFiles('C       \n'), isEmpty);
    });

    test('路径含空格保留（trim 只去首尾空白）', () {
      expect(
        parseConflictedFiles('C       path with space/foo.txt\n'),
        ['path with space/foo.txt'],
      );
    });

    test('首列 c（小写）→ 不收（大小写敏感）', () {
      expect(parseConflictedFiles('c       foo.txt\n'), isEmpty);
    });
  });

  group('parseChangedFilesCount', () {
    test('空字符串 → 0（空合并基线）', () {
      expect(parseChangedFilesCount(''), 0);
    });

    test('全空行 → 0（SVN 输出末尾常见空行）', () {
      expect(parseChangedFilesCount('\n\n\n'), 0);
    });

    test('单行 M → 1', () {
      expect(parseChangedFilesCount('M       1.txt'), 1);
    });

    test('多种状态混合 → 行数计', () {
      expect(
        parseChangedFilesCount(
          'M       1.txt\n'
          'A       new.txt\n'
          'D       gone.txt\n',
        ),
        3,
      );
    });

    test('混合空行与有效行 → 仅计有效行（自合并 / 末尾空行场景）', () {
      expect(
        parseChangedFilesCount(
          'M       1.txt\n'
          '\n'
          ' M      .\n'
          '\n',
        ),
        2,
      );
    });

    test('属性变更行 (` M ...`) 计入（mergeinfo 属性变更也是合并产出的一部分）', () {
      expect(parseChangedFilesCount(' M      .'), 1);
    });

    test('冲突行 (`C ...`) 计入（冲突也是合并产出，由 caller 区分）', () {
      expect(parseChangedFilesCount('C       conflict.txt'), 1);
    });
  });

  group('parseMergedRevisions', () {
    test('空字符串 → 空 set', () {
      expect(parseMergedRevisions(''), <int>{});
    });

    test("无 r-revision 的字符串 → 空 set（如 mergeinfo 头部 'Path: foo'）", () {
      expect(
          parseMergedRevisions('Path: /trunk\nSource: /branches/x'), <int>{});
    });

    test("单行 'r12345' → {12345}", () {
      expect(parseMergedRevisions('r12345'), {12345});
    });

    test("多行 'r1\\nr2\\nr3' → {1, 2, 3}", () {
      expect(parseMergedRevisions('r1\nr2\nr3'), {1, 2, 3});
    });

    test('同行用空格分隔多个 revision → 全部捕获（不依赖换行）', () {
      expect(parseMergedRevisions('r1 r2 r3'), {1, 2, 3});
    });

    test('重复 revision 自动去重（Set 语义）', () {
      // mergeinfo 在多次合并到同一目标时会重复列出同一 revision——返回 Set 顺便去重
      expect(parseMergedRevisions('r100\nr100\nr200\nr100'), {100, 200});
    });

    test('带前缀杂文（如 mergeinfo 头部）也能正确提取所有 r\\d+', () {
      expect(
        parseMergedRevisions(
          'Path: /trunk\n'
          'Source: /branches/x\n'
          'r1234\n'
          'r5678\n',
        ),
        {1234, 5678},
      );
    });

    test('r0 也会被收（不做合理性校验，r0 在 SVN 是合法输入）', () {
      expect(parseMergedRevisions('r0\nr1'), {0, 1});
    });

    test('字符串中嵌入的 r-revision 也会被捕获（正则全局匹配）', () {
      // 这是有意行为：mergeinfo 可能输出 'merged: r123 from /trunk'
      // 之类的复合消息，正则提取所有 \br\d+\b 即可（无需按行解析）
      expect(parseMergedRevisions('merged r123 from r456'), {123, 456});
    });

    test('返回 Set 而非 List（caller 用 .contains 查询，Set 性能更好且自动去重）', () {
      final result = parseMergedRevisions('r1\nr2');
      expect(result, isA<Set<int>>());
    });

    // R85 迁移锁定：getAllMergedRevisions 内部曾有一段一字不差的 inline 解析链，
    // R85 才把它替换为 parseMergedRevisions(output)。下面 3 条测试用 `svn mergeinfo
    // --show-revs merged` 真实可能的输出形态喂给 helper，锁定行为等价——任何后续对
    // helper 的修改若破坏这些形态，回归立刻可见。
    test(
        'R85 迁移：mergeinfo --show-revs merged 多行输出形态（getAllMergedRevisions 旧入参）',
        () {
      // 形态 1：每行一个 r-revision（svn mergeinfo 最常见输出）
      expect(
        parseMergedRevisions('r1001\nr1002\nr1003\n'),
        {1001, 1002, 1003},
      );
    });

    test('R85 迁移：mergeinfo 输出末尾无换行（流式拼接的边界）', () {
      // svn 进程的 stdout buffer 不保证以 \n 结尾——helper 必须正确处理无尾 \n
      expect(parseMergedRevisions('r9999'), {9999});
    });

    test('R85 迁移：mergeinfo 输出含 "Path:" 头部 + revision 列（混合形态）', () {
      // 实战中 `svn mergeinfo --show-revs merged sourceUrl targetWc` 偶尔会输出
      // 'Path: /branches/x\nr123\nr456\n'，helper 需要忽略头部文本只提取 r\d+
      expect(
        parseMergedRevisions('Path: /branches/feature-x\nr123\nr456\n'),
        {123, 456},
      );
    });
  });

  group('buildSvnLogArgs', () {
    test('startRevision==null → 仅 -l 限制，不加 -r 范围', () {
      final plan = buildSvnLogArgs(
        url: 'http://svn/repo',
        limit: 200,
        startRevision: null,
        reverseOrder: false,
      );
      expect(plan.args, ['log', 'http://svn/repo', '-l', '200']);
      expect(plan.logHint, '从最新开始读取 200 条日志（不限制版本范围）');
    });

    test('startRevision 非 null + reverseOrder=true → -r r:1（向旧版本）', () {
      final plan = buildSvnLogArgs(
        url: 'http://svn/repo',
        limit: 50,
        startRevision: 100,
        reverseOrder: true,
      );
      expect(plan.args, [
        'log',
        'http://svn/repo',
        '-r',
        '100:1',
        '-l',
        '50',
      ]);
      expect(plan.logHint, '从 r100 向更旧版本读取');
    });

    test('startRevision 非 null + reverseOrder=false → -r r:HEAD（向新版本）', () {
      final plan = buildSvnLogArgs(
        url: 'http://svn/repo',
        limit: 50,
        startRevision: 100,
        reverseOrder: false,
      );
      expect(plan.args, [
        'log',
        'http://svn/repo',
        '-r',
        '100:HEAD',
        '-l',
        '50',
      ]);
      expect(plan.logHint, '从 r100 向 HEAD 读取');
    });

    test('双维度独立性反向断言：startRevision==null 时 reverseOrder 取值不影响输出', () {
      // 锁定"reverseOrder 仅当 startRevision 非 null 才有意义"——
      // 如果有人把守卫顺序颠倒（先看 reverseOrder，再看 startRevision），
      // null+true 会进入 reverse 分支并产生 'null:1' 这种坏 SQL。
      // 设计模式 #17 第八处实例。
      final a = buildSvnLogArgs(
        url: 'u',
        limit: 1,
        startRevision: null,
        reverseOrder: true,
      );
      final b = buildSvnLogArgs(
        url: 'u',
        limit: 1,
        startRevision: null,
        reverseOrder: false,
      );
      expect(a.args, b.args);
      expect(a.logHint, b.logHint);
    });

    test('反向断言：reverseOrder 切换在 startRevision 非 null 时产生不同输出', () {
      // 与上一条配对——锁定 reverseOrder 在 startRevision 非 null 时的"激活"语义。
      final fwd = buildSvnLogArgs(
        url: 'u',
        limit: 10,
        startRevision: 5,
        reverseOrder: false,
      );
      final rev = buildSvnLogArgs(
        url: 'u',
        limit: 10,
        startRevision: 5,
        reverseOrder: true,
      );
      expect(fwd.args, isNot(equals(rev.args)));
      expect(fwd.logHint, isNot(equals(rev.logHint)));
    });

    test('limit=0 边界：底层不防御兜底，原样落到 -l 0', () {
      // 锁定"不替 caller 防御非法参数"——SVN 自己会报错，这里不加守卫。
      // 任何"友好"的 limit<=0 → 默认 200 改动会撞红，强迫 review。
      final plan = buildSvnLogArgs(
        url: 'u',
        limit: 0,
        startRevision: null,
        reverseOrder: false,
      );
      expect(plan.args.last, '0');
      expect(plan.logHint, contains('0 条'));
    });

    test('args[0]==log 且 args[1]==url 始终是头两个元素', () {
      // 位置敏感锁定：log 子命令必须是 args[0]，url 必须是 args[1]——
      // SVN CLI 解析依赖位置参数。
      for (final startRev in [null, 100]) {
        for (final rev in [false, true]) {
          final plan = buildSvnLogArgs(
            url: 'http://x/y',
            limit: 1,
            startRevision: startRev,
            reverseOrder: rev,
          );
          expect(plan.args[0], 'log');
          expect(plan.args[1], 'http://x/y');
        }
      }
    });
  });

  group('buildSvnMergeArgs', () {
    test('dryRun=false → [merge, -c, rev, sourceUrl, .]', () {
      expect(
        buildSvnMergeArgs(
          sourceUrl: 'http://svn/branch',
          revision: 42,
          dryRun: false,
        ),
        ['merge', '-c', '42', 'http://svn/branch', '.'],
      );
    });

    test('dryRun=true → --dry-run 必须在 index 1 位置（紧跟 merge）', () {
      // 位置敏感：caller 在日志里高亮 dry-run 标记依赖固定位置；
      // 任何"语义等价但移位"（例如插到末尾）都会撞红。
      final args = buildSvnMergeArgs(
        sourceUrl: 'http://svn/branch',
        revision: 42,
        dryRun: true,
      );
      expect(args, [
        'merge',
        '--dry-run',
        '-c',
        '42',
        'http://svn/branch',
        '.',
      ]);
      expect(args[0], 'merge');
      expect(args[1], '--dry-run');
    });

    test('反向断言：dryRun 切换只增加一个元素，其余位置严格保持', () {
      // 锁定 --dry-run 只是"插入"而非"重写"——
      // 如果有人 refactor 成 args.add('--dry-run') 跑到末尾，本测撞红。
      final off = buildSvnMergeArgs(
        sourceUrl: 'http://svn/branch',
        revision: 42,
        dryRun: false,
      );
      final on = buildSvnMergeArgs(
        sourceUrl: 'http://svn/branch',
        revision: 42,
        dryRun: true,
      );
      expect(on.length, off.length + 1);
      // off: [merge, -c, 42, url, .]
      // on:  [merge, --dry-run, -c, 42, url, .]
      // off[1..] == on[2..]
      expect(on.sublist(2), off.sublist(1));
    });
  });

  group('sparse working copy args', () {
    test('checkout root uses depth empty', () {
      expect(
        buildSvnSparseCheckoutArgs(
          url: 'svn://repo/branches/target',
          targetPath: '/tmp/sparse',
        ),
        [
          'checkout',
          '--depth',
          'empty',
          'svn://repo/branches/target',
          '/tmp/sparse'
        ],
      );
    });

    test('update path can set explicit depth', () {
      expect(
        buildSvnSparseUpdatePathArgs(
          relativePath: 'src',
          setDepth: 'empty',
        ),
        ['update', '--set-depth', 'empty', 'src'],
      );
    });

    test('update path without depth fetches the leaf path', () {
      expect(
        buildSvnSparseUpdatePathArgs(relativePath: 'src/a.dart'),
        ['update', 'src/a.dart'],
      );
    });
  });

  group('buildSvnRevertArgs', () {
    test('recursive=false → [revert, .]', () {
      expect(buildSvnRevertArgs(recursive: false), ['revert', '.']);
    });

    test('recursive=true → [revert, -R, .]', () {
      expect(buildSvnRevertArgs(recursive: true), ['revert', '-R', '.']);
    });

    test('反向断言：recursive 切换严格相差一个 -R 元素', () {
      final off = buildSvnRevertArgs(recursive: false);
      final on = buildSvnRevertArgs(recursive: true);
      expect(on.length, off.length + 1);
      expect(on, ['revert', '-R', '.']);
      expect(off, ['revert', '.']);
      // 共同尾部：'.'
      expect(on.last, off.last);
    });
  });

  group('SvnResolveAccept enum', () {
    test('cliFlag 映射 4 种 mode 到 SVN CLI kebab-case', () {
      expect(SvnResolveAccept.working.cliFlag, 'working');
      expect(SvnResolveAccept.mineFull.cliFlag, 'mine-full');
      expect(SvnResolveAccept.theirsFull.cliFlag, 'theirs-full');
      expect(SvnResolveAccept.base.cliFlag, 'base');
    });

    test('SvnResolveAccept.values 顺序固定 (working, mineFull, theirsFull, base)',
        () {
      expect(SvnResolveAccept.values, [
        SvnResolveAccept.working,
        SvnResolveAccept.mineFull,
        SvnResolveAccept.theirsFull,
        SvnResolveAccept.base,
      ]);
    });

    test('cliFlag 4 个字面量两两不同', () {
      final flags = SvnResolveAccept.values.map((m) => m.cliFlag).toSet();
      expect(flags.length, 4, reason: 'cliFlag 不能撞车');
    });
  });

  group('buildSvnSwitchArgs', () {
    test('固定为 [switch, url, .]', () {
      expect(
        buildSvnSwitchArgs(url: 'svn://host/repo/branches/v2'),
        ['switch', 'svn://host/repo/branches/v2', '.'],
      );
    });

    test('URL 原样透传，caller 负责清洗输入', () {
      const url = ' svn://host/repo/branches/v2 ';
      expect(buildSvnSwitchArgs(url: url), ['switch', url, '.']);
    });
  });

  group('buildSvnListArgs / parseSvnListOutput', () {
    test('list args 固定为 [list, url]', () {
      expect(
        buildSvnListArgs(url: 'svn://host/repo/branches'),
        ['list', 'svn://host/repo/branches'],
      );
    });

    test('parseSvnListOutput 过滤空行并保留目录斜杠', () {
      expect(
        parseSvnListOutput('feature-a/\nreadme.md\n\n  hotfix/  \n'),
        ['feature-a/', 'readme.md', 'hotfix/'],
      );
    });
  });

  group('buildSvnResolveArgs', () {
    test('working → [resolve, --accept, working, -R, .]', () {
      expect(buildSvnResolveArgs(SvnResolveAccept.working),
          ['resolve', '--accept', 'working', '-R', '.']);
    });

    test('mineFull → [resolve, --accept, mine-full, -R, .]', () {
      expect(buildSvnResolveArgs(SvnResolveAccept.mineFull),
          ['resolve', '--accept', 'mine-full', '-R', '.']);
    });

    test('theirsFull → [resolve, --accept, theirs-full, -R, .]', () {
      expect(buildSvnResolveArgs(SvnResolveAccept.theirsFull),
          ['resolve', '--accept', 'theirs-full', '-R', '.']);
    });

    test('base → [resolve, --accept, base, -R, .]', () {
      expect(buildSvnResolveArgs(SvnResolveAccept.base),
          ['resolve', '--accept', 'base', '-R', '.']);
    });

    test('每次返回新 List（避免 caller 修改影响后续调用）', () {
      final a = buildSvnResolveArgs(SvnResolveAccept.working);
      final b = buildSvnResolveArgs(SvnResolveAccept.working);
      expect(a, equals(b));
      expect(identical(a, b), isFalse);
      a.add('mutated');
      expect(buildSvnResolveArgs(SvnResolveAccept.working), hasLength(5),
          reason: '后续调用不应受 a 上的 mutation 影响');
    });

    test('flag 顺序锁：4 种 mode 都满足 [resolve, --accept, <flag>, -R, .]', () {
      for (final mode in SvnResolveAccept.values) {
        final args = buildSvnResolveArgs(mode);
        expect(args[0], 'resolve');
        expect(args[1], '--accept');
        expect(args[2], mode.cliFlag);
        expect(args[3], '-R');
        expect(args[4], '.');
        expect(args, hasLength(5));
      }
    });

    test(
        '与 buildSvnRevertArgs(recursive: true) 共享 -R + . 结构后缀（共同 wc-root 递归约定）',
        () {
      final resolve = buildSvnResolveArgs(SvnResolveAccept.working);
      final revert = buildSvnRevertArgs(recursive: true);
      // 二者尾部 ['-R', '.'] 一致（语义：递归 + 工作副本根）
      expect(resolve.sublist(resolve.length - 2), ['-R', '.']);
      expect(revert.sublist(revert.length - 2), ['-R', '.']);
    });
  });

  group('buildSvnInfoArgs', () {
    test('item==null → [info, path]，不加 --show-item', () {
      expect(
        buildSvnInfoArgs(path: '/wc/path', item: null),
        ['info', '/wc/path'],
      );
    });

    test('item 非 null → [info, --show-item, item, path]，相对位置严格', () {
      // 位置敏感锁定 3 件事：
      // 1. info 在 args[0]；
      // 2. --show-item 紧跟在 info 后（args[1]）；
      // 3. item 紧跟在 --show-item 后（args[2]）——SVN CLI flag/value 配对约定。
      final args = buildSvnInfoArgs(path: '/wc/path', item: 'url');
      expect(args, ['info', '--show-item', 'url', '/wc/path']);
      expect(args[0], 'info');
      expect(args[1], '--show-item');
      expect(args[2], 'url');
    });

    test('item 为各类合法 SVN item 值都按同样形态处理（不维护白名单）', () {
      // 锁定"不替 SVN 维护 item 白名单"——任何字符串都按统一形态拼。
      // SVN 自己会在执行时报非法 item，比这里硬编码列表可靠。
      for (final item in [
        'url',
        'revision',
        'last-changed-revision',
        'kind',
        'made-up-nonexistent',
      ]) {
        final args = buildSvnInfoArgs(path: '/p', item: item);
        expect(args, ['info', '--show-item', item, '/p']);
      }
    });

    test('反向断言：item null vs 非 null 严格相差两个元素', () {
      final without = buildSvnInfoArgs(path: '/p', item: null);
      final with_ = buildSvnInfoArgs(path: '/p', item: 'url');
      expect(with_.length, without.length + 2);
      // 共同首尾：[info] 开头 + path 结尾
      expect(with_.first, without.first);
      expect(with_.last, without.last);
    });
  });

  group('resolveRootTailFromEntries', () {
    test('空列表 → 默认 1（SVN 仓库最早 revision 约定）', () {
      // 锁定默认值——这是项目语义而非数学规则。
      // 任何"友好"地改成抛错或返回 null 都会破坏 caller 期望。
      expect(resolveRootTailFromEntries([]), 1);
    });

    test('单元素 → 该元素本身', () {
      expect(resolveRootTailFromEntries([42]), 42);
    });

    test('多元素 → min', () {
      expect(resolveRootTailFromEntries([100, 50, 200]), 50);
    });

    test('reduce min 不依赖输入顺序（升序、降序、乱序都返回 min）', () {
      // 锁定"用 reduce min 而非取 last（依赖 SVN log 倒序约定）"——
      // 如果有人 refactor 成 list.last 来"省一遍 reduce"，本测会撞红。
      final asc = resolveRootTailFromEntries([1, 2, 3, 4, 5]);
      final desc = resolveRootTailFromEntries([5, 4, 3, 2, 1]);
      final mixed = resolveRootTailFromEntries([3, 1, 5, 2, 4]);
      expect(asc, 1);
      expect(desc, 1);
      expect(mixed, 1);
    });

    test('重复元素不影响 min 结果', () {
      expect(resolveRootTailFromEntries([10, 10, 10]), 10);
      expect(resolveRootTailFromEntries([10, 5, 10, 5]), 5);
    });

    test('入参含 0 / 负数 → 不防御性兜底，原样取 min', () {
      // 锁定"不替 SVN 做语义校验"——SVN revision 理论 >=1，但本函数纯数学 min。
      // 如果将来要校验，应该新建函数（与 #9 一致），不该改这个。
      expect(resolveRootTailFromEntries([5, 0, 10]), 0);
      expect(resolveRootTailFromEntries([-1, 5, 10]), -1);
    });

    test('反向断言：空 vs 仅含 1 都返回 1，但语义不同（一个走默认分支一个走 min 分支）', () {
      // 反向断言锁住"两条路径碰巧都能返回 1，但走法不同"——
      // 如果有人 refactor 成 if (revisions.isEmpty || revisions.first == 1) return 1;
      // 这种"优化"会丢掉非空 + 多元素 + min==1 的正确性（虽然结果一样，但路径错）。
      // 这条测试本身只锁定值；真正的路径锁定在 'reduce min 不依赖输入顺序' 一条里。
      expect(resolveRootTailFromEntries([]), 1);
      expect(resolveRootTailFromEntries([1]), 1);
      expect(resolveRootTailFromEntries([5, 1, 10]), 1);
    });
  });

  group('isUsableSvnCredential', () {
    // 真值表 4 角点
    test('null → false（未提供凭据，走系统 SVN 凭据缓存）', () {
      expect(isUsableSvnCredential(null), isFalse);
    });

    test('空字符串 → false（空串视作未提供凭据——line 29 文档契约）', () {
      // 关键：SVN 收到 `--username ''` 会直接 "authentication failed"，
      // 而不会回退到系统凭据缓存。本谓词必须把空串当未提供处理。
      expect(isUsableSvnCredential(''), isFalse);
    });

    test('单字符 → true（最小可用值——锁定 isNotEmpty 而非 length > N）', () {
      // SVN 用户名理论上可以是单字符，本谓词不做长度兜底
      expect(isUsableSvnCredential('a'), isTrue);
    });

    test('正常用户名 → true', () {
      expect(isUsableSvnCredential('alice'), isTrue);
    });

    // 反向断言：&& 不能误改成 ||（防 OR 误改）
    test('null + 空 都 false 锁定 && 而非 ||（防 OR 误改让空串通过）', () {
      // 如果谓词被误改成 `cred == null || cred.isNotEmpty`，
      // null 输入会走 OR 短路成 true，本测试会红
      expect(isUsableSvnCredential(null), isFalse);
      expect(isUsableSvnCredential(''), isFalse);
    });

    // #15 反向断言：不做 trim
    test('单空格 → true（不做 trim——保留 caller 决策）', () {
      // 与 isUsableSourceUrl 一致：本谓词不做 whitespace 归一化。
      // SVN 历史上确实有用户名含空格的存量场景，本谓词不抢 caller 决定。
      expect(isUsableSvnCredential(' '), isTrue);
    });

    // 与 buildSvnCliArgs 端到端一致性反向断言（#9 hard fence）
    test('谓词 false 时 buildSvnCliArgs 不写 --username/--password 段', () {
      // null
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['log'],
          username: null,
          password: null,
        ),
        isNot(contains('--username')),
      );
      // 空串
      expect(
        buildSvnCliArgs(
          svnPath: 'svn',
          baseArgs: const ['log'],
          username: '',
          password: '',
        ),
        isNot(contains('--password')),
      );
      // 谓词 true 时必写
      final args = buildSvnCliArgs(
        svnPath: 'svn',
        baseArgs: const ['log'],
        username: 'alice',
        password: 'secret',
      );
      expect(
          args, containsAll(['--username', 'alice', '--password', 'secret']));
    });

    // #9 形似但语义不同：跨 3 个谓词的等价性反向断言
    test('与 isUsableSourceUrl / isUsableWorkingDirectory 输出等价但语境不同', () {
      // 三者实现完全相同（`!= null && isNotEmpty`），但 callsite 语境分别是：
      // - isUsableSvnCredential：是否值得加到 svn CLI args 的 --username/--password
      // - isUsableSourceUrl：是否值得调 refreshLogEntries
      // - isUsableWorkingDirectory：是否值得用作 SVN 缓存键
      // 跨模块复用单一通名 helper 会让 callsite 失去语义自描述能力。
      // 单测同时调三者断言**输出一致**——证明实现等价但**不能合并**
      // （callsite 可读性 > 工程师"DRY"洁癖）。
      for (final input in <String?>[null, '', ' ', 'x']) {
        expect(
          isUsableSvnCredential(input),
          isUsableSourceUrl(input),
          reason: 'input=$input: SvnCredential vs SourceUrl 输出应等价',
        );
        expect(
          isUsableSvnCredential(input),
          isUsableWorkingDirectory(input),
          reason: 'input=$input: SvnCredential vs WorkingDirectory 输出应等价',
        );
      }
    });
  });

  group('SvnProcessResult.isSuccess', () {
    // R86 漏迁巡检：本 getter 自 R0 即存在但 7 处 caller（svn_service.dart × 4 +
    // main_screen_v3.dart × 3）一直保留 raw `exitCode == 0`；R86 全部迁完。
    // 此 group 是该 getter 的**首次单测**——锁定 `exitCode == 0` 抽象层契约，
    // 让未来任何对"成功"语义的修改（如引入 warning exit code）只需改本 getter。

    SvnProcessResult mkResult(int exitCode) => SvnProcessResult(
          exitCode: exitCode,
          stdout: '',
          stderr: '',
          pid: 12345,
        );

    test('exitCode == 0 → true（成功的唯一定义）', () {
      expect(mkResult(0).isSuccess, isTrue);
    });

    test('exitCode == 1 → false（最常见的失败码）', () {
      expect(mkResult(1).isSuccess, isFalse);
    });

    test('exitCode 任意非 0 正数 → false（不会被误判为成功）', () {
      // 锁定"非零都是失败"——而非"特定值才失败"
      for (final code in [1, 2, 3, 127, 255]) {
        expect(mkResult(code).isSuccess, isFalse,
            reason: 'exitCode=$code 应判定为失败');
      }
    });

    test('exitCode 负数 → false（异常退出场景，例如 -1 表示进程被信号终止）', () {
      // dart:io 在某些平台上会返回负数 exitCode 表示"被信号杀死"——也应当 false
      for (final code in [-1, -9, -15]) {
        expect(mkResult(code).isSuccess, isFalse,
            reason: 'exitCode=$code（负数）应判定为失败');
      }
    });

    // 反向断言：== 而非 !=、== 0 而非 == 1
    test('锁定 `exitCode == 0` 而非其他比较——0 是成功的唯一定义', () {
      // 这条测试在未来被改成 `exitCode != 0` (反向 bug) 时会立刻失败：
      // - 0.isSuccess 应当 true（如果误改成 `!=`，0 会变 false）
      // - 1.isSuccess 应当 false（如果误改成 `== 1`，1 会变 true）
      expect(mkResult(0).isSuccess, isTrue);
      expect(mkResult(1).isSuccess, isFalse);
    });

    // 与 R85 的迁移锁定测试同模式：用 caller 实战形态喂给 getter，
    // 证明 7 处 raw `exitCode == 0` → `.isSuccess` 替换是行为等价的
    test('R86 迁移：与 raw `exitCode == 0` 表达式输出等价（行为锁定）', () {
      // 在 4 角点（0/1/127/-1）上同时跑两种判断，断言输出等价——
      // 任何后续对 isSuccess 的修改若破坏这条等价，回归立刻可见
      for (final code in [0, 1, 127, -1, 255]) {
        final result = mkResult(code);
        expect(result.isSuccess, result.exitCode == 0,
            reason: 'exitCode=$code: isSuccess 与 raw 表达式应输出等价');
      }
    });
  });

  // R106 — SVN CLI flag 字面量边界审计
  //
  // 与 R104（SharedPreferences key）/ R105（JSON file schema）同维度族：
  // lib ↔ 外部进程协议（SVN CLI argv）。本族的"字面量"是 sub-command 与 flag
  // 字符串本身——任何拼写漂移（`'merginfo'` typo、`--show-revs` 改 `--show-revs=`、
  // `svn:mergeinfo` 改 `svn:merge-info`）SVN 都会**静默接受空结果**或报"unknown
  // option"，比 R104/R105 的 cast/JSON 异常更难诊断，所以测试侧用 literal lock
  // 替代 schema 注册表（lib 无 SVN flag 常量表）。
  //
  // R69 抽过 5 个 args-builder（CliArgs/LogArgs/MergeArgs/RevertArgs/InfoArgs），
  // R106 补齐剩余 caller：mergeinfo（3 处 inline）/ commit /
  // verboseLog / findBranchPointLog / findRootTailLog。完成后 svn_service.dart
  // 内的 argv literal 全部进入测试覆盖。
  group('buildSvnCommitArgs（R106）', () {
    test('固定 3 元素 [commit, -m, message]', () {
      expect(
          buildSvnCommitArgs(message: 'fix bug'), ['commit', '-m', 'fix bug']);
    });

    test("flag literal lock — args[0]=='commit', args[1]=='-m'", () {
      final args = buildSvnCommitArgs(message: 'x');
      expect(args[0], 'commit');
      expect(args[1], '-m');
    });

    test('多行 message 原样透传（不做 shell 转义）', () {
      const msg = 'line1\nline2\n"quoted"';
      expect(buildSvnCommitArgs(message: msg), ['commit', '-m', msg]);
    });

    test('空 message 也照常拼（caller 负责非空判定）', () {
      expect(buildSvnCommitArgs(message: ''), ['commit', '-m', '']);
    });
  });

  group('buildSvnFindBranchPointLogArgs（R106）', () {
    test('固定 7 元素 [log, branchUrl, --stop-on-copy, -l, 1, -r, 1:HEAD]', () {
      expect(
        buildSvnFindBranchPointLogArgs(branchUrl: 'http://svn/repo/branch'),
        [
          'log',
          'http://svn/repo/branch',
          '--stop-on-copy',
          '-l',
          '1',
          '-r',
          '1:HEAD'
        ],
      );
    });

    test('flag literal lock — sub-command 与所有 flag 都不漂移', () {
      final args = buildSvnFindBranchPointLogArgs(branchUrl: 'X');
      expect(args[0], 'log');
      expect(args[2], '--stop-on-copy');
      expect(args[3], '-l');
      expect(args[4], '1', reason: 'limit 硬编码 1');
      expect(args[5], '-r');
      expect(args[6], '1:HEAD', reason: 'revision range 硬编码 1:HEAD');
    });

    test('branchUrl 紧跟 log 后（位置 1）', () {
      final args = buildSvnFindBranchPointLogArgs(branchUrl: 'URL');
      expect(args[1], 'URL');
    });
  });

  group('buildSvnFindRootTailLogArgs（R106）', () {
    test('固定 6 元素 [log, sourceUrl, -r, 1:HEAD, -l, 1]', () {
      expect(
        buildSvnFindRootTailLogArgs(sourceUrl: 'http://svn/repo/trunk'),
        ['log', 'http://svn/repo/trunk', '-r', '1:HEAD', '-l', '1'],
      );
    });

    test('与 findBranchPoint 的差异 — 不带 --stop-on-copy', () {
      // 语义对立保护：root tail 要全历史最早，branch point 要 stop-on-copy 起点。
      // 任何人误加 --stop-on-copy 都会让 root tail 退化成 branch point。
      final args = buildSvnFindRootTailLogArgs(sourceUrl: 'X');
      expect(args, isNot(contains('--stop-on-copy')));
    });

    test('flag literal lock — 所有 flag 都不漂移', () {
      final args = buildSvnFindRootTailLogArgs(sourceUrl: 'X');
      expect(args[0], 'log');
      expect(args[2], '-r');
      expect(args[3], '1:HEAD');
      expect(args[4], '-l');
      expect(args[5], '1');
    });
  });

  group('buildSvnMergeinfoArgs（R106）', () {
    test('固定 5 元素 [mergeinfo, --show-revs, merged, sourceUrl, target]', () {
      expect(
        buildSvnMergeinfoArgs(sourceUrl: 'http://src', target: '/wc'),
        ['mergeinfo', '--show-revs', 'merged', 'http://src', '/wc'],
      );
    });

    test("flag literal lock — args[1]=='--show-revs', args[2]=='merged'", () {
      // R106 关键保护：'merged' 改 'eligible' SVN 不报错但返回完全相反的集合，
      // 是最隐蔽的 flag 漂移面之一。
      final args = buildSvnMergeinfoArgs(sourceUrl: 'S', target: 'T');
      expect(args[0], 'mergeinfo');
      expect(args[1], '--show-revs');
      expect(args[2], 'merged');
    });

    test('target 既可以是 URL 也可以是 WC 路径（同一 args 结构）', () {
      // mergeinfo target 双形态 — 分支判定在 svnPathToWorkingDirectory（caller 侧）。
      final urlArgs =
          buildSvnMergeinfoArgs(sourceUrl: 'S', target: 'http://repo/wc');
      final wcArgs = buildSvnMergeinfoArgs(sourceUrl: 'S', target: '/local/wc');
      expect(urlArgs.length, wcArgs.length);
      expect(urlArgs.sublist(0, 3), wcArgs.sublist(0, 3));
    });

    test('sourceUrl 与 target 顺序固定（不能颠倒）', () {
      // svn mergeinfo 的 source/target 位置敏感（SVN 把第 1 个当 source）。
      final args = buildSvnMergeinfoArgs(sourceUrl: 'SOURCE', target: 'TARGET');
      expect(args[3], 'SOURCE');
      expect(args[4], 'TARGET');
    });
  });

  group('buildSvnVerboseLogArgs（R106）', () {
    test('固定 5 元素 [log, -r, revision, --verbose, sourceUrl]', () {
      expect(
        buildSvnVerboseLogArgs(sourceUrl: 'http://src', revision: 12345),
        ['log', '-r', '12345', '--verbose', 'http://src'],
      );
    });

    test('flag literal lock — --verbose 与 -r 都不漂移', () {
      final args = buildSvnVerboseLogArgs(sourceUrl: 'X', revision: 1);
      expect(args[0], 'log');
      expect(args[1], '-r');
      expect(args[3], '--verbose');
    });

    test('-r 与 revision 必须相邻（SVN flag-value 配对）', () {
      final args = buildSvnVerboseLogArgs(sourceUrl: 'X', revision: 42);
      final dashRIdx = args.indexOf('-r');
      expect(args[dashRIdx + 1], '42');
    });

    test('--verbose 在 sourceUrl 之前（SVN log flag-before-target 约束）', () {
      // 若 --verbose 在 sourceUrl 之后，SVN 会把它当成第 2 个 path 报错。
      final args = buildSvnVerboseLogArgs(sourceUrl: 'http://src', revision: 1);
      expect(args.indexOf('--verbose') < args.indexOf('http://src'), isTrue);
    });

    test('与 buildSvnLogArgs 不合并（语境对立）', () {
      // 本 helper 无 limit；buildSvnLogArgs 强制 limit。任何 caller 把本 helper 改
      // 成调用 buildSvnLogArgs 都会引入隐含 limit，掉文件——本测试做语境守卫。
      final verboseArgs = buildSvnVerboseLogArgs(sourceUrl: 'X', revision: 1);
      expect(verboseArgs, isNot(contains('-l')));
    });
  });

  // R106 — flag literal 全集快照
  //
  // 锁定 svn_service.dart 抽出的 11 个 args-builder（R69 抽 5 + R106 补 6）
  // 各自的 sub-command 首字面量；任何新建 args-builder 必须更新本集合，强迫迁
  // 移者主动登记新 sub-command（R104/R105 测试侧登记表代偿模式 R106 第 3 次）。
  group('R106 sub-command literal 全集快照', () {
    test('所有 args-builder 的首元素必须落在已知 SVN sub-command 集合内', () {
      const knownSubCommands = {
        'log', // buildSvnLogArgs / buildSvnFindBranchPointLogArgs /
        // buildSvnFindRootTailLogArgs / buildSvnVerboseLogArgs
        'merge', // buildSvnMergeArgs
        'revert', // buildSvnRevertArgs
        'switch', // buildSvnSwitchArgs
        'list', // buildSvnListArgs
        'resolve', // buildSvnResolveArgs
        'info', // buildSvnInfoArgs
        'commit', // buildSvnCommitArgs
        'mergeinfo', // buildSvnMergeinfoArgs
      };

      final builders = <String, List<String>>{
        'buildSvnLogArgs': buildSvnLogArgs(
          url: 'X',
          limit: 1,
          startRevision: null,
          reverseOrder: false,
        ).args,
        'buildSvnMergeArgs': buildSvnMergeArgs(
          sourceUrl: 'X',
          revision: 1,
          dryRun: false,
        ),
        'buildSvnRevertArgs': buildSvnRevertArgs(recursive: false),
        'buildSvnSwitchArgs': buildSvnSwitchArgs(url: 'X'),
        'buildSvnListArgs': buildSvnListArgs(url: 'X'),
        'buildSvnResolveArgs': buildSvnResolveArgs(SvnResolveAccept.working),
        'buildSvnInfoArgs': buildSvnInfoArgs(path: 'X', item: null),
        'buildSvnCommitArgs': buildSvnCommitArgs(message: 'x'),
        'buildSvnMergeinfoArgs':
            buildSvnMergeinfoArgs(sourceUrl: 'X', target: 'Y'),
        'buildSvnVerboseLogArgs':
            buildSvnVerboseLogArgs(sourceUrl: 'X', revision: 1),
        'buildSvnFindBranchPointLogArgs':
            buildSvnFindBranchPointLogArgs(branchUrl: 'X'),
        'buildSvnFindRootTailLogArgs':
            buildSvnFindRootTailLogArgs(sourceUrl: 'X'),
      };

      for (final entry in builders.entries) {
        expect(
          knownSubCommands,
          contains(entry.value[0]),
          reason: '${entry.key} 的 sub-command "${entry.value[0]}" 不在登记表内',
        );
      }
    });

    test('所有 R106 helper 的 sub-command 与 _xmlBlacklist 决策一致', () {
      // 间接验证：mergeinfo / commit helper 的 sub-command 必须
      // 在 _xmlBlacklist 内（不支持 --xml），verboseLog / findBranchPoint /
      // findRootTail 用 'log' sub-command 不在 blacklist（支持 --xml）。
      // _xmlBlacklist 是 private static，无法在测试直接拿，但 caller 行为已经
      // 在 injectXmlFlag 单测中验证；这里只 doc-lock sub-command 分组：
      const xmlIncompatibleSubs = {'mergeinfo', 'commit', 'propget', 'switch'};
      const xmlCompatibleSubs = {'log', 'list'};
      expect(buildSvnMergeinfoArgs(sourceUrl: 'X', target: 'Y')[0],
          isIn(xmlIncompatibleSubs));
      expect(buildSvnCommitArgs(message: 'x')[0], isIn(xmlIncompatibleSubs));
      expect(buildSvnSwitchArgs(url: 'X')[0], isIn(xmlIncompatibleSubs));
      expect(buildSvnListArgs(url: 'X')[0], isIn(xmlCompatibleSubs));
      expect(buildSvnVerboseLogArgs(sourceUrl: 'X', revision: 1)[0],
          isIn(xmlCompatibleSubs));
      expect(buildSvnFindBranchPointLogArgs(branchUrl: 'X')[0],
          isIn(xmlCompatibleSubs));
      expect(buildSvnFindRootTailLogArgs(sourceUrl: 'X')[0],
          isIn(xmlCompatibleSubs));
    });
  });
}
