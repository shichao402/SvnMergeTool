/// 脚本输出捕获模式
enum CaptureMode {
  /// 不捕获输出
  none,

  /// 捕获 stdout 原文
  stdout,

  /// 捕获 stdout 并解析为 JSON
  json,
}

/// 捕获模式扩展方法
extension CaptureModeExtension on CaptureMode {
  /// 显示名称
  String get displayName {
    switch (this) {
      case CaptureMode.none:
        return '不捕获';
      case CaptureMode.stdout:
        return '文本';
      case CaptureMode.json:
        return 'JSON';
    }
  }

  /// 描述
  String get description {
    switch (this) {
      case CaptureMode.none:
        return '不捕获脚本输出';
      case CaptureMode.stdout:
        return '捕获标准输出作为文本';
      case CaptureMode.json:
        return '捕获标准输出并解析为 JSON';
    }
  }

  /// 从字符串解析
  static CaptureMode fromString(String value) {
    return CaptureMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CaptureMode.none,
    );
  }
}
