import 'stage_type.dart';
import 'failure_action.dart';
import 'capture_mode.dart';

/// Review 阶段的输入配置
class ReviewInputConfig {
  /// 输入框标签
  final String label;

  /// 输入提示
  final String? hint;

  /// 格式校验正则（可选）
  final String? validationRegex;

  /// 是否必填
  final bool required;

  const ReviewInputConfig({
    required this.label,
    this.hint,
    this.validationRegex,
    this.required = true,
  });

  /// 从 JSON 创建
  factory ReviewInputConfig.fromJson(Map<String, dynamic> json) {
    return ReviewInputConfig(
      label: json['label'] as String? ?? 'Input',
      hint: json['hint'] as String?,
      validationRegex: json['validationRegex'] as String?,
      required: json['required'] as bool? ?? true,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'label': label,
      if (hint != null) 'hint': hint,
      if (validationRegex != null) 'validationRegex': validationRegex,
      'required': required,
    };
  }

  /// 复制并修改
  ReviewInputConfig copyWith({
    String? label,
    String? hint,
    String? validationRegex,
    bool? required,
  }) {
    return ReviewInputConfig(
      label: label ?? this.label,
      hint: hint ?? this.hint,
      validationRegex: validationRegex ?? this.validationRegex,
      required: required ?? this.required,
    );
  }
}

/// 阶段配置
class StageConfig {
  /// 唯一标识（用于变量引用）
  final String id;

  /// 阶段类型
  final StageType type;

  /// 显示名称
  final String name;

  /// 脚本路径（script/check/postScript 类型使用）
  final String? script;

  /// 脚本参数
  final List<String>? scriptArgs;

  /// 输出捕获模式
  final CaptureMode captureMode;

  /// 失败时的处理策略
  final FailureAction onFail;

  /// 是否启用
  final bool enabled;

  /// 最大重试次数（onFail 为 retry 时有效）
  final int maxRetries;

  /// 超时时间（秒），0 表示无限制
  final int timeoutSeconds;

  /// Review 阶段的输入配置
  final ReviewInputConfig? reviewInput;

  /// 提交信息模板（commit 阶段使用）
  final String? commitMessageTemplate;

  const StageConfig({
    required this.id,
    required this.type,
    required this.name,
    this.script,
    this.scriptArgs,
    this.captureMode = CaptureMode.none,
    this.onFail = FailureAction.pause,
    this.enabled = true,
    this.maxRetries = 3,
    this.timeoutSeconds = 0,
    this.reviewInput,
    this.commitMessageTemplate,
  });

  /// 创建内置的 prepare 阶段
  factory StageConfig.prepare() {
    return const StageConfig(
      id: 'prepare',
      type: StageType.prepare,
      name: '准备',
      onFail: FailureAction.pause,
    );
  }

  /// 创建内置的 update 阶段
  factory StageConfig.update() {
    return const StageConfig(
      id: 'update',
      type: StageType.update,
      name: '更新',
      onFail: FailureAction.retry,
      maxRetries: 3,
    );
  }

  /// 创建内置的 merge 阶段
  factory StageConfig.merge() {
    return const StageConfig(
      id: 'merge',
      type: StageType.merge,
      name: '合并',
      onFail: FailureAction.pause,
    );
  }

  /// 创建内置的 commit 阶段
  factory StageConfig.commit({String? messageTemplate}) {
    return StageConfig(
      id: 'commit',
      type: StageType.commit,
      name: '提交',
      onFail: FailureAction.pause,
      commitMessageTemplate: messageTemplate,
    );
  }

  /// 创建脚本阶段
  factory StageConfig.script({
    required String id,
    required String name,
    required String script,
    List<String>? args,
    CaptureMode captureMode = CaptureMode.none,
    FailureAction onFail = FailureAction.pause,
    int timeoutSeconds = 0,
  }) {
    return StageConfig(
      id: id,
      type: StageType.script,
      name: name,
      script: script,
      scriptArgs: args,
      captureMode: captureMode,
      onFail: onFail,
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// 创建检查阶段
  factory StageConfig.check({
    required String id,
    required String name,
    required String script,
    List<String>? args,
    FailureAction onFail = FailureAction.pause,
    int timeoutSeconds = 0,
  }) {
    return StageConfig(
      id: id,
      type: StageType.check,
      name: name,
      script: script,
      scriptArgs: args,
      onFail: onFail,
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// 创建 review 阶段
  factory StageConfig.review({
    required String id,
    required String name,
    required ReviewInputConfig input,
  }) {
    return StageConfig(
      id: id,
      type: StageType.review,
      name: name,
      reviewInput: input,
      onFail: FailureAction.pause,
    );
  }

  /// 创建后置脚本阶段
  factory StageConfig.postScript({
    required String id,
    required String name,
    required String script,
    List<String>? args,
    CaptureMode captureMode = CaptureMode.none,
    FailureAction onFail = FailureAction.skip,
    int timeoutSeconds = 0,
  }) {
    return StageConfig(
      id: id,
      type: StageType.postScript,
      name: name,
      script: script,
      scriptArgs: args,
      captureMode: captureMode,
      onFail: onFail,
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// 从 JSON 创建
  factory StageConfig.fromJson(Map<String, dynamic> json) {
    return StageConfig(
      id: json['id'] as String,
      type: StageTypeExtension.fromString(json['type'] as String),
      name: json['name'] as String,
      script: json['script'] as String?,
      scriptArgs: (json['scriptArgs'] as List<dynamic>?)?.cast<String>(),
      captureMode: json['captureMode'] != null
          ? CaptureModeExtension.fromString(json['captureMode'] as String)
          : CaptureMode.none,
      onFail: json['onFail'] != null
          ? FailureActionExtension.fromString(json['onFail'] as String)
          : FailureAction.pause,
      enabled: json['enabled'] as bool? ?? true,
      maxRetries: json['maxRetries'] as int? ?? 3,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 0,
      reviewInput: json['reviewInput'] != null
          ? ReviewInputConfig.fromJson(
              json['reviewInput'] as Map<String, dynamic>)
          : null,
      commitMessageTemplate: json['commitMessageTemplate'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      if (script != null) 'script': script,
      if (scriptArgs != null && scriptArgs!.isNotEmpty) 'scriptArgs': scriptArgs,
      if (captureMode != CaptureMode.none) 'captureMode': captureMode.name,
      'onFail': onFail.name,
      'enabled': enabled,
      if (maxRetries != 3) 'maxRetries': maxRetries,
      if (timeoutSeconds != 0) 'timeoutSeconds': timeoutSeconds,
      if (reviewInput != null) 'reviewInput': reviewInput!.toJson(),
      if (commitMessageTemplate != null)
        'commitMessageTemplate': commitMessageTemplate,
    };
  }

  /// 复制并修改
  StageConfig copyWith({
    String? id,
    StageType? type,
    String? name,
    String? script,
    List<String>? scriptArgs,
    CaptureMode? captureMode,
    FailureAction? onFail,
    bool? enabled,
    int? maxRetries,
    int? timeoutSeconds,
    ReviewInputConfig? reviewInput,
    String? commitMessageTemplate,
  }) {
    return StageConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      script: script ?? this.script,
      scriptArgs: scriptArgs ?? this.scriptArgs,
      captureMode: captureMode ?? this.captureMode,
      onFail: onFail ?? this.onFail,
      enabled: enabled ?? this.enabled,
      maxRetries: maxRetries ?? this.maxRetries,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      reviewInput: reviewInput ?? this.reviewInput,
      commitMessageTemplate: commitMessageTemplate ?? this.commitMessageTemplate,
    );
  }
}
