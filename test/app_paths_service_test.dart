import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:svn_auto_merge/services/app_paths_service.dart';

void main() {
  // 基础 base dir：Unix 风格绝对路径；resolve* 函数走 package:path，
  // 在 Windows 上会自动用 '\\' 拼接，所以断言里也用 path.join 构造期望值
  // 而不是硬编码 '/'，避免 Windows CI 红。
  const baseDir = '/Users/me/Library/Application Support/SvnAutoMerge';

  group('resolveConfigDir (顶层纯函数)', () {
    test('正常路径：<appSupportDir>/config', () {
      expect(resolveConfigDir(baseDir), p.join(baseDir, 'config'));
    });

    test('子目录名是 "config"（小写、单数）——锁定布局契约', () {
      // 任何 PR 把 'config' 改成 'Config' / 'configs' / 'configuration'
      // 都会让用户的历史配置文件凭空消失。
      final result = resolveConfigDir(baseDir);
      expect(result.endsWith(p.join('', 'config')) || result.endsWith('config'),
          isTrue);
      expect(result, isNot(contains('Config')));
      expect(result, isNot(contains('configs')));
      expect(result, isNot(contains('svn_config')),
          reason: 'svn_config 是旧目录名残留；当前配置统一放在 config/source_urls.json');
    });

    test('空字符串 base dir → 仅返回 "config"（不抛异常，path.join 行为）', () {
      // 边界：path.join('', 'config') == 'config'。锁定不做特殊兜底。
      expect(resolveConfigDir(''), 'config');
    });

    test('base dir 末尾有斜杠 → path.join 自动归一化', () {
      // path.join 会处理重复分隔符；锁定不需要 caller 自己 trim。
      expect(resolveConfigDir('$baseDir/'), p.join(baseDir, 'config'));
    });
  });

  group('resolveLogsDir (顶层纯函数)', () {
    test('正常路径：<appSupportDir>/logs', () {
      expect(resolveLogsDir(baseDir), p.join(baseDir, 'logs'));
    });

    test('子目录名是 "logs"（复数）——不是 "log"', () {
      // 锁定 logs vs log 这条字面量；改一个字母就能让历史日志全找不到。
      expect(resolveLogsDir(baseDir).endsWith('logs'), isTrue);
      expect(resolveLogsDir(baseDir).endsWith('log'), isFalse);
    });
  });

  group('resolveCacheDir (顶层纯函数)', () {
    test('正常路径：<dataDir>/cache', () {
      expect(resolveCacheDir(baseDir), p.join(baseDir, 'cache'));
    });

    test('子目录名是 "cache"（小写）', () {
      expect(resolveCacheDir(baseDir).endsWith('cache'), isTrue);
      expect(resolveCacheDir(baseDir), isNot(contains('Cache')));
    });
  });

  group('resolveMergeInfoCacheDir (顶层纯函数)', () {
    test('正常路径：<dataDir>/mergeinfo_cache', () {
      expect(
        resolveMergeInfoCacheDir(baseDir),
        p.join(baseDir, 'mergeinfo_cache'),
      );
    });

    test('子目录名是 "mergeinfo_cache"（snake_case 两段）——锁定 Round 48 教训', () {
      // **不是** 'merge_info_cache'（三段下划线）也**不是** 'mergeinfoCache'（camelCase）。
      // 人脑会自动等价 snake_case 各种变体，但 path.join 严格按字面拼接。
      final result = resolveMergeInfoCacheDir(baseDir);
      expect(result.endsWith('mergeinfo_cache'), isTrue);
      expect(result, isNot(contains('merge_info_cache')));
      expect(result, isNot(contains('mergeinfoCache')));
      expect(result, isNot(contains('mergeInfoCache')));
    });
  });

  group('resolveQueueFilePath (顶层纯函数)', () {
    test('正常路径：<dataDir>/queue.json', () {
      expect(resolveQueueFilePath(baseDir), p.join(baseDir, 'queue.json'));
    });

    test('文件名是 "queue.json"（含 .json 扩展名）', () {
      // 锁定它**是文件而非目录**——caller getQueueFilePath() 不会去 mkdir 这个路径。
      expect(resolveQueueFilePath(baseDir).endsWith('.json'), isTrue);
      expect(resolveQueueFilePath(baseDir).endsWith('queue.json'), isTrue);
    });

    test('不是目录路径：不以分隔符结尾', () {
      // path.join 不会给文件路径补尾随分隔符——锁定这点。
      expect(resolveQueueFilePath(baseDir).endsWith('/'), isFalse);
      expect(resolveQueueFilePath(baseDir).endsWith(r'\'), isFalse);
    });
  });

  group('resolveSourceUrlsConfigPath (顶层纯函数)', () {
    test('正常路径：<configDir>/source_urls.json', () {
      const configDir = '/Users/me/Library/Application Support/SvnAutoMerge/config';
      expect(
        resolveSourceUrlsConfigPath(configDir),
        p.join(configDir, 'source_urls.json'),
      );
    });

    test('文件名是 "source_urls.json"（snake_case 两段 + .json）', () {
      const configDir = '/x';
      final result = resolveSourceUrlsConfigPath(configDir);
      expect(result.endsWith('source_urls.json'), isTrue);
      expect(result, isNot(contains('sourceUrls')));
      expect(result, isNot(contains('source-urls')));
    });

    test('参数命名锁定：接收 configDir 而非 appSupportDir', () {
      // 强制 caller 先经过 resolveConfigDir 一层——单测没法直接断言"参数名"，
      // 但通过组合调用验证两层嵌套是预期行为。
      final configDir = resolveConfigDir(baseDir);
      final fullPath = resolveSourceUrlsConfigPath(configDir);
      expect(fullPath, p.join(baseDir, 'config', 'source_urls.json'));
    });
  });

  group('resolveLogFileCachePath (顶层纯函数)', () {
    test('正常路径：<cacheDir>/log_files_cache.json', () {
      const cacheDir = '/Users/me/Library/Application Support/SvnAutoMerge/cache';
      expect(
        resolveLogFileCachePath(cacheDir),
        p.join(cacheDir, 'log_files_cache.json'),
      );
    });

    test('文件名是 "log_files_cache.json"（log_files 两段 snake_case）', () {
      // **复数 files** 不是 file；snake_case 不是 camelCase。
      const cacheDir = '/x';
      final result = resolveLogFileCachePath(cacheDir);
      expect(result.endsWith('log_files_cache.json'), isTrue);
      expect(result, isNot(contains('logFilesCache')));
      expect(result, isNot(contains('log_file_cache'))); // 单数 file
    });

    test('参数命名锁定：接收 cacheDir 而非 dataDir', () {
      // 同 source_urls.json：强制 caller 先经过 resolveCacheDir。
      final cacheDir = resolveCacheDir(baseDir);
      final fullPath = resolveLogFileCachePath(cacheDir);
      expect(fullPath, p.join(baseDir, 'cache', 'log_files_cache.json'));
    });
  });

  group('完整目录布局组合 (锁定文档注释里的 5 行表格)', () {
    // 这组测试把 resolve* 函数链起来，验证 AppPathsService 的目录布局承诺。
    // 任何中间一层字符串改名，这里都会爆。

    test('布局 1：<app-support>/config/source_urls.json', () {
      final configDir = resolveConfigDir(baseDir);
      final filePath = resolveSourceUrlsConfigPath(configDir);
      expect(filePath, p.join(baseDir, 'config', 'source_urls.json'));
    });

    test('布局 2：<app-support>/logs/', () {
      expect(resolveLogsDir(baseDir), p.join(baseDir, 'logs'));
    });

    test('布局 3：<app-support>/queue.json', () {
      expect(resolveQueueFilePath(baseDir), p.join(baseDir, 'queue.json'));
    });

    test('布局 4：<app-support>/cache/', () {
      expect(resolveCacheDir(baseDir), p.join(baseDir, 'cache'));
    });

    test('布局 5：<app-support>/mergeinfo_cache/', () {
      expect(
        resolveMergeInfoCacheDir(baseDir),
        p.join(baseDir, 'mergeinfo_cache'),
      );
    });

    test('布局 6（衍生）：<app-support>/cache/log_files_cache.json', () {
      // 文档注释没明确列出，但 getLogFileCachePath 的实现承诺是 cache/ 下的文件。
      final cacheDir = resolveCacheDir(baseDir);
      final filePath = resolveLogFileCachePath(cacheDir);
      expect(filePath, p.join(baseDir, 'cache', 'log_files_cache.json'));
    });

    test('两层嵌套：source_urls.json 必须在 config/ 下而非 app-support/ 直接下', () {
      // 锁定"两层目录"——避免有人手抖直接传 baseDir 进 resolveSourceUrlsConfigPath
      // 导致文件被写到错误层级。
      final wrongPath =
          resolveSourceUrlsConfigPath(baseDir); // 故意不经过 resolveConfigDir
      // 这里依然会"工作"（path.join 不会拒绝），但路径会错——
      // 单测断言它**不等于**正确路径。
      final correctPath =
          resolveSourceUrlsConfigPath(resolveConfigDir(baseDir));
      expect(wrongPath, isNot(equals(correctPath)));
      expect(wrongPath, p.join(baseDir, 'source_urls.json'));
      expect(correctPath, p.join(baseDir, 'config', 'source_urls.json'));
    });

    test('两层嵌套：log_files_cache.json 必须在 cache/ 下', () {
      final wrongPath = resolveLogFileCachePath(baseDir); // 故意不经过 resolveCacheDir
      final correctPath = resolveLogFileCachePath(resolveCacheDir(baseDir));
      expect(wrongPath, isNot(equals(correctPath)));
    });
  });
}
