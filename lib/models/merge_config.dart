/// 合并配置模型。
///
/// 这里刻意把源配置和目标配置拆开：源永远是 SVN URL；目标则由互斥模式决定，
/// 避免在调用链里同时传递 `targetWc`、`targetUrl` 和布尔开关时串写。

/// 源配置。
class SourceConfig {
  final String url;

  const SourceConfig({required this.url});

  SourceConfig.normalized(String raw) : url = raw.trim();

  bool get isConfigured => url.trim().isNotEmpty;

  @override
  bool operator ==(Object other) => other is SourceConfig && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'SourceConfig(url: $url)';
}

/// 目标模式。
enum TargetMode {
  /// 使用用户提供的完整本地工作副本。
  fullWorkingCopy,

  /// 使用目标 SVN URL 自动创建临时精简工作副本。
  temporarySparseWorkingCopy,
}

/// 目标配置。
class TargetConfig {
  final TargetMode mode;
  final String workingCopyPath;
  final String svnUrl;
  final String? resolvedSvnUrl;

  const TargetConfig.fullWorkingCopy(String path)
      : mode = TargetMode.fullWorkingCopy,
        workingCopyPath = path,
        svnUrl = '',
        resolvedSvnUrl = null;

  const TargetConfig.sparseTemporary(String url)
      : mode = TargetMode.temporarySparseWorkingCopy,
        workingCopyPath = '',
        svnUrl = url,
        resolvedSvnUrl = url;

  const TargetConfig._resolvedFullWorkingCopy({
    required String path,
    required String resolvedUrl,
  })  : mode = TargetMode.fullWorkingCopy,
        workingCopyPath = path,
        svnUrl = '',
        resolvedSvnUrl = resolvedUrl;

  factory TargetConfig.fromLegacy({
    required String targetWc,
    String? targetUrl,
    required bool useTemporarySparseWorkingCopy,
  }) {
    if (useTemporarySparseWorkingCopy) {
      return TargetConfig.sparseTemporary(targetUrl ?? '');
    }
    return TargetConfig.fullWorkingCopy(targetWc);
  }

  bool get isFullWorkingCopy => mode == TargetMode.fullWorkingCopy;
  bool get isTemporarySparseWorkingCopy =>
      mode == TargetMode.temporarySparseWorkingCopy;

  bool get isConfigured {
    switch (mode) {
      case TargetMode.fullWorkingCopy:
        return workingCopyPath.trim().isNotEmpty;
      case TargetMode.temporarySparseWorkingCopy:
        return svnUrl.trim().isNotEmpty;
    }
  }

  /// 入队时写入旧字段 `targetWc` 的兼容值。
  String get jobTargetWc => isFullWorkingCopy ? workingCopyPath : '';

  /// 入队时写入旧字段 `targetUrl` 的兼容值。
  ///
  /// 完整工作副本模式下目标 URL 由调用方通过 `withResolvedTargetUrl` 补齐；
  /// 精简模式下该值就是用户配置的目标 SVN URL。
  String? get jobTargetUrl =>
      isTemporarySparseWorkingCopy ? svnUrl : resolvedSvnUrl;

  String get probeTarget => isFullWorkingCopy ? workingCopyPath : svnUrl;

  String get probeRole => isFullWorkingCopy ? '目标工作副本' : '目标 SVN URL';

  TargetConfig withResolvedTargetUrl(String resolvedUrl) {
    if (isTemporarySparseWorkingCopy) {
      return this;
    }
    return TargetConfig._resolvedFullWorkingCopy(
      path: workingCopyPath,
      resolvedUrl: resolvedUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TargetConfig &&
      other.mode == mode &&
      other.workingCopyPath == workingCopyPath &&
      other.svnUrl == svnUrl &&
      other.resolvedSvnUrl == resolvedSvnUrl;

  @override
  int get hashCode =>
      Object.hash(mode, workingCopyPath, svnUrl, resolvedSvnUrl);

  @override
  String toString() =>
      'TargetConfig(mode: $mode, workingCopyPath: $workingCopyPath, svnUrl: $svnUrl, resolvedSvnUrl: $resolvedSvnUrl)';
}
