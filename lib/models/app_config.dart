/// 应用配置模型
///
/// 从 config/source_urls.json 加载的配置信息

import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

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
  String get displayText => '$name - $url';
}

/// 预加载停止条件类型
enum PreloadStopType {
  /// 到达分支点
  branchPoint,
  /// 天数范围
  days,
  /// 条数限制
  count,
  /// 指定版本
  revision,
  /// 指定日期
  date,
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
  DateTime? get stopDateTime {
    if (stopDate == null || stopDate!.isEmpty) return null;
    try {
      return DateTime.parse(stopDate!);
    } catch (_) {
      return null;
    }
  }
}

/// 应用设置
@JsonSerializable()
class AppSettings {
  final bool autoLoadHistory;
  final int maxHistoryItems;
  final int defaultMaxRetries;
  final bool autoLoadLogsOnStartup;
  @JsonKey(name: 'svn_log_limit')
  final int svnLogLimit;
  @JsonKey(name: 'log_page_size')
  final int logPageSize;
  @JsonKey(name: 'preload')
  final PreloadSettings preload;

  const AppSettings({
    this.autoLoadHistory = true,
    this.maxHistoryItems = 10,
    this.defaultMaxRetries = 5,
    this.autoLoadLogsOnStartup = false,
    this.svnLogLimit = 200,
    this.logPageSize = 50,
    this.preload = const PreloadSettings(),
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  AppSettings copyWith({
    bool? autoLoadHistory,
    int? maxHistoryItems,
    int? defaultMaxRetries,
    bool? autoLoadLogsOnStartup,
    int? svnLogLimit,
    int? logPageSize,
    PreloadSettings? preload,
  }) {
    return AppSettings(
      autoLoadHistory: autoLoadHistory ?? this.autoLoadHistory,
      maxHistoryItems: maxHistoryItems ?? this.maxHistoryItems,
      defaultMaxRetries: defaultMaxRetries ?? this.defaultMaxRetries,
      autoLoadLogsOnStartup:
          autoLoadLogsOnStartup ?? this.autoLoadLogsOnStartup,
      svnLogLimit: svnLogLimit ?? this.svnLogLimit,
      logPageSize: logPageSize ?? this.logPageSize,
      preload: preload ?? this.preload,
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
      sourceUrls.where((url) => url.enabled).toList();

  /// 默认配置
  factory AppConfig.defaultConfig() {
    return const AppConfig(
      version: '1.0.0',
      sourceUrls: [
        SourceUrlConfig(
          name: '示例：项目主干',
          url: 'https://your-svn-server.com/repos/project/trunk',
          description: '这是一个示例配置，请在 config/source_urls.json 中修改为实际地址',
          enabled: false,
        ),
      ],
      settings: AppSettings(),
    );
  }
}

