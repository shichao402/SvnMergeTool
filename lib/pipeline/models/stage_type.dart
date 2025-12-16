/// Pipeline 阶段类型
enum StageType {
  /// 准备阶段：revert + cleanup
  prepare,

  /// 更新阶段：svn update
  update,

  /// 合并阶段：svn merge（可循环多个 revision）
  merge,

  /// 脚本阶段：执行自定义脚本（生成资源/代码）
  script,

  /// 检查阶段：执行检查脚本（编译/测试）
  check,

  /// 审核阶段：等待用户输入（如 Review ID）
  review,

  /// 提交阶段：svn commit
  commit,

  /// 后置脚本阶段：清理/通知/错误处理
  postScript,
}

/// 阶段类型扩展方法
extension StageTypeExtension on StageType {
  /// 是否为内置阶段（不可删除）
  bool get isBuiltin {
    switch (this) {
      case StageType.prepare:
      case StageType.update:
      case StageType.merge:
      case StageType.commit:
        return true;
      default:
        return false;
    }
  }

  /// 是否为脚本类型阶段
  bool get isScriptType {
    switch (this) {
      case StageType.script:
      case StageType.check:
      case StageType.postScript:
        return true;
      default:
        return false;
    }
  }

  /// 显示名称
  String get displayName {
    switch (this) {
      case StageType.prepare:
        return '准备';
      case StageType.update:
        return '更新';
      case StageType.merge:
        return '合并';
      case StageType.script:
        return '脚本';
      case StageType.check:
        return '检查';
      case StageType.review:
        return '审核';
      case StageType.commit:
        return '提交';
      case StageType.postScript:
        return '后置脚本';
    }
  }

  /// 从字符串解析
  static StageType fromString(String value) {
    return StageType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Unknown StageType: $value'),
    );
  }
}
