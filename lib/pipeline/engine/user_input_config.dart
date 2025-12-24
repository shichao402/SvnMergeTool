/// 用户输入配置
/// 
/// 定义用户输入节点的配置参数
class UserInputConfig {
  /// 输入框标签
  final String label;

  /// 提示文字
  final String? hint;

  /// 验证正则表达式
  final String? validationRegex;

  /// 是否必填
  final bool required;

  const UserInputConfig({
    required this.label,
    this.hint,
    this.validationRegex,
    this.required = true,
  });

  /// 从节点配置创建
  factory UserInputConfig.fromConfig(Map<String, dynamic> config, String defaultLabel) {
    return UserInputConfig(
      label: config['label'] as String? ?? defaultLabel,
      hint: config['prompt'] as String?,
      validationRegex: config['validationPattern'] as String?,
      required: config['required'] as bool? ?? true,
    );
  }
}
