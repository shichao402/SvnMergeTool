/// 参数类型
enum ParamType {
  /// 字符串
  string,

  /// 多行文本
  text,

  /// 整数
  int,

  /// 浮点数
  double,

  /// 布尔值
  bool,

  /// 下拉选择
  select,

  /// 文件路径
  path,

  /// 目录路径
  directory,

  /// 代码编辑器
  code,

  /// 字符串列表
  stringList,

  /// JSON 对象
  json,
}

/// 参数规格
///
/// 定义节点的可配置参数。
/// 用于生成属性面板 UI 和验证用户输入。
class ParamSpec {
  /// 参数键名（在 config 中的 key）
  final String key;

  /// 参数显示标签
  final String label;

  /// 参数类型
  final ParamType type;

  /// 参数描述/提示
  final String? description;

  /// 默认值
  final dynamic defaultValue;

  /// 是否必填
  final bool required;

  /// 下拉选项（type 为 select 时使用）
  final List<SelectOption>? options;

  /// 验证正则（type 为 string/text 时使用）
  final String? validationPattern;

  /// 验证失败提示
  final String? validationMessage;

  /// 最小值（type 为 int/double 时使用）
  final num? min;

  /// 最大值（type 为 int/double 时使用）
  final num? max;

  /// 占位符文本
  final String? placeholder;

  /// 代码语言（type 为 code 时使用）
  final String? codeLanguage;

  const ParamSpec({
    required this.key,
    required this.label,
    required this.type,
    this.description,
    this.defaultValue,
    this.required = false,
    this.options,
    this.validationPattern,
    this.validationMessage,
    this.min,
    this.max,
    this.placeholder,
    this.codeLanguage,
  });

  /// 从 JSON 反序列化
  factory ParamSpec.fromJson(Map<String, dynamic> json) {
    return ParamSpec(
      key: json['key'] as String,
      // 支持 label 或 name 字段
      label: (json['label'] ?? json['name'] ?? json['key']) as String,
      type: ParamType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ParamType.string,
      ),
      description: json['description'] as String?,
      // 支持 default 或 defaultValue 字段
      defaultValue: json['default'] ?? json['defaultValue'],
      required: json['required'] as bool? ?? false,
      options: (json['options'] as List<dynamic>?)
          ?.map((o) => SelectOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      validationPattern: json['validationPattern'] as String?,
      validationMessage: json['validationMessage'] as String?,
      min: json['min'] as num?,
      max: json['max'] as num?,
      placeholder: json['placeholder'] as String?,
      codeLanguage: json['codeLanguage'] as String?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label': label,
      'type': type.name,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      if (required) 'required': required,
      if (options != null) 'options': options!.map((o) => o.toJson()).toList(),
      if (validationPattern != null) 'validationPattern': validationPattern,
      if (validationMessage != null) 'validationMessage': validationMessage,
      if (min != null) 'min': min,
      if (max != null) 'max': max,
      if (placeholder != null) 'placeholder': placeholder,
      if (codeLanguage != null) 'codeLanguage': codeLanguage,
    };
  }

  /// 验证参数值
  ParamValidationResult validate(dynamic value) {
    // 必填检查
    if (required && (value == null || (value is String && value.isEmpty))) {
      return ParamValidationResult.invalid('$label 是必填项');
    }

    if (value == null) {
      return ParamValidationResult.valid();
    }

    // 类型检查
    switch (type) {
      case ParamType.int:
        if (value is! int) {
          return ParamValidationResult.invalid('$label 必须是整数');
        }
        if (min != null && value < min!) {
          return ParamValidationResult.invalid('$label 不能小于 $min');
        }
        if (max != null && value > max!) {
          return ParamValidationResult.invalid('$label 不能大于 $max');
        }
        break;

      case ParamType.double:
        if (value is! num) {
          return ParamValidationResult.invalid('$label 必须是数字');
        }
        if (min != null && value < min!) {
          return ParamValidationResult.invalid('$label 不能小于 $min');
        }
        if (max != null && value > max!) {
          return ParamValidationResult.invalid('$label 不能大于 $max');
        }
        break;

      case ParamType.bool:
        if (value is! bool) {
          return ParamValidationResult.invalid('$label 必须是布尔值');
        }
        break;

      case ParamType.string:
      case ParamType.text:
      case ParamType.code:
        if (value is! String) {
          return ParamValidationResult.invalid('$label 必须是字符串');
        }
        if (validationPattern != null) {
          final regex = RegExp(validationPattern!);
          if (!regex.hasMatch(value)) {
            return ParamValidationResult.invalid(
              validationMessage ?? '$label 格式不正确',
            );
          }
        }
        break;

      case ParamType.select:
        if (options != null && !options!.any((o) => o.value == value)) {
          return ParamValidationResult.invalid('$label 的值不在可选范围内');
        }
        break;

      default:
        break;
    }

    return ParamValidationResult.valid();
  }

  /// 获取有效值（如果值为空则返回默认值）
  dynamic getEffectiveValue(dynamic value) {
    if (value == null || (value is String && value.isEmpty)) {
      return defaultValue;
    }
    return value;
  }

  @override
  String toString() => 'ParamSpec(key: $key, label: $label, type: $type)';
}

/// 下拉选项
class SelectOption {
  /// 选项值
  final dynamic value;

  /// 选项显示文本
  final String label;

  /// 选项描述
  final String? description;

  const SelectOption({
    required this.value,
    required this.label,
    this.description,
  });

  factory SelectOption.fromJson(Map<String, dynamic> json) {
    return SelectOption(
      value: json['value'],
      label: json['label'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'label': label,
      if (description != null) 'description': description,
    };
  }
}

/// 参数验证结果
class ParamValidationResult {
  final bool isValid;
  final String? message;

  const ParamValidationResult._({required this.isValid, this.message});

  factory ParamValidationResult.valid() =>
      const ParamValidationResult._(isValid: true);

  factory ParamValidationResult.invalid(String message) =>
      ParamValidationResult._(isValid: false, message: message);
}
