import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:svn_auto_merge/services/logger_service.dart';
import 'package:svn_auto_merge/services/svn_auth_clear_service.dart';

void main() {
  setUpAll(() {
    // clearAuthCache 会写 AppLogger.credential 日志；单测环境无 Flutter binding 时会挂死。
    logger.enabled = false;
  });
  group('resolveSubversionConfigDir', () {
    test('macOS 默认 → ~/.subversion', () {
      expect(
        resolveSubversionConfigDir(
          operatingSystem: 'macos',
          homeDir: '/Users/me',
        ),
        p.join('/Users/me', '.subversion'),
      );
    });

    test('linux 默认 → ~/.subversion', () {
      expect(
        resolveSubversionConfigDir(
          operatingSystem: 'linux',
          homeDir: '/home/me',
        ),
        p.join('/home/me', '.subversion'),
      );
    });

    test('windows 默认 → %APPDATA%\\Subversion', () {
      expect(
        resolveSubversionConfigDir(
          operatingSystem: 'windows',
          appDataDir: r'C:\Users\me\AppData\Roaming',
        ),
        p.join(r'C:\Users\me\AppData\Roaming', 'Subversion'),
      );
    });

    test('SVN_CONFIG_DIR 环境变量优先', () {
      expect(
        resolveSubversionConfigDir(
          operatingSystem: 'macos',
          homeDir: '/Users/me',
          svnConfigDirEnv: '/custom/svn-config',
        ),
        '/custom/svn-config',
      );
    });

    test('windows 缺少 APPDATA → null', () {
      expect(
        resolveSubversionConfigDir(
          operatingSystem: 'windows',
          appDataDir: null,
        ),
        isNull,
      );
    });

    test('非 windows 缺少 HOME → null', () {
      expect(
        resolveSubversionConfigDir(
          operatingSystem: 'macos',
          homeDir: '',
        ),
        isNull,
      );
    });
  });

  group('resolveSubversionAuthDir', () {
    test('在 config 目录下追加 auth', () {
      expect(
        resolveSubversionAuthDir(
          operatingSystem: 'macos',
          homeDir: '/Users/me',
        ),
        p.join('/Users/me', '.subversion', 'auth'),
      );
    });
  });

  group('describeSvnAuthClearScope', () {
    test('包含三类 auth 子目录说明', () {
      final text = describeSvnAuthClearScope(operatingSystem: 'macos');
      expect(text, contains('svn.simple'));
      expect(text, contains('svn.username'));
      expect(text, contains('svn.ssl.server-trust'));
      expect(text, contains('本应用自身不保存 SVN 凭据'));
    });

    test('macOS 提及钥匙串且不清理', () {
      final text = describeSvnAuthClearScope(operatingSystem: 'macos');
      expect(text, contains('钥匙串'));
      expect(text, contains('不清理'));
    });

    test('windows 提及 APPDATA', () {
      expect(
        describeSvnAuthClearScope(operatingSystem: 'windows'),
        contains('APPDATA'),
      );
    });
  });

  group('describeSvnAuthClearLocalCacheNote', () {
    test('说明 SQLite 缓存与远端鉴权分离', () {
      final text = describeSvnAuthClearLocalCacheNote();
      expect(text, contains('SQLite'));
      expect(text, contains('同步最新'));
      expect(text, contains('加载更多'));
    });
  });

  group('formatSvnAuthClearSnackBar', () {
    test('有凭据时包含文件数与缓存提示', () {
      const result = SvnAuthClearResult(
        authDirPath: '/tmp/auth',
        authDirExisted: true,
        deletedFileCount: 3,
        deletedDirCount: 1,
        clearedCategories: ['svn.simple'],
      );
      expect(
        formatSvnAuthClearSnackBar(result),
        '已清理 3 个鉴权文件。本地已缓存的日志仍会显示；下次访问远端 SVN 时才可能需要重新鉴权。',
      );
    });

    test('无凭据时仍提示缓存行为', () {
      const result = SvnAuthClearResult(
        authDirPath: '/tmp/auth',
        authDirExisted: false,
        deletedFileCount: 0,
        deletedDirCount: 0,
        clearedCategories: ['svn.simple'],
      );
      expect(
        formatSvnAuthClearSnackBar(result),
        contains('本地已缓存的日志仍会显示'),
      );
    });
  });

  group('buildSvnAuthClearDialogText', () {
    test('包含清理目录与 SVN_CONFIG_DIR 提示', () {
      final text = buildSvnAuthClearDialogText(
        operatingSystem: 'macos',
        authDirPath: '/Users/me/.subversion/auth',
        svnConfigDirEnv: '/custom/svn',
      );
      expect(text, contains('/Users/me/.subversion/auth'));
      expect(text, contains('SVN_CONFIG_DIR=/custom/svn'));
      expect(text, contains('SQLite'));
      expect(text, contains('同步最新'));
    });
  });

  group('clearSubversionAuthDirectory', () {
    late Directory tempRoot;
    late Directory authDir;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('svn_auth_clear_test_');
      authDir = Directory(p.join(tempRoot.path, 'auth'));
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('清理已有 svn.simple 凭据文件', () async {
      final simpleDir = Directory(p.join(authDir.path, 'svn.simple'));
      await simpleDir.create(recursive: true);
      final credFile = File(p.join(simpleDir.path, 'abc123'));
      await credFile.writeAsString('cached credential');

      final result = await clearSubversionAuthDirectory(authDir);

      expect(result.authDirExisted, isTrue);
      expect(result.deletedFileCount, 1);
      expect(result.clearedCategories, contains('svn.simple'));
      expect(await credFile.exists(), isFalse);
      expect(await Directory(p.join(authDir.path, 'svn.simple')).exists(),
          isTrue);
    });

    test('auth 目录不存在时创建并初始化标准子目录', () async {
      final result = await clearSubversionAuthDirectory(authDir);

      expect(result.authDirExisted, isFalse);
      expect(result.deletedFileCount, 0);
      expect(await authDir.exists(), isTrue);
      for (final name in kSubversionAuthSubdirs) {
        expect(await Directory(p.join(authDir.path, name)).exists(), isTrue);
      }
      expect(result.clearedCategories, containsAll(kSubversionAuthSubdirs));
    });

    test('空 auth 目录 → hadEntries 为 false', () async {
      await authDir.create(recursive: true);
      final result = await clearSubversionAuthDirectory(authDir);
      expect(result.hadEntries, isFalse);
    });
  });

  group('SvnAuthClearService', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('svn_auth_svc_test_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('clearAuthCache 使用注入的环境解析路径并清理', () async {
      final configDir = Directory(p.join(tempRoot.path, '.subversion'));
      final simpleDir =
          Directory(p.join(configDir.path, 'auth', 'svn.simple'));
      await simpleDir.create(recursive: true);
      await File(p.join(simpleDir.path, 'hash1'))
          .writeAsString('user:pass');

      final service = SvnAuthClearService();
      service.operatingSystem = 'macos';
      service.homeDir = tempRoot.path;
      service.svnConfigDirEnv = null;

      final result = await service.clearAuthCache();

      expect(result.deletedFileCount, 1);
      expect(
        result.authDirPath,
        p.join(tempRoot.path, '.subversion', 'auth'),
      );
      expect(
        await File(p.join(simpleDir.path, 'hash1')).exists(),
        isFalse,
      );
    });

    test('无法解析路径时抛出 StateError', () async {
      final service = SvnAuthClearService();
      service.operatingSystem = 'windows';
      service.appDataDir = null;

      expect(service.clearAuthCache(), throwsA(isA<StateError>()));
    });
  });
}
