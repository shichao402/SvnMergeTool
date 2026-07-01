/// 应用配置模型
///
/// 从用户配置或内置预置配置加载的配置信息。

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

/// 合并任务的默认最大重试次数。
///
/// **为什么定义在 models 层**：这个值是"应用级配置"，被**三个独立层**消费：
/// - `screens/main_screen_v3.dart`：`_maxRetries` 字段初值（用户没存过 settings 时）
/// - `screens/settings_screen.dart` (`parseSettingsFormInputs`)：表单解析兜底
/// - `services/storage_service.dart` (`getDefaultMaxRetries`)：持久化读取兜底
///
/// 三个值必须**永远一致**——任意一处单独改不会爆错，但用户感知会漂移：
/// 比如 storage 改成 3 → 老用户重启后是 3，但新用户走 settings_screen 表单解析又是 5。
/// 放在 models 层是为了让 services / screens 都能 import 而不形成反向依赖。
const int kDefaultMaxRetries = 5;

/// 合并成功后、提交前默认执行的校验脚本相对路径。
///
/// 路径以合并目标工作副本为根，固定使用 `/` 风格分隔符，执行时再转换为当前
/// 平台本地路径。默认值对应目标工作副本下的 `Tools/check.py`。
const String kDefaultMergeValidationScriptPath = 'Tools/check.py';

/// 归一化合并校验脚本配置。
///
/// - 空白配置回落到 [kDefaultMergeValidationScriptPath]。
/// - 用户若误输入 Windows `\` 分隔符，统一转成 `/` 风格保存和展示。
String normalizeMergeValidationScriptPath(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return kDefaultMergeValidationScriptPath;
  }
  return trimmed.replaceAll(r'\', '/');
}

/// 判断合并校验脚本路径是否为 `/` 风格相对路径。
bool isRelativeMergeValidationScriptPath(String value) {
  final path = normalizeMergeValidationScriptPath(value);
  if (path.startsWith('/') || path.startsWith('//')) {
    return false;
  }
  if (RegExp(r'^[A-Za-z]:/').hasMatch(path)) {
    return false;
  }
  return true;
}

/// 单次向 SVN 请求日志的默认最大条数（[AppSettings.svnLogLimit] 默认值）。
///
/// **为什么定义为顶层 const 而不是只在 [AppSettings] 构造器里写死**：与
/// [kDefaultMaxRetries] 同模式——这个值被**多处独立兜底**：
/// - [AppSettings] 构造器默认值（JSON 反序列化无 `svn_log_limit` 字段时使用）
/// - `screens/main_screen_v3.dart` 三处 `appState.config?.settings.svnLogLimit ?? 200`
///   （AppState 还没加载完 config 时使用）
/// - JSON 反序列化生成代码 `app_config.g.dart` 里的 `?? 200`（generator 从构造器
///   默认值反向推导）
///
/// **契约**：这三处的"200"必须**永远一致**。任意单独改一处不会爆错，但用户感知
/// 会漂移：config 加载前 limit 一个值、加载后另一个值，看到的"最近多少条日志"
/// 数量不稳定。提取为常量后，两处 caller 直接 import 这个 const 替代裸字面量；
/// AppSettings 构造器仍保留 `200` 字面量是为了让 `app_config.g.dart` 的 generator
/// 能正常解析（generator 不解析顶层常量引用），由单测显式断言
/// `AppSettings().svnLogLimit == kDefaultSvnLogLimit` 锁定一致性。
///
/// **为什么是 200**：单次 svn log 请求 200 条对绝大多数日常场景足够（一周
/// 提交量），同时不会让初次加载等待太久。再大需要分页，再小则需要频繁加载。
const int kDefaultSvnLogLimit = 200;

/// 日志列表每页的默认显示条数（[AppSettings.logPageSize] 默认值）。
///
/// **为什么定义为顶层 const**：同 [kDefaultSvnLogLimit]——被多处独立兜底：
/// - [AppSettings] 构造器默认值
/// - `providers/app_state.dart`：`_pageSize = _config?.settings.logPageSize ?? 50`
/// - `app_config.g.dart` 的 JSON 反序列化兜底
///
/// **契约**：这三处的"50"必须永远一致。理由同 [kDefaultSvnLogLimit]——避免
/// "config 加载前后用户看到的分页大小不一样"导致的体验漂移。
///
/// **为什么是 50**：50 条覆盖一个屏幕高度，翻页频率合理；25 条容易频繁翻页，
/// 100 条单次渲染稍慢。
const int kDefaultLogPageSize = 50;

/// 渲染 [SourceUrlConfig.displayText] 的展示行：`'$name - $url'`。
///
/// **行为契约**：
/// - 固定 2 段 + 1 个 ` - ` 分隔符（**半角空格 + 半角连字符 + 半角空格**）；
/// - **与 Round 44/45 的 `formatJobDescription` / `formatLogEntryShort` 风格刻意不同**：
///   那两个用的是 `' | '` 半角竖线（4-5 段日志生态分段查询），这里只有 2 段简单
///   "标签 - 值"展示，用 ` - ` 更符合 UI 直觉（菜单项、下拉选项的标准）。**两类
///   分隔符语义不同**，单测显式断言 `' | '` **不出现**在结果里来锁定差异。
/// - 任意字段为空字符串都直接拼，不做"占位文案"——空 name 渲染成 `' - $url'`
///   （前导 ` - `）作为 bug 信号显眼。
/// - **不**对 url 做 trim 或规范化（这是渲染函数；URL 规范化由上游 SourceUrlConfig
///   构造时负责）。
@visibleForTesting
String formatSourceUrlDisplayText({
  required String name,
  required String url,
}) =>
    '$name - $url';

/// 把 [PreloadSettings.stopDate] 字符串解析为 [DateTime]；任何失败一律返回 `null`。
///
/// **行为契约**（**所有失败路径都是 `null`，不抛异常**——预加载是后台静默任务，
/// 不能因为用户在 settings 里填了 `'invalid'` 让整个预加载链路崩溃）：
/// - `null` → `null`（未配置）；
/// - 空字符串 `''` → `null`（**注意**：与 `null` 等价对待，因为 settings UI 的清空
///   按钮可能写入空串而不是真正的 `null`，这两种"无值"语义相同）；
/// - 非 ISO 格式（如 `'2024/01/01'` / `'invalid'` / `'  2024-01-01  '`）→ `null`；
///   `DateTime.parse` 严格按 ISO-8601，**不**做容错或宽松匹配。**为什么不容错**：
///   宽松匹配会让"用户以为已生效但实际格式错误"的 bug 静默存在；返回 null →
///   预加载器走"无截止日期"路径，用户能从行为上感知到（看到一直在加载历史日志）。
/// - 合法 ISO 字符串（`'2024-01-01'` / `'2024-01-01T10:00:00Z'` / `'2024-01-01T10:00:00.000+0800'`）
///   → 对应 `DateTime`；
/// - **不**调用 `.toLocal()` 或 `.toUtc()`——保持 `DateTime.parse` 的原始时区语义，
///   下游 `preload_service.dart` 自行决定如何比较（已经覆盖在 preload 的测试里）。
@visibleForTesting
DateTime? parseStopDateTime(String? stopDate) {
  if (stopDate == null || stopDate.isEmpty) return null;
  try {
    return DateTime.parse(stopDate);
  } catch (_) {
    return null;
  }
}

/// 从源 URL 配置列表中过滤出 `enabled == true` 的子集；保持入参顺序，返回新列表。
///
/// **行为契约**：
/// - 仅保留 `enabled == true` 的元素，其它丢弃；
/// - **保持入参顺序**——`SourceUrlConfig` 在 UI 下拉框中按列表顺序展示，过滤后顺序
///   不能乱（用户配置了 `[A, B, C]`，禁用 B → 期望看到 `[A, C]` 而非 `[C, A]`）；
/// - **返回新列表**（`.toList()`）——调用方拿到的列表可以独立修改而不污染原配置；
///   单测显式锁定"修改返回值不影响 source"的不变量。
/// - 空输入 → 空列表；
/// - 全部 disabled → 空列表（**不**回退到全列表——"全禁用 = 用户明确不要任何 URL"，
///   静默回退会让 main_screen_v3 在用户禁用所有 URL 时仍尝试用第一个，违背用户意图）。
/// - **不去重**：如果输入有两个 url 相同的 enabled 项，全部保留——这是上游配置文件的
///   bug 信号，应当显眼出现而非被静默合并。
@visibleForTesting
List<SourceUrlConfig> filterEnabledSourceUrls(List<SourceUrlConfig> all) =>
    all.where((url) => url.enabled).toList();

/// 源 URL 配置
@JsonSerializable()
class SourceUrlConfig {
  final String name;
  final String url;
  final String description;
  final bool enabled;

  const SourceUrlConfig({
    required this.name,
    required this.url,
    this.description = '',
    this.enabled = true,
  });

  factory SourceUrlConfig.fromJson(Map<String, dynamic> json) =>
      _$SourceUrlConfigFromJson(json);

  Map<String, dynamic> toJson() => _$SourceUrlConfigToJson(this);

  SourceUrlConfig copyWith({
    String? name,
    String? url,
    String? description,
    bool? enabled,
  }) {
    return SourceUrlConfig(
      name: name ?? this.name,
      url: url ?? this.url,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
    );
  }

  /// 获取显示文本
  String get displayText => formatSourceUrlDisplayText(name: name, url: url);
}

/// 预加载设置
@JsonSerializable()
class PreloadSettings {
  /// 是否启用后台静默预加载
  @JsonKey(name: 'enabled')
  final bool enabled;

  /// 是否在到达分支点时停止
  @JsonKey(name: 'stop_on_branch_point')
  final bool stopOnBranchPoint;

  /// 天数范围限制（0 表示不限制）
  @JsonKey(name: 'max_days')
  final int maxDays;

  /// 条数限制（0 表示不限制）
  @JsonKey(name: 'max_count')
  final int maxCount;

  /// 指定截止版本（0 表示不限制）
  @JsonKey(name: 'stop_revision')
  final int stopRevision;

  /// 指定截止日期（null 表示不限制）
  @JsonKey(name: 'stop_date')
  final String? stopDate;

  const PreloadSettings({
    this.enabled = true,
    this.stopOnBranchPoint = true,
    this.maxDays = 90,
    this.maxCount = 1000,
    this.stopRevision = 0,
    this.stopDate,
  });

  factory PreloadSettings.fromJson(Map<String, dynamic> json) =>
      _$PreloadSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$PreloadSettingsToJson(this);

  PreloadSettings copyWith({
    bool? enabled,
    bool? stopOnBranchPoint,
    int? maxDays,
    int? maxCount,
    int? stopRevision,
    String? stopDate,
  }) {
    return PreloadSettings(
      enabled: enabled ?? this.enabled,
      stopOnBranchPoint: stopOnBranchPoint ?? this.stopOnBranchPoint,
      maxDays: maxDays ?? this.maxDays,
      maxCount: maxCount ?? this.maxCount,
      stopRevision: stopRevision ?? this.stopRevision,
      stopDate: stopDate ?? this.stopDate,
    );
  }

  /// 解析截止日期
  DateTime? get stopDateTime => parseStopDateTime(stopDate);
}

/// 应用配置中的基础设置
@JsonSerializable()
class AppSettings {
  /// 单次向 SVN 请求日志的最大条数
  @JsonKey(name: 'svn_log_limit')
  final int svnLogLimit;

  /// 日志列表每页显示条数
  @JsonKey(name: 'log_page_size')
  final int logPageSize;

  const AppSettings({
    this.svnLogLimit = 200,
    this.logPageSize = 50,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  AppSettings copyWith({
    int? svnLogLimit,
    int? logPageSize,
  }) {
    return AppSettings(
      svnLogLimit: svnLogLimit ?? this.svnLogLimit,
      logPageSize: logPageSize ?? this.logPageSize,
    );
  }
}

/// 应用配置
@JsonSerializable()
class AppConfig {
  final String version;

  @JsonKey(name: 'source_urls')
  final List<SourceUrlConfig> sourceUrls;

  final AppSettings settings;

  const AppConfig({
    required this.version,
    required this.sourceUrls,
    required this.settings,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AppConfigToJson(this);

  /// 获取所有启用的源 URL
  List<SourceUrlConfig> get enabledSourceUrls =>
      filterEnabledSourceUrls(sourceUrls);

  /// 默认配置
  factory AppConfig.defaultConfig() {
    return const AppConfig(
      version: '1.0.0',
      sourceUrls: [
        SourceUrlConfig(
          name: '示例：项目主干',
          url: 'https://your-svn-server.com/repos/project/trunk',
          description: '这是一个示例配置，请在用户配置文件中修改为实际地址',
          enabled: false,
        ),
      ],
      settings: AppSettings(),
    );
  }
}
