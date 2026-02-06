/// 脚本路径服务
///
/// 管理脚本目录和路径转换，支持相对路径以便于分享。
///
/// 支持的相对路径前缀：
/// - `@scripts/` - 指向 `~/.svn_flow/scripts/` 目录
///
/// 示例：
/// - 绝对路径: `/Users/xxx/.svn_flow/scripts/my_script.py`
/// - 相对路径: `@scripts/my_script.py`
library;

import 'dart:io';

import 'logger_service.dart';

/// 脚本路径服务
class ScriptPathService {
  ScriptPathService._();
  static final ScriptPathService instance = ScriptPathService._();

  /// 相对路径前缀
  static const String scriptsPrefix = '@scripts/';

  /// 获取用户主目录
  static String get _homeDir =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';

  /// 获取 svn_flow 根目录
  static String get svnFlowDir => '$_homeDir/.svn_flow';

  /// 获取脚本目录路径
  static String get scriptsDirectory => '$svnFlowDir/scripts';

  /// 确保脚本目录存在
  static Future<void> ensureScriptsDirectory() async {
    final dir = Directory(scriptsDirectory);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
      AppLogger.app.info('已创建脚本目录: $scriptsDirectory');
    }
  }

  /// 判断是否为相对路径
  static bool isRelativePath(String path) {
    return path.startsWith(scriptsPrefix);
  }

  /// 判断绝对路径是否在脚本目录下
  static bool isInScriptsDirectory(String absolutePath) {
    // 规范化路径进行比较
    final normalizedPath = _normalizePath(absolutePath);
    final normalizedScriptsDir = _normalizePath(scriptsDirectory);
    return normalizedPath.startsWith('$normalizedScriptsDir/');
  }

  /// 将绝对路径转换为相对路径
  ///
  /// 如果路径在脚本目录下，返回 `@scripts/xxx` 格式
  /// 否则返回原路径
  static String toRelativePath(String absolutePath) {
    if (absolutePath.isEmpty) return absolutePath;
    if (isRelativePath(absolutePath)) return absolutePath;

    final normalizedPath = _normalizePath(absolutePath);
    final normalizedScriptsDir = _normalizePath(scriptsDirectory);

    if (normalizedPath.startsWith('$normalizedScriptsDir/')) {
      final relativePart =
          normalizedPath.substring(normalizedScriptsDir.length + 1);
      return '$scriptsPrefix$relativePart';
    }

    return absolutePath;
  }

  /// 将相对路径转换为绝对路径
  ///
  /// 如果是 `@scripts/xxx` 格式，展开为完整路径
  /// 否则返回原路径
  static String toAbsolutePath(String path) {
    if (path.isEmpty) return path;

    if (path.startsWith(scriptsPrefix)) {
      final relativePart = path.substring(scriptsPrefix.length);
      return '$scriptsDirectory/$relativePart';
    }

    return path;
  }

  /// 规范化路径（处理符号链接、冗余斜杠等）
  static String _normalizePath(String path) {
    // 移除尾部斜杠
    var normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    // 替换多个连续斜杠为单个
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    return normalized;
  }

  /// 获取路径的显示名称
  ///
  /// 相对路径直接显示，绝对路径显示文件名
  static String getDisplayName(String path) {
    if (path.isEmpty) return '未选择';
    if (isRelativePath(path)) {
      return path;
    }
    // 对于绝对路径，显示文件名
    final file = File(path);
    return file.uri.pathSegments.last;
  }

  /// 检查脚本文件是否存在
  static Future<bool> scriptExists(String path) async {
    final absolutePath = toAbsolutePath(path);
    return File(absolutePath).exists();
  }

  /// 列出脚本目录下的所有脚本
  static Future<List<ScriptFileInfo>> listScripts() async {
    await ensureScriptsDirectory();
    
    final dir = Directory(scriptsDirectory);
    final scripts = <ScriptFileInfo>[];

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.py')) {
        final relativePath = toRelativePath(entity.path);
        scripts.add(ScriptFileInfo(
          absolutePath: entity.path,
          relativePath: relativePath,
          name: entity.uri.pathSegments.last,
        ));
      }
    }

    return scripts;
  }
}

/// 脚本文件信息
class ScriptFileInfo {
  final String absolutePath;
  final String relativePath;
  final String name;

  const ScriptFileInfo({
    required this.absolutePath,
    required this.relativePath,
    required this.name,
  });
}
