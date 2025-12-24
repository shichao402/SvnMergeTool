/// 执行器状态
enum ExecutorStatus {
  /// 空闲
  idle,

  /// 运行中
  running,

  /// 已暂停（等待用户输入）
  paused,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已取消
  cancelled,
}
