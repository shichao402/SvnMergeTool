/// 阶段失败时的处理策略
enum FailureAction {
  /// 暂停等待人工处理
  pause,

  /// 跳过此阶段继续执行
  skip,

  /// 标记任务失败，停止执行
  fail,

  /// 自动重试（受 maxRetries 限制）
  retry,

  /// 回滚到 Pipeline 开始状态
  rollback,

  /// 中止并回滚
  abort,
}

/// 失败策略扩展方法
extension FailureActionExtension on FailureAction {
  /// 显示名称
  String get displayName {
    switch (this) {
      case FailureAction.pause:
        return '暂停等待';
      case FailureAction.skip:
        return '跳过继续';
      case FailureAction.fail:
        return '标记失败';
      case FailureAction.retry:
        return '自动重试';
      case FailureAction.rollback:
        return '回滚';
      case FailureAction.abort:
        return '中止';
    }
  }

  /// 描述
  String get description {
    switch (this) {
      case FailureAction.pause:
        return '暂停 Pipeline，等待人工处理后继续';
      case FailureAction.skip:
        return '跳过当前阶段，继续执行后续阶段';
      case FailureAction.fail:
        return '标记任务失败，停止执行';
      case FailureAction.retry:
        return '自动重试当前阶段';
      case FailureAction.rollback:
        return '回滚工作副本到 Pipeline 开始状态';
      case FailureAction.abort:
        return '中止执行并回滚';
    }
  }

  /// 从字符串解析
  static FailureAction fromString(String value) {
    return FailureAction.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Unknown FailureAction: $value'),
    );
  }
}
