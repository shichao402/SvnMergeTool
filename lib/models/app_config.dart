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

  const AppSettings({
    this.autoLoadHistory = true,
    this.maxHistoryItems = 10,
    this.defaultMaxRetries = 5,
    this.autoLoadLogsOnStartup = false,
    this.svnLogLimit = 200,
    this.logPageSize = 50,
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
  }) {
    return AppSettings(
      autoLoadHistory: autoLoadHistory ?? this.autoLoadHistory,
      maxHistoryItems: maxHistoryItems ?? this.maxHistoryItems,
      defaultMaxRetries: defaultMaxRetries ?? this.defaultMaxRetries,
      autoLoadLogsOnStartup:
          autoLoadLogsOnStartup ?? this.autoLoadLogsOnStartup,
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

