/// 步骤执行输出
///
/// 执行步骤时返回的结果信息。
/// - `port` 表示结果通道，例如 `success`、`failure`
/// - `data` 用于携带步骤结果数据
/// - `message` 用于记录额外说明
class StepOutput {
  /// 结果通道
  final String port;

  /// 步骤结果数据
  final Map<String, dynamic> data;

  /// 说明信息
  final String? message;

  /// 是否成功
  final bool isSuccess;

  /// 是否取消
  final bool isCancelled;

  const StepOutput({
    required this.port,
    this.data = const {},
    this.message,
    this.isSuccess = true,
    this.isCancelled = false,
  });

  /// 成功输出（触发 `success` 通道）
  factory StepOutput.success({
    Map<String, dynamic>? data,
    String? message,
  }) {
    return StepOutput(
      port: 'success',
      data: data ?? const {},
      message: message,
      isSuccess: true,
    );
  }

  /// 失败输出（触发 `failure` 通道）
  factory StepOutput.failure({
    String? port,
    Map<String, dynamic>? data,
    String? message,
  }) {
    return StepOutput(
      port: port ?? 'failure',
      data: data ?? const {},
      message: message,
      isSuccess: false,
    );
  }

  /// 自定义通道输出
  factory StepOutput.port(
    String port, {
    Map<String, dynamic>? data,
    String? message,
    bool isSuccess = true,
  }) {
    return StepOutput(
      port: port,
      data: data ?? const {},
      message: message,
      isSuccess: isSuccess,
    );
  }

  /// 取消输出
  factory StepOutput.cancelled({String? message}) {
    return StepOutput(
      port: 'cancelled',
      message: message ?? '已取消',
      isSuccess: false,
      isCancelled: true,
    );
  }

  StepOutput copyWith({
    String? port,
    Map<String, dynamic>? data,
    String? message,
    bool? isSuccess,
    bool? isCancelled,
  }) {
    return StepOutput(
      port: port ?? this.port,
      data: data ?? this.data,
      message: message ?? this.message,
      isSuccess: isSuccess ?? this.isSuccess,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }

  @override
  String toString() {
    return 'StepOutput(port: $port, isSuccess: $isSuccess, data: $data, message: $message)';
  }
}
