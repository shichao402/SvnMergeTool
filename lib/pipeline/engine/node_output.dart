/// 节点执行输出
///
/// 执行器返回此对象，指定：
/// - 触发哪个输出端口
/// - 传递给下游节点的数据
/// - 日志消息
class NodeOutput {
  /// 触发的输出端口 ID
  final String port;

  /// 传递给下游节点的数据
  final Map<String, dynamic> data;

  /// 日志消息
  final String? message;

  /// 是否成功
  final bool isSuccess;

  /// 是否取消
  final bool isCancelled;

  const NodeOutput({
    required this.port,
    this.data = const {},
    this.message,
    this.isSuccess = true,
    this.isCancelled = false,
  });

  /// 成功输出（触发 success 端口）
  factory NodeOutput.success({
    Map<String, dynamic>? data,
    String? message,
  }) {
    return NodeOutput(
      port: 'success',
      data: data ?? const {},
      message: message,
      isSuccess: true,
    );
  }

  /// 失败输出（触发 failure 端口）
  factory NodeOutput.failure({
    String? port,
    Map<String, dynamic>? data,
    String? message,
  }) {
    return NodeOutput(
      port: port ?? 'failure',
      data: data ?? const {},
      message: message,
      isSuccess: false,
    );
  }

  /// 自定义端口输出
  factory NodeOutput.port(
    String port, {
    Map<String, dynamic>? data,
    String? message,
    bool isSuccess = true,
  }) {
    return NodeOutput(
      port: port,
      data: data ?? const {},
      message: message,
      isSuccess: isSuccess,
    );
  }

  /// 取消输出
  factory NodeOutput.cancelled({String? message}) {
    return NodeOutput(
      port: 'cancelled',
      message: message ?? '已取消',
      isSuccess: false,
      isCancelled: true,
    );
  }

  /// 复制并修改
  NodeOutput copyWith({
    String? port,
    Map<String, dynamic>? data,
    String? message,
    bool? isSuccess,
    bool? isCancelled,
  }) {
    return NodeOutput(
      port: port ?? this.port,
      data: data ?? this.data,
      message: message ?? this.message,
      isSuccess: isSuccess ?? this.isSuccess,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }

  @override
  String toString() {
    return 'NodeOutput(port: $port, isSuccess: $isSuccess, data: $data, message: $message)';
  }
}
