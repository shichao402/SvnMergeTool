/// 把"应用支持目录布局"集中表达成 7 个纯字符串函数——**应用目录布局契约**。
///
/// 这些函数不做 IO（不 `mkdir`、不 `exists`、不抛异常），只负责把 base 路径与子目录
/// / 子文件名拼接成完整路径。把它们提到顶层独立测试，是为了：
/// 1. **锁定目录布局**：当前布局来自 [AppPathsService] 类文档注释里的 5 行表格——
///    `config/`、`logs/`、`queue.json`、`cache/`、`mergeinfo_cache/`、
///    `cache/log_files_cache.json`、`config/source_urls.json`。这些字符串散落在 7
///    个 IO 方法里以裸字面量出现，**任何"看着不顺手"的字符串改名都会改变用户的存储
///    位置**——产生"用户启动新版本后，历史配置/缓存全部凭空消失"的事故。集中到顶层
///    后，单测显式断言每条字符串子段，让 PR review 一眼看穿任何字符串改动。
/// 2. **可测试**：原 `getXxxDir` 方法依赖 `path_provider` 插件——单测里 mock 平台
///    通道才能跑。把字符串拼接拆出来后，单测**完全不依赖 Flutter 平台**：传入虚构
///    base dir、断言输出路径，纯字符串 in、纯字符串 out。
/// 3. **跨平台一致**：所有函数走 `package:path` 的 `path.join`，自动处理 `'/'`
///    （Unix/macOS）vs `'\\'`（Windows）分隔符——**故意不**在本服务层做手写
///    分隔符拼接，避免引入平台分叉 bug。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 拼接"配置目录"的完整路径：`<appSupportDir>/config`。
///
/// **核心契约**：
/// - 子目录名 **必须**是 `'config'`（小写）；如有人改成 `'Config'` 或 `'configs'`
///   单测立刻爆——这是**用户配置文件存储位置**的关键不变量。
/// - 仅做拼接，**不**创建目录、**不**校验存在性——IO 由 caller 显式做。
/// - **不**对 `appSupportDir` 做 trim 或合法性校验：上游 `path_provider` 返回的
///   永远是合法绝对路径；本层不重复校验。
@visibleForTesting
String resolveConfigDir(String appSupportDir) =>
    path.join(appSupportDir, 'config');

/// 拼接"日志目录"的完整路径：`<appSupportDir>/logs`。
///
/// **核心契约**：
/// - 子目录名是 `'logs'`（复数，小写）；不是 `'log'`。
/// - **不**做 IO；纯字符串拼接。
@visibleForTesting
String resolveLogsDir(String appSupportDir) =>
    path.join(appSupportDir, 'logs');

/// 拼接"缓存目录"的完整路径：`<dataDir>/cache`。
///
/// **核心契约**：
/// - 子目录名是 `'cache'`（小写）。
/// - 注意 `dataDir` 在当前实现里**等价于** `appSupportDir`（见
///   `AppPathsService.getDataDir`，是 `getAppSupportDir` 的薄包装）——但语义上"数据
///   目录"和"应用支持目录"是两个层面：本函数接收 `dataDir` 而非 `appSupportDir`，
///   **保留未来分叉的余地**（若日后把数据目录搬到 `<appSupport>/data`，本函数无需
///   修改）。
/// - **不**做 IO；纯字符串拼接。
@visibleForTesting
String resolveCacheDir(String dataDir) => path.join(dataDir, 'cache');

/// 拼接"mergeinfo 缓存目录"的完整路径：`<dataDir>/mergeinfo_cache`。
///
/// **核心契约**：
/// - 子目录名 **必须**是 `'mergeinfo_cache'`（snake_case，单词间下划线）；
///   **不是** `'merge_info_cache'`（三段）也**不是** `'mergeinfoCache'`
///   （camelCase）。这是 Round 48 教训的延续——人脑会自动等价 snake_case
///   各种变体，但 `path.join` 不会，单测显式锁定字面量。
/// - **不**做 IO；纯字符串拼接。
@visibleForTesting
String resolveMergeInfoCacheDir(String dataDir) =>
    path.join(dataDir, 'mergeinfo_cache');

/// 拼接"任务队列文件"的完整路径：`<dataDir>/queue.json`。
///
/// **核心契约**：
/// - 文件名 **必须**是 `'queue.json'`（小写 + .json 扩展名）。
/// - **是文件而非目录**：caller `getQueueFilePath()` 不会去 mkdir 这个路径——
///   单测断言路径以 `.json` 结尾以保护这个语义。
/// - **不**做 IO；纯字符串拼接。
@visibleForTesting
String resolveQueueFilePath(String dataDir) =>
    path.join(dataDir, 'queue.json');

/// 拼接"源 URL 历史配置文件"的完整路径：`<configDir>/source_urls.json`。
///
/// **核心契约**：
/// - 文件名 **必须**是 `'source_urls.json'`（snake_case + .json 扩展名）。
/// - 关键参数命名：接收 `configDir` 而非 `appSupportDir`——**强制 caller 先经过
///   `resolveConfigDir` 一层**，避免有人手抖直接传 `appSupportDir` 进来导致文件被
///   写到错误层级（`<appSupport>/source_urls.json` 而不是
///   `<appSupport>/config/source_urls.json`）。
/// - **不**做 IO；纯字符串拼接。
@visibleForTesting
String resolveSourceUrlsConfigPath(String configDir) =>
    path.join(configDir, 'source_urls.json');

/// 拼接"日志文件元信息缓存"的完整路径：`<cacheDir>/log_files_cache.json`。
///
/// **核心契约**：
/// - 文件名 **必须**是 `'log_files_cache.json'`（snake_case，复数 `files`，
///   .json 扩展名）。
/// - 关键参数命名：接收 `cacheDir` 而非 `dataDir`——同 [resolveSourceUrlsConfigPath]
///   的理由，**强制 caller 先经过 `resolveCacheDir`**，把"两层目录嵌套"的语义钉死
///   在调用栈上而不是依赖单个字符串拼接的运气。
/// - **不**做 IO；纯字符串拼接。
@visibleForTesting
String resolveLogFileCachePath(String cacheDir) =>
    path.join(cacheDir, 'log_files_cache.json');

/// 应用运行时目录服务
///
/// 当前统一目录结构：
/// - <app-support>/config/source_urls.json
/// - <app-support>/logs/
/// - <app-support>/queue.json
/// - <app-support>/cache/
/// - <app-support>/mergeinfo_cache/
class AppPathsService {
  static final AppPathsService _instance = AppPathsService._internal();
  factory AppPathsService() => _instance;
  AppPathsService._internal();

  String? _appSupportDir;

  Future<String> getAppSupportDir() async {
    if (_appSupportDir != null) {
      return _appSupportDir!;
    }

    final appDir = await getApplicationSupportDirectory();
    _appSupportDir = await _ensureDir(appDir.path);
    return _appSupportDir!;
  }

  Future<String> getConfigDir() async {
    final appSupportDir = await getAppSupportDir();
    return _ensureDir(resolveConfigDir(appSupportDir));
  }

  Future<String> getLogsDir() async {
    final appSupportDir = await getAppSupportDir();
    return _ensureDir(resolveLogsDir(appSupportDir));
  }

  Future<String> getDataDir() async {
    return getAppSupportDir();
  }

  Future<String> getCacheDir() async {
    final dataDir = await getDataDir();
    return _ensureDir(resolveCacheDir(dataDir));
  }

  Future<String> getMergeInfoCacheDir() async {
    final dataDir = await getDataDir();
    return _ensureDir(resolveMergeInfoCacheDir(dataDir));
  }

  Future<String> getQueueFilePath() async {
    final dataDir = await getDataDir();
    return resolveQueueFilePath(dataDir);
  }

  Future<String> getSourceUrlsConfigPath() async {
    final configDir = await getConfigDir();
    return resolveSourceUrlsConfigPath(configDir);
  }

  Future<String> getLogFileCachePath() async {
    final cacheDir = await getCacheDir();
    return resolveLogFileCachePath(cacheDir);
  }

  Future<String> _ensureDir(String dirPath) async {
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }
}
