import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:svn_auto_merge/services/logger_service.dart';
import 'package:svn_auto_merge/services/svn_auth_clear_service.dart';
import 'package:svn_auto_merge/services/svn_auth_exceptions.dart';
import 'package:svn_auto_merge/services/svn_auth_gate_service.dart';
import 'package:svn_auto_merge/services/svn_service.dart';

void main() {
  setUpAll(() {
    logger.enabled = false;
  });

  group('classifyAuthProbe', () {
    test('exit 0 → ok', () {
      expect(
        classifyAuthProbe(exitCode: 0, output: ''),
        AuthProbeStatus.ok,
      );
    });

    test('authorization failed → needsAuth', () {
      expect(
        classifyAuthProbe(
          exitCode: 1,
          output: 'svn: Authorization failed',
        ),
        AuthProbeStatus.needsAuth,
      );
    });

    test('其它错误 → error', () {
      expect(
        classifyAuthProbe(exitCode: 1, output: 'svn: E170001: Not found'),
        AuthProbeStatus.error,
      );
    });
  });

  group('collectAuthGuideUrls', () {
    test('收集源与目标 URL，本地路径不入列', () {
      expect(
        collectAuthGuideUrls(
          sourceUrl: 'https://svn.example.com/src',
          targetUrl: '/tmp/wc',
        ),
        ['https://svn.example.com/src'],
      );
    });

    test('目标 SVN URL 入列', () {
      expect(
        collectAuthGuideUrls(
          sourceUrl: 'svn://host/src',
          targetUrl: 'svn://host/target',
        ),
        ['svn://host/src', 'svn://host/target'],
      );
    });
  });

  group('formatSvnAuthTerminalCommand', () {
    test('生成 svn info 命令', () {
      expect(
        formatSvnAuthTerminalCommand(
          svnExecutable: '/opt/homebrew/bin/svn',
          url: 'https://svn.example.com/repo',
        ),
        '/opt/homebrew/bin/svn info https://svn.example.com/repo',
      );
    });
  });

  group('isSvnAuthRequiredError', () {
    test('SvnAuthRequiredException', () {
      expect(
        isSvnAuthRequiredError(
          const SvnAuthRequiredException(url: 'https://x'),
        ),
        isTrue,
      );
    });

    test('SvnException + needsAuth', () {
      expect(
        isSvnAuthRequiredError(
          SvnException('x', output: 'Authorization failed'),
        ),
        isTrue,
      );
    });

    test('其它异常', () {
      expect(isSvnAuthRequiredError(Exception('x')), isFalse);
    });
  });

  group('normalizeSvnAuthError', () {
    test('SvnException needsAuth → SvnAuthRequiredException', () {
      final normalized = normalizeSvnAuthError(
        SvnException('fail', output: 'no more credentials'),
        url: 'https://svn.example.com',
      );
      expect(normalized, isA<SvnAuthRequiredException>());
      expect((normalized as SvnAuthRequiredException).url,
          'https://svn.example.com');
    });
  });

  group('buildSvnAuthAddDialogText', () {
    test('包含推荐路径、终端命令与 macOS 钥匙串说明', () {
      final text = buildSvnAuthAddDialogText(
        operatingSystem: 'macos',
        urls: const ['https://svn.example.com/src'],
        terminalCommands: const ['svn info https://svn.example.com/src'],
      );
      expect(text, contains('【推荐】'));
      expect(text, contains('本应用不保存 SVN 密码'));
      expect(text, contains('svn info https://svn.example.com/src'));
      expect(text, contains('钥匙串'));
    });

    test('无 URL 时提示先配置', () {
      final text = buildSvnAuthAddDialogText(
        operatingSystem: 'linux',
        urls: const [],
        terminalCommands: const [],
      );
      expect(text, contains('请先在主界面配置源 URL'));
    });
  });

  group('buildSvnAuthCredentialsHintText', () {
    test('说明仅按需填写且不落盘', () {
      final text = buildSvnAuthCredentialsHintText();
      expect(text, contains('仅当您希望用账号密码登录时填写'));
      expect(text, contains('关闭对话框后即丢弃'));
    });
  });

  group('validateSvnAuthCredentialsInput', () {
    test('空用户名 → 错误', () {
      expect(
        validateSvnAuthCredentialsInput(username: '  ', password: 'secret'),
        '请输入用户名',
      );
    });

    test('空密码 → 错误', () {
      expect(
        validateSvnAuthCredentialsInput(username: 'alice', password: ''),
        '请输入密码',
      );
    });

    test('有效输入 → null', () {
      expect(
        validateSvnAuthCredentialsInput(username: 'alice', password: 'secret'),
        isNull,
      );
    });
  });

  group('sanitizeSvnAuthErrorMessage', () {
    test('移除输出中的密码片段', () {
      expect(
        sanitizeSvnAuthErrorMessage(
          'failed with secret123 in args',
          password: 'secret123',
        ),
        'failed with **** in args',
      );
    });

    test('无密码时不改动', () {
      expect(
        sanitizeSvnAuthErrorMessage('plain error'),
        'plain error',
      );
    });
  });

  group('SvnAuthGateService.resolveAuthUiState', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('svn_auth_gate_test_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('有 auth 缓存文件 → hasAuth', () async {
      final configDir = Directory(p.join(tempRoot.path, '.subversion'));
      final simpleDir =
          Directory(p.join(configDir.path, 'auth', 'svn.simple'));
      await simpleDir.create(recursive: true);
      await File(p.join(simpleDir.path, 'hash1')).writeAsString('cred');

      final gate = SvnAuthGateService();
      gate.operatingSystem = 'macos';
      gate.homeDir = tempRoot.path;
      gate.clearService = SvnAuthClearService()
        ..operatingSystem = 'macos'
        ..homeDir = tempRoot.path;

      final state = await gate.resolveAuthUiState();
      expect(state, SvnAuthUiState.hasAuth);
    });

    test('无缓存且无 URL → needsAuth', () async {
      final gate = SvnAuthGateService();
      gate.operatingSystem = 'macos';
      gate.homeDir = tempRoot.path;
      gate.clearService = SvnAuthClearService()
        ..operatingSystem = 'macos'
        ..homeDir = tempRoot.path;

      final state = await gate.resolveAuthUiState();
      expect(state, SvnAuthUiState.needsAuth);
    });
  });

  group('SvnAuthGateService.ensureAuthForUrl', () {
    test('本地路径不拦截', () async {
      final gate = SvnAuthGateService();
      await expectLater(
        gate.ensureAuthForUrl('/tmp/working-copy'),
        completes,
      );
    });
  });
}
