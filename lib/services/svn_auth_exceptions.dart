/// SVN 鉴权相关异常（独立模块，避免 svn_service 与 gate 循环依赖）。
library;

/// 远端 SVN 操作因缺少鉴权而失败时抛出；[needsAuth] 恒为 true。
class SvnAuthRequiredException implements Exception {
  final String url;
  final String message;

  const SvnAuthRequiredException({
    required this.url,
    this.message = '需要 SVN 鉴权',
  });

  bool get needsAuth => true;

  @override
  String toString() => 'SvnAuthRequiredException: $message ($url)';
}
