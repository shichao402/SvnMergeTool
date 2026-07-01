/// 执行器状态
enum ExecutorStatus {
  /// 空闲
  idle,

  /// 运行中
  running,

  /// 已暂停（等待人工处理）
  paused,

  /// 已完成
  completed,
}
