/// 版本服务
///
/// 用于在运行时读取和管理版本号
/// 从 pubspec.yaml 读取版本号（由构建脚本从 VERSION.yaml 同步）

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;
import 'logger_service.dart';

class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  String? _cachedVersion;
  String? _cachedVersionNumber;
  int? _cachedBuildNumber;

  /// 获取完整版本号（格式: x.y.z+build）
  Future<String> getVersion() async {
    if (_cachedVersion != null) {
      return _cachedVersion!;
    }

    try {
      String pubspecContent;
      
      // 尝试从文件系统读取（开发环境）
      final currentDir = Directory.current;
      final pubspecFile = File(path.join(currentDir.path, 'pubspec.yaml'));
      
      if (await pubspecFile.exists()) {
        pubspecContent = await pubspecFile.readAsString();
      } else {
        // 尝试从 assets 读取（打包环境）
        try {
          pubspecContent = await rootBundle.loadString('pubspec.yaml');
        } catch (_) {
          // 如果都失败，尝试从可执行文件目录查找
          final executable = Platform.resolvedExecutable;
          final execDir = path.dirname(executable);
          final execPubspecFile = File(path.join(execDir, 'pubspec.yaml'));
          
          if (await execPubspecFile.exists()) {
            pubspecContent = await execPubspecFile.readAsString();
          } else {
            throw Exception('无法找到 pubspec.yaml 文件');
          }
        }
      }
      
      final pubspec = loadYaml(pubspecContent) as Map;
      final version = pubspec['version'] as String?;

      if (version == null) {
        throw Exception('pubspec.yaml 中未找到 version 字段');
      }

      _cachedVersion = version;
      return version;
    } catch (e, stackTrace) {
      AppLogger.app.error('获取版本号失败', e, stackTrace);
      // 返回默认版本号
      return '1.0.0+1';
    }
  }

  /// 获取版本号部分（不含构建号，格式: x.y.z）
  Future<String> getVersionNumber() async {
    if (_cachedVersionNumber != null) {
      return _cachedVersionNumber!;
    }

    final version = await getVersion();
    // 分离版本号和构建号
    final parts = version.split('+');
    _cachedVersionNumber = parts[0];
    return _cachedVersionNumber!;
  }

  /// 获取构建号
  Future<int> getBuildNumber() async {
    if (_cachedBuildNumber != null) {
      return _cachedBuildNumber!;
    }

    final version = await getVersion();
    // 分离版本号和构建号
    final parts = version.split('+');
    if (parts.length > 1) {
      _cachedBuildNumber = int.tryParse(parts[1]) ?? 0;
    } else {
      _cachedBuildNumber = 0;
    }
    return _cachedBuildNumber!;
  }

  /// 检查版本兼容性
  ///
  /// [otherVersion] 要比较的版本号（格式: x.y.z 或 x.y.z+build）
  /// [minVersion] 最小版本要求（格式: x.y.z）
  ///
  /// 返回 true 如果 otherVersion >= minVersion
  bool checkCompatibility(String otherVersion, String minVersion) {
    try {
      // 提取版本号部分（去除构建号）
      final otherParts = otherVersion.split('+')[0].split('.');
      final minParts = minVersion.split('.');

      if (otherParts.length != 3 || minParts.length != 3) {
        return false;
      }

      final otherMajor = int.parse(otherParts[0]);
      final otherMinor = int.parse(otherParts[1]);
      final otherPatch = int.parse(otherParts[2]);

      final minMajor = int.parse(minParts[0]);
      final minMinor = int.parse(minParts[1]);
      final minPatch = int.parse(minParts[2]);

      // 比较版本号
      if (otherMajor > minMajor) return true;
      if (otherMajor < minMajor) return false;

      if (otherMinor > minMinor) return true;
      if (otherMinor < minMinor) return false;

      return otherPatch >= minPatch;
    } catch (e, stackTrace) {
      AppLogger.app.error('版本兼容性检查失败', e, stackTrace);
      return false;
    }
  }

  /// 清除缓存（用于重新加载版本号）
  void clearCache() {
    _cachedVersion = null;
    _cachedVersionNumber = null;
    _cachedBuildNumber = null;
  }
}

/// 全局版本服务实例（便捷访问）
final versionService = VersionService();

