/// 版本服务
///
/// 用于在运行时读取和管理版本号
/// 从 pubspec.yaml 读取版本号（由构建脚本从 VERSION.yaml 同步）

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path;
import 'logger_service.dart';

/// 解析后的 pubspec 版本字符串。
///
/// pubspec 版本约定 `x.y.z+build`（`build` 可选）。本类把字符串拆成两段，
/// 其它代码不必再各自 `split('+')`。
class ParsedVersion {
  /// 不含构建号的版本号部分（例如 `'1.2.3'`），原样保留 split 结果，**不**做合法性校验。
  final String versionNumber;

  /// 构建号；缺省（无 `+`）或 `+` 后非整数 → 0（与 `getBuildNumber` 历史回落一致）。
  final int buildNumber;

  const ParsedVersion({required this.versionNumber, required this.buildNumber});

  @override
  bool operator ==(Object other) =>
      other is ParsedVersion &&
      other.versionNumber == versionNumber &&
      other.buildNumber == buildNumber;

  @override
  int get hashCode => Object.hash(versionNumber, buildNumber);

  @override
  String toString() => 'ParsedVersion($versionNumber+$buildNumber)';
}

/// 把 pubspec 风格的 `x.y.z[+build]` 字符串拆成 [ParsedVersion]。
///
/// 行为契约：
/// - 无 `+`（如 `'1.2.3'`）→ `versionNumber='1.2.3'`, `buildNumber=0`
/// - 有 `+` 且 build 是整数（如 `'1.2.3+5'`）→ `buildNumber=5`
/// - 有 `+` 但 build 非整数 / 空（如 `'1.2.3+abc'` / `'1.2.3+'`）→ `buildNumber=0`
/// - 多个 `+`（如 `'1.2.3+5+6'`）→ 取**首段** `versionNumber='1.2.3'`，剩下整段
///   `'5+6'` 给 `int.tryParse` → `null` → `buildNumber=0`（与 `String.split('+')` 后只
///   取 `[0]` / `[1]` 的现有取值差异：现有 `getBuildNumber` 取 `parts[1]='5'` 得 5；
///   本函数因为只 split 一次而得 0。**这是行为收紧**，但 pubspec 版本字符串
///   实际只允许一个 `+`，与生产输入无差异）。
///
/// 不做"`x.y.z`"长度校验——`versionNumber` 的合法性交给上层（如 [isVersionAtLeast]）。
@visibleForTesting
ParsedVersion parseVersionString(String version) {
  final plusIndex = version.indexOf('+');
  if (plusIndex < 0) {
    return ParsedVersion(versionNumber: version, buildNumber: 0);
  }
  final versionNumber = version.substring(0, plusIndex);
  final buildPart = version.substring(plusIndex + 1);
  final buildNumber = int.tryParse(buildPart) ?? 0;
  return ParsedVersion(versionNumber: versionNumber, buildNumber: buildNumber);
}

/// 比较语义化版本：`version >= minVersion` 时返回 true。
///
/// - `version` 允许带 `+build`（构建号在比较时被忽略，与 [checkCompatibility]
///   原行为一致）；`minVersion` 不允许带 `+build`，但带了也只是 `split('+')[0]`
///   后的解析失败兜底为 false。
/// - 任意一侧 `x.y.z` 段数 != 3 / 非整数 → 返回 false（保守，原代码也是 false）。
/// - 比较顺序 major → minor → patch，patch 用 `>=`。
@visibleForTesting
bool isVersionAtLeast(String version, String minVersion) {
  try {
    // 提取版本号部分（去除构建号）
    final lhsParts = version.split('+').first.split('.');
    final rhsParts = minVersion.split('.');

    if (lhsParts.length != 3 || rhsParts.length != 3) {
      return false;
    }

    final lhsMajor = int.parse(lhsParts[0]);
    final lhsMinor = int.parse(lhsParts[1]);
    final lhsPatch = int.parse(lhsParts[2]);

    final rhsMajor = int.parse(rhsParts[0]);
    final rhsMinor = int.parse(rhsParts[1]);
    final rhsPatch = int.parse(rhsParts[2]);

    if (lhsMajor != rhsMajor) return lhsMajor > rhsMajor;
    if (lhsMinor != rhsMinor) return lhsMinor > rhsMinor;
    return lhsPatch >= rhsPatch;
  } catch (_) {
    return false;
  }
}

/// 从 pubspec.yaml 文本中抽出 `version` 顶层字段。
///
/// 行为契约（R108 边界 contract 锁定——pubspec.yaml schema 与 lib 解析的耦合点）：
/// - 输入是 yaml 文本（已被 [getVersion] 三路加载——开发态 fs / 打包 rootBundle /
///   exec dir 兜底——读到的字符串）；本函数只关心**抽取**，不关心**来源**。
/// - 顶层非 Map（例如 yaml 是裸数组 `[]` 或顶层是 String）→ 抛 TypeError，
///   `getVersion` 外层 catch 兜回 `'1.0.0+1'` 默认值。**这是契约**：pubspec
///   按 yaml 规范必须是 Map；裸数组 yaml 走兜底符合"格式损坏 → 默认值"语义。
/// - Map 中无 `'version'` key → 返回 `null`（**不抛**——`getVersion` 检查 null
///   后显式 `throw Exception('pubspec.yaml 中未找到 version 字段')`，被同一 catch
///   兜底，与 TypeError 路径殊途同归，但保持错误信号语义"字段缺失"vs"格式损坏"
///   的区分以便日志诊断）。
/// - `version` 字段非 String（例如写成数字 `version: 5`）→ 返回 `null`（同上路径）。
/// - 其他非 `version` 顶层字段一律忽略——pubspec 还有 `name`/`dependencies` 等
///   几十个字段都不是本函数关心的。
///
/// **why 抽出**：R108 把 inline 的 `loadYaml(...) as Map; map['version'] as String?`
/// 提到顶层，让"pubspec schema 与 lib 解析的字段名耦合"成为可测断面——
/// 任何 `'version'` typo / 字段重命名 / 顶层 schema 漂移在测试侧立即撞红。
@visibleForTesting
String? extractPubspecVersion(String yamlContent) {
  final pubspec = loadYaml(yamlContent) as Map;
  return pubspec['version'] as String?;
}

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
            // R98 anti-symmetric throw 标记（参见 feedback_audit_dimension_switch.md
            // "throw 对称性审计"维度）：本 throw 在外层 catch（line ~149）被吞掉，
            // 回退到默认版本 '1.0.0+1'。即没有外部 caller 能观察到此 Exception——
            // throw 是诊断信号（写入 AppLogger），不是契约。**刻意不补单测断言**：
            // 测 throw 会绑定不应是契约的实现细节，未来若改用其他兜底策略（比如
            // 直接返回 'unknown'）单测会无谓地红。要测的是 getVersion() 的兜底
            // 输出契约（'1.0.0+1'），不是路径上的 throw。
            throw Exception('无法找到 pubspec.yaml 文件');
          }
        }
      }
      
      final version = extractPubspecVersion(pubspecContent);

      if (version == null) {
        // R98 anti-symmetric throw 标记（同上）：被外层 catch 吞掉，回退默认版本。
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
    _cachedVersionNumber = parseVersionString(version).versionNumber;
    return _cachedVersionNumber!;
  }

  /// 获取构建号
  Future<int> getBuildNumber() async {
    if (_cachedBuildNumber != null) {
      return _cachedBuildNumber!;
    }

    final version = await getVersion();
    _cachedBuildNumber = parseVersionString(version).buildNumber;
    return _cachedBuildNumber!;
  }

  /// 检查版本兼容性
  ///
  /// [otherVersion] 要比较的版本号（格式: x.y.z 或 x.y.z+build）
  /// [minVersion] 最小版本要求（格式: x.y.z）
  ///
  /// 返回 true 如果 otherVersion >= minVersion
  bool checkCompatibility(String otherVersion, String minVersion) {
    return isVersionAtLeast(otherVersion, minVersion);
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

