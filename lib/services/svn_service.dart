/// SVN 操作服务 - 统一封装所有 SVN 命令
///
/// 此类提供了所有 SVN 操作的统一入口，包括：
/// - 基础命令：log, merge, commit, update, revert, cleanup
/// - 查询命令：info, status, mergeinfo, propget
/// - 错误处理：统一的错误处理和日志输出
///
/// **重要：SVN 鉴权管理**
/// - SVN 鉴权完全依赖 SVN 自身管理，本项目不存储用户名和密码
/// - 当需要认证时，SVN 会通过系统机制（如 Keychain）提示用户输入
/// - 本项目不再提供应用内凭证对话框，直接复用系统已有的 SVN 凭证缓存

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/process_output_decoder.dart';
import 'log_filter_service.dart' show appLogSeparator;
import 'logger_service.dart';
import 'svn_xml_parser.dart';

/// 判断 SVN 命令行的 [username] / [password] 凭据是否「值得加到 args」。
///
/// **核心契约**：仅当 [credential] 非 null **且** 非空字符串时返回 true。
///
/// **为什么这个谓词单独抽**：原 `buildSvnCliArgs` 在 username / password 两处
/// 各内联了一句 `cred != null && cred.isNotEmpty`——两处共享同一份"空串视作未提供凭据"
/// 决策（与本文件文档注释 line 29 显式声明的"`isNotEmpty` 判定，空串视作未提供凭据"
/// 契约一致）。任何一处把 `&&` 误改成 `||`、或把 `isNotEmpty` 漏掉，都会让
/// `--username ''` 或 `--password ''` 进入 svn 进程参数——SVN 收到空串凭据会
/// 直接报错（"authentication failed"）而非走系统凭据缓存，破坏 line 8-11 文档
/// 声明的"完全依赖 SVN 自身管理凭据"设计。
///
/// **为什么不复用 [isUsableSourceUrl] 或 [isUsableWorkingDirectory]**：三者签名同形
/// （`String? -> bool`），实现也完全相同（`!= null && isNotEmpty`），但**语境
/// 完全不同**——
/// - [isUsableSourceUrl]（app_state.dart）：是否值得调 `refreshLogEntries`；
/// - [isUsableWorkingDirectory]（log_filter_service.dart）：是否值得用作 SVN
///   缓存键；
/// - 本谓词：是否值得加到 svn CLI args 的 `--username/--password` 段。
///
/// 跨模块复用一个 `isUsableNonEmptyString` 之类的通名 helper 会让 callsite 失去
/// 语义自描述能力（"这次到底防的是哪种空？"），按设计模式 #9 拒绝合并。
@visibleForTesting
bool isUsableSvnCredential(String? credential) =>
    credential != null && credential.isNotEmpty;

/// 拼接最终调用 `Process.run` 用的 svn 命令行参数。
///
/// 顺序（与原 `_buildSvnArgs` 完全一致）：
/// 1. `svnPath`（绝对路径或 `'svn'`）
/// 2. 仅当 `username` 非空时追加 `--username <username>`
/// 3. 仅当 `password` 非空时追加 `--password <password>`
/// 4. 始终追加 `--non-interactive`，让 SVN 直接复用系统已缓存凭据
/// 5. 最后追加 `baseArgs`
///
/// 与生产逻辑一致地使用"非空"判定（`isNotEmpty`），空串视作未提供凭据。
@visibleForTesting
List<String> buildSvnCliArgs({
  required String svnPath,
  required List<String> baseArgs,
  String? username,
  String? password,
}) {
  final args = <String>[svnPath];
  if (isUsableSvnCredential(username)) {
    args.addAll(['--username', username!]);
  }
  if (isUsableSvnCredential(password)) {
    args.addAll(['--password', password!]);
  }
  args.add('--non-interactive');
  args.addAll(baseArgs);
  return args;
}

/// `injectXmlFlag` 的纯决策结果。
///
/// - [args]：注入处理之后应该传给 `_buildSvnArgs` 的 base 参数；
/// - [didInsert]：是否真的插入了 `--xml`；
/// - [suppressedCommand]：useXml=true 但命令在黑名单里时的命令名，
///   非 null 表示需要打 "命令 X 不支持 --xml" 的警告日志。
@visibleForTesting
class XmlInjectionResult {
  final List<String> args;
  final bool didInsert;
  final String? suppressedCommand;

  const XmlInjectionResult({
    required this.args,
    required this.didInsert,
    required this.suppressedCommand,
  });
}

/// 决定是否在 svn 子命令后插入 `--xml`，并返回新的参数列表。
///
/// 规则（与原内联逻辑严格一致）：
/// - `useXml=false` → 原样返回 [args]，不插入；
/// - `useXml=true` 但 [args] 已经包含 `--xml` → 不重复插入；
/// - `useXml=true` 且子命令（args[0]）在 [xmlBlacklist] 中 → 不插入，
///   并在 [XmlInjectionResult.suppressedCommand] 中带回命令名让调用方打日志；
/// - 其它情况：在第 1 位（紧跟子命令后）插入 `--xml`。
///
/// 不会修改入参。
@visibleForTesting
XmlInjectionResult injectXmlFlag(
  List<String> args, {
  required bool useXml,
  required Set<String> xmlBlacklist,
}) {
  if (!useXml) {
    return XmlInjectionResult(
      args: List<String>.from(args),
      didInsert: false,
      suppressedCommand: null,
    );
  }
  final out = List<String>.from(args);
  if (out.contains('--xml')) {
    return XmlInjectionResult(
      args: out,
      didInsert: false,
      suppressedCommand: null,
    );
  }
  final command = out.isNotEmpty ? out[0] : '';
  if (xmlBlacklist.contains(command)) {
    return XmlInjectionResult(
      args: out,
      didInsert: false,
      suppressedCommand: command,
    );
  }
  out.insert(1, '--xml');
  return XmlInjectionResult(
    args: out,
    didInsert: true,
    suppressedCommand: null,
  );
}

/// 把字符串裁短到 [maxLen] 字符以内，超过则尾部加 `...`。
///
/// 用于失败日志里的 stdout 预览。`maxLen` 默认 200，与原行内逻辑一致；
/// 注意 `...` 不计入 `maxLen`，因此最长输出为 `maxLen + 3`。
@visibleForTesting
String truncateForLog(String text, {int maxLen = 200}) {
  if (text.length <= maxLen) return text;
  return '${text.substring(0, maxLen)}...';
}

/// 渲染 SVN 命令输出摘要日志：`(XML 输出: N 行, M 字符)` 或 `(输出: ...)`。
@visibleForTesting
String formatSvnOutputSummary({
  required int lines,
  required int size,
  required bool useXml,
}) {
  final label = useXml ? 'XML 输出' : '输出';
  return '($label: $lines 行, $size 字符)';
}

/// 渲染 [SvnException.toString] 的多行消息。提取为纯函数便于断言格式。
@visibleForTesting
String formatSvnExceptionMessage({
  required String message,
  String? command,
  int? exitCode,
  String output = '',
}) {
  final buffer = StringBuffer('SvnException: $message');
  if (command != null) {
    buffer.write('\nCommand: $command');
  }
  if (exitCode != null) {
    buffer.write('\nExit code: $exitCode');
  }
  if (output.isNotEmpty) {
    buffer.write('\nOutput: $output');
  }
  return buffer.toString();
}

/// 把 [SvnService.probeSvnLocation] 内部捕获的异常翻译成给用户看的一句话错误。
///
/// **为什么抽**：probe 发生在 `_startMerge` 入口（用户刚点"开始合并"）——错误
/// 必须在 SnackBar 一行内说清"是什么问题"，不能直接把 `SvnException.toString()`
/// 那种多行 `Command/Exit code/Output` 块塞给用户。
///
/// **三档分支**：
/// 1. `SvnException` + 输出含鉴权关键词（[svnOutputNeedsAuth]）→ `'<role> 校验失败：需要 SVN 凭据，请在设置中配置'`。
/// 2. `SvnException` 其他 → `'<role> 校验失败：<message>'`（仅取 `e.message`，丢弃 command/exitCode/output 三段）。
/// 3. 其他类型异常 → `'<role> 校验失败：<error>'`（toString 兜底）。
///
/// **role 入参**：`'源 URL'` / `'目标工作副本'`，由 caller 决定文案语境，避免
/// 错误信息抽象化（用户更想知道是哪一项配错了，而不是"SVN 校验失败"）。
@visibleForTesting
String formatProbeFailureReason({
  required String role,
  required Object error,
}) {
  if (error is SvnException) {
    if (svnOutputNeedsAuth(error.output)) {
      return '$role 校验失败：需要 SVN 凭据，请在设置中配置';
    }
    return '$role 校验失败：${error.message}';
  }
  return '$role 校验失败：$error';
}

/// 判断 SVN 命令输出是否提示需要鉴权。匹配几个常见英文短语的小写子串。
@visibleForTesting
bool svnOutputNeedsAuth(String output) {
  final lower = output.toLowerCase();
  return lower.contains('authorization failed') ||
      lower.contains('authentication') ||
      lower.contains('could not authenticate') ||
      lower.contains('no more credentials');
}

/// 渲染 `_runSvnCommand` 入口的"开始执行"日志正文行。
///
/// 与原内联拼接（`_log('[SVN 命令执行] svn $displayArgs$authInfo$xmlInfo$workingDirInfo')`）严格等价。
///
/// **契约**：
/// - 始终以 `'[SVN 命令执行] svn '` + `displayArgs` 起头。
/// - `username == null` 不追加 `--username` 段；`username` 非 null（**包括空串**）
///   时追加 ` --username $username --password ****`——与原 `username != null`
///   判定保持一致；`_runSvnCommand` 上层入参遵循"非 null 即视为有提供凭据"的
///   语义，由 `buildSvnCliArgs` 在最终调用 svn 时再做 `isNotEmpty` 收紧。日志
///   行作为审计手段，**保留这种"username 给了空串"的可见性**而不是静默吞掉。
/// - 密码**永远显示成 `****`**——只要 `username != null` 就跟着追加 ` --password ****`，
///   不管 password 真实值；防止真实密码被打印到日志里。这是**安全决策**，**不要**
///   改成"只在 password 非空时才打印 ****"——那会让"用户名给了但密码忘填"这种
///   错误从日志里彻底消失。
/// - `useXml` 为 true 时追加 `' [XML 输出]'`，否则不追加。
/// - `workingDirectory != null` 时追加 `' (工作目录: <wd>)'`，**不**做 `isEmpty` 判定
///   （空字符串走原 `!= null` 分支，与原行为一致；上层 `_runSvnCommand` 不传空串）。
/// - 4 段拼接顺序固定：`displayArgs` → `authInfo` → `xmlInfo` → `workingDirInfo`。
@visibleForTesting
String formatSvnCommandStartLine({
  required String displayArgs,
  required String? username,
  required bool useXml,
  required String? workingDirectory,
}) {
  final authInfo =
      username != null ? ' --username $username --password ****' : '';
  final xmlInfo = useXml ? ' [XML 输出]' : '';
  final workingDirInfo =
      workingDirectory != null ? ' (工作目录: $workingDirectory)' : '';
  return '[SVN 命令执行] svn $displayArgs$authInfo$xmlInfo$workingDirInfo';
}

/// 渲染 `_runSvnCommand` 成功路径的结果行。
///
/// **契约**：固定模板 `'✓ SVN 命令执行成功 (退出码: <c>, 耗时: <ms>ms)'`；
/// `durationMs` 走纯 int 渲染，**不**做 ">= 1000ms 转秒" 之类的格式化（保持
/// 与原代码 `${duration.inMilliseconds}ms` 一致，且方便机读断言）。
@visibleForTesting
String formatSvnSuccessLine({
  required int exitCode,
  required int durationMs,
}) =>
    '✓ SVN 命令执行成功 (退出码: $exitCode, 耗时: ${durationMs}ms)';

/// 渲染 `_runSvnCommand` 失败路径的结果首行（不含后续 `命令: / 错误: / 输出:` 三行）。
///
/// **契约**：固定模板 `'✗ SVN 命令执行失败 (退出码: <c>, 耗时: <ms>ms)'`；与
/// [formatSvnSuccessLine] 对称，仅首字符 `✗` / `✓` 不同——单测显式锁定这两个
/// 字符的区分。
@visibleForTesting
String formatSvnFailureLine({
  required int exitCode,
  required int durationMs,
}) =>
    '✗ SVN 命令执行失败 (退出码: $exitCode, 耗时: ${durationMs}ms)';

/// `findBranchPoint` 入口的 3 行启动 dump（不含命令行那行——命令行是动态构造、
/// 走原 `_log('  命令: ...')` 不进本函数）。
///
/// **契约**：3 行顺序固定（标题 / 分支 URL / 工作目录）；标题恒为
/// `'【SvnService.findBranchPoint】查找分支点'` 且**不带缩进**；2 个数据行带
/// `'  '` 前缀（与 `formatRefreshLogEntriesHeaderLines` 同构）。
/// `workingDirectory == null` → `'未指定'`（与原 `?? "未指定"` 一致）。
@visibleForTesting
List<String> formatFindBranchPointHeaderLines({
  required String branchUrl,
  required String? workingDirectory,
}) {
  return [
    '【SvnService.findBranchPoint】查找分支点',
    '  分支 URL: $branchUrl',
    '  工作目录: ${workingDirectory ?? "未指定"}',
  ];
}

/// 渲染 `findBranchPoint` 末尾的结果行（"找到 r$X" 或 "未找到"）。
///
/// **契约**：
/// - `branchPoint != null` → `'  ✓ 找到分支点: r$branchPoint'`（两空格缩进 +
///   `✓` + 空格）。
/// - `branchPoint == null` → `'  ⚠ 未找到分支点'`（两空格缩进 + `⚠`）。
/// - **不**做 `branchPoint <= 0` 防御——SVN 的 revision 永远 >= 1，0/负值 by
///   contract 不会出现；如果出现是 SVN 输出异常，应该让上层错误暴露。
@visibleForTesting
String formatBranchPointResultLine(int? branchPoint) {
  if (branchPoint == null) {
    return '  ⚠ 未找到分支点';
  }
  return '  ✓ 找到分支点: r$branchPoint';
}

/// 把 SVN 路径参数翻译成 `_runSvnCommand` 的 `workingDirectory` 入参。
///
/// **契约**：仓库 URL（`http://` / `https://` / `svn://` / `svn+ssh://` /
/// `file://`）返回 `null`（让命令在当前 cwd 执行，不切换工作目录）；本地路径原样返回。
///
/// 这条决策在 `getInfo` / `isRevisionMerged` 等 SVN URL 调用点共用，避免把
/// `svn://...` 误当成本地 cwd（Windows/macOS 上都会导致 Process.run 以非法
/// workingDirectory 启动）。
///
/// **不做的事**：不做 trim、不做大小写转换（`'HTTP://x'` 不算 URL，会被当作本地路径）、
/// 不验证 URL 合法性。SVN 命令行本身的 URL 解析就是大小写敏感，本守卫与 caller 约定一致。
bool isSvnRepositoryUrl(String path) {
  return path.startsWith('http://') ||
      path.startsWith('https://') ||
      path.startsWith('svn://') ||
      path.startsWith('svn+ssh://') ||
      path.startsWith('file://');
}

@visibleForTesting
String? svnPathToWorkingDirectory(String path) {
  return isSvnRepositoryUrl(path) ? null : path;
}

/// SVN mergeinfo 的目标既可以是仓库 URL，也可以是本地工作副本路径。
///
/// URL 目标必须让 `_runSvnCommand` 在默认 cwd 下执行；否则 `Process.run` 会把
/// `svn://...` / `https://...` 当成本地 workingDirectory，命令在启动前就失败。
@visibleForTesting
String? svnMergeinfoTargetToWorkingDirectory(String target) {
  return svnPathToWorkingDirectory(target);
}

/// 扫 `svn status` 文本输出，判断是否存在冲突标记。
///
/// **契约 — SVN status 输出格式**：每行第一列是状态码（`M`/`A`/`D`/`C`/...），
/// 其中 `C` = conflicted。本函数仅看**首字母**——不是 `contains('C')`、不是 `startsWith('C ')`。
/// 这样能避免：（1）误把 `'M'` 后包含 'C' 的文件名（如 `M  hello.cpp`）当作冲突；
/// （2）误把 `'      C'`（前面有空格的 SVN 状态续行）当作冲突。
///
/// **空行跳过**——SVN 输出末尾常带空行，`line[0]` 在空字符串上会抛 RangeError。
///
/// 输入空字符串 / 全空行 / 没有 C 起首的行 → false。一旦发现任意一行 `line[0] == 'C'` → true（短路）。
///
/// **不做的事**：不区分 'C'（属性 / 内容冲突）和 'C ' 后第二列的 'C'（属性冲突）等
/// SVN 8 个细分状态——caller 只关心"有没有冲突"这一条决策。
@visibleForTesting
bool svnStatusOutputHasConflict(String statusOutput) {
  for (final line in statusOutput.split('\n')) {
    if (line.isNotEmpty && line[0] == 'C') {
      return true;
    }
  }
  return false;
}

/// 扫 `svn status` 文本输出，提取所有"内容冲突"行的相对路径列表。
///
/// **契约**：与 [svnStatusOutputHasConflict] 同一份解析规则的列表化版本——
/// - 仅 `line[0] == 'C'` 的行被纳入（不看第二列的属性冲突，与 hasConflict 保持一致）；
/// - SVN status 单字符状态行的第 7 列（索引 7）起为路径——`'C       conflict.txt'`
///   的状态部分占 7 个字符（1 列状态码 + 6 列其他元信息）。本 helper 用 `substring(7).trim()`
///   提路径，再用 `.isNotEmpty` 过滤——空字符串 / 只剩空白的行被丢弃；
/// - 单字符行 `'C'`（line.length < 8）→ `substring(7)` 抛 RangeError，故先判
///   `line.length >= 8` 再切；不满足直接跳过（无可解析路径）；
/// - 空字符串 / 全空行 / 没 C 起首的行 → 返回空 list；
/// - 顺序保留 SVN 输出的原始顺序——caller 可放心取 `first` 当作"用户最先要看的冲突文件"。
///
/// **不做的事**：不做绝对路径解析（caller 用 `p.join(targetWc, relative)` 自己拼接）；
/// 不做文件存在性检查（开文件交给 OS）；不区分文件 / 目录冲突（caller 看到路径自行决定）。
///
/// **与 [svnStatusOutputHasConflict] 共存原因**：那个是 bool 短路（hasConflicts() 用），
/// 这个返回路径列表（listConflictedFiles() / 打开冲突文件 用）；语义不同、调用频次也不同——
/// 频繁的 hasConflict 检查走短路 bool 更便宜，少量的 list 用全量扫。
@visibleForTesting
List<String> parseConflictedFiles(String statusOutput) {
  final result = <String>[];
  for (final line in statusOutput.split('\n')) {
    if (line.isEmpty || line[0] != 'C') continue;
    if (line.length < 8) continue; // 'C' 单字符等无路径行
    final path = line.substring(7).trim();
    if (path.isEmpty) continue;
    result.add(path);
  }
  return result;
}

/// 扫 `svn status` 文本输出，统计本次合并实际影响的文件数（条目数）。
///
/// **契约 — 用于"合并完成时给用户反馈实际改动数"**：
/// - 每个非空行视为一个被影响的条目（修改 / 新增 / 删除 / 冲突 / 属性变更等）；
/// - 不区分状态码（M/A/D/C/G/U/R/!/?/~ 等都计入）——caller 只想知道"这次合并到底干了多少事"；
/// - 0 行 = 空合并（svn merge 接受了 revision 但没有产生任何工作副本差异，例如自合并 / 已合并过 /
///   仅 mergeinfo 属性变更 cherry-pick 同分支历史 commit 等场景）；
/// - 跳过空行（SVN 输出末尾常带空行，避免被误计）。
///
/// **不做的事**：不解析路径、不分类状态、不区分文件 vs 目录、不计 mergeinfo 属性变更
/// （`svn status` 输出里 ` M ...` 第二列 'M' 的属性变更行仍计入，因为它们对应到 `.` 本身的
/// mergeinfo 记录，从用户视角"这次合并改了什么"角度看属于"改了 1 处属性"）。
///
/// 这与 [parseConflictedFiles] / [svnStatusOutputHasConflict] 是同一份 status 输出的不同维度
/// （那两个看 'C'，本 helper 看"非空行"），三者互不重复——但本 helper 在 merge_execution_state
/// 的 `_runMergeStep` 内被独立调用：listConflictedFiles 已经跑了一次 status，本次再跑一次
/// 是为了避免破坏 listConflictedFiles 的契约（只返路径列表，加 statusOutput 字段是 breaking
/// change）；一次 status ~40ms 量级，相对 svn merge 远程调用可忽略。
@visibleForTesting
int parseChangedFilesCount(String statusOutput) {
  var count = 0;
  for (final line in statusOutput.split('\n')) {
    if (line.isEmpty) continue;
    count++;
  }
  return count;
}

/// 解析 `svn mergeinfo --show-revs merged` 的文本输出，提取所有已合并的 revision。
///
/// **契约 — 输出格式**：每个 revision 形如 `rNNNN`，可能多行（每行一个）也可能同一行（用空白分隔）。
/// 用 `RegExp(r'r(\d+)')` **全局匹配**——不解析行结构、不假设分隔符。
///
/// 返回 `Set<int>`（不是 List）——caller 通常做 `.contains(rev)` 查询，Set 适配；
/// 同时去重——同一个 revision 被 mergeinfo 重复列出（例如多次合并到同一目标）只算一次。
///
/// `int.tryParse` 失败的项被丢弃（理论上正则保证 `\d+` 不会失败，但配合 `.where(r != null)` 让
/// nullable 路径不抛异常——纯防御）。
///
/// **不做的事**：不验证 revision 的合理性（如 `r0` 也会被收）；不区分 source / target；
/// 不解析 mergeinfo 头部行（如 'Path:'）——正则只匹配 `r\d+` 模式，无关行天然过滤。
///
/// 该决策在 `isRevisionMerged` / `checkMergedStatus` / `getAllMergedRevisions` **三处**
/// inline 重复（同款 RegExp + 同款 cast 链）；R0~R6 早期抽出本 helper 时漏迁了
/// `getAllMergedRevisions` 那一处，R85 补迁完成。现在 svn_service.dart 内全部 3 个
/// mergeinfo 文本输出 caller 都走本 helper——任何 RegExp 调整或 `int.tryParse` 行为
/// 变更只需改本函数一处。
@visibleForTesting
Set<int> parseMergedRevisions(String mergeinfoOutput) {
  final revisionPattern = RegExp(r'r(\d+)');
  return revisionPattern
      .allMatches(mergeinfoOutput)
      .map((m) => int.tryParse(m.group(1)!))
      .where((r) => r != null)
      .cast<int>()
      .toSet();
}

/// `buildSvnLogArgs` 的纯决策结果。
///
/// - [args]：传给 `_runSvnCommand` 的参数列表（不含 'svn' 前缀，含 `useXml` 走外层注入）。
/// - [logHint]：提供给 `_log` 的一行人类可读描述，与 args 的 3 个分支一一对应。
///   分离这一字段是为了让 caller **同时**拿到「命令」和「描述」，避免在 caller 里
///   重复一次三分支判断。
@visibleForTesting
class SvnLogArgsPlan {
  final List<String> args;
  final String logHint;

  const SvnLogArgsPlan({required this.args, required this.logHint});
}

/// 构造 `svn log` 的命令参数与描述行。
///
/// **三分支契约**（与原 inline 严格 1:1）：
/// - `startRevision == null` → `[log, url, -l, $limit]`，`logHint = '从最新开始读取
///   $limit 条日志（不限制版本范围）'`；
/// - `startRevision != null && reverseOrder == true` → `[log, url, -r, '$startRev:1',
///   -l, $limit]`，`logHint = '从 r$startRev 向更旧版本读取'`；
/// - `startRevision != null && reverseOrder == false` → `[log, url, -r,
///   '$startRev:HEAD', -l, $limit]`，`logHint = '从 r$startRev 向 HEAD 读取'`。
///
/// **故意不**做的事：
/// - 不校验 `limit > 0`（caller 是 `Future<String> log(...)`，签名给了默认 200，
///   传 0 是 caller 的责任，底层不防御性兜底）；
/// - 不校验 url 非空（同理，UI 层负责）；
/// - 不在 reverseOrder=true 时忽略 startRevision（**reverseOrder 仅当 startRevision
///   非 null 才有意义**——单测显式锁定 startRevision==null 时 reverseOrder 取值不影响输出）。
@visibleForTesting
SvnLogArgsPlan buildSvnLogArgs({
  required String url,
  required int limit,
  required int? startRevision,
  required bool reverseOrder,
}) {
  final args = ['log', url];
  if (startRevision == null) {
    args.addAll(['-l', limit.toString()]);
    return SvnLogArgsPlan(
      args: args,
      logHint: '从最新开始读取 $limit 条日志（不限制版本范围）',
    );
  }
  if (reverseOrder) {
    args.addAll(['-r', '$startRevision:1', '-l', limit.toString()]);
    return SvnLogArgsPlan(
      args: args,
      logHint: '从 r$startRevision 向更旧版本读取',
    );
  }
  args.addAll(['-r', '$startRevision:HEAD', '-l', limit.toString()]);
  return SvnLogArgsPlan(
    args: args,
    logHint: '从 r$startRevision 向 HEAD 读取',
  );
}

/// 构造 `svn merge -c` 的命令参数。
///
/// **契约**：
/// - 基础形态：`[merge, -c, $revision, $sourceUrl, .]`；
/// - `dryRun == true` → 在 **index 1** 插入 `'--dry-run'`，最终：
///   `[merge, --dry-run, -c, $revision, $sourceUrl, .]`。
///
/// **位置敏感**：`--dry-run` 必须紧跟在 `merge` 之后（index 1），不能放最末尾——
/// SVN CLI 解析器虽然容忍尾部 flag，但 caller 已经依赖这个固定位置在日志/UI
/// 显示时高亮 dry-run 标记。单测显式锁定 index。
@visibleForTesting
List<String> buildSvnMergeArgs({
  required String sourceUrl,
  required int revision,
  required bool dryRun,
}) {
  final args = ['merge', '-c', revision.toString(), sourceUrl, '.'];
  if (dryRun) {
    // R124 mutator 二档判据：`args.insert(1, '--dry-run')` 是 List.insert **档 1**
    // ——index ≡ 1 是**常量字面量**，由 SVN CLI 位置敏感约束决定（必须紧跟
    // 'merge' sub-command 才能被 SVN 识别为 merge 的 flag）。这是 R106 CLI 位置
    // 敏感性 doc 化的姊妹——R106 锁"flag 必须紧跟 sub-command"的协议契约，R124
    // 从 mutator 视角锁"insert(1, ...) index 1 是常量"的结构契约。同模式 callsite
    // 还有 svn_service.dart `args.insert(1, '--show-item')` + `args.insert(2, item)`
    // (buildSvnInfoArgs) 与 svn_service.dart `out.insert(1, '--xml')`（XML 注入）。
    args.insert(1, '--dry-run');
  }
  return args;
}

/// 构造 `svn revert` 的命令参数。
///
/// **契约**：
/// - `recursive == true` → `[revert, -R, .]`；
/// - `recursive == false` → `[revert, .]`。
///
/// **不**支持 path 参数——所有 caller 都在 `workingDirectory: targetWc` 下执行
/// `revert .`（恢复整个工作副本根）。如果将来需要 revert 单个文件，**新加 caller
/// 不应该改这个函数**——而是新建 `buildSvnRevertPathArgs(...)`，避免本函数签名
/// 因为可选 path 而出现"recursive 为 true 时 path 必须给某种值"这种隐性耦合。
@visibleForTesting
List<String> buildSvnRevertArgs({required bool recursive}) {
  return recursive ? ['revert', '-R', '.'] : ['revert', '.'];
}

/// 构造 `svn switch <url> .` 的命令参数。
///
/// 工作目录由 caller 设置为目标工作副本根，参数里的 `.` 表示切换整个工作副本。
@visibleForTesting
List<String> buildSvnSwitchArgs({required String url}) {
  return ['switch', url, '.'];
}

/// 构造 `svn list <url>` 的命令参数。
///
/// 用于在线浏览仓库目录；输出保持 SVN 文本格式，目录项通常以 `/` 结尾。
@visibleForTesting
List<String> buildSvnListArgs({required String url}) {
  return ['list', url];
}

/// 解析 `svn list` 文本输出，过滤空行并保留 SVN 返回的条目名称。
@visibleForTesting
List<String> parseSvnListOutput(String output) {
  return output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// SVN `svn resolve --accept <mode>` 的 mode 枚举。
///
/// **4 种 mode 语义**（来自 SVN 官方 `svn help resolve`）：
/// - [working]：保留工作副本的当前内容（含手工编辑结果），把冲突标记清掉；
///   一键 P0 默认按钮使用此模式——用户已经在 `打开冲突文件` 后手动改完了。
/// - [mineFull]：用我方分支的整个文件覆盖工作副本，丢弃 incoming 的所有改动；
///   适用于"完全确定不要对方这次的改动"——慎用。
/// - [theirsFull]：用对方（incoming）分支的整个文件覆盖工作副本，丢弃我方所有改动；
///   适用于"完全采纳对方版本"——慎用。
/// - [base]：恢复到合并发生前的 BASE 版本（既不要我方改动，也不要对方改动）；
///   语义最破坏性，几乎只有"这次合并完全错了，撤回到原状"才用。
///
/// **CLI flag 映射**：通过 [cliFlag] 序列化为 SVN CLI 期望的 `working` /
/// `mine-full` / `theirs-full` / `base` 字面量；序列化与 CLI 解析层强绑定，
/// 不经过 enum.name（enum.name 是 camelCase，SVN 期望 kebab-case，不一致）。
enum SvnResolveAccept {
  working,
  mineFull,
  theirsFull,
  base;

  /// SVN CLI `--accept` 期望的字面量。
  ///
  /// **强契约**：与 SVN CLI 对接，任何拼写改动都会让 svn 进程报
  /// `svn: E... invalid 'accept' ARG`。修改前必须同步更新单测。
  String get cliFlag {
    switch (this) {
      case SvnResolveAccept.working:
        return 'working';
      case SvnResolveAccept.mineFull:
        return 'mine-full';
      case SvnResolveAccept.theirsFull:
        return 'theirs-full';
      case SvnResolveAccept.base:
        return 'base';
    }
  }
}

/// 构造 `svn resolve --accept <mode> -R .` 的命令参数。
///
/// **契约 — 固定 5 元素**（顺序敏感）：`[resolve, --accept, <mode.cliFlag>, -R, .]`。
///
/// **mode 语义对比**（详见 [SvnResolveAccept] 文档）：
/// - `working`：保留 WC 当前内容，把冲突标记清掉（一键场景默认）；
/// - `mine-full` / `theirs-full`：粗粒度二选一，覆盖整个文件，需用户明确选择；
/// - `base`：恢复到合并前 BASE 版本，最破坏性。
///
/// **为什么强制 `-R` 递归**：暂停态多文件冲突常见（merge 把若干文件标 conflict），
/// 用户已经在 `打开工作副本目录` 后逐文件 resolve 完，按钮应该是"全部一并标记"，
/// 而不是"只标当前目录顶层文件"。
///
/// **路径用 `.`**：与 [buildSvnRevertArgs] 同款约定——caller (`SvnService.resolveAccept`)
/// 用 `workingDirectory: targetWc` 进入工作副本根，再以 `.` 作为参数；避免在
/// args 里直接拼绝对路径，从而绕过 `_runSvnCommand` 的 cwd 切换。
@visibleForTesting
List<String> buildSvnResolveArgs(SvnResolveAccept mode) {
  return ['resolve', '--accept', mode.cliFlag, '-R', '.'];
}

/// 构造 `svn info` 的命令参数。
///
/// **契约**：
/// - 基础形态：`[info, $path]`；
/// - `item != null` → 在 **index 1** 与 **index 2** 分别插入 `'--show-item'` 与 `item`，
///   最终：`[info, --show-item, $item, $path]`。
///
/// **位置敏感**：`--show-item` 与 item 的相对顺序固定（flag 在前、值在后，是
/// SVN CLI 的强约束），且必须紧跟在 `info` 之后；caller 依赖这个固定形态来匹配
/// 测试桩输出。
///
/// **不**做的事：
/// - 不校验 `item` 是否在 SVN 支持的列表里（'url' / 'revision' / 'last-changed-revision'
///   等等）——SVN 自己会在执行时报错，比在这里维护一份白名单更可靠。
@visibleForTesting
List<String> buildSvnInfoArgs({
  required String path,
  required String? item,
}) {
  final args = ['info', path];
  if (item != null) {
    args.insert(1, '--show-item');
    args.insert(2, item);
  }
  return args;
}

/// 构造 `svn mergeinfo --show-revs merged <sourceUrl> <target>` 的命令参数。
///
/// **契约 — 固定 5 元素**（顺序敏感）：
/// `[mergeinfo, --show-revs, merged, sourceUrl, target]`。
///
/// **为什么 [target] 是 String 而不是 working_copy / url 分支**：SVN mergeinfo 的
/// target 既可以是本地 WC 路径，也可以是仓库 URL，命令行格式完全一致——分支判定
/// 在 [svnPathToWorkingDirectory]（caller 侧）做，不在 args 构造里做。
///
/// **R106 收口**：原本 svn_service.dart 内 3 处 inline 重复（`isRevisionMerged` /
/// `checkMergedStatus` / `getAllMergedRevisions`），都是同一份字面量序列。任何
/// `'merged'` 改成 `'eligible'`、或 `'--show-revs'` 换成 `--show-revs=merged` 这类
/// flag 形态调整，都只需改本函数一处。
///
/// **不做的事**：不做 `useXml` 决策——mergeinfo 不支持 --xml（参见 [_xmlBlacklist]
/// 注释），那是 caller 侧的 `useXml: false` 决策，不在 args 构造里。
@visibleForTesting
List<String> buildSvnMergeinfoArgs({
  required String sourceUrl,
  required String target,
}) {
  return ['mergeinfo', '--show-revs', 'merged', sourceUrl, target];
}

/// 构造 `svn commit -m <message>` 的命令参数。
///
/// **契约**：固定 3 元素 `[commit, -m, message]`；不含 path（caller 走
/// `workingDirectory: targetWc`，与 [buildSvnRevertArgs] 同款风格——不把 path
/// 塞进 args，依赖 workingDirectory）。
///
/// **不**做的事：不校验 message 非空；不做 multi-line 转义（Dart 的 Process.run
/// 走 argv 数组，不走 shell 拼接，多行 message 原样透传 SVN）。
@visibleForTesting
List<String> buildSvnCommitArgs({required String message}) {
  return ['commit', '-m', message];
}

/// 构造 `svn log -r <rev> --verbose <sourceUrl>` 的命令参数（用于 [getRevisionFiles]）。
///
/// **契约**：固定 5 元素 `[log, -r, '$revision', --verbose, sourceUrl]`。
///
/// **位置敏感**：`-r` 与 revision 必须相邻（SVN CLI 的 flag-value 强约束）；
/// `--verbose` 在 sourceUrl 之前（SVN log 的 flag 必须在 target 之前才能被
/// 正确识别为 log 的 flag 而非 path 的一部分）。
///
/// **与 [buildSvnLogArgs] 的关系**：本 helper 与 [buildSvnLogArgs] **不**合并——
/// 前者是"读 revision 详情（含 verbose 文件列表，无 limit）"，后者是"翻页读
/// 多条 log（有 limit / startRevision / reverseOrder 三分支）"，语境不同（参见
/// 谓词不合并模式 #9）。强行合并会让 helper 多出 `verbose: bool` 参数，每个
/// caller 都得为对方场景的字段填默认值——抽象成本 > 字面量重复成本。
@visibleForTesting
List<String> buildSvnVerboseLogArgs({
  required String sourceUrl,
  required int revision,
}) {
  return ['log', '-r', revision.toString(), '--verbose', sourceUrl];
}

/// 构造 `svn checkout --depth empty <url> <targetPath>` 的参数。
@visibleForTesting
List<String> buildSvnSparseCheckoutArgs({
  required String url,
  required String targetPath,
}) {
  return ['checkout', '--depth', 'empty', url, targetPath];
}

/// 构造 sparse working copy 中的 `svn update` 路径参数。
@visibleForTesting
List<String> buildSvnSparseUpdatePathArgs({
  required String relativePath,
  String? setDepth,
}) {
  final args = ['update'];
  if (setDepth != null) {
    args.addAll(['--set-depth', setDepth]);
  }
  args.add(relativePath);
  return args;
}

/// 构造 `findBranchPoint` 用的 `svn log --stop-on-copy -l 1 -r 1:HEAD <branchUrl>` 参数。
///
/// **契约**：固定 7 元素 `[log, branchUrl, --stop-on-copy, -l, '1', -r, '1:HEAD']`。
///
/// **为什么 limit 硬编码 '1'**：caller [SvnService.findBranchPoint] 只关心**最早一条**
/// （stop-on-copy 保证返回的就是分支点本身），多读没意义；
/// **为什么 -r '1:HEAD' 硬编码**：分支点必在 `[1, HEAD]` 范围内，传更窄的范围会
/// 漏掉分支点。
///
/// **位置敏感**：`branchUrl` 紧跟 `log` 后（SVN CLI 的 target 位置约定）；
/// `--stop-on-copy` 必须在 target 之后才能正确被识别为 log 的 flag。
@visibleForTesting
List<String> buildSvnFindBranchPointLogArgs({required String branchUrl}) {
  return ['log', branchUrl, '--stop-on-copy', '-l', '1', '-r', '1:HEAD'];
}

/// 构造 `findRootTail` 用的 `svn log -r 1:HEAD -l 1 <sourceUrl>` 参数。
///
/// **契约**：固定 6 元素 `[log, sourceUrl, -r, '1:HEAD', -l, '1']`。
///
/// **与 [buildSvnFindBranchPointLogArgs] 的差异**：本 helper **不带** `--stop-on-copy`——
/// 寻找 ROOT_TAIL 时要的是整条历史的**最早 revision**（不在乎是否跨过 copy 边界），
/// 而 findBranchPoint 要的是**当前 branch 的起点**（必须 stop on copy）。语义对立，
/// 强行合并（如加 `stopOnCopy: bool` 参数）会让 caller 易混淆——分开抽。
///
/// **位置**：`sourceUrl` 紧跟 `log` 后；revision range 与 limit flag 在尾部。
@visibleForTesting
List<String> buildSvnFindRootTailLogArgs({required String sourceUrl}) {
  return ['log', sourceUrl, '-r', '1:HEAD', '-l', '1'];
}

/// 从一批 SVN log entries 的 revision 列表里，决定 ROOT_TAIL 值。
///
/// **契约**：
/// - 入参为空 → 返回 **1**（SVN 仓库的最早 revision 默认值，与原 inline 注释
///   `'未找到根尾，默认使用 r1'` 完全等价）；
/// - 入参非空 → 返回 `min(revisions)`（最早 revision；SVN log 默认按时间倒序，
///   最后一条最早，这里用 reduce min 不依赖输入顺序，更稳）。
///
/// **设计选择**：默认值硬编码为 1 而非允许 caller 传入——
/// 1. 整个项目里 ROOT_TAIL 的 fallback 永远是 1（SVN 语义决定）；
/// 2. 如果将来有"branch 仓库"场景需要不同 fallback，**新增 caller 应该新建函数**
///    而不是给本函数加 `fallback` 参数；与 #9 一致：形似但语义不同就分开。
///
/// **不**做的事：
/// - 不在入参含负数/0 时校验或抛错——SVN revision 理论上 >= 1，但本函数只做
///   纯数学 min，不替 SVN 语义校验做防御。
@visibleForTesting
int resolveRootTailFromEntries(List<int> revisions) {
  if (revisions.isEmpty) return 1;
  return revisions.reduce((a, b) => a < b ? a : b);
}

/// ProcessResult 的包装类，用于处理编码问题
///
/// 这是一个公开的类，供其他模块使用（如 WorkingCopyManager）
class SvnProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final int pid;

  SvnProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.pid,
  });

  /// 是否成功——`exitCode == 0` 的唯一抽象层。
  ///
  /// **为什么本 getter 是唯一事实源**：项目内 [SvnProcessResult] 的所有 caller
  /// 都应当走 `result.isSuccess` 而**不**直接读 `result.exitCode == 0`：
  /// - **未来兼容性**：若某天 SVN CLI 引入"warning exit code"（如 1 = 部分成功），
  ///   只需改本 getter 一处，所有 caller 自动跟进。
  /// - **可读性**：`if (result.isSuccess)` 比 `if (result.exitCode == 0)` 更接近
  ///   业务语义（"调用成功 vs 失败"）；后者把"成功是什么"的语义判断责任甩给
  ///   每一个 caller，违反 SRP。
  /// - **R86 漏迁巡检收口**：R0 era 即存在本 getter，但 4 处 svn_service.dart
  ///   内部 caller（line 708/993/1021/1046）+ 3 处 main_screen_v3.dart caller
  ///   （line 1354/1418/1459，通过 `_wcManager.update/revert/cleanup` 拿到
  ///   `SvnProcessResult`）一直保留 raw `exitCode == 0`。R86 全部迁完。
  /// - **非 SvnProcessResult 不要勉强用本 getter**：例如 svn_service.dart 内
  ///   `Process.run('svn', ['--version'])`（参见 `_detectSvnPath` 实现，行号
  ///   随重构变动；用 `grep -n "Process.run('svn', \['--version'\]"` 定位）
  ///   返回 dart:io 的 `ProcessResult` 而非本类型，没有 `isSuccess`——保留 raw
  ///   `exitCode == 0` 是正确的。
  bool get isSuccess => exitCode == 0;
}

class SvnService {
  /// 单例模式
  static final SvnService _instance = SvnService._internal();
  factory SvnService() => _instance;
  SvnService._internal();

  /// 测试钩子：子类构造 fake。
  @visibleForTesting
  SvnService.forTesting();

  /// 日志回调
  Function(String)? onLog;

  /// SVN 可执行文件路径（初始化时自动检测）
  String _svnPath = 'svn';

  /// 不支持 --xml 参数的 SVN 命令黑名单
  ///
  /// 这些命令不支持 XML 输出，即使 useXml=true 也不会添加 --xml 参数
  ///
  /// 注意：mergeinfo 命令在某些 SVN 版本中不支持 --xml，需要文本解析
  static const Set<String> _xmlBlacklist = {
    'merge',
    'commit',
    'update',
    'revert',
    'cleanup',
    'status',
    'mergeinfo', // mergeinfo 不支持 --xml 参数
    'add',
    'delete',
    'move',
    'copy',
    'mkdir',
    'propset',
    'propget',
    'proplist',
    'propdel',
    'lock',
    'unlock',
    'switch',
    'export',
    'import',
    'checkout',
    'co',
  };

  /// 初始化服务
  Future<void> init() async {
    // 自动检测 SVN 路径
    await _detectSvnPath();
  }

  /// 检测 SVN 可执行文件路径
  ///
  /// macOS GUI 应用的 PATH 环境变量与终端不同，
  /// 需要在常见路径中查找 svn 可执行文件
  Future<void> _detectSvnPath() async {
    // 常见的 SVN 安装路径
    final possiblePaths = [
      'svn', // 系统 PATH（可能在终端有效但 GUI 无效）
      '/usr/local/bin/svn', // Homebrew (Intel Mac)
      '/opt/homebrew/bin/svn', // Homebrew (Apple Silicon)
      '/usr/bin/svn', // 系统自带
      '/opt/local/bin/svn', // MacPorts
    ];

    for (final path in possiblePaths) {
      try {
        final result = await Process.run(path, ['--version']);
        if (result.exitCode == 0) {
          _svnPath = path;
          _log('检测到 SVN 路径: $_svnPath');
          return;
        }
      } catch (e) {
        // 继续尝试下一个路径
      }
    }

    // 如果都没找到，保持默认值 'svn'，让后续命令报错
    _log('⚠ 未找到 SVN 可执行文件，将使用默认路径: svn');
  }

  /// 记录日志
  void _log(String message) {
    AppLogger.svn.info(message);
    onLog?.call(message);
  }

  /// 构建 SVN 命令参数
  ///
  /// [username] 和 [password] 参数是可选的，仅在需要临时传递凭证时使用
  /// 正常情况下不传递这些参数，让 SVN 使用自己的凭证缓存
  List<String> _buildSvnArgs(
    List<String> baseArgs, {
    String? username,
    String? password,
  }) =>
      buildSvnCliArgs(
        svnPath: _svnPath,
        baseArgs: baseArgs,
        username: username,
        password: password,
      );

  /// 执行 SVN 命令
  ///
  /// [args] SVN 命令参数（不包含 'svn' 前缀）
  /// [useXml] 是否使用 --xml 参数（默认 false，某些命令不支持 XML）
  /// [workingDirectory] 工作目录
  /// [username] SVN 用户名
  /// [password] SVN 密码
  Future<SvnProcessResult> _runSvnCommand(
    List<String> args, {
    bool useXml = false,
    String? workingDirectory,
    String? username,
    String? password,
  }) async {
    // 如果需要 XML 输出，检查命令是否支持 XML
    final injection =
        injectXmlFlag(args, useXml: useXml, xmlBlacklist: _xmlBlacklist);
    final finalArgs = injection.args;
    if (injection.suppressedCommand != null) {
      _log('⚠ 命令 "${injection.suppressedCommand}" 不支持 --xml 参数，已忽略 useXml 设置');
    }

    final fullArgs =
        _buildSvnArgs(finalArgs, username: username, password: password);

    // 隐藏密码的日志输出
    final displayArgs = finalArgs.join(' ');

    // 记录命令执行开始
    _log(appLogSeparator);
    _log(formatSvnCommandStartLine(
      displayArgs: displayArgs,
      username: username,
      useXml: useXml,
      workingDirectory: workingDirectory,
    ));
    _log(appLogSeparator);

    final startTime = DateTime.now();

    // 使用 latin1 编码读取原始字节，避免 UTF-8 解码错误
    // Windows 上 SVN 可能输出 GBK 编码的中文
    final result = await Process.run(
      fullArgs[0],
      fullArgs.sublist(1),
      workingDirectory: workingDirectory,
      stdoutEncoding: latin1,
      stderrEncoding: latin1,
    );

    final stdout = decodeProcessOutput(result.stdout.toString());
    final stderr = decodeProcessOutput(result.stderr.toString());

    // 创建一个包装结果
    final wrappedResult = SvnProcessResult(
      exitCode: result.exitCode,
      stdout: stdout,
      stderr: stderr,
      pid: result.pid,
    );

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    final output = stdout + stderr;

    // 记录命令执行结果
    if (wrappedResult.isSuccess) {
      _log(formatSvnSuccessLine(
        exitCode: wrappedResult.exitCode,
        durationMs: duration.inMilliseconds,
      ));
    } else {
      _log(formatSvnFailureLine(
        exitCode: wrappedResult.exitCode,
        durationMs: duration.inMilliseconds,
      ));
      // 失败时记录命令和错误输出，便于排查
      _log('  命令: svn $displayArgs');
      if (stderr.isNotEmpty) {
        _log('  错误: ${stderr.trim()}');
      }
      if (stdout.isNotEmpty) {
        _log('  输出: ${truncateForLog(stdout.trim())}');
      }
    }

    // 记录输出内容（仅摘要，不记录详细内容）
    if (output.isNotEmpty) {
      final lines = output.split('\n').length;
      final size = output.length;
      _log(formatSvnOutputSummary(lines: lines, size: size, useXml: useXml));
    } else {
      _log('(无输出内容)');
    }

    _log(appLogSeparator);

    if (wrappedResult.exitCode != 0) {
      // R98 symmetric throw 标记（参见 feedback_audit_dimension_switch.md
      // "throw 对称性审计"维度）：SvnException 类本身已带完整测试覆盖
      // （test/svn_service_test.dart `group('SvnException')` + `group('formatSvnExceptionMessage')`），
      // 锁定了 toString 格式、needsAuth 解析等所有契约面。本 throw 是契约的*产生者*，
      // 单测锁的是契约的*结构*——比直接断言 throw 类更稳健（生产代码改 throw 时机
      // 不破测试，只要契约面不变）。
      throw SvnException(
        'SVN 命令执行失败 (退出码: ${wrappedResult.exitCode})',
        command: displayArgs,
        exitCode: wrappedResult.exitCode,
        output: output,
      );
    }

    return wrappedResult;
  }

  /// 查找分支点（用于 stopOnCopy 功能）
  ///
  /// [branchUrl] 分支的 URL
  /// [workingDirectory] 工作目录（可选，用于 SVN 命令执行上下文）
  /// [username] SVN 用户名（可选）
  /// [password] SVN 密码（可选）
  ///
  /// 返回分支点的 revision 号，如果未找到则返回 null
  ///
  /// 注意：这是一个业务逻辑方法，专门用于查找分支点
  Future<int?> findBranchPoint(
    String branchUrl, {
    String? workingDirectory,
    String? username,
    String? password,
  }) async {
    _log(appLogSeparator);
    for (final line in formatFindBranchPointHeaderLines(
      branchUrl: branchUrl,
      workingDirectory: workingDirectory,
    )) {
      _log(line);
    }

    // 执行 svn log --stop-on-copy -l 1 -r 1:HEAD（R106 抽出 buildSvnFindBranchPointLogArgs）
    final args = buildSvnFindBranchPointLogArgs(branchUrl: branchUrl);
    _log('  命令: svn ${args.join(' ')} --xml');

    final result = await _runSvnCommand(
      args,
      useXml: true,
      workingDirectory: workingDirectory,
      username: username,
      password: password,
    );

    final xmlOutput = result.stdout.toString();
    final entries = SvnXmlParser.parseLog(xmlOutput);

    final int? branchPoint = entries.isNotEmpty ? entries.first.revision : null;
    _log(formatBranchPointResultLine(branchPoint));

    _log(appLogSeparator);
    return branchPoint;
  }

  /// 查找根尾（ROOT_TAIL）- 整个SVN路径的最早revision
  ///
  /// [sourceUrl] 源 URL
  /// [workingDirectory] 工作目录（可选，用于 SVN 命令执行上下文）
  /// [username] SVN 用户名（可选）
  /// [password] SVN 密码（可选）
  ///
  /// 返回根尾的 revision 号（通常是1），如果未找到则返回 null
  ///
  /// 注意：通过 `svn log -r 1:HEAD`（不加stopOnCopy，不加limit）获取所有日志，
  /// 然后取最小的revision作为ROOT_TAIL
  /// 由于可能数据量很大，这里使用一个较大的limit（如10000）来获取足够的数据
  Future<int?> findRootTail(
    String sourceUrl, {
    String? workingDirectory,
    String? username,
    String? password,
  }) async {
    _log(appLogSeparator);
    _log('【SvnService.findRootTail】查找根尾（ROOT_TAIL）');
    _log('  源 URL: $sourceUrl');
    _log('  工作目录: ${workingDirectory ?? "未指定"}');

    // 执行 svn log -r 1:HEAD（不加stopOnCopy，使用 limit=1 获取第一条数据，即最早的数据）
    // 注意：SVN log 返回的是按时间倒序（最新的在前），所以需要取最后一个（最小的revision）
    // R106 抽出 buildSvnFindRootTailLogArgs（与 buildSvnFindBranchPointLogArgs 故意分开）
    final args = buildSvnFindRootTailLogArgs(sourceUrl: sourceUrl);
    _log('  命令: svn ${args.join(' ')} --xml');
    _log('  说明: 获取从r1到HEAD的日志，取最小的revision作为ROOT_TAIL');

    final result = await _runSvnCommand(
      args,
      useXml: true,
      workingDirectory: workingDirectory,
      username: username,
      password: password,
    );

    final xmlOutput = result.stdout.toString();
    final entries = SvnXmlParser.parseLog(xmlOutput);

    final rootTail =
        resolveRootTailFromEntries(entries.map((e) => e.revision).toList());
    if (entries.isNotEmpty) {
      _log('  ✓ 找到根尾（ROOT_TAIL）: r$rootTail');
    } else {
      _log('  ⚠ 未找到根尾，默认使用 r1');
    }

    _log(appLogSeparator);
    return rootTail;
  }

  /// 获取 SVN 日志
  ///
  /// [url] SVN URL
  /// [limit] 返回的日志条数
  /// [workingDirectory] 工作目录（可选，用于 SVN 命令执行上下文）
  /// [startRevision] 起始版本号（可选，从指定版本开始读取）
  /// [username] SVN 用户名（可选）
  /// [password] SVN 密码（可选）
  ///
  /// 注意：
  /// - 这是一个底层方法，只负责执行 SVN 命令
  /// - 不包含任何业务逻辑（如分支点查找）
  /// - 如果需要查找分支点，请使用 findBranchPoint() 方法
  /// - [reverseOrder] 如果为 true，从 startRevision 向更旧的版本读取；否则向 HEAD 读取
  Future<String> log(
    String url, {
    int limit = 200,
    String? workingDirectory,
    int? startRevision,
    bool reverseOrder = false,
    String? username,
    String? password,
  }) async {
    _log(appLogSeparator);
    _log('【SvnService.log】开始读取 SVN 日志');
    _log('  URL: $url');
    _log('  限制条数: $limit');
    _log(
        '  startRevision: ${startRevision != null ? "r$startRevision" : "未指定（从最新开始）"}');
    _log('  workingDirectory: ${workingDirectory ?? "未指定"}');

    // 构建命令参数（使用 XML 输出）
    final plan = buildSvnLogArgs(
      url: url,
      limit: limit,
      startRevision: startRevision,
      reverseOrder: reverseOrder,
    );
    _log('  ${plan.logHint}');

    _log('  命令参数: ${plan.args.join(' ')}');

    // 使用 XML 输出
    final result = await _runSvnCommand(
      plan.args,
      useXml: true,
      workingDirectory: workingDirectory,
      username: username,
      password: password,
    );

    final xmlOutput = result.stdout.toString();
    _log('  ✓ SVN 日志读取完成');
    _log(appLogSeparator);

    // 解析 XML 输出
    final entries = SvnXmlParser.parseLog(xmlOutput);
    _log('成功解析 ${entries.length} 条日志');
    _log('成功读取 SVN 日志');
    _log('=== SVN 日志读取完成 ===');

    // 返回 XML 输出（保持向后兼容）
    return xmlOutput;
  }

  /// 执行 SVN merge
  ///
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  /// [targetWc] 目标工作副本路径
  /// [dryRun] 是否为预览模式
  Future<void> merge(
    String sourceUrl,
    int revision,
    String targetWc, {
    bool dryRun = false,
    String? username,
    String? password,
  }) async {
    _log('合并 r$revision 从 $sourceUrl 到 $targetWc...');

    final args = buildSvnMergeArgs(
      sourceUrl: sourceUrl,
      revision: revision,
      dryRun: dryRun,
    );
    if (dryRun) {
      _log('以 dry-run 模式执行 merge（不修改本地文件，仅预览）');
    }

    await _runSvnCommand(
      args,
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    _log('合并完成');
  }

  /// 执行 SVN commit
  Future<SvnProcessResult> commit(
    String targetWc,
    String message, {
    String? username,
    String? password,
  }) async {
    _log('提交更改...');

    final result = await _runSvnCommand(
      buildSvnCommitArgs(message: message),
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    _log('提交成功');
    return result;
  }

  /// 执行 SVN update
  ///
  /// 返回结果，可以检查 exitCode 判断是否成功
  Future<SvnProcessResult> update(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    _log('更新工作副本: $targetWc');

    final result = await _runSvnCommand(
      ['update'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    if (result.isSuccess) {
      _log('更新完成');
    } else {
      _log('更新失败: ${result.stderr}');
    }
    return result;
  }

  /// 执行 SVN switch
  ///
  /// 返回结果，可以检查 exitCode 判断是否成功。
  Future<SvnProcessResult> switchToUrl(
    String targetWc,
    String url, {
    String? username,
    String? password,
  }) async {
    _log('切换工作副本: $targetWc -> $url');

    final result = await _runSvnCommand(
      buildSvnSwitchArgs(url: url),
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    if (result.isSuccess) {
      _log('切换完成');
    } else {
      _log('切换失败: ${result.stderr}');
    }
    return result;
  }

  /// 执行 SVN revert
  ///
  /// 返回结果，可以检查 exitCode 判断是否成功
  /// [recursive] 是否递归还原（默认 false）
  Future<SvnProcessResult> revert(
    String targetWc, {
    bool recursive = false,
    String? username,
    String? password,
  }) async {
    _log('还原本地修改: $targetWc (recursive: $recursive)');

    final args = buildSvnRevertArgs(recursive: recursive);
    final result = await _runSvnCommand(
      args,
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    if (result.isSuccess) {
      _log('还原完成');
    } else {
      _log('还原失败: ${result.stderr}');
    }
    return result;
  }

  /// 一键标记冲突已解决：`svn resolve --accept <mode> -R .`。
  ///
  /// **使用场景**：暂停态用户碰到 textConflict / treeConflict，已经手工编辑文件
  /// 或决定保留 working copy 形态后，需要一键把所有冲突标记为已解决，再按"继续"
  /// 让 merge_execution_state 重跑当前 revision 的提交步骤。
  ///
  /// **mode 默认值**：[SvnResolveAccept.working]——一键按钮的最常见场景是"用户
  /// 已手工改完，保留 WC 当前形态"。其余 3 种 mode（`mine-full` / `theirs-full` /
  /// `base`）由 UI 高级 dialog 显式选择后传入，语义破坏性递增。
  ///
  /// **为什么不在这里直接调 commit / resume**：本方法只负责一个原子动作——把
  /// 冲突标记位清掉。继续 / 跳过 / 终止 仍由 [MergeExecutionState] 三个 onResume /
  /// onSkip / onCancel 入口控制；UI 层在 SnackBar 提示成功后由用户**自行**点击
  /// "继续"按钮，与 R130 cross-provider 通信反模式审计一致——避免 service 跨界
  /// 调用 provider 方法。
  Future<SvnProcessResult> resolveAccept(
    String targetWc, {
    SvnResolveAccept mode = SvnResolveAccept.working,
    String? username,
    String? password,
  }) async {
    _log('标记冲突已解决: $targetWc (--accept ${mode.cliFlag} -R)');

    final args = buildSvnResolveArgs(mode);
    final result = await _runSvnCommand(
      args,
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    if (result.isSuccess) {
      _log('冲突标记完成');
    } else {
      _log('冲突标记失败: ${result.stderr}');
    }
    return result;
  }

  /// 执行 SVN cleanup
  ///
  /// 返回结果，可以检查 exitCode 判断是否成功
  Future<SvnProcessResult> cleanup(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    _log('清理工作副本: $targetWc');

    final result = await _runSvnCommand(
      ['cleanup'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    if (result.isSuccess) {
      _log('清理完成');
    } else {
      _log('清理失败: ${result.stderr}');
    }
    return result;
  }

  /// 浏览 SVN 仓库目录。
  Future<List<String>> listRepository(
    String url, {
    String? username,
    String? password,
  }) async {
    _log('浏览仓库目录: $url');

    final result = await _runSvnCommand(
      buildSvnListArgs(url: url),
      username: username,
      password: password,
    );

    final entries = parseSvnListOutput(result.stdout.toString());
    _log('仓库目录读取完成: ${entries.length} 项');
    return entries;
  }

  /// 检查工作副本是否有冲突
  Future<bool> hasConflicts(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    final result = await _runSvnCommand(
      ['status'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    return svnStatusOutputHasConflict(result.stdout.toString());
  }

  /// 列出工作副本中所有冲突文件的相对路径（按 svn status 原始顺序）。
  ///
  /// **何时被调用**：暂停态 textConflict 任务下，UI 提供"打开冲突文件"按钮 →
  /// caller 用本方法拿冲突文件列表，再取第一条解析为绝对路径并交给系统打开。
  ///
  /// **与 [hasConflicts] 的分工**：那个是 bool 短路、本方法返回完整列表；
  /// 二者共用 `svn status` 命令但解析 helper 不同（`svnStatusOutputHasConflict`
  /// vs `parseConflictedFiles`），契约见两个 helper 的 dartdoc。
  ///
  /// 没有冲突 → 返回空 list（不抛异常）。caller 应判 `.isEmpty` 决定是否
  /// 给用户 SnackBar "无冲突文件可打开"提示。
  Future<List<String>> listConflictedFiles(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    final result = await _runSvnCommand(
      ['status'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    return parseConflictedFiles(result.stdout.toString());
  }

  /// 统计工作副本里被改动的条目数（用于"合并完成时给用户反馈实际改动数"）。
  ///
  /// **何时被调用**：`MergeExecutionState._runMergeStep` 在 `svn merge` 成功且无冲突
  /// 后调用本方法，把数字写进执行日志（"r$revision 合并成功 — 实际改动 N 个文件" /
  /// "r$revision 合并成功 — 但未产生任何差异（空合并）"），帮用户分辨"成功"是否真有
  /// 内容变更（例如自合并 / 已合并过的 revision 重跑都会得到 0）。
  ///
  /// **实现**：跑 `svn status` 拿原始输出，调顶层 helper [parseChangedFilesCount] 解析。
  /// 0 行 = 空合并。本方法不抛业务异常（status 命令失败时仍按 _runSvnCommand 的常规异常路径）。
  Future<int> countChangedFiles(
    String targetWc, {
    String? username,
    String? password,
  }) async {
    final result = await _runSvnCommand(
      ['status'],
      workingDirectory: targetWc,
      username: username,
      password: password,
    );

    return parseChangedFilesCount(result.stdout.toString());
  }

  /// 启动合并前对 sourceUrl / targetWc 做 SVN 连通性预校验。
  ///
  /// **为什么需要**：原 `_startMerge` 仅做 `isNotEmpty` 字段存在性校验，错误的
  /// URL（已删除分支 / typo / 网络断开）或不存在的工作副本路径要等到第一步
  /// `prepare` 阶段跑 `svn revert` / `svn cleanup` 才报错——此时任务已经入队，
  /// 用户必须先"跳过 / 终止"才能改配置，体验割裂。预校验提前到点击"开始合并"
  /// 那一刻给反馈。
  ///
  /// **实现**：直接调 [getInfo] 拿 `<path>` 的 url 字段——`svn info` 是最轻量的
  /// 连通性探针，URL 模式会走网络握手，路径模式会读 .svn 元数据；任一失败抛
  /// `SvnException` 被本方法 try/catch 转译为字符串错误。
  ///
  /// **返回值**：`null` 表示通过；非空字符串是给 SnackBar 用的一句话错误（已经
  /// 经过 [formatProbeFailureReason] 翻译，不含多行 Command/Exit code 噪音）。
  ///
  /// **role 入参**：用于错误文案前缀（'源 URL' / '目标工作副本'），由 caller
  /// 决定语境。
  Future<String?> probeSvnLocation(
    String path, {
    required String role,
    String? username,
    String? password,
  }) async {
    try {
      await getInfo(
        path,
        item: 'url',
        username: username,
        password: password,
      );
      return null;
    } catch (e) {
      return formatProbeFailureReason(role: role, error: e);
    }
  }

  /// 获取 SVN info
  ///
  /// [path] 工作副本路径或 URL
  /// [item] 要获取的信息项（如 'url', 'revision' 等），如果为 null 则返回完整 XML
  Future<String> getInfo(
    String path, {
    String? item,
    String? username,
    String? password,
  }) async {
    AppLogger.svn.info('【SvnService.getInfo】获取 SVN 信息');
    AppLogger.svn.info('  路径: $path');
    AppLogger.svn.info('  项目: ${item ?? "全部"}');

    final args = buildSvnInfoArgs(path: path, item: item);

    final result = await _runSvnCommand(
      args,
      useXml: item == null, // 如果指定了 item，使用文本输出；否则使用 XML
      workingDirectory: svnPathToWorkingDirectory(path),
      username: username,
      password: password,
    );

    final output = result.stdout.toString().trim();

    // 如果使用 XML，解析并提取 URL
    if (item == null) {
      final infoMap = SvnXmlParser.parseInfo(output);
      final url = infoMap['url'] ?? output;
      AppLogger.svn.info('  提取的 URL: $url');
      return url;
    }

    AppLogger.svn.info('  返回结果: $output');
    return output;
  }

  /// 检查 revision 是否已经合并到目标路径或 URL
  ///
  /// 使用标准的 SVN mergeinfo 命令检查
  /// [sourceUrl] 源 URL
  /// [revision] 要检查的版本号
  /// [target] 目标工作副本路径或仓库 URL
  ///
  /// 返回 true 表示已合并，false 表示未合并
  ///
  /// 注意：mergeinfo 不支持 --xml，使用文本解析
  Future<bool> isRevisionMerged({
    required String sourceUrl,
    required int revision,
    required String target,
    String? username,
    String? password,
    bool throwOnError = false,
  }) async {
    try {
      _log('检查 revision r$revision 是否已合并到 $target');
      // 使用 svn mergeinfo 命令检查（mergeinfo 不支持 --xml，使用文本输出）
      final result = await _runSvnCommand(
        buildSvnMergeinfoArgs(sourceUrl: sourceUrl, target: target),
        useXml: false, // mergeinfo 不支持 XML
        workingDirectory: svnMergeinfoTargetToWorkingDirectory(target),
        username: username,
        password: password,
      );

      final mergedRevisions = parseMergedRevisions(result.stdout.toString());
      if (mergedRevisions.contains(revision)) {
        _log('✓ revision r$revision 已合并到目标');
        return true;
      }

      _log('✗ revision r$revision 未合并到目标');
      return false;
    } catch (e, stackTrace) {
      if (throwOnError) {
        _log('✗ 无法确认 revision r$revision 是否已合并到目标: $e');
        AppLogger.svn.error('确认合并状态异常', e, stackTrace);
        rethrow;
      }
      // 如果命令失败（例如工作副本不存在或不是工作副本），返回 false
      _log('⚠ 检查合并状态失败: $e，假设未合并');
      AppLogger.svn.error('检查合并状态异常', e, stackTrace);
      return false;
    }
  }

  /// 批量检查多个 revision 的合并状态
  ///
  /// 返回一个 Map，key 是 revision，value 是是否已合并
  ///
  /// 注意：mergeinfo 不支持 --xml，使用文本解析
  Future<Map<int, bool>> checkMergedStatus({
    required String sourceUrl,
    required List<int> revisions,
    required String targetWc,
    String? username,
    String? password,
  }) async {
    final result = <int, bool>{};

    _log('批量检查 ${revisions.length} 个 revision 的合并状态');

    // 先获取所有已合并的 revision（mergeinfo 不支持 XML，使用文本输出）
    try {
      final mergeinfoResult = await _runSvnCommand(
        buildSvnMergeinfoArgs(sourceUrl: sourceUrl, target: targetWc),
        useXml: false, // mergeinfo 不支持 XML
        workingDirectory: svnMergeinfoTargetToWorkingDirectory(targetWc),
        username: username,
        password: password,
      );

      final mergedRevisions =
          parseMergedRevisions(mergeinfoResult.stdout.toString());

      _log('已合并的 revision 数量: ${mergedRevisions.length}');

      // 检查每个 revision
      for (final rev in revisions) {
        result[rev] = mergedRevisions.contains(rev);
      }
    } catch (e, stackTrace) {
      // 如果命令失败，所有 revision 都标记为未合并
      _log('⚠ 批量检查合并状态失败: $e，假设所有 revision 都未合并');
      AppLogger.svn.error('批量检查合并状态异常', e, stackTrace);
      for (final rev in revisions) {
        result[rev] = false;
      }
    }

    return result;
  }

  /// 获取所有已合并的 revision
  ///
  /// 返回一个 Set，包含所有已合并的 revision
  ///
  /// 注意：mergeinfo 不支持 --xml，使用文本解析
  Future<Set<int>> getAllMergedRevisions({
    required String sourceUrl,
    required String targetWc,
    String? username,
    String? password,
  }) async {
    _log('获取所有已合并的 revision: $sourceUrl -> $targetWc');

    try {
      final mergeinfoResult = await _runSvnCommand(
        buildSvnMergeinfoArgs(sourceUrl: sourceUrl, target: targetWc),
        useXml: false, // mergeinfo 不支持 XML
        workingDirectory: svnMergeinfoTargetToWorkingDirectory(targetWc),
        username: username,
        password: password,
      );

      final output = mergeinfoResult.stdout.toString();
      // 解析文本输出（格式：r12345 或 r12345\nr12346\n...）
      // 与 isRevisionMerged / checkMergedStatus 共用同一份 parseMergedRevisions——R85 补迁
      // 漏掉的 inline 解析链，让 svn_service.dart 内全部 3 个 mergeinfo 输出 caller
      // 走同一个 helper（曾经 doc 写"两处"是因 R0~R6 抽出时漏统计了本函数）。
      final mergedRevisions = parseMergedRevisions(output);

      _log('已合并的 revision 数量: ${mergedRevisions.length}');
      return mergedRevisions;
    } catch (e, stackTrace) {
      _log('⚠ 获取已合并的 revision 失败: $e');
      AppLogger.svn.error('获取已合并的 revision 异常', e, stackTrace);
      return {};
    }
  }

  /// 获取 revision 涉及的文件列表
  ///
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  ///
  /// 返回文件路径列表（相对于仓库根目录）
  Future<List<String>> getRevisionFiles({
    required String sourceUrl,
    required int revision,
    String? username,
    String? password,
  }) async {
    try {
      _log('获取 revision r$revision 涉及的文件列表');
      // 使用 svn log --verbose --xml 获取文件列表
      final result = await _runSvnCommand(
        buildSvnVerboseLogArgs(sourceUrl: sourceUrl, revision: revision),
        useXml: true,
        username: username,
        password: password,
      );

      final xmlOutput = result.stdout.toString();
      // 解析 XML 输出
      final files = SvnXmlParser.parseLogFiles(xmlOutput);

      _log('revision r$revision 涉及 ${files.length} 个文件');
      return files;
    } catch (e, stackTrace) {
      _log('❌ 获取文件列表失败: $e');
      AppLogger.svn.error('获取文件列表异常', e, stackTrace);
      return [];
    }
  }

  /// 获取 revision 涉及的结构化变更路径。
  Future<List<SvnLogChangedPath>> getRevisionChangedPaths({
    required String sourceUrl,
    required int revision,
    String? username,
    String? password,
  }) async {
    try {
      _log('获取 revision r$revision 的结构化变更路径');
      final result = await _runSvnCommand(
        buildSvnVerboseLogArgs(sourceUrl: sourceUrl, revision: revision),
        useXml: true,
        username: username,
        password: password,
      );

      final paths = SvnXmlParser.parseLogChangedPaths(result.stdout.toString());
      _log('revision r$revision 解析到 ${paths.length} 条变更路径');
      return paths;
    } catch (e, stackTrace) {
      _log('❌ 获取结构化变更路径失败: $e');
      AppLogger.svn.error('获取结构化变更路径异常', e, stackTrace);
      return [];
    }
  }

  /// 以 depth=empty 检出一个临时精简工作副本根目录。
  Future<void> checkoutSparseRoot(
    String targetUrl,
    String targetPath, {
    String? username,
    String? password,
  }) async {
    _log('创建临时精简工作副本: $targetUrl -> $targetPath');
    await _runSvnCommand(
      buildSvnSparseCheckoutArgs(url: targetUrl, targetPath: targetPath),
      username: username,
      password: password,
    );
    _log('临时精简工作副本根目录已创建');
  }

  /// 在 sparse working copy 内拉取一个目录或文件路径。
  Future<void> updateSparsePath(
    String workingCopy,
    String relativePath, {
    String? setDepth,
    String? username,
    String? password,
  }) async {
    _log('更新精简工作副本路径: $relativePath');
    await _runSvnCommand(
      buildSvnSparseUpdatePathArgs(
        relativePath: relativePath,
        setDepth: setDepth,
      ),
      workingDirectory: workingCopy,
      username: username,
      password: password,
    );
  }
}

/// SVN 异常类
class SvnException implements Exception {
  final String message;
  final String? command;
  final int? exitCode;
  final String output;

  SvnException(
    this.message, {
    this.command,
    this.exitCode,
    this.output = '',
  });

  @override
  String toString() => formatSvnExceptionMessage(
        message: message,
        command: command,
        exitCode: exitCode,
        output: output,
      );

  /// 检查是否需要认证
  bool get needsAuth => svnOutputNeedsAuth(output);
}
