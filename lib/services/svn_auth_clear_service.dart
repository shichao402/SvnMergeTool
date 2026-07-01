/// SVN 鉴权缓存清理服务（单点实现）。
///
/// 本应用不自行存储 SVN 用户名/密码（见 [SvnService] 文档），所有鉴权依赖
/// Subversion 客户端及其系统凭据存储：
///
/// - **文件缓存（所有平台）**：`<subversion-config>/auth/` 下的
///   `svn.simple/`（用户名+密码）、`svn.username/`（记住的用户名）、
///   `svn.ssl.server-trust/`（SSL 服务器信任）。
/// - **macOS**：部分 SVN 构建还会把密码写入 Keychain；清理文件缓存后
///   Subversion 不再复用已缓存凭据（`--non-interactive` 会失败并提示重新鉴权）。
///   孤立的 Keychain 项不会自动重新登录。
/// - **Windows**：命令行 SVN 默认使用 `%APPDATA%\Subversion\auth\`；
///   部分发行版可能额外使用 Windows 凭据管理器，本服务以 Subversion auth
///   目录为主清理范围。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'logger_service.dart';

/// Subversion 鉴权缓存子目录名（与 SVN 上游布局一致）。
const List<String> kSubversionAuthSubdirs = [
  'svn.simple',
  'svn.username',
  'svn.ssl.server-trust',
];

/// 解析 Subversion 配置根目录（不含 `auth`）。
///
/// 优先级：
/// 1. 环境变量 `SVN_CONFIG_DIR`（非空）
/// 2. Windows → `%APPDATA%\Subversion`
/// 3. 其它 → `$HOME/.subversion`
@visibleForTesting
String? resolveSubversionConfigDir({
  required String operatingSystem,
  String? homeDir,
  String? appDataDir,
  String? svnConfigDirEnv,
}) {
  final envOverride = svnConfigDirEnv?.trim();
  if (envOverride != null && envOverride.isNotEmpty) {
    return envOverride;
  }
  if (operatingSystem == 'windows') {
    final appData = appDataDir?.trim();
    if (appData == null || appData.isEmpty) {
      return null;
    }
    return p.join(appData, 'Subversion');
  }
  final home = homeDir?.trim();
  if (home == null || home.isEmpty) {
    return null;
  }
  return p.join(home, '.subversion');
}

/// 解析 Subversion `auth` 目录完整路径。
@visibleForTesting
String? resolveSubversionAuthDir({
  required String operatingSystem,
  String? homeDir,
  String? appDataDir,
  String? svnConfigDirEnv,
}) {
  final configDir = resolveSubversionConfigDir(
    operatingSystem: operatingSystem,
    homeDir: homeDir,
    appDataDir: appDataDir,
    svnConfigDirEnv: svnConfigDirEnv,
  );
  if (configDir == null) {
    return null;
  }
  return p.join(configDir, 'auth');
}

/// 清理范围说明（设置页展示用）。
@visibleForTesting
String describeSvnAuthClearScope({required String operatingSystem}) {
  final platformNote = switch (operatingSystem) {
    'macos' =>
      'macOS 上部分 SVN 构建还会把密码写入系统钥匙串；本操作不清理钥匙串条目。',
    'windows' =>
      'Windows 上默认清理 %APPDATA%\\Subversion\\auth\\ 下的 Subversion 鉴权文件；'
      '部分发行版可能额外使用 Windows 凭据管理器，本操作不清理该处。',
    _ =>
      '清理 ~/.subversion/auth/ 下的 Subversion 鉴权文件。',
  };
  return '将删除 Subversion auth 缓存（svn.simple 用户名密码、svn.username 记住的用户名、'
      'svn.ssl.server-trust SSL 信任记录）。本应用自身不保存 SVN 凭据。$platformNote';
}

/// 清理鉴权对日志浏览的影响说明（设置页展示用）。
///
/// 与 [describeSvnAuthClearScope] 分离：前者描述「删什么」，本函数描述「不删什么 /
/// 用户仍能看到什么」——避免把「清理凭据」与「清理日志缓存」混为一谈。
@visibleForTesting
String describeSvnAuthClearLocalCacheNote() {
  return '不会清除本应用已缓存的 SVN 日志（SQLite）。已加载的日志列表仍会显示；'
      '只有下次向远端执行 svn 命令（如主界面「同步最新」「加载更多」）时才可能需要重新鉴权。';
}

/// 验证清理是否生效的操作提示（设置页展示用）。
@visibleForTesting
String describeSvnAuthClearVerifyHint() {
  return '若要验证清理是否生效，可回到主界面点击「同步最新」或「加载更多」，'
      '观察是否出现鉴权失败；若仓库匿名可读或系统钥匙串仍有效，远端访问也可能无需重新输入。';
}

/// 组装设置页「清理 SVN 鉴权」确认对话框正文。
@visibleForTesting
String buildSvnAuthClearDialogText({
  required String operatingSystem,
  String? authDirPath,
  String? svnConfigDirEnv,
}) {
  final buffer = StringBuffer(describeSvnAuthClearScope(operatingSystem: operatingSystem));
  if (authDirPath != null && authDirPath.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('将清理目录：${authDirPath.trim()}');
    final envOverride = svnConfigDirEnv?.trim();
    if (envOverride != null && envOverride.isNotEmpty) {
      buffer.writeln('（当前进程 SVN_CONFIG_DIR=$envOverride）');
    }
  }
  buffer
    ..writeln()
    ..writeln(describeSvnAuthClearLocalCacheNote())
    ..writeln()
    ..write(describeSvnAuthClearVerifyHint());
  return buffer.toString();
}

/// 清理完成后的 SnackBar 文案。
@visibleForTesting
String formatSvnAuthClearSnackBar(SvnAuthClearResult result) {
  final summary = result.hadEntries
      ? '已清理 ${result.deletedFileCount} 个鉴权文件'
      : '未发现已缓存的鉴权文件（目录已重置）';
  return '$summary。本地已缓存的日志仍会显示；下次访问远端 SVN 时才可能需要重新鉴权。';
}

/// 单次清理结果。
class SvnAuthClearResult {
  final String? authDirPath;
  final bool authDirExisted;
  final int deletedFileCount;
  final int deletedDirCount;
  final List<String> clearedCategories;

  const SvnAuthClearResult({
    required this.authDirPath,
    required this.authDirExisted,
    required this.deletedFileCount,
    required this.deletedDirCount,
    required this.clearedCategories,
  });

  bool get hadEntries => deletedFileCount > 0 || deletedDirCount > 0;
}

/// 统计 [authDir] 下待清理条目数（不修改磁盘）。
@visibleForTesting
Future<({int fileCount, int dirCount, List<String> categories})>
    countSubversionAuthEntries(Directory authDir) async {
  var fileCount = 0;
  var dirCount = 0;
  final categories = <String>[];

  if (!await authDir.exists()) {
    return (fileCount: 0, dirCount: 0, categories: categories);
  }

  await for (final entity in authDir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      fileCount++;
    } else if (entity is Directory) {
      if (entity.path != authDir.path) {
        dirCount++;
      }
    }
  }

  for (final name in kSubversionAuthSubdirs) {
    final sub = Directory(p.join(authDir.path, name));
    if (await sub.exists()) {
      categories.add(name);
    }
  }

  return (fileCount: fileCount, dirCount: dirCount, categories: categories);
}

/// 删除 [authDir] 下所有鉴权缓存文件与子目录，并重建空的标准子目录。
@visibleForTesting
Future<SvnAuthClearResult> clearSubversionAuthDirectory(Directory authDir) async {
  final existed = await authDir.exists();
  final counts = await countSubversionAuthEntries(authDir);
  final clearedCategories = List<String>.from(counts.categories);

  if (existed) {
    await for (final entity in authDir.list(followLinks: false)) {
      if (entity is File) {
        await entity.delete();
      } else if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
  } else {
    await authDir.create(recursive: true);
  }

  for (final name in kSubversionAuthSubdirs) {
    final sub = Directory(p.join(authDir.path, name));
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    if (!clearedCategories.contains(name)) {
      clearedCategories.add(name);
    }
  }

  return SvnAuthClearResult(
    authDirPath: authDir.path,
    authDirExisted: existed,
    deletedFileCount: counts.fileCount,
    deletedDirCount: counts.dirCount,
    clearedCategories: clearedCategories,
  );
}

/// SVN 鉴权缓存清理（IO 入口，单例）。
class SvnAuthClearService {
  static final SvnAuthClearService _instance = SvnAuthClearService._internal();
  factory SvnAuthClearService() => _instance;
  SvnAuthClearService._internal();

  @visibleForTesting
  String operatingSystem = Platform.operatingSystem;

  @visibleForTesting
  String? homeDir = Platform.environment['HOME'];

  @visibleForTesting
  String? appDataDir = Platform.environment['APPDATA'];

  @visibleForTesting
  String? svnConfigDirEnv = Platform.environment['SVN_CONFIG_DIR'];

  /// 清理当前用户 Subversion 鉴权缓存。
  Future<SvnAuthClearResult> clearAuthCache() async {
    final authPath = resolveSubversionAuthDir(
      operatingSystem: operatingSystem,
      homeDir: homeDir,
      appDataDir: appDataDir,
      svnConfigDirEnv: svnConfigDirEnv,
    );

    if (authPath == null) {
      const message = '无法解析 Subversion auth 目录（缺少 HOME 或 APPDATA）';
      AppLogger.credential.error(message);
      throw StateError(message);
    }

    AppLogger.credential.info('开始清理 SVN 鉴权缓存: $authPath');

    final result = await clearSubversionAuthDirectory(Directory(authPath));

    AppLogger.credential.info(
      'SVN 鉴权缓存清理完成: 目录存在=${result.authDirExisted}, '
      '删除文件=${result.deletedFileCount}, 删除子目录=${result.deletedDirCount}, '
      '范围=${result.clearedCategories.join(', ')}',
    );

    return result;
  }
}
