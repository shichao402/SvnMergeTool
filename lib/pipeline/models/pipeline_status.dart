/// Pipeline 整体执行状态
enum PipelineStatus {
  /// 空闲，未开始
  idle,

  /// 运行中
  running,

  /// 暂停（等待用户输入或人工处理）
  paused,

  /// 完成
  completed,

  /// 失败
  failed,

  /// 已取消
  cancelled,

  /// 回滚中
  rollingBack,
}

/// Pipeline 状态扩展方法
extension PipelineStatusExtension on PipelineStatus {
  /// 是否为终态
  bool get isTerminal {
    switch (this) {
      case PipelineStatus.completed:
      case PipelineStatus.failed:
      case PipelineStatus.cancelled:
        return true;
      default:
        return false;
    }
  }

  /// 是否可以继续执行
  bool get canResume {
    return this == PipelineStatus.paused;
  }

  /// 是否可以取消
  bool get canCancel {
    switch (this) {
      case PipelineStatus.running:
      case PipelineStatus.paused:
        return true;
      default:
        return false;
    }
  }

  /// 是否可以回滚
  bool get canRollback {
    switch (this) {
      case PipelineStatus.running:
      case PipelineStatus.paused:
      case PipelineStatus.failed:
        return true;
      default:
        return false;
    }
  }

  /// 显示名称
  String get displayName {
    switch (this) {
      case PipelineStatus.idle:
        return '空闲';
      case PipelineStatus.running:
        return '运行中';
      case PipelineStatus.paused:
        return '暂停';
      case PipelineStatus.completed:
        return '完成';
      case PipelineStatus.failed:
        return '失败';
      case PipelineStatus.cancelled:
        return '已取消';
      case PipelineStatus.rollingBack:
        return '回滚中';
    }
  }

  /// 图标字符
  String get icon {
    switch (this) {
      case PipelineStatus.idle:
        return '○';
      case PipelineStatus.running:
        return '▶';
      case PipelineStatus.paused:
        return '⏸';
      case PipelineStatus.completed:
        return '✓';
      case PipelineStatus.failed:
        return '✗';
      case PipelineStatus.cancelled:
        return '⊘';
      case PipelineStatus.rollingBack:
        return '↺';
    }
  }

  /// 从字符串解析
  static PipelineStatus fromString(String value) {
    return PipelineStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => throw ArgumentError('Unknown PipelineStatus: $value'),
    );
  }
}
