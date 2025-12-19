import 'package:mobx/mobx.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../models/stage_status.dart';
import '../models/stage_type.dart';

/// 阶段节点数据
/// 
/// 用于存储在 vyuh_node_flow 的 Node<StageData> 中，
/// 包含执行配置和运行时状态。
class StageData implements NodeData {
  /// 阶段类型
  final StageType type;

  /// 阶段名称
  final String name;

  /// 阶段描述
  final String? description;

  /// 是否启用
  final bool enabled;

  // ==================== 执行配置 ====================

  /// 脚本路径（用于 script/check/postScript 类型）
  final String? scriptPath;

  /// 脚本参数
  final List<String>? scriptArgs;

  /// 提交消息模板（用于 commit 类型）
  /// 支持变量：${job.xxx}, ${input.xxx}, ${stages.xxx.output}
  final String? commitMessageTemplate;

  /// Review 输入配置（用于 review 类型）
  final ReviewInputData? reviewInput;

  // ==================== 运行时状态（Observable） ====================

  /// 执行状态
  final Observable<StageStatus> _status;
  StageStatus get status => _status.value;
  set status(StageStatus value) => runInAction(() => _status.value = value);

  /// 错误信息
  final Observable<String?> _errorMessage;
  String? get errorMessage => _errorMessage.value;
  set errorMessage(String? value) => runInAction(() => _errorMessage.value = value);

  /// 执行进度 (0.0 - 1.0)
  final Observable<double> _progress;
  double get progress => _progress.value;
  set progress(double value) => runInAction(() => _progress.value = value);

  /// 执行输出
  final Observable<String?> _output;
  String? get output => _output.value;
  set output(String? value) => runInAction(() => _output.value = value);

  /// 用户输入（review 阶段）
  final Observable<String?> _userInput;
  String? get userInput => _userInput.value;
  set userInput(String? value) => runInAction(() => _userInput.value = value);

  /// 执行开始时间
  final Observable<DateTime?> _startTime;
  DateTime? get startTime => _startTime.value;
  set startTime(DateTime? value) => runInAction(() => _startTime.value = value);

  /// 执行结束时间
  final Observable<DateTime?> _endTime;
  DateTime? get endTime => _endTime.value;
  set endTime(DateTime? value) => runInAction(() => _endTime.value = value);

  StageData({
    required this.type,
    required this.name,
    this.description,
    this.enabled = true,
    this.scriptPath,
    this.scriptArgs,
    this.commitMessageTemplate,
    this.reviewInput,
    StageStatus initialStatus = StageStatus.pending,
  })  : _status = Observable(initialStatus),
        _errorMessage = Observable(null),
        _progress = Observable(0.0),
        _output = Observable(null),
        _userInput = Observable(null),
        _startTime = Observable(null),
        _endTime = Observable(null);

  /// 执行耗时
  Duration? get duration {
    if (startTime == null) return null;
    final end = endTime ?? DateTime.now();
    return end.difference(startTime!);
  }

  /// 重置运行时状态
  void reset() {
    runInAction(() {
      _status.value = StageStatus.pending;
      _errorMessage.value = null;
      _progress.value = 0.0;
      _output.value = null;
      _userInput.value = null;
      _startTime.value = null;
      _endTime.value = null;
    });
  }

  @override
  NodeData clone() {
    return StageData(
      type: type,
      name: name,
      description: description,
      enabled: enabled,
      scriptPath: scriptPath,
      scriptArgs: scriptArgs != null ? List.from(scriptArgs!) : null,
      commitMessageTemplate: commitMessageTemplate,
      reviewInput: reviewInput?.clone(),
      initialStatus: status,
    );
  }

  /// 从 JSON 反序列化
  factory StageData.fromJson(Map<String, dynamic> json) {
    return StageData(
      type: StageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => StageType.script,
      ),
      name: json['name'] as String,
      description: json['description'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      scriptPath: json['scriptPath'] as String?,
      scriptArgs: (json['scriptArgs'] as List<dynamic>?)?.cast<String>(),
      commitMessageTemplate: json['commitMessageTemplate'] as String?,
      reviewInput: json['reviewInput'] != null
          ? ReviewInputData.fromJson(json['reviewInput'] as Map<String, dynamic>)
          : null,
      initialStatus: json['status'] != null
          ? StageStatus.values.firstWhere(
              (e) => e.name == json['status'],
              orElse: () => StageStatus.pending,
            )
          : StageStatus.pending,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'name': name,
      if (description != null) 'description': description,
      'enabled': enabled,
      if (scriptPath != null) 'scriptPath': scriptPath,
      if (scriptArgs != null) 'scriptArgs': scriptArgs,
      if (commitMessageTemplate != null) 'commitMessageTemplate': commitMessageTemplate,
      if (reviewInput != null) 'reviewInput': reviewInput!.toJson(),
      'status': status.name,
    };
  }

  // ==================== 工厂方法 ====================

  /// 创建准备阶段
  factory StageData.prepare({String name = '准备'}) {
    return StageData(type: StageType.prepare, name: name);
  }

  /// 创建更新阶段
  factory StageData.update({String name = '更新'}) {
    return StageData(type: StageType.update, name: name);
  }

  /// 创建合并阶段
  factory StageData.merge({String name = '合并'}) {
    return StageData(type: StageType.merge, name: name);
  }

  /// 创建提交阶段
  factory StageData.commit({
    String name = '提交',
    String? messageTemplate,
  }) {
    return StageData(
      type: StageType.commit,
      name: name,
      commitMessageTemplate: messageTemplate,
    );
  }

  /// 创建审核阶段
  factory StageData.review({
    String name = '审核',
    required ReviewInputData input,
  }) {
    return StageData(
      type: StageType.review,
      name: name,
      reviewInput: input,
    );
  }

  /// 创建脚本阶段
  factory StageData.script({
    String name = '脚本',
    required String scriptPath,
    List<String>? args,
  }) {
    return StageData(
      type: StageType.script,
      name: name,
      scriptPath: scriptPath,
      scriptArgs: args,
    );
  }
}

/// Review 输入配置
class ReviewInputData {
  /// 输入提示
  final String prompt;

  /// 输入标签
  final String label;

  /// 是否必填
  final bool required;

  /// 默认值
  final String? defaultValue;

  /// 验证正则
  final String? validationPattern;

  /// 验证失败提示
  final String? validationMessage;

  const ReviewInputData({
    required this.prompt,
    required this.label,
    this.required = true,
    this.defaultValue,
    this.validationPattern,
    this.validationMessage,
  });

  ReviewInputData clone() {
    return ReviewInputData(
      prompt: prompt,
      label: label,
      required: required,
      defaultValue: defaultValue,
      validationPattern: validationPattern,
      validationMessage: validationMessage,
    );
  }

  factory ReviewInputData.fromJson(Map<String, dynamic> json) {
    return ReviewInputData(
      prompt: json['prompt'] as String,
      label: json['label'] as String,
      required: json['required'] as bool? ?? true,
      defaultValue: json['defaultValue'] as String?,
      validationPattern: json['validationPattern'] as String?,
      validationMessage: json['validationMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'label': label,
      'required': required,
      if (defaultValue != null) 'defaultValue': defaultValue,
      if (validationPattern != null) 'validationPattern': validationPattern,
      if (validationMessage != null) 'validationMessage': validationMessage,
    };
  }
}
