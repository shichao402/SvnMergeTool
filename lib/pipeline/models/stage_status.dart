/// 阶段执行状态
enum StageStatus {
  /// 等待执行
  pending,

  /// 执行中
  running,

  /// 暂停（等待输入或人工处理）
  paused,

  /// 完成
  completed,

  /// 已跳过
  skipped,

  /// 失败
  failed,
}

/// 阶段状态扩展方法
extension StageStatusExtension on StageStatus {
  /// 是否为终态（不会再变化）
  bool get isTerminal {
    switch (this) {
      case StageStatus.completed:
      case StageStatus.skipped:
      case StageStatus.failed:
        return true;
      default:
        return false;
    }
  }

  /// 是否为成功状态
  bool get isSuccess {
    switch (this) {
      case StageStatus.completed:
      case StageStatus.skipped:
        return true;
      default:
        return false;
    }
  }

  /// 显示名称
  String get displayName {
    switch (this) {
      case StageStatus.pending:
        return '等待';
      case StageStatus.running:
        return '执行中';
      case StageStatus.paused:
        return '暂停';
      case StageStatus.completed:
        return '完成';
      case StageStatus.skipped:
        return '已跳过';
      case StageStatus.failed:
        return '失败';
    }
  }

  /// 图标字符
  String get icon {
    switch (this) {
      case StageStatus.pending:
        return '○';
      case StageStatus.running:
        return '◐';
      case StageStatus.paused:
        return '⏸';
      case StageStatus.completed:
        return '✓';
      case StageStatus.skipped:
        return '⏭';
      case StageStatus.failed:
        return '✗';
    }
  }

  /// 从字符串解析
  static StageStatus fromString(String value) {
    return StageStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Unknown StageStatus: $value'),
    );
  }
}
