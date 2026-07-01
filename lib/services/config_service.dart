/// 配置管理服务
///
/// 负责加载和管理应用配置文件
///
/// 配置文件策略：
/// - 用户配置（可写）：保存在 Application Support 目录
/// - 预置配置（只读）：打包在 assets/config/source_urls.json
/// - 读取优先级：用户配置 > 预置配置

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import 'app_paths_service.dart';
import 'logger_service.dart';

/// 渲染"从用户配置加载"的 info 日志行。
///
/// 行为契约：
/// - 路径原样拼接，不做存在性校验、不做规范化（如 `~` 展开），与调用点
///   `getUserConfigFilePath()` 的返回值保持一对一对应。
/// - 空字符串路径会得到 `'从用户配置加载：'`（冒号后空白），用于让上层"路径
///   计算返回空字符串"的 bug 在日志里立即可见，而不是被静默掩盖。
@visibleForTesting
String formatConfigLoadFromUserLine(String userConfigPath) =>
    '从用户配置加载：$userConfigPath';

/// 渲染"从预置配置加载（assets）"的 info 日志行。
///
/// 行为契约：
/// - 零参数纯字符串。抽出来仅为了与 [formatConfigLoadFromUserLine] 配对：两条
///   渲染函数共同表达"配置加载来源"枚举，未来若新增第三条来源（例如从远端
///   拉取），新增渲染函数同样落在这里，避免分布在调用点。
/// - 字面括号是全角"（）"——与 ConfigService 内其它日志的中文标点保持一致；
///   测试会锁定这个字面，避免被"随手"改成半角后影响日志检索。
@visibleForTesting
String formatConfigLoadFromAssetsLine() => '从预置配置加载（assets）';

/// 渲染"预置配置加载失败"的 warn 日志行。
///
/// 行为契约：
/// - 直接 `'$error'`，依赖 `Object.toString()`。`null` 会被打印为 `'null'`
///   （Dart 字符串插值的语义），这并非期望路径，但一旦上游真的传 null，让
///   日志里看见 `'预置配置加载失败：null'` 比静默吞掉好。
/// - 不在这里清洗敏感信息——assets 加载错误本身只可能携带 Flutter framework
///   的内部异常，不会含外部 secret。
@visibleForTesting
String formatConfigAssetsLoadFailedLine(Object error) =>
    '预置配置加载失败：$error';

/// 渲染"配置加载成功"的 info 日志行。
///
/// 行为契约：
/// - `source` 是中文枚举值，由调用点决定（当前实现是 `'用户配置'` / `'预置配置'`）。
///   渲染函数不校验枚举范围——任意字符串都直接拼进去，让"未来新增的来源
///   名"零成本地走这里。
/// - `sourceUrlCount` 是 `_config!.sourceUrls.length`（**非** `enabledSourceUrls.length`），
///   这是配置文件里**所有**源 URL 的条数，包括 `enabled=false` 的——这是历史
///   行为（line 86 的原始字面），保留是为了让"我配置了几条"的运维感知与
///   配置文件直接对齐。
/// - `sourceUrlCount < 0` 不做防御：`List.length` 永远 ≥ 0，传负数等于上层在
///   假传，应该爆出来。
@visibleForTesting
String formatConfigLoadedSummaryLine({
  required String source,
  required int sourceUrlCount,
}) =>
    '配置加载成功（$source）：$sourceUrlCount 个源 URL';

/// 渲染"加载成功汇总"行下的单条源 URL 列表项。
///
/// 行为契约：
/// - **结构性两空格缩进**：开头的 `'  - '` 是契约的**核心**——它让本行视觉上
///   挂在 [formatConfigLoadedSummaryLine] 输出的下方。任何"清理"这个缩进的
///   重构都会破坏运维读日志的层次感，因此测试明确锁定 `startsWith('  - ')`。
/// - 名字与 URL 都原样拼接，不做转义、不做长度截断：URL 通常较长（80~120 字符），
///   截断会让运维难以核对，宁可让一行变长。
/// - `name` 含换行 / `url` 含换行 → 输出会跨行；这是"配置文件被人手动编辑成
///   错误格式"的信号，应该让日志里直观可见，而非被吞掉。
@visibleForTesting
String formatConfigSourceUrlEntryLine(SourceUrlConfig url) =>
    '  - ${url.name}: ${url.url}';

/// 渲染"加载配置文件失败"的 warn 日志行。
///
/// 行为契约：
/// - 与 [formatConfigAssetsLoadFailedLine] 区分：那一条是"assets 子流程"失败，
///   这一条是"整个 loadConfig 兜底"失败。两条会被同一次失败的双重路径同时
///   打出来（先 `预置配置加载失败：...`，再 `加载配置文件失败：...`），刻意
///   保留——双重日志对应"内层 + 外层"两个上下文。
/// - 错误对象同 [formatConfigAssetsLoadFailedLine]，依赖 `toString()`。
@visibleForTesting
String formatConfigLoadFailedLine(Object error) => '加载配置文件失败：$error';

/// 渲染"配置已保存"的 info 日志行。
///
/// 行为契约：
/// - 路径原样拼接，对应 [formatConfigLoadFromUserLine] 的"读"侧——读和写指向
///   同一个 `getUserConfigFilePath()` 的返回值，两条日志放在一起就是配置文件
///   读写循环的完整闭环。
/// - 与读侧字面"从用户配置加载："不同，这里是"配置已保存到用户目录："——
///   动词 + 介宾结构是刻意拉开的，避免运维把读和写混淆。
@visibleForTesting
String formatConfigSavedLine(String configPath) => '配置已保存到用户目录：$configPath';

/// 反序列化 [ConfigService] 的配置文件 JSON 字符串为 [AppConfig]。
///
/// **契约**（R105 持久化 schema 审计）：
/// - 顶层必须是 JSON 对象，且包含 `source_urls` 与 `settings` 两个键——契约由
///   `AppConfig.fromJson`（即 `_$AppConfigFromJson`）决定，本函数只是 IO/解析
///   边界的薄壳。**不要**改 lib/models/app_config.dart 的 `@JsonKey(name: ...)`：
///   用户磁盘上的 config 文件还在用旧字段名；R101 已经把 AppConfig round-trip 测试
///   锁住、本函数只补"读边界"的契约。
/// - 解析失败时抛 [TypeError] / [FormatException]——调用方 `loadConfig` 用 try/catch
///   吞掉后回退到 `AppConfig.defaultConfig()`（R98 反对称 throw 模式）。
/// - 与 [parseQueueJson] 不同的是：config 文件解析失败时**有兜底默认值**（用户体验
///   层面"丢失自定义源 URL 列表"是可恢复的，重新配即可）；queue 文件不是——
///   损坏的队列只能强制空 + 用户重建，因为损坏数据如果部分恢复会让"恢复合并"
///   走错 revision。两类文件的容错策略对偶。
@visibleForTesting
AppConfig parseAppConfigJson(String jsonContent) {
  final json = jsonDecode(jsonContent) as Map<String, dynamic>;
  return AppConfig.fromJson(json);
}

/// 序列化 [AppConfig] 为配置文件 JSON 字符串。
///
/// **契约**（与 [parseAppConfigJson] 配对，R105 持久化 schema 审计）：
/// - 顶层固定为 `{'source_urls': [...], 'settings': {...}}`——字段名锁在 lib/models/
///   app_config.dart 的 `@JsonKey(name: ...)` 上，R101 round-trip 测试已覆盖
///   AppConfig 端；本函数额外锁"文件 IO 边界一定走 jsonEncode + 2 空格缩进"。
/// - 缩进格式与队列文件一致（[JsonEncoder.withIndent]("  ")）——人类可读，
///   且让两个文件的视觉风格统一。
@visibleForTesting
String serializeAppConfigJson(AppConfig config) {
  final json = config.toJson();
  return const JsonEncoder.withIndent('  ').convert(json);
}

class ConfigService {
  /// 单例模式
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  AppConfig? _config;

  final AppPathsService _paths = AppPathsService();

  /// 用户配置文件路径缓存
  String? _userConfigPath;

  /// 获取用户配置目录（可写）
  ///
  /// 路径：
  /// - getApplicationSupportDirectory()/config/
  Future<String> getUserConfigDir() async {
    return _paths.getConfigDir();
  }

  /// 获取用户配置文件路径
  Future<String> getUserConfigFilePath() async {
    if (_userConfigPath != null) {
      return _userConfigPath!;
    }
    _userConfigPath = await _paths.getSourceUrlsConfigPath();
    return _userConfigPath!;
  }

  /// 加载配置文件
  ///
  /// 优先级：
  /// 1. 用户配置（getApplicationSupportDirectory()/config）
  /// 2. 预置配置（assets）
  Future<AppConfig> loadConfig() async {
    if (_config != null) {
      return _config!;
    }

    try {
      String content;
      String source;

      // 策略1: 优先从用户配置目录加载
      final userConfigPath = await getUserConfigFilePath();
      final userConfigFile = File(userConfigPath);

      if (await userConfigFile.exists()) {
        content = await userConfigFile.readAsString();
        source = '用户配置';
        AppLogger.config.info(formatConfigLoadFromUserLine(userConfigPath));
      } else {
        // 策略2: 从 assets 加载预置配置
        try {
          content =
              await rootBundle.loadString('assets/config/source_urls.json');
          source = '预置配置';
          AppLogger.config.info(formatConfigLoadFromAssetsLine());
        } catch (assetsError) {
          AppLogger.config.warn(formatConfigAssetsLoadFailedLine(assetsError));
          // R98 anti-symmetric throw 标记（参见 feedback_audit_dimension_switch.md
          // "throw 对称性审计"维度）：本 throw 在外层 catch（line ~184）被吞掉，
          // 回退到 AppConfig.defaultConfig()。即没有外部 caller 能观察到此 Exception——
          // throw 是诊断信号（写入 AppLogger），不是契约。**刻意不补单测断言**：
          // 要测的是 loadConfig() 的兜底输出（defaultConfig），不是路径上的 throw。
          throw Exception('无法加载配置文件');
        }
      }

      // R105：JSON schema / 字段名契约锁在 [parseAppConfigJson] 测试上
      _config = parseAppConfigJson(content);

      AppLogger.config.info(formatConfigLoadedSummaryLine(
        source: source,
        sourceUrlCount: _config!.sourceUrls.length,
      ));
      for (var url in _config!.enabledSourceUrls) {
        AppLogger.config.info(formatConfigSourceUrlEntryLine(url));
      }

      return _config!;
    } catch (e, stackTrace) {
      AppLogger.config.warn(formatConfigLoadFailedLine(e));
      AppLogger.config.warn('使用默认配置');
      AppLogger.config.error('配置加载异常详情', e, stackTrace);
      _config = AppConfig.defaultConfig();
      return _config!;
    }
  }

  /// 保存配置文件（始终保存到用户配置目录）
  Future<void> saveConfig(AppConfig config) async {
    final configPath = await getUserConfigFilePath();
    final configFile = File(configPath);

    try {
      // 确保目录存在
      await configFile.parent.create(recursive: true);

      // 写入文件
      // R105：JSON schema / 缩进格式锁在 [serializeAppConfigJson] 测试上
      final content = serializeAppConfigJson(config);
      await configFile.writeAsString(content);

      _config = config;
      AppLogger.config.info(formatConfigSavedLine(configPath));
    } catch (e, stackTrace) {
      AppLogger.config.error('保存配置文件失败', e, stackTrace);
      rethrow;
    }
  }

  /// 获取当前配置（如果未加载则先加载）
  Future<AppConfig> getConfig() async {
    if (_config == null) {
      await loadConfig();
    }
    return _config!;
  }

  /// 刷新配置（重新加载）
  Future<AppConfig> refreshConfig() async {
    _config = null;
    return await loadConfig();
  }

  /// 获取所有启用的源 URL
  Future<List<SourceUrlConfig>> getEnabledSourceUrls() async {
    final config = await getConfig();
    return config.enabledSourceUrls;
  }
}
