/// SVN 失败原因分类与友好提示。
///
/// 把 SVN/svn-CLI 抛出的原始错误字符串归到一个**有限的枚举集合**，让暂停面板
/// 可以显示「分类标签 + 操作建议」而不是只甩原始日志。
///
/// 设计要点：
/// - 纯函数（不依赖 provider / context / 文件系统）；
/// - 模式匹配按"先精确（错误码）→ 后语义（关键词）→ 最后兜底（unknown）"
///   三段式，避免 `'conflict'` 关键词把 `tree conflict` 抢到 `textConflict`；
/// - 中文/英文关键词都识别（svn 默认英文，部分本地化版本会带中文）；
/// - 单测全覆盖每个 kind 的代表性错误样本，新增 kind 时强制扩展枚举与单测。
library;

/// SVN 失败原因分类。
///
/// 每个 kind 对应一类**用户角度可识别**的失败原因——不是 svn 错误码的镜像，
/// 而是"用户接下来该做什么"的归类。
enum SvnFailureKind {
  /// `svn: E195020` 等：tree conflict（目录/文件结构性冲突）。
  /// 通常需要人工到工作副本里 svn resolve 或手动恢复。
  treeConflict,

  /// 文本冲突（同行修改）；常见 marker：`Conflict discovered in`、`<<<<<<<`。
  /// 用户需要打开冲突文件手动合并。
  textConflict,

  /// `svn: E160028` 等：commit 时上游已更新，需要先 update 再 commit。
  /// 项目内 commit 步会自动重试 N 次，超限则归到本类。
  outOfDate,

  /// 服务端 pre-commit hook 要求提交信息包含 CRID / Code Review ID。
  /// 用户需要补充提交附加信息后继续 commit 步。
  missingCrid,

  /// 认证/授权失败：`svn: E170001`、`Authentication failed`、`Authorization failed`。
  /// 用户需要更新凭据或检查仓库权限。
  authFailed,

  /// 工作副本/路径被锁：`svn: E155004`、`is locked`、`run 'svn cleanup'`。
  /// 用户需要执行 svn cleanup 或解除外部进程占用。
  locked,

  /// 路径/资源不存在：`svn: E170000`、`Path not found`、`No such revision`。
  /// 通常是源 URL 配错、revision 不存在、或路径已被删除。
  notFound,

  /// 网络故障：`Connection refused`、`Could not connect`、`timed out`、`network is unreachable`。
  /// 用户需要检查 VPN / 仓库地址 / 防火墙。
  network,

  /// 工作副本损坏：`svn: E155017`、`is not a working copy`、`is missing or not a directory`。
  /// 用户通常需要重新 checkout。
  workingCopyCorrupt,

  /// 未识别的失败——所有不匹配上面分类的错误都归这里。UI 会显示原始错误正文。
  unknown,
}

/// `SvnFailureKind` 的 UI 展示信息：
/// - [label]：chip 上显示的中文短名（≤ 6 字）；
/// - [hint]：两到三句操作建议；
/// - [severity]：严重度，UI 用来选 chip 颜色（normal=橙、severe=红）。
class SvnFailurePresentation {
  final String label;
  final String hint;
  final SvnFailureSeverity severity;

  const SvnFailurePresentation({
    required this.label,
    required this.hint,
    required this.severity,
  });
}

enum SvnFailureSeverity {
  /// 用户能直接操作恢复（如 update、resolve）。橙色 chip。
  normal,

  /// 需要排查或修配置（如认证、网络、wc 损坏）。红色 chip。
  severe,
}

/// 静态映射——每个 kind 一行表项。
/// 故意写成顶层 const map（而非函数里的 switch）：单测可以直接遍历枚举验证
/// 「每个 kind 都有 presentation」，新增枚举值时编译器会在 missing entry 处
/// 报 missing key 警告（map literal 没编译期检查，所以靠单测兜底——
/// `presentationFor` 的 default 分支专门承载这个保证）。
const Map<SvnFailureKind, SvnFailurePresentation> _kPresentations = {
  SvnFailureKind.treeConflict: SvnFailurePresentation(
    label: '目录冲突',
    hint: '存在 tree conflict（文件被删/移/改名等）。请到工作副本手动 svn resolve 或恢复目录后再继续。',
    severity: SvnFailureSeverity.normal,
  ),
  SvnFailureKind.textConflict: SvnFailurePresentation(
    label: '内容冲突',
    hint: '存在文本冲突。请打开冲突文件（含 <<<<<<< 标记）手动合并后 svn resolve，再点继续。',
    severity: SvnFailureSeverity.normal,
  ),
  SvnFailureKind.outOfDate: SvnFailurePresentation(
    label: '版本过期',
    hint: '提交时仓库已被他人更新。可点继续重试（会自动 update 后重试 commit）；多次失败请提高重试上限。',
    severity: SvnFailureSeverity.normal,
  ),
  SvnFailureKind.missingCrid: SvnFailurePresentation(
    label: '缺少CRID',
    hint: '提交被服务端 Code Review 规则拦截。请补充 CRID / Code Review ID 后再点继续。',
    severity: SvnFailureSeverity.normal,
  ),
  SvnFailureKind.authFailed: SvnFailurePresentation(
    label: '认证失败',
    hint: '账号或权限不足。请检查 SVN 凭据是否过期，或确认对目标分支有提交权限。',
    severity: SvnFailureSeverity.severe,
  ),
  SvnFailureKind.locked: SvnFailurePresentation(
    label: '工作副本被锁',
    hint: '工作副本被锁。请关闭其它 SVN 客户端，或在工作副本目录执行 svn cleanup 后再继续。',
    severity: SvnFailureSeverity.normal,
  ),
  SvnFailureKind.notFound: SvnFailurePresentation(
    label: '路径不存在',
    hint: '源路径或 revision 不存在。请确认源分支 URL 与待合并 revision 是否正确。',
    severity: SvnFailureSeverity.severe,
  ),
  SvnFailureKind.network: SvnFailurePresentation(
    label: '网络异常',
    hint: '无法连接 SVN 服务器。请检查网络/VPN/仓库地址，恢复后点继续。',
    severity: SvnFailureSeverity.severe,
  ),
  SvnFailureKind.workingCopyCorrupt: SvnFailurePresentation(
    label: '工作副本损坏',
    hint: '工作副本不完整或不是合法的 SVN 目录。请重新 checkout 工作副本后再继续。',
    severity: SvnFailureSeverity.severe,
  ),
  SvnFailureKind.unknown: SvnFailurePresentation(
    label: '未分类',
    hint: '未识别的错误。请查看下方原始错误信息或日志面板进一步排查。',
    severity: SvnFailureSeverity.normal,
  ),
};

/// 取分类对应的 UI 展示信息。
///
/// **行为契约**：永远返回非 null（不在枚举里的 kind 会触发 dart 编译错误，
/// 所以这里 `!` 安全；但 default 路径仍兜底返回 unknown 的 presentation——
/// 单测显式覆盖每个 kind，确保 map 与 enum 同步）。
SvnFailurePresentation presentationFor(SvnFailureKind kind) =>
    _kPresentations[kind] ?? _kPresentations[SvnFailureKind.unknown]!;

/// 把任意 SVN 错误正文归到 [SvnFailureKind]。
///
/// **匹配优先级**（同一字符串可能含多个关键词时按此顺序裁定）：
/// 1. tree conflict（必须比 textConflict 先判，因为 'conflict' 同时匹配两者）；
/// 2. text conflict（含 `<<<<<<<` marker 或 'conflict' 但非 tree）；
/// 3. out-of-date（`E160028` 或 `out-of-date` / `out of date`）；
/// 4. missing CRID（`crid` / `code-review` / `code review` / `Code-Review-Rule`）；
/// 5. auth failed（`E170001` / authentication / authorization / 认证）；
/// 6. locked（`E155004` / 'is locked' / 'svn cleanup' / 锁定）；
/// 7. working copy corrupt（`E155017` / 'is not a working copy' / 'missing or not a directory'）；
/// 8. not found（`E170000` / 'not found' / 'no such revision' / '不存在'）；
/// 9. network（`Connection refused` / `Could not connect` / 'timed out' / '无法连接'）；
/// 10. unknown（兜底）。
///
/// 入参为 `null` / 空 / 仅空白 → unknown。
SvnFailureKind classifySvnFailure(String? errorMessage) {
  if (errorMessage == null) return SvnFailureKind.unknown;
  final raw = errorMessage.trim();
  if (raw.isEmpty) return SvnFailureKind.unknown;
  final lower = raw.toLowerCase();

  // 1. tree conflict（先于普通 conflict）
  if (lower.contains('tree conflict') ||
      lower.contains('e195020') ||
      lower.contains('目录冲突')) {
    return SvnFailureKind.treeConflict;
  }

  // 2. text conflict
  if (lower.contains('<<<<<<<') ||
      lower.contains('conflict discovered') ||
      lower.contains('text conflict') ||
      lower.contains('文本冲突') ||
      lower.contains('冲突')) {
    return SvnFailureKind.textConflict;
  }
  // 含 'conflict' 但又不是 tree——也归 textConflict
  if (lower.contains('conflict')) {
    return SvnFailureKind.textConflict;
  }

  // 3. out-of-date
  if (lower.contains('e160028') ||
      lower.contains('out-of-date') ||
      lower.contains('out of date')) {
    return SvnFailureKind.outOfDate;
  }

  // 4. missing CRID / Code Review ID
  if (lower.contains('crid') ||
      lower.contains('code-review') ||
      lower.contains('code review') ||
      lower.contains('codereview') ||
      lower.contains('review id') ||
      lower.contains('code-review-rule')) {
    return SvnFailureKind.missingCrid;
  }

  // 5. auth
  if (lower.contains('e170001') ||
      lower.contains('e170013') && lower.contains('auth') ||
      lower.contains('authentication failed') ||
      lower.contains('authorization failed') ||
      lower.contains('access denied') ||
      lower.contains('认证失败') ||
      lower.contains('授权失败') ||
      lower.contains('权限不足')) {
    return SvnFailureKind.authFailed;
  }

  // 6. locked（注意先于 working-copy-corrupt 匹配，因为 'svn cleanup' 通常是锁信号）
  if (lower.contains('e155004') ||
      lower.contains('is locked') ||
      lower.contains('run \'svn cleanup\'') ||
      lower.contains('run "svn cleanup"') ||
      lower.contains('svn cleanup') ||
      lower.contains('已被锁定') ||
      lower.contains('被锁')) {
    return SvnFailureKind.locked;
  }

  // 7. wc corrupt
  if (lower.contains('e155017') ||
      lower.contains('e155009') ||
      lower.contains('is not a working copy') ||
      lower.contains('missing or not a directory') ||
      lower.contains('不是有效的工作副本')) {
    return SvnFailureKind.workingCopyCorrupt;
  }

  // 8. not found
  if (lower.contains('e170000') ||
      lower.contains('e160013') ||
      lower.contains('path not found') ||
      lower.contains('no such revision') ||
      lower.contains('not found') ||
      lower.contains('does not exist') ||
      lower.contains('不存在')) {
    return SvnFailureKind.notFound;
  }

  // 9. network
  if (lower.contains('connection refused') ||
      lower.contains('could not connect') ||
      lower.contains('connection timed out') ||
      lower.contains('timed out') ||
      lower.contains('network is unreachable') ||
      lower.contains('unable to connect') ||
      lower.contains('无法连接') ||
      lower.contains('连接超时') ||
      lower.contains('网络不可达')) {
    return SvnFailureKind.network;
  }

  return SvnFailureKind.unknown;
}
