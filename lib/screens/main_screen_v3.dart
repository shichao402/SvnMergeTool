/// SVN 合并助手主界面
///
/// 当前版本采用组件化结构组织主界面。
/// - 主屏幕只负责组装各组件和管理状态
/// - UI 组件独立，易于替换和测试
///
/// **R144 Future 链式（.then / .catchError / .whenComplete）协议审计 doc-block**
///
/// 与 R142（dart:async 时间轴）/ R143（dart:async Stream producer）正交叠加，
/// 形成 dart:async 三元闭合（time axis / stream / future chain）。本协议沿
/// "future chain 三段语义" 的 surface 闭合：`.then(` / `.catchError(` /
/// `.whenComplete(` —— 三段合法存在性 + lib 实测分布 + 跨档不变量 V1/V2/V3/V4 +
/// R119 三档框架在 chain 形态下的 doc-as-test 锚点。
///
/// **lib/ 全集表（R144 sweep）**：
/// | API           | 总站点 | 文件分布                                                                |
/// |---------------|--------|------------------------------------------------------------------------|
/// | `.then(`      | 5      | main.dart × 2（站点 P/Q）/ main_screen_v3.dart × 3（站点 R/S/T）          |
/// | `.catchError(`| 4      | main_screen_v3.dart × 4（站点 U/V/W/X）；logger 内 3 处由 R119 helper 包 |
/// | `.whenComplete(`| 0    | lib/ 0 站点（**negative-space invariant V3**）                          |
///
/// **5 + 4 = 9 链式站点矩阵（按 R119 三档归属分类）**：
/// - 站点 P  main.dart:378            — `.then`  R119 档 1 — fire-and-forget + callee 内部 try-catch sidechannel
/// - 站点 Q  main.dart:382（嵌套 P 内）— `.then`  R119 档 1 — 同上（嵌套 then 链）
/// - 站点 R  main_screen_v3.dart:807  — `.then`  R119 档 3 — `await` + then 串副作用（_onValidationError 注册）
/// - 站点 S  main_screen_v3.dart:812  — `.then`  R119 档 3 — `await` + then 串副作用（onProgressChanged 注册）
/// - 站点 T  main_screen_v3.dart:1155 — `.then`  R119 档 1+sidechannel — fire-and-forget + .catchError 旁路化（站点 X 配对）
/// - 站点 U  main_screen_v3.dart:804  — `.catchError` R119 档 3 — `await … .catchError` 旁路化（错误转日志，不抛）
/// - 站点 V  main_screen_v3.dart:809  — `.catchError` R119 档 3 — 同 U（chain at 站点 R 末尾）
/// - 站点 W  main_screen_v3.dart:833  — `.catchError` R119 档 3 — 同 U（chain at 站点 S 末尾）
/// - 站点 X  main_screen_v3.dart:1159 — `.catchError` R119 档 1+sidechannel — fire-and-forget chain 末尾旁路化（站点 T 配对）
///
/// **三档归属总数**：档 1 = 站点 P/Q（2）/ 档 1+sidechannel = 站点 T+X（1 对）/
/// 档 2 = lib 0 站点（已被 logger `silentlyDiscardAsyncError` helper 吸收 3 处）/
/// 档 3 = 站点 R/S/U/V/W（5）。lib 当前 0 站点直接 `.catchError((_) {})` 静默吞 ——
/// 全部走 R119 档 2 helper（`silentlyDiscardAsyncError`）抽象闭合（V2 律实例化）。
///
/// **V 系四律（future chain 协议跨档不变量）**：
/// - **V1 chain 起点档位归属律**：每个 `.then(` / `.catchError(` 起点必须有 R119
///   档位归属注释（doc 中提"R119 档 1/2/3"或锚点关键字）。lib 当前 9 站点全部
///   ≥1 处 doc 锚点（main.dart 372 行 doc 头 / main_screen_v3 798-803 init 序列
///   doc / 1144-1147 startBackgroundPreload doc）。
/// - **V2 catchError 显式静默吞禁止律**：lib/ 内**禁止**直接写 `.catchError((_) {})`
///   或 `.catchError((e) {})` 而函数体为空——必须走 R119 档 2 helper
///   `silentlyDiscardAsyncError`。当前 4 处 inline `.catchError((e) {…})` 全部带
///   `AppLogger.ui.error` 落日志旁路化（档 3），无空体；档 2 静默吞由 helper
///   单点提供（logger_service.dart:344）。
/// - **V3 whenComplete negative-space invariant**：lib/ 内 `.whenComplete(` 0
///   站点。引入 `.whenComplete(` 必须先升档 4 评估（finally 语义在 chain 形态
///   的位置）+ 更新本矩阵；否则视为协议未闭合。同 R140 M4 / R142 U4 / R143 B4
///   negative-space invariant 模式同律。
/// - **V4 chain 嵌套深度律**：lib/ 内 `.then(...).then(` 嵌套链允许（站点 P→Q
///   嵌套 1 层）；嵌套 ≥3 层需评估改 async/await 重写——chain 嵌套深度 ≥3 让
///   stack trace 失真、reviewer 难追"哪个 then 失败走哪个 catchError"。
///
/// **R119 ↔ R144 接合面（同 surface 双协议第 3 次实例）**：R119 锁 fire-and-forget
/// 异步契约（"是否 await + 错误如何处置"语义维度）/ R144 锁 future chain 形态
/// （`.then`/`.catchError`/`.whenComplete` 三段语法表面）—— 两协议同 surface
/// 但维度正交：一个落"语义档位"、一个落"语法表面"。前 2 次实例：R142 B 站
/// R120-3/R142-2 / R143 A 站 R121-3/R143-2；R144 整 surface 9 站点都受 R119 三档
/// 同时受 R144 V 系四律。
///
/// **R136 ↔ R144 正交**：R136 取消信号协议（cooperative cancellation）只走标志位
/// + watcher polling，0 处用 future chain 表达取消——chain 不被当成取消通道用，
/// 与 R144 future chain "数据/错误流" 语义清晰隔离（与 R136 ↔ R143 同律）。
///
/// **N-tuple invariance 模板第 24 次复用 / 第 8 次维度切换**（dart:async 三元
/// 闭合首次形式化：API 表面 R142 → producer 表面 R143 → chain 形态 R144）。
/// **doc-only audit 模式 R85+ N+21 次复用** + `_stripComments` doc-as-test
/// 防御 helper 第 14 次复用（R130-R143 复用，R144 第 14 次）。
///
/// **故意不做**：(1) **不引入 `.whenComplete(`**——当前 finally 语义可由
/// async/await 函数体内 try-finally 表达，引入 chain 形态的 whenComplete 会让
/// finally 跨 microtask 边界、stack trace 在异常诊断时丢上下文；V3 negative
/// invariant 锁此设计。(2) **不抽 `awaitOrLog<T>(future, logger, msg)` helper**
/// ——当前 4 处 `await … .catchError((e) { AppLogger.ui.error(…, e); })` 各
/// 自要传不同的日志消息字符串（"文件缓存服务初始化失败"/"日志缓存服务初始化
/// 失败"/"预加载服务初始化失败"/"后台预加载失败"）+ 不同 tag（ui），抽 helper
/// 只是字符串包装、不增语义清晰度（与 R141/R142/R143 故意不抽 helper 同源）。
/// (3) **不把 R119 三档框架并入 R144 V 系**——R119 锁"为什么/如何处置错误"语义、
/// R144 锁"用哪个 chain 段表达"语法；强行合并会丢两轴正交性（与 R120/R142
/// 双轴叠加同律）。(4) **不审计测试代码中的 then/catchError**——测试是 mock
/// 时钟/异步之外的人造场景，不参与生产协议审计（与 R142 同律）。
///
/// **未来候选**：持久化层数据迁移协议（version field / migration script）/ JSON
/// file format 持久化兼容审计第 2 轮（R105 配置文件迁移路径）/ SP key 命名规范
/// 审计（snake_case 一致性 + tag 前缀规则）/ Iterable / Stream 转换协议（map /
/// where / fold 不变量）/ async generator (async*) 维度（lib 当前 0 站点）/
/// FFI / Isolate 调用边界协议 / WidgetsBinding lifecycle 钩子协议（addObserver
/// / removeObserver 配对——R136 cancel signal 之外的另一种"signal channel"）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/merge_execution_state.dart';
import '../models/app_config.dart'
    show
        PreloadSettings,
        kDefaultMaxRetries,
        kDefaultMergeValidationScriptPath,
        kDefaultSvnLogLimit;
import '../models/log_entry.dart';
import '../models/merge_config.dart';
import '../models/merge_job.dart';
import '../services/svn_service.dart';
import '../services/logger_service.dart';
import '../services/storage_service.dart';
import '../services/log_filter_service.dart';
import '../services/log_file_cache_service.dart';
import '../services/preload_service.dart';
import '../services/log_cache_service.dart';
import '../services/log_sync_service.dart';
import '../services/working_copy_manager.dart';
import '../services/gongfeng_cr_service.dart';
import 'settings_screen.dart';
import '../utils/open_directory.dart';

// 组件导入
import 'components/config_bar.dart';
import 'components/step_execution_view.dart';
import 'components/log_list_panel.dart';
import 'components/pending_panel.dart';
import 'components/job_queue_panel.dart';
import 'components/merge_execution_panel.dart';
import 'components/status_bar.dart';
import 'components/dialogs/config_dialog.dart';
import 'components/dialogs/log_dialog.dart';
import 'components/dialogs/switch_branch_dialog.dart';

/// 操作阶段枚举
enum OperationPhase {
  /// 选择阶段：浏览日志、选择 revision
  select,

  /// 执行阶段：标准合并执行中
  execute,
}

/// 从 [MergeExecutionState] 的两个核心 flag 推断主屏当前应处于哪个交互阶段。
///
/// **契约（真值表，按 OR 语义合并）**：
/// | isProcessing | hasPausedJob | →                          |
/// |--------------|--------------|----------------------------|
/// | false        | false        | OperationPhase.select      |
/// | false        | true         | OperationPhase.execute     |
/// | true         | false        | OperationPhase.execute     |
/// | true         | true         | OperationPhase.execute     |
///
/// 反过来说：**唯一**进入 [OperationPhase.select] 的组合是 `(false, false)`——
/// 任何一个 flag 为真都立即切到执行阶段。这条反向契约由 #15 "反向断言契约边界"
/// 单测专门锁住，防止以后改成 AND 或单条件判定时被静默放过。
///
/// **为什么抽**：
/// - 原 `_getCurrentPhase` 接收 `MergeExecutionState`，单测必须构造 Provider，纯函数化后
///   只暴露两个 bool，单测直接传字面量即可。
/// - 该函数是整个主屏 select↔execute 视图切换的唯一入口（`build` 里的三元判定都基于它），
///   是个**载荷决策点**——一旦判定漏改，UI 会卡在错误阶段、用户操作错位。
/// - `pending` 状态的任务**不算**执行阶段：这是产品规则（`_getCurrentPhase` 注释也明确说了），
///   契约通过 `isProcessing` 取 `running` 而非更宽松的 `running||pending` 来体现，本函数只读两个
///   预消化好的 bool，把语义判断推给 caller（`merge_execution_state.dart` 的 getter）。
@visibleForTesting
OperationPhase resolveOperationPhase({
  required bool isProcessing,
  required bool hasPausedJob,
}) {
  if (isProcessing || hasPausedJob) {
    return OperationPhase.execute;
  }
  return OperationPhase.select;
}

/// 用户点"配置"准备改 sourceUrl/targetWc 时，是否需要先弹"二次确认"。
///
/// **行为契约（OR 真值表，与 [resolveOperationPhase] 同语义合并）**：
/// | isProcessing | hasPausedJob | →     |
/// |--------------|--------------|-------|
/// | false        | false        | false |
/// | false        | true         | true  |
/// | true         | false        | true  |
/// | true         | true         | true  |
///
/// **为什么要警告**：
/// - 已暂停 / 执行中的 `MergeJob` 都自带 `sourceUrl` / `targetWc` 字段副本（见
///   `lib/models/merge_job.dart`），改主屏的 `_sourceUrlController.text` 不会
///   反向改任务实例——用户极易以为"现在改了 source 就能影响下一步合并"，
///   但实际上 paused job resume 走的是任务自己保存的 source/target。
/// - 同时主屏 controller 的值是新加任务（`_addRevisionsToPending` /
///   `_startMergeWithSelected`）的输入源——改了之后再"继续"是改了**未来**任务，
///   不是当前 paused 任务。这条二义性历史上一直裸奔，没有任何 UI 提示。
///
/// **为什么不直接 disable "配置" 按钮**：用户可能就是想先把配置改回来再准备
/// 后续工作（比如终止当前任务后立刻新建任务）。disable 太硬，弹一个能"取消/继续"
/// 的对话框最不打扰、又能把责任明确告知用户。
///
/// **为什么用两个 bool 而不是直接接 [MergeExecutionState]**：保持本函数纯，单测
/// 不必构造 Provider；caller 在调用点用 `mergeState.isProcessing` 派生即可。
@visibleForTesting
bool shouldWarnBeforeEditingConfig({
  required bool isProcessing,
  required bool hasPausedJob,
}) =>
    isProcessing || hasPausedJob;

@visibleForTesting
bool hasPendingSourceMismatch({
  required List<int> pendingRevisions,
  required String currentSourceUrl,
  required String? pendingSourceUrl,
}) {
  if (pendingRevisions.isEmpty) {
    return false;
  }

  final current = currentSourceUrl.trim();
  final pending = (pendingSourceUrl ?? '').trim();
  if (current.isEmpty || pending.isEmpty) {
    return false;
  }

  return current != pending;
}

@visibleForTesting
String summarizeSourceUrl(String sourceUrl) {
  // 每个 segment 在 split 后单独 trim，再过滤掉空段（包括"纯空白段"）。
  // 这样 'svn://.../branches/v2  ' 这种带尾随/段内空白的输入也能拼出干净的
  // 'branches/v2' 提示文案，不会把空格漏到 UI 上。
  final segments = sourceUrl
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length >= 2) {
    return '${segments[segments.length - 2]}/${segments.last}';
  }
  return sourceUrl.trim();
}

@visibleForTesting
String deriveDefaultBranchesUrl(String currentTargetUrl) {
  final trimmed = trimSvnUrlTrailingSlash(currentTargetUrl);
  if (trimmed.isEmpty) return '';

  final segments = trimmed.split('/');
  final branchesIndex = segments.lastIndexOf('branches');
  if (branchesIndex >= 0) {
    return segments.sublist(0, branchesIndex + 1).join('/');
  }

  for (final marker in const ['trunk', 'tags']) {
    final index = segments.lastIndexOf(marker);
    if (index >= 0) {
      return [...segments.sublist(0, index), 'branches'].join('/');
    }
  }

  return joinSvnUrl(trimmed, 'branches');
}

@visibleForTesting
List<String> buildSwitchBranchHistory({
  required String currentTargetUrl,
  required String currentSourceUrl,
  required Iterable<String> switchBranchHistory,
  required Iterable<String> sourceUrlHistory,
  required Iterable<String> configuredSourceUrls,
}) {
  final urls = <String>{};
  void add(String url) {
    final normalized = stripUrlWhitespace(url);
    if (normalized.isNotEmpty) {
      urls.add(normalized);
    }
  }

  add(currentTargetUrl);
  add(currentSourceUrl);
  for (final url in switchBranchHistory) {
    add(url);
  }
  for (final url in sourceUrlHistory) {
    add(url);
  }
  for (final url in configuredSourceUrls) {
    add(url);
  }
  return urls.toList();
}

@visibleForTesting
String resolveInitialTargetUrl({
  required String? lastTargetUrl,
  required Iterable<String> targetUrlHistory,
}) {
  final last = stripUrlWhitespace(lastTargetUrl ?? '');
  if (last.isNotEmpty) return last;

  for (final url in targetUrlHistory) {
    final normalized = stripUrlWhitespace(url);
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

@visibleForTesting
bool shouldClearSelectedRevisionsOnSourceChange({
  required Iterable<int> selectedRevisions,
  required String? previousSourceUrl,
  required String currentSourceUrl,
}) {
  if (selectedRevisions.isEmpty) {
    return false;
  }

  final previous = (previousSourceUrl ?? '').trim();
  final current = currentSourceUrl.trim();
  return previous != current;
}

/// 当待合并列表绑定的源分支与当前选中的源分支不一致时，返回提示文案；否则返回 null。
///
/// 提示文案形如 `待合并列表来自 <pending>，当前日志来自 <current>`，源 URL 都会被
/// `summarizeSourceUrl` 截到尾两段。
@visibleForTesting
String? buildPendingSourceWarning({
  required List<int> pendingRevisions,
  required String currentSourceUrl,
  required String? pendingSourceUrl,
}) {
  final hasMismatch = hasPendingSourceMismatch(
    pendingRevisions: pendingRevisions,
    currentSourceUrl: currentSourceUrl,
    pendingSourceUrl: pendingSourceUrl,
  );
  if (!hasMismatch) {
    return null;
  }

  // 防御性兜底：在 hasMismatch=true 时 pendingSourceUrl 一定非空，但保留以防判定函数将来变化。
  if (pendingSourceUrl == null || pendingSourceUrl.trim().isEmpty) {
    return null;
  }

  return '待合并列表来自 ${summarizeSourceUrl(pendingSourceUrl)}，当前日志来自 ${summarizeSourceUrl(currentSourceUrl)}';
}

/// 把工作副本锁信息描述成简短中文短语，用于 “工作副本正在执行 X，请稍后再试” 之类提示。
///
/// - `lockInfo == null` → 返回 `当前操作`（兜底文案，避免拼出 `执行 null`）。
/// - 优先使用 `lockInfo.description`；为空时回落到 `operationType.label`。
@visibleForTesting
String describeLockOperation(WcLockInfo? lockInfo) {
  if (lockInfo == null) {
    return '当前操作';
  }
  return lockInfo.description ?? lockInfo.operationType.label;
}

/// 当工作副本被占用时，拼出"工作副本正在执行 X，请稍后再试"的完整提示文案。
///
/// **契约**：固定模板 `'工作副本正在执行${describeLockOperation(lockInfo)}，请稍后再试'`，
/// `lockInfo` 解析交由 [describeLockOperation] 处理。
///
/// **为什么抽**：`_svnUpdate` / `_svnRevert` / `_svnCleanup` 三处的锁占用错误分支拼了相同的
/// 字符串模板，未来如果文案要改（比如加上锁定时长 / 切换语言）只需要改这一处。
@visibleForTesting
String formatWcLockedMessage(WcLockInfo? lockInfo) {
  return '工作副本正在执行${describeLockOperation(lockInfo)}，请稍后再试';
}

/// 在 [jobs] 中按 `jobId` 线性查找任务；找不到返回 `null`。
///
/// **契约**：第一个匹配项即返回；当 jobId 在队列中重复（理论上不应发生，但模型不强制唯一）
/// 时只会返回首个。`jobs` 为空时直接返回 `null`。
///
/// 抽出自 `_findQueueJob`——核心是一个 jobId 等值匹配，与状态机/队列实现无关，便于在测试里
/// 用 `MergeJob` 列表字面量直接验证。
@visibleForTesting
MergeJob? findJobById(Iterable<MergeJob> jobs, int jobId) {
  for (final job in jobs) {
    if (job.jobId == jobId) {
      return job;
    }
  }
  return null;
}

/// 从一组日志条目中筛出"已被合并过"的 revision 集合（用于左侧 LogListPanel 的合并标记着色）。
///
/// **契约**（与 [computeSelectableRevisions] 形似但语义相反——一个收"还能选的"、本函数收"已经合过的"）：
/// - 返回 `Set<int>`，caller 直接传给 `LogListPanel.mergedRevisions` 用作行级 boolean 查询。
/// - `isMerged` 是注入的谓词（通常封装 `appState.isRevisionMergedSync(rev, sourceUrl, targetWc)`），
///   保持本函数纯——不依赖 Provider/AppState、不依赖 sourceUrl/targetWc 字符串本身。
/// - 顺序与 [entries] 一致（`Set` 实现是 `LinkedHashSet`），单测显式锁定。
/// - **不**与 [computeSelectableRevisions] 合并：那个还要排除 pending；本函数不关心 pending（界面
///   "已合并"标记不应被"已加入待办"覆盖——一个 revision 既可以"已合并过"又"出现在 pending"，
///   两个 Set 各自独立标记）。本注释里的"语义相反"即指此处的可同时为真。
@visibleForTesting
Set<int> computeMergedRevisions({
  required Iterable<LogEntry> entries,
  required bool Function(int revision) isMerged,
}) {
  final result = <int>{};
  for (final entry in entries) {
    if (isMerged(entry.revision)) {
      result.add(entry.revision);
    }
  }
  return result;
}

/// 从一组日志条目中筛出"既未在 pending 列表、又未被合并过"的 revision 集合。
///
/// **契约**：
/// - 返回 `Set<int>`——caller 既可以直接合并到 `_selectedRevisions`，也可以取 `.length` 当作
///   "可选项数量"展示（`_buildSelectPhaseView` 的 `selectableEntryCount` 与
///   `_selectAllSelectableRevisions` 的全选集合就是这两种用法）。
/// - `isMerged` 是注入的谓词（通常封装了 `appState.isRevisionMergedSync(rev, sourceUrl, targetWc)`），
///   保持本函数纯——不依赖 Provider/AppState。
/// - 顺序与 [entries] 一致（`Set` 实现是 `LinkedHashSet`），单测显式锁定。
@visibleForTesting
Set<int> computeSelectableRevisions({
  required Iterable<LogEntry> entries,
  required Iterable<int> pendingRevisions,
  required bool Function(int revision) isMerged,
}) {
  final pendingSet = pendingRevisions.toSet();
  final result = <int>{};
  for (final entry in entries) {
    final revision = entry.revision;
    if (pendingSet.contains(revision)) continue;
    if (isMerged(revision)) continue;
    result.add(revision);
  }
  return result;
}

/// 从日志条目构造提交阶段使用的完整原始 SVN message 映射。
///
/// key 使用字符串化 revision，直接匹配 [MergeJob.sourceMessagesByRevision] 的持久化形态。
/// value 必须来自 [LogEntry.message] 原始字段，不能使用列表展示层的单行化文本。
@visibleForTesting
Map<String, String> buildSourceMessagesByRevision(Iterable<LogEntry> entries) {
  final messages = <String, String>{};
  for (final entry in entries) {
    messages[entry.revision.toString()] = entry.message;
  }
  return messages;
}

/// 把"待合并列表绑定的源分支 URL"渲染成 PendingPanel 顶部的简短标签。
///
/// **契约**：
/// - `pendingSourceUrl == null` → `null`（PendingPanel 据此隐藏标签行）。
/// - trim 后为空 → `null`（同上，避免显示一个空尾段）。
/// - 否则用 [summarizeSourceUrl] 截到尾两段。
@visibleForTesting
String? buildPendingSourceLabel(String? pendingSourceUrl) {
  if (pendingSourceUrl == null) return null;
  if (pendingSourceUrl.trim().isEmpty) return null;
  return summarizeSourceUrl(pendingSourceUrl);
}

/// 决定"预加载进度文案"是否应该展示——只有当当前选中的源分支 URL 与预加载正在跑的源分支
/// 一致时，才把 [statusDescription] 展示在状态摘要里；否则**静默隐藏**。
///
/// **契约**（看似简单的三元写法藏着一个具体的产品规则——必须钉死）：
/// - `sourceUrl != preloadSourceUrl` → `null`（**静默**——不展示"该进度属于另一个分支"的提示，
///   因为切分支时旧进度对当前界面已经无意义；显式提示反而是噪音）。
/// - `sourceUrl == preloadSourceUrl` 且 `statusDescription == null` → `null`（同样隐藏——
///   预加载不在跑或未上报描述时，不渲染空行）。
/// - `sourceUrl == preloadSourceUrl` 且 `statusDescription != null` → 透传 [statusDescription]，
///   **不**对内容做 trim / 占位 / 截断（caller 决定如何排版）。
/// - `sourceUrl == ''` 与 `preloadSourceUrl == ''` 也算一致（按字符串等值匹配）；
///   生产路径下两者都为空意味着用户尚未选源，预加载也不会跑，进入 `statusDescription == null` 分支。
/// - **入参约定**：[sourceUrl] 是当前 UI 上的 trim 后字符串（caller 已经 `.text.trim()` 过），
///   [preloadSourceUrl] 是预加载进度自报的源分支字符串，两者按字面比较——
///   trim 不一致会被视为"不一致"，这是有意保留的契约（防止 caller 漏 trim 时静默拼接出错的进度）。
@visibleForTesting
String? resolvePreloadStatusText({
  required String sourceUrl,
  required String? preloadSourceUrl,
  required String? statusDescription,
}) {
  if (sourceUrl != preloadSourceUrl) return null;
  return statusDescription;
}

/// 日志列表底部"边界提示"的语义类型。
///
/// 把"还能不能继续加载"做成枚举而不是依赖字符串等值比较——
/// `canLoadMore` 直接读 [LogBoundaryDescription.canLoadMore] 字段即可，
/// 文案变了不会破坏判定。
enum LogBoundaryReason {
  /// 当前没有缓存日志，不展示边界提示。
  noCache,

  /// stopOnCopy 模式下，已加载到分支点。不可继续加载。
  reachedBranchPoint,

  /// stopOnCopy 模式下，离分支点还有距离，可继续加载。
  canExtendToBranchPoint,

  /// 预加载已完成且明确报告"无更早历史"。不可继续加载。
  preloadExhausted,

  /// 上次 `_loadMoreLogs` 返回 0 条新日志（针对当前 sourceUrl）。不可继续加载。
  noMoreHistory,

  /// 默认情况：可继续加载。
  canLoadMore,
}

/// 边界提示装配结果：UI 文案 + 可加载与否。
class LogBoundaryDescription {
  /// 展示给用户的文案；`null` 表示不展示边界提示行。
  final String? text;

  /// 当前边界状态分类。
  final LogBoundaryReason reason;

  const LogBoundaryDescription({required this.text, required this.reason});

  /// 是否可以继续向更旧 revision 扩展。
  ///
  /// **契约**：仅 [LogBoundaryReason.reachedBranchPoint] /
  /// [LogBoundaryReason.preloadExhausted] / [LogBoundaryReason.noMoreHistory]
  /// 三种"已到底"语义返回 false，其余（包括无缓存）返回 true。
  ///
  /// 注意：`noCache` 也算"可加载"——caller（`_buildSelectPhaseView`）会用
  /// `cachedLogCount > 0` 单独把按钮关掉，这里不重复判断。
  bool get canLoadMore {
    switch (reason) {
      case LogBoundaryReason.reachedBranchPoint:
      case LogBoundaryReason.preloadExhausted:
      case LogBoundaryReason.noMoreHistory:
        return false;
      case LogBoundaryReason.noCache:
      case LogBoundaryReason.canExtendToBranchPoint:
      case LogBoundaryReason.canLoadMore:
        return true;
    }
  }
}

/// 计算日志列表底部的"还能加载到哪里"边界提示。
///
/// **决策优先级（从高到低）**：
/// 1. `cachedLogCount == 0` → [LogBoundaryReason.noCache]，`text=null`
/// 2. stopOnCopy 模式且持有分支点 + 最早缓存 revision：
///    - 最早缓存 ≤ 分支点 → [LogBoundaryReason.reachedBranchPoint]
///    - 否则 → [LogBoundaryReason.canExtendToBranchPoint]，文案带 r{branchPoint}
/// 3. 预加载完成且当前 sourceUrl 的预加载明确报告 noMoreData
///    → [LogBoundaryReason.preloadExhausted]
/// 4. `noMoreHistorySourceUrl == sourceUrl` → [LogBoundaryReason.noMoreHistory]
/// 5. 默认 → [LogBoundaryReason.canLoadMore]
///
/// **抽离动机**：原 `_buildBoundaryText` 把 5 个分支揉在 30 行 if/return 链里，
/// 且 caller 通过 `boundaryText != '已到分支点，不再向更旧版本扩展'` 等字符串比较反推
/// "能不能加载更多"——文案一改就静默崩。改成结构化结果后，文案与判定彻底解耦。
@visibleForTesting
LogBoundaryDescription buildLogBoundaryDescription({
  required String sourceUrl,
  required String targetWc,
  required int cachedLogCount,
  required bool stopOnCopy,
  required int? cachedBranchPoint,
  required int? earliestCachedRevision,
  required String? preloadSourceUrl,
  required PreloadStatus preloadStatus,
  required PreloadStopReason? preloadStopReason,
  required String? noMoreHistorySourceUrl,
}) {
  if (cachedLogCount == 0) {
    return const LogBoundaryDescription(
      text: null,
      reason: LogBoundaryReason.noCache,
    );
  }

  if (stopOnCopy &&
      targetWc.isNotEmpty &&
      cachedBranchPoint != null &&
      earliestCachedRevision != null) {
    if (earliestCachedRevision <= cachedBranchPoint) {
      return const LogBoundaryDescription(
        text: '已到分支点，不再向更旧版本扩展',
        reason: LogBoundaryReason.reachedBranchPoint,
      );
    }
    return LogBoundaryDescription(
      text: '还可继续加载到分支点 r$cachedBranchPoint',
      reason: LogBoundaryReason.canExtendToBranchPoint,
    );
  }

  final preloadMatchesSource = preloadSourceUrl == sourceUrl;
  if (preloadMatchesSource &&
      preloadStatus == PreloadStatus.completed &&
      preloadStopReason == PreloadStopReason.noMoreData) {
    return const LogBoundaryDescription(
      text: '历史已全部加载',
      reason: LogBoundaryReason.preloadExhausted,
    );
  }

  if (noMoreHistorySourceUrl == sourceUrl) {
    return const LogBoundaryDescription(
      text: '历史已全部加载',
      reason: LogBoundaryReason.noMoreHistory,
    );
  }

  return const LogBoundaryDescription(
    text: '可继续向更旧 revision 扩展',
    reason: LogBoundaryReason.canLoadMore,
  );
}

/// 检查"开始合并"的前置条件，返回阻止合并的错误文案；通过则返回 `null`。
///
/// **校验顺序（与原 `_startMerge` 内 5 个 if 链严格一致——顺序敏感）**：
/// 1. 完整工作副本模式下 `sourceUrl` 或 `targetWc` 为空 → "请填写源 URL 和目标工作副本"
///    临时精简工作副本模式下 `sourceUrl` 或 `targetUrl` 为空 → "请填写源 URL 和目标 SVN URL"
/// 2. `pendingRevisions` 为空 → "待合并列表为空"
/// 3. 待合并列表绑定的源分支与当前不一致（[hasPendingSourceMismatch]）
///    → "当前源分支与待合并列表不一致，请先清空待合并列表"
/// 4. `(pendingSourceUrl ?? sourceUrl).trim()` 为空 → "待合并列表缺少源分支信息，请重新选择 revision"
/// 5. `isLocked == true` → "有暂停的任务需要处理"
/// 全部通过 → 返回 `null`，caller 继续 `addJob`。
///
/// **为什么抽**：原内联 5 个 if/return 分支在 stateful 方法里、依赖 Provider 与
/// controller，无法单测；且文案散落硬编码——以后改文案（比如 i18n）必须一处一处搜。
/// 抽出后：
/// - 文案与 caller 解耦，单测可逐条 expect 字面值
/// - **顺序敏感性**也被单测锁住（先验空字段，再验 mismatch 等）
/// - caller 退化为 `final err = validateMergeStartPreconditions(...); if (err != null) { _showError(err); return; }`
///
/// **注意**：`effectiveSourceUrl` 的计算（`pendingSourceUrl ?? sourceUrl` then trim）**不**包含在内——
/// 那是 caller 的职责（caller 还要用它做 `addJob` 调用），本函数只做校验。
@visibleForTesting
String? validateMergeStartPreconditions({
  required String sourceUrl,
  required TargetConfig targetConfig,
  required Iterable<int> pendingRevisions,
  required String? pendingSourceUrl,
  required bool isLocked,
}) {
  if (targetConfig.isTemporarySparseWorkingCopy) {
    if (sourceUrl.isEmpty || targetConfig.svnUrl.isEmpty) {
      return '请填写源 URL 和目标 SVN URL';
    }
  } else if (sourceUrl.isEmpty || targetConfig.workingCopyPath.isEmpty) {
    return '请填写源 URL 和目标工作副本';
  }

  final pendingList = pendingRevisions.toList(growable: false);
  if (pendingList.isEmpty) {
    return '待合并列表为空';
  }

  if (hasPendingSourceMismatch(
    pendingRevisions: pendingList,
    currentSourceUrl: sourceUrl,
    pendingSourceUrl: pendingSourceUrl,
  )) {
    return '当前源分支与待合并列表不一致，请先清空待合并列表';
  }

  final effectiveSourceUrl = (pendingSourceUrl ?? sourceUrl).trim();
  if (effectiveSourceUrl.isEmpty) {
    return '待合并列表缺少源分支信息，请重新选择 revision';
  }

  if (isLocked) {
    return '有暂停的任务需要处理';
  }

  return null;
}

@visibleForTesting
String resolveLogTargetStateKey(TargetConfig targetConfig) {
  return targetConfig.isTemporarySparseWorkingCopy
      ? targetConfig.svnUrl.trim()
      : targetConfig.workingCopyPath.trim();
}

/// 决定"删除任务成功" SnackBar 应该显示哪条文案。
///
/// **契约**（与原 `_deleteQueueJob` 内联三元 `job.status == JobStatus.pending ? ... : ...` 严格一致）：
/// - `JobStatus.pending` → `'任务 #N 已移出队列'`（语义：还没跑过的任务被取消排队）
/// - 其他全部 4 个状态（`running` / `paused` / `done` / `failed`）→ `'任务 #N 记录已移除'`
///   （语义：跑过的任务记录被清理；不影响 SVN 仓库）
///
/// **为什么用穷举式 switch 而非保留三元**：
/// - 三元只有"pending vs 其他"两条分支，JobStatus 未来若增加第 6 态（如 `cancelled`），
///   会被默默归到"记录已移除"——这未必是想要的，加新枚举时应该被强制 review。
/// - 显式 switch + 单测真值表锁定 5 个状态的字面文案，未来增态时编译器立刻提示。
///
/// **Why not 合并到 displayName**：
/// `JobStatusExtension.displayName` 是"状态名"（"等待"、"完成"...），本函数渲染的是
/// "操作结果文案"（"已移出队列" vs "记录已移除"），前缀都不同，刻意不复用——
/// 设计模式 #9：形似但语义不同的函数不合并。
///
/// **入参契约**：`jobId` 直接拼到 `'#N'`，不做合法性校验（负数/0 也照常拼接，由 caller 保证非空）。
@visibleForTesting
String describeJobDeletionSuccess({
  required int jobId,
  required JobStatus status,
}) {
  switch (status) {
    case JobStatus.pending:
      return '任务 #$jobId 已移出队列';
    case JobStatus.running:
    case JobStatus.paused:
    case JobStatus.done:
    case JobStatus.failed:
      return '任务 #$jobId 记录已移除';
  }
}

/// 删除单条任务前的二次确认 dialog 文案。
///
/// **为什么需要**：删除任务是不可逆破坏性操作——失败 / 已完成的任务可能含数十至数百条
/// 已合并 revision 的进度记录，误点会让用户无法回到原 jobId 确认进度。同 panel
/// `_clearPendingJobs` / `_cancelPausedJobWithConfirm` / `_clearHistoryJobs` 都走
/// `_confirmQueueAction`，唯有单条删除原裸调没有兜底——这条收口拉齐破坏性操作的体验。
///
/// **文案分支**（基于 `completedIndex.clamp(0, totalRevisions)`）：
/// - `clamped == 0` → 没合并过任何 revision，仅警告"任务无法恢复"：
///   `'删除后任务将从队列移除，任务无法恢复。'`
/// - `clamped > 0` → 已有合并进度，显示进度数字让用户掂量代价：
///   `'删除后任务将从队列移除，已合并 X / Y 个 revision 不会回滚但任务无法恢复。'`
///
/// **决策权衡**：
/// - 文案动词"删除后任务将从队列移除"与 R13 终止任务"终止后任务将从队列移除"句式同型，
///   保持破坏性操作文案家族一致；
/// - 不复用 `formatJobProgressText` 等 helper——文案语境是 confirm dialog 而非 status bar，
///   语序与 join 字符不同（confirm 强调"X / Y 不会回滚"语义）；
/// - `completedIndex` 走 `clamp(0, totalRevisions)` 与 `clampedCompletedRevisionCount`
///   同款边界保护，避免 completedIndex 越界（虽然 model 已保证，但 doc 锁更稳）。
@visibleForTesting
String buildDeleteJobConfirmMessage({
  required int completedIndex,
  required int totalRevisions,
}) {
  final clamped = completedIndex.clamp(0, totalRevisions);
  if (clamped == 0) {
    return '删除后任务将从队列移除，任务无法恢复。';
  }
  return '删除后任务将从队列移除，已合并 $clamped / $totalRevisions 个 revision 不会回滚但任务无法恢复。';
}

/// `_markConflictsResolved` 成功路径的 SnackBar 文案（按"标记后是否真的清干净"分流）。
///
/// **为什么需要**：`svn resolve --accept <mode>` 退出码 0 **不**保证 working copy
/// 不再有冲突——tree conflict / mode 与文件实际状态不匹配 / 部分文件未被 -R 命中
/// 时，svn 可能 exit 0 但 `svn status` 首列仍出现 'C' 行。原 `_markConflictsResolved`
/// 仅 `if (result.isSuccess)` 一条路径直接报告"已标记冲突为已解决"，用户点"继续"
/// 任务跑到 merge 步又重新冲突暂停，浪费时间且体验割裂。
///
/// **契约（两档）**：
/// - `remainingConflictCount <= 0` → 走原成功文案
///   `'已标记冲突为已解决（accept X），可点击"继续"重试'`；
/// - `remainingConflictCount > 0` → 走警告文案
///   `'已运行 svn resolve（accept X），但仍检测到 N 个冲突文件，请手动检查后再继续'`，
///   显式让用户知道**不要**直接点继续，先去 WC 看看哪些文件还没干净。
///
/// **为什么不复用 `hasConflicts`（bool）**：bool 没法在文案里报"还剩 N 个"——
/// caller 走 `listConflictedFiles(targetWc).length` 同一份 svn status 解析、
/// 既能反映 bool 等价语义、又能告诉用户具体数量；本 helper 接 int 而非 bool
/// 把"是否警告"和"剩余数量"两个语义统一在一个入参里，单测真值表更紧凑。
///
/// **不做的事**：本 helper **不**返回 stderr / 失败文案——失败路径（`result.isSuccess == false`）
/// 与 catch 分支由 caller 直接处理，与 cleanup / openWc 等 paused-action 反馈风格一致；
/// 本 helper 仅覆盖"svn resolve 退出 0 但 WC 仍脏"的隐藏漏洞。
@visibleForTesting
String formatMarkResolvedFeedback({
  required String modeFlag,
  required int remainingConflictCount,
}) {
  if (remainingConflictCount <= 0) {
    return '已标记冲突为已解决（accept $modeFlag），可点击"继续"重试';
  }
  return '已运行 svn resolve（accept $modeFlag），但仍检测到 $remainingConflictCount 个冲突文件，请手动检查后再继续';
}

/// `svn cleanup` 成功路径的 SnackBar 文案（按"cleanup 后 WC 是否真可用"分流）。
///
/// **为什么需要**：`svn cleanup` 退出码 0 **不**保证 working copy 真的能继续使用——
/// 外部进程仍持有文件锁、`.svn` 元数据被破坏、磁盘故障、权限异常等场景下 svn 仍可能
/// exit 0（cleanup 只能处理"卡住的事务"，处理不了"WC 结构性损坏 / 外部占用"）。
/// 原 `_runSvnCleanup` / `_svnCleanup` 仅 `if (result.isSuccess)` 一条路径直接报告
/// "已执行 svn cleanup"，用户点"继续"任务跑到下一步又因 .svn 不可读 / 文件被锁再次
/// 暂停，体验割裂。
///
/// **两个 caller 的语境差异（[resumePrompt] 入参）**：
/// - 暂停态 `_runSvnCleanup`（`resumePrompt: true`，默认）：紧跟"暂停 → 继续"流，
///   成功文案需明示"可点击 继续 重试"；失败文案末尾"请手动检查后再继续"。
/// - 主屏工具栏 `_svnCleanup`（`resumePrompt: false`）：用户主动点击"清理工作副本"，
///   不在暂停 → 继续语境；成功文案为"清理完成，工作副本已可用"；
///   失败文案末尾"请手动检查"（无"再继续"）。
///
/// **契约（两档 × resumePrompt 维度）**：
/// - `probeError == null`（含 `''` empty string 防御）→ 走成功文案：
///   - `resumePrompt: true`  → `'已执行 svn cleanup，可点击"继续"重试'`
///   - `resumePrompt: false` → `'清理完成，工作副本已可用'`
/// - `probeError` 是非空错误描述（[SvnService.probeSvnLocation] 已经过
///   `formatProbeFailureReason` 翻译，不含多行 stderr 噪音）→ 走警告文案：
///   - `resumePrompt: true`  → `'已运行 svn cleanup，但工作副本仍不可用：<probeError>，请手动检查后再继续'`
///   - `resumePrompt: false` → `'已运行 svn cleanup，但工作副本仍不可用：<probeError>，请手动检查'`
///
/// **为什么用 [SvnService.probeSvnLocation] 而非 hasConflicts / status**：
/// - cleanup 修复的不是冲突，是事务锁 / 元数据；后验维度应当是"WC 元数据是否可读"
///   而非"是否有冲突标记"——`svn info <wc>` 是最直接的"WC 是否可用"探针。
/// - 与第二十六轮 `_startMerge` 预校验、第二十九轮 `_testSvnConnectivity` 同款
///   `probeSvnLocation` 入口家族——错误翻译 / SnackBar 噪音控制规则单一来源。
///
/// **不做的事**：本 helper **不**返回 stderr / 失败文案——cleanup 自身失败路径
/// （`result.isSuccess == false`）与 catch 分支由 caller 直接处理（保持原 SnackBar），
/// 与 [formatMarkResolvedFeedback] 同款风格；本 helper 仅覆盖"svn cleanup 退出 0
/// 但 WC 仍不可用"的隐藏漏洞。
@visibleForTesting
String formatCleanupFeedback({
  String? probeError,
  bool resumePrompt = true,
}) {
  final unusable = probeError != null && probeError.isNotEmpty;
  if (!unusable) {
    return resumePrompt ? '已执行 svn cleanup，可点击"继续"重试' : '清理完成，工作副本已可用';
  }
  final tail = resumePrompt ? '请手动检查后再继续' : '请手动检查';
  return '已运行 svn cleanup，但工作副本仍不可用：$probeError，$tail';
}

/// `svn update` 成功路径的 SnackBar 文案（按"update 后是否仍有冲突文件"分流）。
///
/// **为什么需要**：`svn update` 在服务器端改动与本地修改产生冲突时，svn 仅把冲突文件
/// 标记为 'C' 状态并继续返回 exit 0——也就是说 `result.isSuccess == true` **不**保证
/// working copy 真的干净。原 `_svnUpdate` 仅 `if (result.isSuccess) _showSuccess('更新完成')`
/// 一条路径直接报告"更新完成"，用户随后启动合并任务又因 'C' 状态文件再次暂停，体验割裂。
///
/// **契约（两档）**：
/// - `remainingConflictCount <= 0`（含负数防御，`listConflictedFiles` 实际不会返回负数，
///   但 helper 接 int 不应在边界上崩）→ `'更新完成，工作副本干净'`
/// - `remainingConflictCount > 0` → `'已执行 svn update，但仍有 N 个冲突文件，请手动解决'`
///
/// **为什么用 [SvnService.listConflictedFiles] 而非 hasConflicts**：bool 没法在文案里
/// 报"还剩 N 个"——caller 走 `listConflictedFiles(targetWc).length` 同一份 svn status
/// 解析、既能反映 bool 等价语义、又能告诉用户具体数量；本 helper 接 int 而非 bool
/// 把"是否警告"和"剩余数量"两个语义统一在一个入参里，单测真值表更紧凑。
/// 与第二十八轮 [formatMarkResolvedFeedback] 同款设计动机——后验维度是冲突数 int。
///
/// **不做的事**：本 helper **不**返回 stderr / 失败文案——update 自身失败路径
/// （`result.isSuccess == false`）与 catch 分支由 caller 直接处理（保持原 SnackBar），
/// 与 [formatMarkResolvedFeedback] / [formatCleanupFeedback] 同款风格；本 helper 仅
/// 覆盖"svn update 退出 0 但 WC 仍有 'C' 状态文件"的隐藏漏洞。
@visibleForTesting
String formatUpdateFeedback({int remainingConflictCount = 0}) {
  if (remainingConflictCount <= 0) {
    return '更新完成，工作副本干净';
  }
  return '已执行 svn update，但仍有 $remainingConflictCount 个冲突文件，请手动解决';
}

/// "加载更多日志"按钮是否应当启用。
///
/// **契约（合取——两个条件必须同时成立）**：
/// - `cachedLogCount > 0`：必须有缓存日志才能"再加载"——`LogBoundaryDescription.canLoadMore`
///   注释明确说 `noCache → canLoadMore=true`（"无缓存"算可加载，因为它是"还没开始"语义），
///   这意味着 caller 必须**额外**用 `cachedLogCount > 0` 把"还没开始加载"和"已加载过且能继续"
///   两种语义分裂——不能只看 boundary 一个 flag。
/// - `boundary.canLoadMore`：边界判定显式允许（未到分支点 / 未耗尽 / 未到底）。
///
/// **为什么抽**：原 `_buildSelectPhaseView` 内联 `_cachedLogCount > 0 && boundary.canLoadMore`
/// 把这条"两 flag 必须 AND"的契约埋在 widget 装配代码里——任何人误删一边、或把 caller
/// 改成只读 boundary 一个值，UI 会在 cachedLogCount==0 的瞬间错误地把按钮亮起来
/// （或反之，当 boundary=false 但 cachedLogCount>0 时该禁不禁）。抽出后单测显式锁
/// 4 种 (cachedLogCount cmp 0, canLoadMore) 真值表组合，回归不会再静默。
///
/// **入参约定**：
/// - `cachedLogCount` 取自 `_cachedLogCount`，约定 ≥ 0；负数会被等同于 0（`> 0` 判定）。
/// - `boundary` 是 [buildLogBoundaryDescription] 的返回值，仅依赖其 `.canLoadMore` getter——
///   函数本身不复算 reason，避免和 [LogBoundaryDescription.canLoadMore] 的 3-of-6 名单逻辑
///   重复，单一来源。
@visibleForTesting
bool resolveCanLoadMore({
  required int cachedLogCount,
  required LogBoundaryDescription boundary,
}) {
  return cachedLogCount > 0 && boundary.canLoadMore;
}

/// "添加到待合并"成功提示文案——基于"用户期望加入数量 vs 实际新增数量"分流。
///
/// **真 bug 背景**：`_addSelectedToPending` 早期版本固定弹 `已添加 $count 个 revision`，
/// 其中 `count = _selectedRevisions.length`。但 [AppState.addPendingRevisions] 转发到
/// [mergePendingRevisions]，对 incoming 与 existing 做 union 去重——如果用户选中的
/// revision 已在 pendingRevisions 中（再次添加 / 跨筛选切换 / 跨页选择），实际新增数
/// `< selectedCount`，但 SnackBar 仍报 selectedCount，与 `_showInfo('已清空 N 个待合并
/// revision')` / `_showSuccess('已删除任务 #ID')` 等家族里一贯的"反馈数 == 真实数"
/// 契约不一致，属于真 UX bug 而非纯样式分歧。
///
/// **三档分流（合取——三档互斥且穷尽）**：
/// - `addedCount == 0`：所选 revision 全部已在列表中——文案"全部 N 个 revision 已在
///   待合并列表中"，避免误导用户以为加入了新内容。
/// - `addedCount == selectedCount`：全部 N 个都是新加入——保留原文案"已添加 N 个 revision"
///   维持兼容（既有用户文案肌肉记忆 + 字面量层无破坏性变更）。
/// - `0 < addedCount < selectedCount`：部分新增、部分已存在——文案"已添加 M 个 revision
///   （其中 K 个已在列表中跳过）"，K = selectedCount - addedCount。
///
/// **入参约定**：
/// - `selectedCount`：用户在 UI 选中的 revision 数量（_selectedRevisions.length 快照），
///   约定 ≥ 1 才进入 caller（`_addSelectedToPending` 已在前置 if 拦掉空选）；
///   防御性接受 0：addedCount 必然也是 0，落到第一档"全部 0 个" 文案——
///   实际不会被 caller 触发，仅为单测 / 未来重构容错。
/// - `addedCount`：调用 `addPendingRevisions` 前后 `pendingRevisions.length` 的差值，
///   约定 ∈ [0, selectedCount]——不变量由 [mergePendingRevisions] 的 union 语义保证。
///
/// **不做的事**：本 helper **不**判断 selectedCount == 0 的空提示——caller 自己用
/// _showError('请先选择...')；本 helper 只覆盖"已加成功后该说什么"路径。
@visibleForTesting
String formatPendingAddSnackBar({
  required int selectedCount,
  required int addedCount,
}) {
  if (addedCount == 0) {
    return '全部 $selectedCount 个 revision 已在待合并列表中';
  }
  if (addedCount == selectedCount) {
    return '已添加 $addedCount 个 revision';
  }
  final skipped = selectedCount - addedCount;
  return '已添加 $addedCount 个 revision（其中 $skipped 个已在列表中跳过）';
}

/// _runLogDataAction 中 sync 段成功但 apply 段（_applySelectionContext）失败时的
/// SnackBar 文案 helper。
///
/// **真 bug 背景**：`_runLogDataAction` 早期版本把 `action()`（sync 段写 DB / 远程拉取）
/// 与 `_applySelectionContext()`（UI 段刷 minRevision / mergeinfo / log cache summary）
/// 包在同一个 `try` 块内。当 sync 成功（addedCount=N>0、SVN 已落盘）但 apply 抛错
/// （DB 锁 / 缓存服务异常 / 文件权限等），catch 块统一弹 `'日志同步失败: $e'`，
/// 与实际状态完全背离——日志已同步但 UI 没刷新，用户误以为同步未完成会再点
/// "同步最新"重新触发远程 SVN 请求（浪费带宽 + 极端情况触发 SVN 服务端节流）。
///
/// 修复方案：caller 拆成两段 try——sync 段抛错走原"日志同步失败"路径，apply
/// 段抛错走本 helper 渲染的"已同步但刷新失败"路径，让用户从文案就能区分两种
/// 失败语义。与第三十七轮 `formatPendingAddSnackBar` "反馈数 == 真实数" family 同型。
///
/// **两档分流**：
/// - `addedCount > 0`：sync 真有新数据，主信息突出"已同步 N 条" + 提示界面刷新失败
///   可重试，避免用户重复点 sync。
/// - `addedCount <= 0`：sync 完成但无新数据，apply 失败提示用户界面状态可能过期，
///   可重新切换 sourceUrl 触发再刷。
///
/// **不变量**：caller 保证 sync 段已成功返回；`error` 来自 apply 段 catch 的 `$e` 字符串。
@visibleForTesting
String formatLogApplyFailureFeedback({
  required int addedCount,
  required String error,
}) {
  if (addedCount > 0) {
    return '日志已同步 $addedCount 条，但界面刷新失败: $error；'
        '可重试同步或切换源 URL 重新加载';
  }
  return '日志同步完成但界面刷新失败: $error；可切换源 URL 重新加载';
}

/// _openConflictFile 成功后 SnackBar 文案 helper。
///
/// **职责**：根据 `listConflictedFiles` 返回的总数和实际打开的相对路径，
/// 生成两档分流文案——单冲突简版 / 多冲突带剩余数提示。
///
/// **入参**：
/// - `totalCount`：当次 `listConflictedFiles` 返回的冲突文件总数；
/// - `openedRelative`：本次打开的那条（即 `conflicted.first`）。
///
/// **为什么两档**：
/// - `totalCount == 1` 时用户只需改这一个，简洁文案足够；
/// - `totalCount > 1` 时用户不知道还有几个等着，必须明示"1/N + 改完点继续会重检"。
///
/// **不变量**：caller 已保证 `totalCount >= 1`（`isEmpty` 路径已在外层走 "未发现冲突文件" 提示）。
@visibleForTesting
String formatOpenConflictFileFeedback({
  required int totalCount,
  required String openedRelative,
}) {
  if (totalCount <= 1) {
    return '已打开冲突文件: $openedRelative';
  }
  return '已打开冲突文件 1/$totalCount: $openedRelative；改完后点"继续"会自动检测剩余冲突';
}

@visibleForTesting
String buildGfCrTitle(MergeJob job) {
  final revision = job.currentRevision;
  final sourceName = extractSourceDisplayName(job.sourceUrl);
  final targetName = extractSourceDisplayName(job.targetUrl ?? job.targetWc);
  final revisionPart = revision == null ? '' : ' r$revision';
  return 'Merge$revisionPart: $sourceName -> $targetName';
}

@visibleForTesting
String buildGfCrDescription(MergeJob job) {
  final revision = job.currentRevision;
  final lines = <String>[
    if (revision != null) 'Revision: r$revision',
    'Source: ${job.sourceUrl}',
    if (job.targetUrl != null && job.targetUrl!.isNotEmpty)
      'Target: ${job.targetUrl}',
    'Working copy: ${job.targetWc}',
  ];
  return lines.join('\n');
}

/// Code Review 发起成功后，用于对话框展示的完整提交 Message。
///
/// 优先使用 [buildCommitMessage]（含已自动回填的 [MergeJob.commitSupplement]）；
/// 无当前 revision 时回退到 supplement 文本。
@visibleForTesting
String buildCodeReviewCommitMessage(MergeJob job) {
  final revision = job.currentRevision;
  if (revision == null) {
    return job.commitSupplement?.trim() ?? '';
  }
  return buildCommitMessage(job, revision);
}

@visibleForTesting
String shellSingleQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

@visibleForTesting
String escapeAppleScriptString(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', r'\"');
}

@visibleForTesting
OpenDirectoryCommand? resolveGfAuthLoginCommand({
  required String platform,
  required String workingDirectory,
}) {
  final quotedDir = shellSingleQuote(workingDirectory);
  switch (platform) {
    case 'macos':
      final script = 'cd $quotedDir; gf auth login';
      return OpenDirectoryCommand(
        executable: 'osascript',
        args: [
          '-e',
          'tell application "Terminal" to do script "${escapeAppleScriptString(script)}"',
          '-e',
          'tell application "Terminal" to activate',
        ],
      );
    case 'linux':
      return OpenDirectoryCommand(
        executable: 'x-terminal-emulator',
        args: [
          '-e',
          'bash',
          '-lc',
          'cd $quotedDir; gf auth login; exec bash',
        ],
      );
    case 'windows':
      return OpenDirectoryCommand(
        executable: 'cmd',
        args: [
          '/c',
          'start',
          '',
          'cmd',
          '/k',
          'cd /d "$workingDirectory" && gf auth login',
        ],
      );
  }
  return null;
}

class _LogSelectionContext {
  final String sourceUrl;
  final String targetWc;
  final String targetStateKey;
  final bool stopOnCopy;
  final int? minRevision;

  const _LogSelectionContext({
    required this.sourceUrl,
    required this.targetWc,
    required this.targetStateKey,
    required this.stopOnCopy,
    required this.minRevision,
  });
}

class MainScreenV3 extends StatefulWidget {
  const MainScreenV3({super.key});

  @override
  State<MainScreenV3> createState() => _MainScreenV3State();
}

/// **R131 widget setState 时机 + mounted check 一致性审计 — 三档分类**：
///
/// 本类与 `settings_screen.dart:_SettingsScreenState` 是 lib 内仅有的两个
/// 持有 setState 调用的 State 类（lib 内非 widget 类 0 处 setState —— 与
/// R130 I4 "0 处 addListener / removeListener" 同律契约）。setState 的时机
/// 按"调用栈是否跨过 await"分三档：
///
/// - **档 1 = sync 直接 setState**：在同步事件回调（onPressed / onTap /
///   onChanged / onSelectionChanged / onHorizontalDragUpdate 等）内紧跟
///   mutator 调用，**闭包内不存在任何 await**；本类站点：1127 / 1146 / 1159
///   / 1208 / 1253 / 1574 / 1705+ / 1736+ / 1801+ / 1810+ / 1838+。这一档
///   不需要 mounted check —— Flutter framework 保证：如果 widget 已 unmount，
///   事件回调不会触发（gesture / pointer router 已解绑）。
/// - **档 2 = conditional / 嵌套 mounted-guarded setState**：setState 出现在
///   被宿主函数 mounted-guard 包裹的回调闭包内；本类站点：`_loadMoreLogs`
///   闭包内 1098 / 1100 处 setState，由 1093 行 `if (!mounted) return` 守护
///   addedCount，但是 closure 自带前置 guard；以及 `_syncLatestLogs` 闭包
///   内 1071 处（**R131 修复**：原先紧跟 await 后无 mounted check，现已补
///   `if (!mounted) return` 与 `_loadMoreLogs` 对偶对齐）。
/// - **档 3 = async-bracket setState**：跨 `await` 边界后的 setState，必须
///   前置 `if (!mounted) return;` 或 `if (mounted) { ... }`；本类站点：
///   643 行（`_preloadService.init().then` 回调，641 行 `if (!mounted)
///   return` 守护）/ 699 行（`getPreloadSettingsTyped` await 后，698 行
///   `if (mounted)` 守护）/ 844 行（`getLatestRangeEntryCount` await 后，
///   842 行 `if (!mounted) return` 守护）/ 1558 行（`SettingsScreen.show`
///   await 后，1557 行 `mounted` 短路）。
///
/// **跨档不变量 I1/I2/I3**：
/// - I1: 档 3 站点 100% 配 mounted check —— 否则 framework 抛出
///   `setState() called after dispose()`；这是 **运行时硬性契约**，不是
///   软约定（与 R125 release 序列方向 / R127 init 末位 notify 同等强度）。
/// - I2: lib 内非 widget 类 0 处 setState —— provider / service 类只能通过
///   notifyListeners 触发刷新（R128 协议），不允许跨类直接 setState；
///   与 R130 I4 (0 处 addListener) 形成**接合面**：provider 推送（生产）+
///   widget setState（消费）+ 0 监听器订阅 = "推送-消费链路严格分离"。
/// - I3: 档 2 / 档 3 不可降档为档 1 —— 即使闭包"看起来"是同步事件，只要
///   存在 await 边界（直接 / 通过宿主函数间接）就必须当档 3 处理。
///   `_syncLatestLogs` 闭包就是 R131 漏档案例：原先按"档 1 同步直觉"写
///   `setState`，实际是档 3（闭包内有 await）—— 本轮补 mounted check 修正。
///
/// **与 R128/R129/R130 接合面 (R131 是接合面三角的 widget-side 镜像)**：
/// - R128 锁 provider notifyListeners 触发协议（生产端时机）；
/// - R129 锁 widget lifecycle dispose（消费端释放）；
/// - R130 锁 cross-provider 通信链路（生产-消费图）；
/// - **R131 锁 widget setState 时机（消费端时机）** —— 与 R128 形成
///   "trigger 协议对偶"：provider 用 notifyListeners 自触发 / widget 用
///   setState 自触发，两者各有"生命周期 race 防护契约"（provider 在
///   `dispose` 后 notifyListeners 抛 `assert(_debugDisposed != true)` /
///   widget 在 `unmount` 后 setState 抛 `setState() called after dispose`）。
///
/// **R131 漏档收口**：本轮通过审计发现 2 处真实档 3 漏 mounted check
/// 站点（main_screen_v3.dart:1071 _syncLatestLogs / settings_screen.dart:315
/// _pickDate），均补 `if (!mounted) return` 修正；这是 R85-R89 漏迁巡检
/// 模式在 widget 维度的延伸 —— "看起来对的代码"经审计才发现是 race 隐患。
///
/// **R132 TextEditingController.text 写时机审计 — 三档分类**：
/// R131 锁 setState 时机，R132 锁 `.text=` 写时机 —— **同三档框架**，
/// 同跨档不变量 I1/I2/I3，但目标资源是 owned `TextEditingController`
/// 而非 widget 自身的 setState 调度器。dispose 后写 `.text=` 抛
/// `FlutterError: A TextEditingController was used after being disposed`。
///
/// 三档分类：
/// - **档 1 = sync 直接 .text=**：在同步事件回调或 initState 同步路径内
///   紧跟 `.text =`，闭包内不存在 await；本类站点：`_initializeFields`
///   814 / 817 / 821 行（initState 同步路径）；config_dialog.dart:72/98
///   onSelected 同步事件；settings_screen `_loadSettings` 同步赋值。
///   档 1 不需 mounted check —— widget 未 mount 前不进 build / 事件回调
///   不会触发于 unmounted widget。
/// - **档 2 = 嵌套 mounted-guarded .text=**：受宿主函数 mounted-guard
///   守护的回调闭包内 `.text=`；本 lib 当前 0 处。
/// - **档 3 = async-bracket .text=**：跨 `await` 边界后的 `.text=`，
///   必须前置 `if (!mounted) return;`（StatefulWidget）或
///   `if (!context.mounted) return;`（StatelessWidget）；本类站点：
///   `_loadAuthorFilterHistory:831`（**R132 修复**：原先 await
///   `getLastAuthorFilter()` 后无 mounted check 直接写
///   `_filterAuthorController.text`）；config_dialog.dart:`_pickTargetWc:49`
///   （**R132 修复**：StatelessWidget 用 `context.mounted` 替代）；
///   settings_screen.dart:`_pickDate:318`（已由 R131 补 `if (!mounted) return`
///   守护，setState 闭包内 `.text=` 一并受保护——R131 修复同时覆盖
///   R132 维度）。
///
/// **R132 跨档不变量 I1/I2/I3**（与 R131 同模板）：
/// - I1: 档 3 `.text=` 站点 100% 配 mounted / context.mounted check ——
///   运行时硬性契约（与 R131 setState I1 同律）。
/// - I2: 仅 widget 类持有 owned TextEditingController —— provider /
///   service / model 0 处 `TextEditingController` 字段（与 R131 I2 setState
///   同律的 controller 维度对偶）。
/// - I3: StatefulWidget 用 `mounted` / StatelessWidget 用 `context.mounted`
///   —— 不可混用（StatelessWidget 无 `mounted` 字段；StatefulWidget 有
///   两者但 `mounted` 字段更可靠，因 `context.mounted` 在 dispose-as-context-
///   parent 边界期间 0.x ms 内可能短暂返回 true）。
///
/// **R129/R131/R132 widget owned-resource 三角接合面**：
/// - R129 锁 dispose（owned controller 何时释放）；
/// - R131 锁 setState（widget 何时刷新）；
/// - **R132 锁 `.text=`（owned controller 何时变更）** ——
///   三轮正交叠加形成 widget owned-resource 完整审计三角：释放 / 刷新 /
///   变更。任何 owned `TextEditingController` 必同时锁三轮契约。
///
/// **R132 漏档收口**：本轮发现 2 处真实档 3 漏 mounted check 的 `.text=`
/// 站点（main_screen_v3.dart:831 _loadAuthorFilterHistory /
/// config_dialog.dart:49 _pickTargetWc），均补 mounted / context.mounted
/// 守护；这是 R85-R89 漏迁巡检模式在 widget owned-resource 维度的二次延伸
/// （R131 = setState 维度首次延伸 / R132 = .text= 维度二次延伸）。
class _MainScreenV3State extends State<MainScreenV3> {
  // ============ Controllers ============
  //
  // **R133 controller flow topology — owner/borrower/disposer 三角分离协议**：
  // R129 锁 dispose 时机（释放点）/ R131 锁 setState 时机（widget 自身刷新）/
  // R132 锁 `.text=` 时机（owned controller 变更）；R133 锁 controller **流向
  // 拓扑**——同一 controller 跨 widget 边界后，三种角色（创建/写/释放）可分离。
  //
  // **三角色定义**：
  // - **Owner（创建者 + 释放者，单一职责）**：构造 `TextEditingController()` 的
  //   类，必须在自身 dispose 内 `.dispose()`。owner = disposer 是 R129 I3
  //   1:1 owned-vs-disposed parity 在跨 widget 维度的强化——即使 controller 被
  //   传给其他 widget，dispose 责任**不可转移**，否则 borrower lifecycle 短于
  //   owner lifecycle 时（Dialog dismiss）会让 owner 持有已 disposed 引用。
  // - **Writer（写入者，可多点）**：执行 `.text=` 的代码位置；可以是 owner 自身
  //   或 borrower。R132 三档分类（sync 直接 / 嵌套 mounted-guarded / async-bracket）
  //   在每个 writer 站点独立适用——borrower 内的 async-bracket 必用
  //   `context.mounted`（StatelessWidget）/ owner 内的必用 `mounted` 字段
  //   （StatefulWidget），R132 I3 已锁。
  // - **Borrower（借用者，纯写或纯读，无释放责任）**：通过 final field /
  //   构造参数接收 controller 引用的 widget，仅消费（read `.text` / write
  //   `.text=` / 绑定到 `TextField.controller:`）；**故意不 dispose**——若
  //   borrower dispose 会导致 owner 后续 .text= 抛 disposed exception。
  //
  // **本类的 owner-borrower 拓扑（R133 doc-as-test 反向锁的目标）**：
  // | Controller                | Owner            | Borrowers (writers)    | Borrowers (readers-only) |
  // |---------------------------|------------------|------------------------|--------------------------|
  // | `_sourceUrlController`    | _MainScreenV3State | SourceUrlDialog (写×1) | SourceUrlDialog (TextField) |
  // | `_targetWcController`     | _MainScreenV3State | TargetWorkingCopyDialog (写×2) | TargetWorkingCopyDialog (TextField) |
  // | `_targetUrlController`    | _MainScreenV3State | TargetSvnUrlDialog (写×1) | TargetSvnUrlDialog (TextField) |
  // | `_filterAuthorController` | _MainScreenV3State | （仅 owner 自身写）    | _LogFilterBar / _LogListPanelInner (TextField) |
  // | `_filterTitleController`  | _MainScreenV3State | （仅 owner 自身写）    | _LogFilterBar / _LogListPanelInner (TextField) |
  //
  // **R133 跨档不变量 J1/J2/J3/J4**（与 R129 I1-I4 / R132 I1-I3 同模板，跨 widget
  // 维度特化）：
  // - **J1**: 1 controller = 1 owner ——`final XxxController = TextEditingController()`
  //   字面构造站点必须**唯一**对应一处 dispose 调用；不可 owner-shifted（多处
  //   类同时构造同语义 controller 也违反此律——会让 dispose 序列模糊）。
  // - **J2**: borrower **必无 dispose** ——任何接收 `TextEditingController` 作
  //   构造参数 / final field 的 widget 不得调用 `.dispose()`；R129 I2 (every
  //   owned Disposable 必在 super.dispose 之前 dispose) 在 R133 维度下读作
  //   "borrower 没有 owned 资源、所以也没有释放责任"。
  // - **J3**: borrower 写站点的 mounted check 形态由 borrower 子类型决定 ——
  //   StatelessWidget borrower（如 TargetWorkingCopyDialog）用 `context.mounted`；
  //   StatefulWidget borrower（lib 内当前 0 处）用 `mounted` 字段。R132 I3 在
  //   borrower 维度的特化。
  // - **J4**: owner-borrower lifecycle 包含关系 —— owner lifecycle ⊇ borrower
  //   lifecycle（borrower 必先 dismount，owner 才能 dispose owned controllers）。
  //   违反此关系会让 borrower 在 owner dispose 后仍写 disposed controller 抛
  //   FlutterError。本 lib 通过 Dialog dismiss / Navigator.pop 在 owner 之前
  //   销毁 borrower 满足此关系；J4 不靠测试硬锁（lifecycle 顺序由 framework /
  //   navigation 自然保证）而靠 J3 的 mounted check 兜底（即使 J4 偶发反向
  //   borrower 的 .text= 也被 mounted check 短路）。
  //
  // **R129/R131/R132/R133 widget owned-resource 四角接合面**：
  // - R129 锁释放（dispose 顺序）；
  // - R131 锁刷新（setState 时机）；
  // - R132 锁变更（.text= 时机）；
  // - **R133 锁流向（owner/borrower/disposer 拓扑）** ——四轮正交叠加形成
  //   owned controller 完整审计四角。任何引入新 owned `Disposable` 必同时套
  //   四轮契约：构造 (R133 owner) / 释放 (R129) / 刷新 (R131) / 变更 (R132)。
  //
  // **R133 与 R130 cross-provider 拓扑模式同构**：R130 锁 ChangeNotifier 通信
  // 链路（生产-消费），R133 锁 controller 拓扑（创建-写-释放）——都是"跨 widget
  // 边界的资源流向"维度，R133 是 R130 模式在 owned-resource 维度的姊妹延伸；
  // R130 的"显式优于隐式"原则在 R133 实例化为"borrower 通过构造参数显式接收
  // 而非 InheritedWidget / Provider 隐式查找"。
  //
  // **R85-R89 漏迁巡检模式 widget 维度三次延伸**：R131 setState 维度 / R132 .text=
  // 维度 / **R133 拓扑维度**——本轮巡检确认 lib 内 0 处 borrower-as-disposer
  // 反模式 + 0 处 multi-owner 反模式 + 0 处 detached 构造（borrower 内部 new
  // 后 inject 给 owner）。doc-as-test 反向锁这三个反模式。
  final _sourceUrlController = TextEditingController();
  final _targetWcController = TextEditingController();
  final _targetUrlController = TextEditingController();
  final _filterAuthorController = TextEditingController();
  final _filterTitleController = TextEditingController();
  final _filterMessageController = TextEditingController();
  // commitSupplement 输入框：用户自由补充 commit message（如 CRID / 需求编号）。
  // 故意不在加入队列后清空——批量合并通常复用同一个 CRID，每次清空反而徒增重输成本。
  final _commitSupplementController = TextEditingController();

  // ============ State ============
  int _maxRetries = kDefaultMaxRetries;
  String? _mergeValidationScriptPath = kDefaultMergeValidationScriptPath;
  bool _logListStopOnCopy = true;
  String? _lastSourceUrl;
  String? _lastTargetWc;
  final Set<int> _selectedRevisions = {};
  String? _pendingSourceUrl;
  int? _cachedBranchPoint;
  int _cachedLogCount = 0;
  int? _latestCachedRevision;
  int? _earliestCachedRevision;
  String? _noMoreHistorySourceUrl;
  PreloadProgress _preloadProgress = const PreloadProgress();
  PreloadSettings _preloadSettings = const PreloadSettings();
  String? _selectedStepId; // 步骤视图中选中的步骤 ID
  double _panelWidth = 320.0; // 右侧面板宽度
  bool _isValidatingMerge = false; // 启动合并前 probe 阶段的按钮锁定标志
  bool _isSvnSwitching = false; // svn switch 执行中阻断主界面其它操作

  // ============ Services ============
  final _logFileCacheService = LogFileCacheService();
  final _preloadService = PreloadService();
  final _logCacheService = LogCacheService();
  final _logSyncService = LogSyncService();
  final _svnService = SvnService();
  final _wcManager = WorkingCopyManager();
  final _gongfengCrService = GongfengCrService();

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _initServices();
  }

  void _initServices() async {
    // R119 档 3（await + catchError 旁路化）：3 个 init 都 await——必须按顺
    // 序初始化、后续步骤依赖前序状态。然而**不希望**单一服务初始化失败让
    // 整个 _initServices 抛出（会让后续 _autoLoadLogsIfPossible 也跳过）；
    // catchError 的角色是"把异常转成日志记录 + 让 future complete normally"，
    // 等价于 `try { await x } catch (e) { log(e) }` 的链式语法糖。这与档 1
    // (main.dart:240 fire-and-forget) 和档 2 (logger_service:547 静默吞)
    // 都不同——档 3 必须落日志，错误**有诊断通道**。
    //
    // R126 启动序列约束（5-step 顺序锁，多服务编排式 init / 对偶 R125 close 序列）：
    // step 1：`await _logFileCacheService.init()` —— 文件列表缓存先就绪（log_cache
    //   下游会用到，preload_service 不直接用但概念上独立）。
    // step 2：`await _logCacheService.init()` + .then 设置 onValidationError 回调。
    //   **必须先于 step 3** —— preload_service.init 内部 `await _cacheService.init()`
    //   再次调 logCacheService（幂等但状态依赖）；callback 注入也必须在 init resolve
    //   后（_logCacheService 内部 init 完成才能挂回调）。
    // step 3：`await _preloadService.init()` + .then 设置 onProgressChanged 回调。
    //   **必须先于 step 4** —— `_loadPreloadSettings` 读 storage 并 push 到 preload
    //   service 内部 settings；preload service 必须先初始化才能接收 settings。
    // step 4：`await _loadPreloadSettings()` —— 同步把 storage 持久化的 settings 灌
    //   入 preload service 的内部状态。
    // step 5：`WidgetsBinding.addPostFrameCallback(_autoLoadLogsIfPossible)` ——
    //   **必须最后**：调度到首帧 build 完成后再 trigger 自动加载，否则 trigger 时
    //   widget tree 尚未 mount，showDialog / setState 会失败。这是 fire-and-forget
    //   形态（不 await）但被 framework 串行化——前序 4 步的 await 顺序保证 schedule
    //   时刻一定在所有 init 完成后。
    //
    // **R126 启动方向单调原则（多服务编排式实例化）**：底层服务 → 中间服务 → 配置
    // 注入 → UI 调度。任意一对反序会让前序状态尚未就绪时被消费（log_cache 未 init
    // 就调 preload 会触发 LateInitializationError；preload 未 init 就 _loadSettings
    // 会让 settings 写到尚未存在的内部 state）。catchError 在 step 1/2/3 各挂一个
    // 但**不**改变顺序契约——错误被旁路化但顺序仍然是 happens-before。
    await _logFileCacheService.init().catchError((e) {
      AppLogger.ui.error('文件缓存服务初始化失败', e);
    });
    await _logCacheService.init().then((_) {
      _logCacheService.onValidationError = _handleCacheValidationError;
    }).catchError((e) {
      AppLogger.ui.error('日志缓存服务初始化失败', e);
    });
    await _preloadService.init().then((_) {
      _preloadService.onProgressChanged = (progress) {
        if (!mounted) return;

        setState(() {
          _preloadProgress = progress;
          if (progress.status == PreloadStatus.loading) {
            _noMoreHistorySourceUrl = null;
          }
        });

        if (progress.sourceUrl != null) {
          final appState = Provider.of<AppState>(context, listen: false);
          appState.updateCachedTotalCount(
            progress.sourceUrl!,
            progress.loadedCount,
            pageSize: appState.pageSize,
          );
          _refreshLogCacheSummary(progress.sourceUrl!);
        }
      };
    }).catchError((e) {
      AppLogger.ui.error('预加载服务初始化失败', e);
    });
    await _loadPreloadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoLoadLogsIfPossible();
    });
  }

  void _handleCacheValidationError(CacheValidationError error) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('缓存数据库不匹配'),
          ],
        ),
        content: Text('期望: ${error.expectedUrl}\n实际: ${error.actualUrl}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreloadSettings() async {
    try {
      final storageService = StorageService();
      final settings = await storageService.getPreloadSettingsTyped();
      final maxRetries = await storageService.getDefaultMaxRetries();
      final validationScriptPath =
          await storageService.getMergeValidationScriptPath();
      if (mounted) {
        setState(() {
          _preloadSettings = settings;
          _maxRetries = maxRetries;
          _mergeValidationScriptPath = validationScriptPath;
        });
      }
    } catch (e) {
      AppLogger.ui.error('加载设置失败', e);
      if (mounted) {
        // _loadPreloadSettings 在 initState 链路中 await 调用，catch 触发时 first frame
        // 可能尚未渲染（StorageService 初始 await 极快异常时尤其），ScaffoldMessenger
        // 入队仍安全但确保 build 完再渲染，用 addPostFrameCallback 推迟到下一帧。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showError('加载设置失败，已使用默认值: $e');
          }
        });
      }
    }
  }

  /// **R129 widget lifecycle dispose 维度审计 — 档 3 stateful + owned Disposable**：
  ///
  /// **三档分类（widget 维度，对偶 R121 service 资源释放协议三档框架的 widget 实例化）**：
  /// - 档 1 = StatelessWidget / 无 State 类（无 dispose 责任）；
  /// - 档 2 = StatefulWidget 但 State 无 owned Disposable（override dispose 仅作扩展点
  ///   或完全可省，例如 `merge_execution_panel.dart:_MergeExecutionPanelState`）；
  /// - 档 3 = StatefulWidget + State 持有 owned Disposable（必须在 dispose 内反向 unwind，
  ///   本类与 `settings_screen.dart:_SettingsScreenState` 同档）。
  ///
  /// **跨档不变量 I1/I2/I3/I4（与 R128 跨档不变量 I1/I2/I3 同模板，widget 维度特化）**：
  /// - I1: `super.dispose()` 必为末位 —— Flutter framework 强约束，否则后续 `mounted`
  ///   读取 / framework hook 触发 race；与 R127 init 末位 `notifyListeners` 形成
  ///   **对偶位**（init 末位是"对外宣告就绪"、dispose 末位是"对外宣告释放"）。
  /// - I2: 每个 owned Disposable（TextEditingController / ScrollController /
  ///   FocusNode / AnimationController / StreamSubscription）必在 `super.dispose()`
  ///   之前 dispose —— 反过来会让 framework 在 owner 仍持有资源时拆 widget 树，
  ///   触发 "_debugDispose was called more than once" 类断言。
  /// - I3: 1:1 owned-vs-disposed parity —— 类内每个 `final _xxxController = ...()`
  ///   声明必有对应 `_xxxController.dispose()` 调用；R128 I3 (every-mutator-reaches-notify)
  ///   在 lifecycle 维度的同律特化。
  /// - I4: dispose 顺序 = 反序于 declaration —— 本类 4 个 controller declaration
  ///   顺序 `_sourceUrlController, _targetWcController, _filterAuthorController,
  ///   _filterTitleController`，dispose 顺序故意保持**同序**（不严格反序）；这是
  ///   widget 维度对 R125 `handle → memory → file → log` 释放方向单调原则的**简化**
  ///   ——4 个 controller 之间无依赖、无顺序约束，同序释放与反序释放语义等价；
  ///   维持同序减少阅读负担。约束在于"全部释放完才 super.dispose"，不在内部顺序。
  ///
  /// **R125/R127 镜像对偶在 widget 维度的实例化**：R125 锁 service close 序列方向
  /// `handle → memory → file → log`；R127 锁 service init 反方向 `path → handle →
  /// memory → log`；本档的 widget dispose 序列方向是 `controllers → super.dispose`
  /// （单层简化形态）—— 与 R127 widget initState 序列 `super.initState() → init
  /// resources → schedule callbacks` 形成首尾对偶。
  ///
  /// **三档框架第 9 次复用（lifecycle 维度首次形式化）**：R98 异常 / R119 异步错误 /
  /// R120 等待 / R121 release function 级 / R125 release step 级 / R126 init step
  /// 级 / R127 init step 级 + 嵌套 / R128 trigger 级 / **R129 lifecycle 级**——
  /// 三档框架 channel-agnostic + granularity-agnostic + duality-aware +
  /// dimension-extensible 四性质再升级。
  @override
  void dispose() {
    _sourceUrlController.dispose();
    _targetWcController.dispose();
    _targetUrlController.dispose();
    _filterAuthorController.dispose();
    _filterTitleController.dispose();
    _filterMessageController.dispose();
    _commitSupplementController.dispose();
    super.dispose();
  }

  void _initializeFields() {
    final appState = Provider.of<AppState>(context, listen: false);

    if (isUsableSourceUrl(appState.lastSourceUrl)) {
      _sourceUrlController.text = appState.lastSourceUrl!;
    } else if (appState.config != null &&
        appState.config!.enabledSourceUrls.isNotEmpty) {
      _sourceUrlController.text = appState.config!.enabledSourceUrls.first.url;
    }

    if (appState.lastTargetWc != null) {
      _targetWcController.text = appState.lastTargetWc!;
      _lastTargetWc = appState.lastTargetWc!;
    }
    final initialTargetUrl = resolveInitialTargetUrl(
      lastTargetUrl: appState.lastTargetUrl,
      targetUrlHistory: appState.targetUrlHistory,
    );
    if (initialTargetUrl.isNotEmpty) {
      _targetUrlController.text = initialTargetUrl;
    }

    _lastSourceUrl = _sourceUrlController.text.trim();
    _loadAuthorFilterHistory();
  }

  /// **R132 TextEditingController.text 写时机审计 — 档 3 async-bracket（跨
  /// await 边界）**：本函数在 `initState → _initializeFields → _loadAuthorFilterHistory`
  /// 链路上 fire-and-forget 调用（非 await，无父函数 mounted-guard 包裹），
  /// `await storageService.getLastAuthorFilter()` 期间 widget 可被 dispose
  /// （用户在异步等待中关闭/切换页）。dispose 后 `_filterAuthorController` 已
  /// 被释放，再写 `.text = lastAuthor` 触发 `FlutterError: A
  /// TextEditingController was used after being disposed`。R132 显式补
  /// `if (!mounted) return;` 关闭 race window。
  ///
  /// 与同 lib R131 修复的 `_syncLatestLogs:1071` / `settings_screen._pickDate`
  /// 共享同模板——await 后 .text= / setState 之前必须自检 mounted。
  Future<void> _loadAuthorFilterHistory() async {
    final storageService = StorageService();
    final lastAuthor = await storageService.getLastAuthorFilter();
    final lastTitle = await storageService.getLastTitleFilter();
    final lastMessage = await storageService.getLastMessageFilter();
    if (!mounted) return;
    if (lastAuthor != null && lastAuthor.isNotEmpty) {
      _filterAuthorController.text = lastAuthor;
    }
    if (lastTitle != null && lastTitle.isNotEmpty) {
      _filterTitleController.text = lastTitle;
    }
    if (lastMessage != null && lastMessage.isNotEmpty) {
      _filterMessageController.text = lastMessage;
    }
  }

  TargetConfig _currentTargetConfig(AppState appState) {
    if (appState.useTemporarySparseWorkingCopy) {
      return TargetConfig.sparseTemporary(
        stripUrlWhitespace(_targetUrlController.text.trim()),
      );
    }
    return TargetConfig.fullWorkingCopy(_targetWcController.text.trim());
  }

  Future<_LogSelectionContext?> _prepareLogSelectionContext({
    bool? stopOnCopy,
  }) async {
    final sourceUrl = _sourceUrlController.text.trim();
    if (sourceUrl.isEmpty) {
      return null;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final effectiveStopOnCopy = stopOnCopy ?? _logListStopOnCopy;
    final targetConfig = _currentTargetConfig(appState);
    final targetWc = targetConfig.isFullWorkingCopy
        ? targetConfig.workingCopyPath.trim()
        : '';
    final targetStateKey = resolveLogTargetStateKey(targetConfig);

    if (shouldClearSelectedRevisionsOnSourceChange(
      selectedRevisions: _selectedRevisions,
      previousSourceUrl: _lastSourceUrl,
      currentSourceUrl: sourceUrl,
    )) {
      _selectedRevisions.clear();
    }

    if (_lastSourceUrl != null && _lastSourceUrl != sourceUrl) {
      _cachedBranchPoint = null;
      _noMoreHistorySourceUrl = null;
      LogFilterService.clearBranchPointCache(workingDirectory: _lastTargetWc);
    }
    _lastSourceUrl = sourceUrl;

    if (_lastTargetWc != null && _lastTargetWc != targetStateKey) {
      _cachedBranchPoint = null;
      LogFilterService.clearBranchPointCache(workingDirectory: _lastTargetWc);
    }
    _lastTargetWc = targetStateKey;

    await appState.saveSourceUrlToHistory(sourceUrl);
    if (targetWc.isNotEmpty) {
      await appState.saveTargetWcToHistory(targetWc);
    }

    if (_noMoreHistorySourceUrl != sourceUrl) {
      _noMoreHistorySourceUrl = null;
    }

    int? minRevision;
    if (effectiveStopOnCopy && targetStateKey.isNotEmpty) {
      minRevision = await _getBranchPoint(targetStateKey);
    }

    return _LogSelectionContext(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      targetStateKey: targetStateKey,
      stopOnCopy: effectiveStopOnCopy,
      minRevision: minRevision,
    );
  }

  Future<void> _refreshLogCacheSummary(String sourceUrl) async {
    final latestRange = await _logCacheService.getLatestRange(sourceUrl);
    final cachedCount =
        await _logCacheService.getLatestRangeEntryCount(sourceUrl);
    if (!mounted) return;

    setState(() {
      if (_sourceUrlController.text.trim() != sourceUrl) {
        return;
      }
      _cachedLogCount = cachedCount;
      _latestCachedRevision = latestRange?.startRevision;
      _earliestCachedRevision = latestRange?.endRevision;
    });
  }

  LogBoundaryDescription _buildBoundaryDescription({
    required String sourceUrl,
    required String targetWc,
  }) {
    return buildLogBoundaryDescription(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      cachedLogCount: _cachedLogCount,
      stopOnCopy: _logListStopOnCopy,
      cachedBranchPoint: _cachedBranchPoint,
      earliestCachedRevision: _earliestCachedRevision,
      preloadSourceUrl: _preloadProgress.sourceUrl,
      preloadStatus: _preloadProgress.status,
      preloadStopReason: _preloadProgress.stopReason,
      noMoreHistorySourceUrl: _noMoreHistorySourceUrl,
    );
  }

  Future<void> _applySelectionContext(
    _LogSelectionContext contextData, {
    bool refreshMergeInfo = false,
  }) async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.setMinRevision(
      contextData.minRevision,
      sourceUrl: contextData.sourceUrl,
    );
    await _refreshLogCacheSummary(contextData.sourceUrl);

    if (refreshMergeInfo && contextData.targetStateKey.isNotEmpty) {
      await _updateMergedStatus(
        contextData.sourceUrl,
        contextData.targetStateKey,
        forceRefresh: true,
      );
    }
  }

  Future<void> _runLogDataAction(
    Future<int> Function(_LogSelectionContext contextData) action, {
    required String successMessage,
    String? noChangeMessage,
    bool refreshMergeInfo = false,
  }) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final contextData = await _prepareLogSelectionContext();
    if (contextData == null) {
      _showError('请填写源 URL');
      return;
    }

    appState.setLoadingData(true);

    int addedCount = 0;
    try {
      try {
        addedCount = await action(contextData);
      } catch (e, stackTrace) {
        // sync 段失败：远程 SVN 请求 / DB 写入未完成，走原"日志同步失败"路径。
        AppLogger.ui.error('日志数据操作失败（sync 段）', e, stackTrace);
        if (mounted) {
          _showError('日志同步失败: $e');
        }
        return;
      }

      try {
        await _applySelectionContext(
          contextData,
          refreshMergeInfo: refreshMergeInfo,
        );
      } catch (e, stackTrace) {
        // apply 段失败：sync 已落盘（addedCount 已拿到），仅 UI 刷新失败——文案
        // 必须明示"已同步但界面刷新失败"，避免用户误以为没同步成功而重复点击。
        AppLogger.ui.error('日志数据操作失败（apply 段）', e, stackTrace);
        if (mounted) {
          _showError(formatLogApplyFailureFeedback(
            addedCount: addedCount,
            error: '$e',
          ));
        }
        return;
      }

      if (!mounted) return;

      if (addedCount > 0) {
        _showSuccess(successMessage.replaceFirst('{count}', '$addedCount'));
      } else if (noChangeMessage != null && noChangeMessage.isNotEmpty) {
        _showInfo(noChangeMessage);
      }
    } finally {
      appState.setLoadingData(false);
    }
  }

  Future<void> _autoLoadLogsIfPossible() async {
    final contextData = await _prepareLogSelectionContext();
    if (contextData == null) {
      return;
    }

    await _applySelectionContext(
      contextData,
      refreshMergeInfo: contextData.targetStateKey.isNotEmpty,
    );

    if (!mounted) {
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    _startBackgroundPreload(
      contextData.sourceUrl,
      contextData.targetStateKey,
      appState,
    );
  }

  void _startBackgroundPreload(
      String sourceUrl, String targetWc, AppState appState) {
    if (!_preloadSettings.enabled) return;

    // R119 档 1（fire-and-forget then 链）变体：caller 不 await——背景预加载
    // 跑多久取决于 svn log 量级，不能阻塞 UI（与 main.dart:240 同源动机）。
    // then 链用来串"完成后刷新 UI"，catchError 落 error 日志（**不**静默吞，
    // 故区别于档 2）。等价于"档 1 + sidechannel doc 化"——错误既不抛也不
    // 静默，旁路到日志系统。
    _preloadService
        .startPreload(
      sourceUrl: sourceUrl,
      settings: _preloadSettings,
      workingDirectory: targetWc.isNotEmpty ? targetWc : null,
      fetchLimit: appState.config?.settings.svnLogLimit ?? kDefaultSvnLogLimit,
    )
        .then((_) {
      if (mounted && _preloadProgress.status == PreloadStatus.completed) {
        appState.refreshLogEntries(sourceUrl);
      }
    }).catchError((e) {
      AppLogger.ui.error('后台预加载失败', e);
    });
  }

  Future<int?> _getBranchPoint(String target) async {
    if (_cachedBranchPoint != null) return _cachedBranchPoint;
    final cached = LogFilterService.getCachedBranchPoint(target);
    if (cached != null) {
      _cachedBranchPoint = cached;
      return cached;
    }
    try {
      final branchUrl = isSvnRepositoryUrl(target)
          ? target
          : await _svnService.getInfo(target);
      final branchPoint = await _svnService.findBranchPoint(
        branchUrl,
        workingDirectory: isSvnRepositoryUrl(target) ? null : target,
      );
      if (branchPoint != null) {
        _cachedBranchPoint = branchPoint;
        LogFilterService.cacheBranchPoint(target, branchPoint);
      }
      return branchPoint;
    } catch (e) {
      AppLogger.ui.error('查询分支点失败', e);
      return null;
    }
  }

  Future<void> _updateMergedStatus(String sourceUrl, String targetWc,
      {bool forceRefresh = false}) async {
    if (targetWc.isEmpty || sourceUrl.isEmpty) return;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.loadMergeInfo(
        sourceUrl: sourceUrl,
        targetWc: targetWc,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      AppLogger.ui.error('更新合并状态失败', e);
    }
  }

  // ============ 事件处理 ============

  Future<void> _refreshLogList(bool stopOnCopy) async {
    final contextData =
        await _prepareLogSelectionContext(stopOnCopy: stopOnCopy);
    if (contextData == null) {
      _showError('请填写源 URL');
      return;
    }

    await _applySelectionContext(
      contextData,
      refreshMergeInfo: contextData.targetStateKey.isNotEmpty,
    );
  }

  Future<void> _applyFilter() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final contextData = await _prepareLogSelectionContext();
    if (contextData == null) {
      _showError('请填写源 URL');
      return;
    }

    final authorFilter = _filterAuthorController.text.trim();
    final titleFilter = _filterTitleController.text.trim();
    final messageFilter = _filterMessageController.text.trim();
    final storageService = StorageService();
    if (authorFilter.isNotEmpty) {
      await storageService.addAuthorToFilterHistory(authorFilter);
      await storageService.saveLastAuthorFilter(authorFilter);
    }
    if (titleFilter.isNotEmpty) {
      await storageService.saveLastTitleFilter(titleFilter);
    }
    if (messageFilter.isNotEmpty) {
      await storageService.saveLastMessageFilter(messageFilter);
    }

    await appState.setFilter(
      author: authorFilter.isEmpty ? null : authorFilter,
      title: titleFilter.isEmpty ? null : titleFilter,
      message: messageFilter.isEmpty ? null : messageFilter,
      minRevision: contextData.minRevision,
      clearMinRevision: !contextData.stopOnCopy,
      sourceUrl: contextData.sourceUrl,
    );
    await _refreshLogCacheSummary(contextData.sourceUrl);
  }

  /// 一键清空 3 个文本筛选框（提交者 / 标题 / 内容）并立即重新过滤。
  ///
  /// **不**清 stopOnCopy / minRevision——这两者由独立的"排除分支前"checkbox
  /// 显式控制，与文本框语义独立（参见 [hasActiveLogTextFilter] 的 dartdoc）。
  ///
  /// 流程：
  /// 1. 清空 3 个 controller 的 text；
  /// 2. setState 触发 build，按钮 disabled（hasActiveLogTextFilter == false）；
  /// 3. 调 `_applyFilter()` 把空过滤推到 AppState（== 显示全部条目）。
  Future<void> _clearAllLogFilters() async {
    _filterAuthorController.clear();
    _filterTitleController.clear();
    _filterMessageController.clear();
    if (mounted) setState(() {});
    await _applyFilter();
  }

  Future<void> _syncLatestLogs({bool refreshMergeInfo = true}) async {
    await _runLogDataAction(
      (_LogSelectionContext contextData) async {
        final appState = Provider.of<AppState>(context, listen: false);
        final addedCount = await _logSyncService.syncFromHead(
          sourceUrl: contextData.sourceUrl,
          limit: appState.config?.settings.svnLogLimit ?? kDefaultSvnLogLimit,
        );

        if (!mounted) {
          return addedCount;
        }

        setState(() => _noMoreHistorySourceUrl = null);
        return addedCount;
      },
      successMessage: '已同步 {count} 条最新日志',
      noChangeMessage: '没有发现新的日志',
      refreshMergeInfo: refreshMergeInfo,
    );
  }

  Future<void> _loadMoreLogs() async {
    await _runLogDataAction(
      (_LogSelectionContext contextData) async {
        final appState = Provider.of<AppState>(context, listen: false);
        final addedCount = await _logSyncService.syncLogs(
          sourceUrl: contextData.sourceUrl,
          limit: appState.config?.settings.svnLogLimit ?? kDefaultSvnLogLimit,
          stopOnCopy: contextData.stopOnCopy,
          targetWorkingDirectory: contextData.targetStateKey.isNotEmpty
              ? contextData.targetStateKey
              : null,
          loadMore: true,
        );

        if (!mounted) {
          return addedCount;
        }

        if (addedCount == 0) {
          setState(() => _noMoreHistorySourceUrl = contextData.sourceUrl);
        } else {
          setState(() => _noMoreHistorySourceUrl = null);
        }

        return addedCount;
      },
      successMessage: '已加载 {count} 条更旧日志',
      noChangeMessage: '没有更多历史日志可加载',
    );
  }

  void _selectAllSelectableRevisions() {
    if (!mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final sourceUrl = _sourceUrlController.text.trim();
    final targetConfig = _currentTargetConfig(appState);
    final targetStateKey = resolveLogTargetStateKey(targetConfig);

    final selectable = computeSelectableRevisions(
      entries: appState.paginatedLogEntries,
      pendingRevisions: appState.pendingRevisions,
      isMerged: (revision) => appState.isRevisionMergedSync(
        revision,
        sourceUrl: sourceUrl,
        targetWc: targetStateKey,
      ),
    );

    setState(() {
      _selectedRevisions
        ..clear()
        ..addAll(selectable);
    });

    if (selectable.isNotEmpty) {
      _showInfo('已选中当前页 ${selectable.length} 个可合并 revision');
    } else {
      _showInfo('当前页没有可选 revision');
    }
  }

  void _clearSelectedRevisions() {
    if (_selectedRevisions.isEmpty) {
      return;
    }

    final count = _selectedRevisions.length;
    setState(() => _selectedRevisions.clear());
    _showInfo('已清空 $count 个选中项');
  }

  Future<void> _clearPendingRevisions() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (appState.pendingRevisions.isEmpty) {
      _showInfo('待合并列表已经是空的');
      return;
    }

    final count = appState.pendingRevisions.length;
    final confirmed = await _confirmQueueAction(
      title: '清空待合并列表',
      message: '将移除 $count 个待合并 revision，操作不可恢复。',
      confirmLabel: '清空',
    );
    if (!confirmed) return;
    if (!mounted) return;

    appState.clearPendingRevisions();
    setState(() => _pendingSourceUrl = null);
    _showInfo('已清空 $count 个待合并 revision');
  }

  bool _hasPendingSourceMismatch(String currentSourceUrl) {
    final appState = Provider.of<AppState>(context, listen: false);
    return hasPendingSourceMismatch(
      pendingRevisions: appState.pendingRevisions,
      currentSourceUrl: currentSourceUrl,
      pendingSourceUrl: _pendingSourceUrl,
    );
  }

  String? _buildPendingSourceWarning(String currentSourceUrl) {
    final appState = Provider.of<AppState>(context, listen: false);
    return buildPendingSourceWarning(
      pendingRevisions: appState.pendingRevisions,
      currentSourceUrl: currentSourceUrl,
      pendingSourceUrl: _pendingSourceUrl,
    );
  }

  void _removePendingRevision(int revision) {
    final appState = Provider.of<AppState>(context, listen: false);
    appState.removePendingRevisions([revision]);

    if (appState.pendingRevisions.isEmpty && _pendingSourceUrl != null) {
      setState(() => _pendingSourceUrl = null);
    }
    _showInfo('已从待合并移除 r$revision');
  }

  void _addSelectedToPending() {
    if (_selectedRevisions.isEmpty) {
      _showError('请先选择要合并的 revision');
      return;
    }
    final appState = Provider.of<AppState>(context, listen: false);
    final sourceUrl = _sourceUrlController.text.trim();
    final selectedCount = _selectedRevisions.length;

    if (_hasPendingSourceMismatch(sourceUrl)) {
      final pendingSourceUrl = _pendingSourceUrl;
      _showError(
        '待合并列表已绑定到 ${summarizeSourceUrl(pendingSourceUrl ?? '')}，请先清空后再切换源分支',
      );
      return;
    }

    final beforeLen = appState.pendingRevisions.length;
    appState.addPendingRevisions(_selectedRevisions.toList());
    final addedCount = appState.pendingRevisions.length - beforeLen;
    setState(() {
      _selectedRevisions.clear();
      if (sourceUrl.isNotEmpty) {
        _pendingSourceUrl = sourceUrl;
      }
    });
    _showSuccess(formatPendingAddSnackBar(
      selectedCount: selectedCount,
      addedCount: addedCount,
    ));
  }

  Future<void> _startMerge() async {
    if (_isValidatingMerge) {
      // 双击 / probe 期间任何重入立刻丢弃，避免并发跑两次 svn info。
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);

    final sourceUrl = _sourceUrlController.text.trim();
    final targetConfig = _currentTargetConfig(appState);
    final pendingRevisions = appState.pendingRevisions.toList();

    final error = validateMergeStartPreconditions(
      sourceUrl: sourceUrl,
      targetConfig: targetConfig,
      pendingRevisions: pendingRevisions,
      pendingSourceUrl: _pendingSourceUrl,
      isLocked: mergeState.isLocked,
    );
    if (error != null) {
      _showError(error);
      return;
    }

    final effectiveSourceUrl = (_pendingSourceUrl ?? sourceUrl).trim();
    var resolvedTargetConfig = targetConfig;

    // 启动合并前 SVN 连通性预校验：避免错误的 URL / 工作副本路径要等到第一步
    // prepare 阶段才报错（详见 SvnService.probeSvnLocation 的 dartdoc）。
    setState(() => _isValidatingMerge = true);
    try {
      final sourceProbeError = await _svnService.probeSvnLocation(
        effectiveSourceUrl,
        role: '源 URL',
      );
      if (!mounted) return;
      if (sourceProbeError != null) {
        _showError(sourceProbeError);
        return;
      }

      final targetProbeError = await _svnService.probeSvnLocation(
        targetConfig.probeTarget,
        role: targetConfig.probeRole,
      );
      if (!mounted) return;
      if (targetProbeError != null) {
        _showError(targetProbeError);
        return;
      }

      if (targetConfig.isFullWorkingCopy) {
        final resolvedTargetUrl = await _svnService
            .getInfo(targetConfig.workingCopyPath, item: 'url');
        if (!mounted) return;
        resolvedTargetConfig = targetConfig.withResolvedTargetUrl(
          resolvedTargetUrl.trim().isEmpty
              ? targetConfig.workingCopyPath
              : resolvedTargetUrl.trim(),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('解析目标 SVN URL 失败', e, stackTrace);
      if (!mounted) return;
      _showError('解析目标 SVN URL 失败: $e');
      return;
    } finally {
      if (mounted) {
        setState(() => _isValidatingMerge = false);
      }
    }

    final sourceEntries = await appState.getEntriesByRevisions(
      effectiveSourceUrl,
      pendingRevisions,
    );
    if (!mounted) return;
    final sourceMessagesByRevision =
        buildSourceMessagesByRevision(sourceEntries);

    final result = await mergeState.addJob(
      sourceConfig: SourceConfig(url: effectiveSourceUrl),
      targetConfig: resolvedTargetConfig,
      revisions: pendingRevisions,
      maxRetries: _maxRetries,
      sourceMessagesByRevision: sourceMessagesByRevision,
      commitSupplement: _commitSupplementController.text,
      mergeValidationScriptPath: _mergeValidationScriptPath,
    );

    if (!result.isApplied || result.jobId == null) {
      _showInfo('未能创建任务，请检查当前队列状态');
      return;
    }

    final createdJobId = result.jobId!;
    await appState.saveTargetConfig(targetConfig);
    appState.clearPendingRevisions();
    setState(() => _pendingSourceUrl = null);
    _showSuccess('任务 #$createdJobId 已添加');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<bool> _confirmQueueAction({
    required String title,
    required String message,
    String confirmLabel = '确认',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  MergeJob? _findQueueJob(MergeExecutionState mergeState, int jobId) =>
      findJobById(mergeState.jobs, jobId);

  Future<void> _deleteQueueJob(
    MergeExecutionState mergeState,
    int jobId,
  ) async {
    final job = _findQueueJob(mergeState, jobId);
    if (job == null) {
      _showInfo('任务不存在，列表已更新');
      return;
    }

    final confirmed = await _confirmQueueAction(
      title: '删除任务 #$jobId',
      message: buildDeleteJobConfirmMessage(
        completedIndex: job.completedIndex,
        totalRevisions: job.revisions.length,
      ),
      confirmLabel: '删除',
    );
    if (!confirmed) return;

    final result = await mergeState.deleteJob(jobId);
    switch (result.status) {
      case QueueMutationStatus.applied:
        _showSuccess(describeJobDeletionSuccess(
          jobId: jobId,
          status: job.status,
        ));
        return;
      case QueueMutationStatus.blocked:
        _showInfo('运行中或暂停的任务不能删除');
        return;
      case QueueMutationStatus.notFound:
        _showInfo('任务不存在，列表已更新');
        return;
    }
  }

  Future<void> _requeueRemainingJob(
    MergeExecutionState mergeState,
    int jobId,
  ) async {
    final result = await mergeState.enqueueRemainingJob(jobId);
    switch (result.status) {
      case QueueMutationStatus.applied:
        _showSuccess('已创建剩余任务 #${result.jobId}');
        return;
      case QueueMutationStatus.blocked:
        _showInfo('当前任务没有可重新排队的剩余 revision');
        return;
      case QueueMutationStatus.notFound:
        _showInfo('任务不存在，列表已更新');
        return;
    }
  }

  Future<void> _clearPendingJobs(MergeExecutionState mergeState) async {
    if (mergeState.pendingJobs.isEmpty) {
      _showInfo('没有待清空的任务');
      return;
    }

    final confirmed = await _confirmQueueAction(
      title: '清空待执行任务',
      message: '将移除当前排队但尚未执行的任务，已完成和失败记录会保留。',
      confirmLabel: '清空',
    );
    if (!confirmed) return;

    final result = await mergeState.clearPendingJobs();
    if (!result.isApplied) {
      _showInfo('没有待执行任务被清空');
      return;
    }

    _showSuccess('已清空 ${result.affectedCount} 个待执行任务');
  }

  Future<void> _cancelPausedJobWithConfirm(
    MergeExecutionState mergeState,
  ) async {
    if (mergeState.pausedJob == null) {
      _showInfo('当前没有暂停中的任务');
      return;
    }

    final confirmed = await _confirmQueueAction(
      title: '终止当前任务',
      message:
          '终止后任务将从队列移除，已合并的 revision 不会回滚但任务无法恢复；如需仅跳过当前 revision 请使用"跳过"按钮。',
      confirmLabel: '终止',
    );
    if (!confirmed) return;

    await mergeState.cancelPausedJob();
    _showSuccess('已终止任务');
  }

  Future<void> _resumePausedJobWithFeedback(
    MergeExecutionState mergeState,
  ) async {
    final paused = mergeState.pausedJob;
    if (paused == null) {
      _showInfo('当前没有暂停中的任务');
      return;
    }
    final jobId = paused.jobId;
    _showInfo('继续执行任务 #$jobId');
    await mergeState.resumePausedJob();
  }

  Future<void> _skipCurrentRevisionWithFeedback(
    MergeExecutionState mergeState,
  ) async {
    final paused = mergeState.pausedJob;
    if (paused == null) {
      _showInfo('当前没有暂停中的任务');
      return;
    }
    final skippedRevision = paused.currentRevision;
    if (skippedRevision == null) {
      _showInfo('当前任务没有可跳过的 revision');
      return;
    }
    _showInfo('已跳过 r$skippedRevision，继续执行任务 #${paused.jobId}');
    await mergeState.skipCurrentRevision();
  }

  Future<void> _clearFinishedJobs(MergeExecutionState mergeState) async {
    if (mergeState.finishedJobs.isEmpty) {
      _showInfo('没有可清理的历史记录');
      return;
    }

    final confirmed = await _confirmQueueAction(
      title: '清理历史任务',
      message: '将删除已完成和已失败的本地任务记录，不影响 SVN 仓库状态。',
      confirmLabel: '清理',
    );
    if (!confirmed) return;

    final result = await mergeState.clearFinishedJobs();
    if (!result.isApplied) {
      _showInfo('没有历史任务被清理');
      return;
    }

    _showSuccess('已清理 ${result.affectedCount} 条历史任务');
  }

  // ============ SVN 操作 ============

  Future<void> _handleSvnOperation(SvnOperation operation) async {
    if (_isSvnSwitching) {
      _showInfo('正在切换目标分支，请稍后再试');
      return;
    }

    switch (operation) {
      case SvnOperation.update:
        await _svnUpdate();
        break;
      case SvnOperation.switchBranch:
        await _svnSwitch();
        break;
      case SvnOperation.revert:
        await _svnRevert();
        break;
      case SvnOperation.cleanup:
        await _svnCleanup();
        break;
    }
  }

  Future<void> _svnSwitch() async {
    final targetWc = _targetWcController.text.trim();
    if (targetWc.isEmpty) {
      _showError('请先选择目标工作副本');
      return;
    }

    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);
    if (mergeState.isProcessing || mergeState.hasPausedJob) {
      _showError('当前有合并任务执行或暂停，不能切换目标分支');
      return;
    }

    if (_wcManager.isLocked(targetWc)) {
      final lockInfo = _wcManager.getLockInfo(targetWc);
      _showError(formatWcLockedMessage(lockInfo));
      return;
    }

    String currentTargetUrl;
    try {
      currentTargetUrl = await _svnService.getInfo(targetWc, item: 'url');
    } catch (e, stackTrace) {
      AppLogger.ui.error('读取当前目标分支 URL 失败', e, stackTrace);
      if (!mounted) return;
      _showError('读取当前目标分支 URL 失败: $e');
      return;
    }
    if (!mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final sourceUrl = _sourceUrlController.text.trim();
    final selectedUrl = await SwitchBranchDialog.show(
      context: context,
      currentTargetUrl: currentTargetUrl,
      initialBrowseUrl: deriveDefaultBranchesUrl(currentTargetUrl),
      branchHistory: buildSwitchBranchHistory(
        currentTargetUrl: currentTargetUrl,
        currentSourceUrl: sourceUrl,
        switchBranchHistory: appState.switchBranchHistory,
        sourceUrlHistory: appState.sourceUrlHistory,
        configuredSourceUrls:
            appState.config?.enabledSourceUrls.map((item) => item.url) ??
                const <String>[],
      ),
      onLoadRepository: (url) => _svnService.listRepository(url),
    );

    if (selectedUrl == null) return;
    if (!mounted) return;

    final targetUrl = stripUrlWhitespace(selectedUrl);
    if (targetUrl.isEmpty) {
      _showError('请选择要切换到的分支 URL');
      return;
    }
    if (targetUrl == stripUrlWhitespace(currentTargetUrl)) {
      _showInfo('目标工作副本已经在该分支');
      return;
    }

    if (_wcManager.isLocked(targetWc)) {
      final lockInfo = _wcManager.getLockInfo(targetWc);
      _showError(formatWcLockedMessage(lockInfo));
      return;
    }

    setState(() => _isSvnSwitching = true);
    AppLogger.ui.info('开始切换工作副本: $targetWc -> $targetUrl');
    _showInfo('正在切换目标分支...');

    try {
      final result = await _wcManager.switchToUrl(targetWc, targetUrl);
      if (!mounted) return;

      if (result.isSuccess) {
        AppLogger.ui.info('工作副本切换成功');
        await appState.saveSwitchBranchToHistory(targetUrl);
        await appState.saveTargetWcToHistory(targetWc);
        _cachedBranchPoint = null;
        LogFilterService.clearBranchPointCache(workingDirectory: targetWc);
        if (sourceUrl.isNotEmpty) {
          await appState.loadMergeInfo(
            sourceUrl: sourceUrl,
            targetWc: targetWc,
            fullRefresh: true,
          );
        }
        if (mounted) {
          _showSuccess('切换完成');
          await _refreshLogList(_logListStopOnCopy);
        }
      } else {
        AppLogger.ui.error('工作副本切换失败: ${result.stderr}');
        _showError('切换失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('工作副本切换异常', e, stackTrace);
      if (!mounted) return;
      _showError('切换异常: $e');
    } finally {
      if (mounted) {
        setState(() => _isSvnSwitching = false);
      }
    }
  }

  Future<void> _svnUpdate() async {
    final targetWc = _targetWcController.text.trim();
    if (targetWc.isEmpty) {
      _showError('请先选择目标工作副本');
      return;
    }

    if (_wcManager.isLocked(targetWc)) {
      final lockInfo = _wcManager.getLockInfo(targetWc);
      _showError(formatWcLockedMessage(lockInfo));
      return;
    }

    AppLogger.ui.info('开始更新工作副本: $targetWc');
    _showInfo('正在更新工作副本...');

    try {
      final result = await _wcManager.update(targetWc);

      if (result.isSuccess) {
        AppLogger.ui.info('工作副本更新成功');
        // svn update 在服务器端改动与本地修改冲突时仅把文件标 'C' 状态，仍 exit 0。
        // 后验 listConflictedFiles 才能真正确认 WC 是否干净。
        // 与第二十八轮 _markConflictsResolved + 第三十/三十一轮 _runSvnCleanup/_svnCleanup
        // 后验家族同款风格——"成功后调 SVN 后验"的隐藏漏洞律。
        final conflicts = await _svnService.listConflictedFiles(targetWc);
        if (!mounted) return;
        final message = formatUpdateFeedback(
          remainingConflictCount: conflicts.length,
        );
        if (conflicts.isEmpty) {
          _showSuccess(message);
        } else {
          AppLogger.ui.error('update 后仍有冲突: ${conflicts.length} 个');
          _showError(message);
        }

        final sourceUrl = _sourceUrlController.text.trim();
        if (sourceUrl.isNotEmpty) {
          await _updateMergedStatus(sourceUrl, targetWc, forceRefresh: true);
          if (!mounted) return;
          await _syncLatestLogs(refreshMergeInfo: false);
        }
      } else {
        AppLogger.ui.error('工作副本更新失败: ${result.stderr}');
        if (!mounted) return;
        _showError('更新失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('工作副本更新异常', e, stackTrace);
      if (!mounted) return;
      _showError('更新异常: $e');
    }
  }

  Future<void> _svnRevert() async {
    final targetWc = _targetWcController.text.trim();
    if (targetWc.isEmpty) {
      _showError('请先选择目标工作副本');
      return;
    }

    if (_wcManager.isLocked(targetWc)) {
      final lockInfo = _wcManager.getLockInfo(targetWc);
      _showError(formatWcLockedMessage(lockInfo));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认还原'),
        content: Text('确定要还原 "$targetWc" 吗？\n\n这将撤销所有本地修改！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('还原'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    AppLogger.ui.info('开始还原工作副本: $targetWc');
    _showInfo('正在还原工作副本...');

    try {
      final sourceUrl = _sourceUrlController.text.trim();
      final result = await _wcManager.revert(
        targetWc,
        recursive: true,
        sourceUrl: sourceUrl,
        refreshMergeInfo: true,
      );

      if (!mounted) return;

      if (result.isSuccess) {
        AppLogger.ui.info('工作副本还原成功');
        _showSuccess('还原完成');

        if (mounted && sourceUrl.isNotEmpty) {
          final appState = Provider.of<AppState>(context, listen: false);
          await appState.loadMergeInfo(
            sourceUrl: sourceUrl,
            targetWc: targetWc,
            fullRefresh: true,
          );
        }
      } else {
        AppLogger.ui.error('工作副本还原失败: ${result.stderr}');
        _showError('还原失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('工作副本还原异常', e, stackTrace);
      if (!mounted) return;
      _showError('还原异常: $e');
    }
  }

  Future<void> _svnCleanup() async {
    final targetWc = _targetWcController.text.trim();
    if (targetWc.isEmpty) {
      _showError('请先选择目标工作副本');
      return;
    }

    if (_wcManager.isLocked(targetWc)) {
      final lockInfo = _wcManager.getLockInfo(targetWc);
      _showError(formatWcLockedMessage(lockInfo));
      return;
    }

    AppLogger.ui.info('开始清理工作副本: $targetWc');
    _showInfo('正在清理工作副本...');

    try {
      final result = await _wcManager.cleanup(targetWc);

      if (result.isSuccess) {
        AppLogger.ui.info('工作副本清理成功');
        // svn cleanup exit 0 不保证 WC 真的可用——外部锁 / .svn 元数据损坏 / 磁盘
        // 故障下 cleanup 仍可能 exit 0。后验 probeSvnLocation 才能真正确认 WC 可用。
        // 与 _runSvnCleanup（暂停态入口）同款风格，但 resumePrompt: false——主屏
        // 工具栏不在"暂停 → 继续"语境，文案不诱导点继续。
        final probeError = await _svnService.probeSvnLocation(
          targetWc,
          role: '工作副本',
        );
        if (!mounted) return;
        final message = formatCleanupFeedback(
          probeError: probeError,
          resumePrompt: false,
        );
        if (probeError == null || probeError.isEmpty) {
          _showSuccess(message);
        } else {
          AppLogger.ui.error('cleanup 后 WC 仍不可用: $probeError');
          _showError(message);
        }
      } else {
        AppLogger.ui.error('工作副本清理失败: ${result.stderr}');
        if (!mounted) return;
        _showError('清理失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('工作副本清理异常', e, stackTrace);
      if (!mounted) return;
      _showError('清理异常: $e');
    }
  }

  Future<void> _openSettings() async {
    final result = await SettingsScreen.show(
      context,
      currentPreloadSettings: _preloadSettings,
      currentMaxRetries: _maxRetries,
      currentMergeValidationScriptPath: _mergeValidationScriptPath,
    );
    if (result != null && mounted) {
      setState(() {
        _preloadSettings = result.preloadSettings;
        _maxRetries = result.maxRetries;
        _mergeValidationScriptPath = result.mergeValidationScriptPath;
      });
      _showSuccess('已保存设置');
    }
  }

  Future<bool> _confirmConfigEditIfNeeded() async {
    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);
    if (!shouldWarnBeforeEditingConfig(
      isProcessing: mergeState.isProcessing,
      hasPausedJob: mergeState.hasPausedJob,
    )) {
      return true;
    }

    final proceed = await _confirmEditConfigWhileBusy(mergeState);
    if (!mounted) return false;
    return proceed == true;
  }

  Future<void> _showSourceConfigDialog() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (!await _confirmConfigEditIfNeeded()) return;
    _openSourceConfigDialog(appState);
  }

  Future<void> _showTargetConfigDialog() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (!await _confirmConfigEditIfNeeded()) return;
    if (appState.useTemporarySparseWorkingCopy) {
      _openTargetUrlConfigDialog(appState);
    } else {
      _openTargetConfigDialog(appState);
    }
  }

  void _openSourceConfigDialog(AppState appState) {
    SourceUrlDialog.show(
      context: context,
      sourceUrlController: _sourceUrlController,
      sourceUrlHistory: appState.sourceUrlHistory,
      onConfirm: () {
        setState(() {});
        _refreshLogList(_logListStopOnCopy);
      },
    );
  }

  void _openTargetConfigDialog(AppState appState) {
    TargetWorkingCopyDialog.show(
      context: context,
      targetWcController: _targetWcController,
      targetWcHistory: appState.targetWcHistory,
      onConfirm: () {
        setState(() {});
        _refreshLogList(_logListStopOnCopy);
      },
    );
  }

  void _openTargetUrlConfigDialog(AppState appState) {
    TargetSvnUrlDialog.show(
      context: context,
      targetUrlController: _targetUrlController,
      targetUrlHistory: appState.targetUrlHistory,
      onConfirm: () async {
        final targetUrl = stripUrlWhitespace(_targetUrlController.text);
        _targetUrlController.text = targetUrl;
        setState(() {});
        await appState.saveTargetUrlToHistory(targetUrl);
      },
    );
  }

  /// 暂停 / 执行中切配置前的二次确认对话框。
  ///
  /// 用户点了主标题旁的"配置"入口、但当前有 paused job 或 isProcessing == true 时，
  /// 先弹这一层提示——展示活动任务的 sourceUrl / targetWc（来自任务自己的字段，
  /// **不是**主屏 controller），明确告知"修改不影响当前任务，仅作用于下一次新建
  /// 的合并任务"。点取消（默认）→ 返回 `false`，不打开配置弹窗；点"继续修改"
  /// → 返回 `true`，调用方再打开源或目标的专用配置弹窗。
  ///
  /// **为什么走 [showDialog] 而不是 SnackBar**：SnackBar 不可阻塞、用户可能错过；
  /// 这个决策的副作用（保存历史 / 改新任务输入源）足够大，值得一个能让人主动点
  /// 的 modal。
  Future<bool?> _confirmEditConfigWhileBusy(
      MergeExecutionState mergeState) async {
    final paused = mergeState.pausedJob;
    final activeJob = paused ?? mergeState.currentJob;
    final activeSource = activeJob?.sourceUrl ?? '';
    final activeTarget = activeJob?.targetWc ?? '';
    final stateLabel =
        paused != null ? '暂停' : (mergeState.isProcessing ? '执行中' : '活动');
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('当前有$stateLabel任务，确定要改配置？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '修改源 URL / 目标工作副本不会影响已暂停或正在执行的任务（任务自带配置副本），'
              '仅会改变下一次新建合并任务时的输入。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (activeSource.isNotEmpty)
              Text('当前任务源：$activeSource', style: const TextStyle(fontSize: 12)),
            if (activeTarget.isNotEmpty)
              Text('当前任务目标：$activeTarget',
                  style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续修改'),
          ),
        ],
      ),
    );
  }

  void _showLogDialog(MergeExecutionState mergeState) {
    LogDialog.show(
      context: context,
      log: mergeState.log,
      lineCount: mergeState.logLineCount,
      onClear: () => mergeState.clearLog(),
    );
  }

  /// 在系统文件管理器中打开工作副本目录。
  ///
  /// **复用 `settings_screen.dart` 的 `resolveOpenDirectoryCommand`**：那里已沉淀
  /// "macos→open / windows→explorer / linux→xdg-open / 其他→null" 的跨平台命令
  /// 解析逻辑及单测；这里直接复用，避免散落两套。
  ///
  /// 失败 / 不支持平台时通过 SnackBar 反馈，不抛异常——和 `_openLogDirectory` 同款
  /// 用户体验。
  Future<void> _openWorkingCopyDirectory(String path) async {
    try {
      final command = resolveOpenDirectoryCommand(
        platform: Platform.operatingSystem,
        path: path,
      );
      if (command != null) {
        await Process.run(command.executable, command.args);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('不支持的平台，工作副本目录: $path')),
          );
        }
      }
    } catch (e) {
      AppLogger.ui.error('打开工作副本目录失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开工作副本目录失败: $e')),
        );
      }
    }
  }

  /// 用户点击"停止预加载"按钮的入口：调 `_preloadService.stopPreload()` 并 SnackBar 反馈。
  ///
  /// **为什么要 SnackBar**：`stopPreload()` 只是把内部 `_shouldStop` 标记为 true，
  /// 真正生效要等到下一轮 while 循环的 `!_shouldStop` 判定（最长可能等到当前 SVN
  /// 请求结束 + 100ms throttle）。期间 UI 状态条（"加载中..."）不会立刻改变。
  /// 没有 SnackBar 反馈时用户可能会反复点击"以为没生效"。
  void _stopPreloadWithFeedback() {
    _preloadService.stopPreload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已请求停止预加载（当前轮结束后生效）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// 用户点击"导出 CSV"按钮的入口：把当前过滤后的全部日志条目写入用户指定的 CSV 文件。
  ///
  /// **流程**：
  /// 1. `appState.getAllFilteredEntries(sourceUrl)` 从缓存拿到全部匹配条目（按
  ///    revision 降序，与列表展示顺序一致）；
  /// 2. 空列表 → SnackBar "当前无可导出条目"，提前返回，**不**弹文件对话框
  ///    （让用户选半天保存路径却拿到空数据是糟糕体验）；
  /// 3. `formatLogEntriesAsCsv` 渲染成字符串；
  /// 4. `FilePicker.platform.saveFile(...)` 让用户选保存路径，默认文件名走
  ///    `formatCsvExportFileName(DateTime.now())`；
  /// 5. 用户取消（返回 null）→ 不做任何事，不报错；
  /// 6. 写文件 + SnackBar "已导出 N 条到 <path>"；
  /// 7. 任何异常 → SnackBar 失败提示，不抛——与 [_openConflictFile] 同款体验。
  ///
  /// **为什么不传 bytes 给 FilePicker**：`saveFile` 在 macOS / Linux 不会自动写
  /// bytes（实现差异），而是返回路径让 caller 自己写。统一走 `File.writeAsString`
  /// 更稳，所有平台行为一致。
  Future<void> _exportFilteredAsCsv(String sourceUrl) async {
    final appState = Provider.of<AppState>(context, listen: false);
    try {
      final entries = await appState.getAllFilteredEntries(sourceUrl);
      if (!mounted) return;
      if (entries.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前无可导出条目')),
        );
        return;
      }
      final defaultName = formatCsvExportFileName(DateTime.now());
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出过滤后的日志为 CSV',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (!mounted) return;
      if (savePath == null) return; // 用户取消
      final csv = formatLogEntriesAsCsv(entries);
      await File(savePath).writeAsString(csv);
      if (!mounted) return;
      // 真 bug 修复：原 SnackBar 仅显示文案 `已导出 N 条到 <path>`，用户想验证
      // CSV 必须手动复制路径打开。同 panel 的 _openConflictFile 已用
      // resolveOpenFileCommand + Process.run 跨平台打开文件，这里复用同款体验：
      // 加 SnackBarAction "打开" 一键打开导出的 CSV，与冲突文件按钮对齐。
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('已导出 ${entries.length} 条到 $savePath'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '打开',
            onPressed: () => _openExportedCsvFile(savePath),
          ),
        ),
      );
    } catch (e) {
      AppLogger.ui.error('导出 CSV 失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 CSV 失败: $e')),
        );
      }
    }
  }

  /// 打开刚导出的 CSV 文件（由 [_exportFilteredAsCsv] 成功 SnackBar 的 "打开" 按钮触发）。
  ///
  /// 复用 [resolveOpenFileCommand]——和 [_openConflictFile] 同款跨平台命令解析；
  /// 失败 / 不支持平台 → SnackBar 反馈，不抛异常。
  Future<void> _openExportedCsvFile(String path) async {
    try {
      final command = resolveOpenFileCommand(
        platform: Platform.operatingSystem,
        path: path,
      );
      if (command != null) {
        await Process.run(command.executable, command.args);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('不支持的平台，CSV 路径: $path')),
          );
        }
      }
    } catch (e) {
      AppLogger.ui.error('打开导出的 CSV 失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开 CSV 失败: $e')),
        );
      }
    }
  }

  /// 一键标记冲突已解决：调用 `SvnService.resolveAccept` 跑 `svn resolve --accept <mode> -R .`。
  ///
  /// **何时被调用**：暂停态 textConflict / treeConflict 时，[MergeExecutionPanel] 会渲染
  /// "标记为已解决"按钮（参见 [shouldShowMarkResolvedButton]）；用户点击后触发本方法。
  ///
  /// **mode 参数**：默认 [SvnResolveAccept.working]——"按已编辑的 WC 形态标记完成"
  /// 是最常见场景。Panel 端 PopupMenuButton 让用户在高级菜单显式切换到
  /// `mine-full` / `theirs-full` / `base`，本方法透传给 svn_service 即可。
  ///
  /// **失败 / 异常时怎么办**：仅 SnackBar 反馈，不抛异常、不自动重试——与
  /// [_openWorkingCopyDirectory] 同款体验。**不**主动 resume 任务，由用户在 SnackBar
  /// 看到成功提示后手动点"继续"，避免 service 跨界调 provider 的反模式（见 R130）。
  Future<void> _markConflictsResolved(
    String targetWc, {
    SvnResolveAccept mode = SvnResolveAccept.working,
  }) async {
    try {
      final result = await _svnService.resolveAccept(targetWc, mode: mode);
      if (!mounted) return;
      if (result.isSuccess) {
        // svn resolve exit 0 不保证 WC 真的干净——再读一次 svn status 校验。
        // 见 [formatMarkResolvedFeedback] dartdoc 的"两档契约"。
        final remaining = await _svnService.listConflictedFiles(targetWc);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              formatMarkResolvedFeedback(
                modeFlag: mode.cliFlag,
                remainingConflictCount: remaining.length,
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('标记失败: ${result.stderr.isEmpty ? "未知错误" : result.stderr}'),
          ),
        );
      }
    } catch (e) {
      AppLogger.ui.error('标记冲突已解决失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('标记冲突已解决失败: $e')),
        );
      }
    }
  }

  /// 对 locked 暂停态调用 `svn cleanup`。
  ///
  /// **触发条件**：仅当 [pausedJob.failureKind] == [SvnFailureKind.locked]
  /// 时 panel 才会渲染按钮（参见 [shouldShowCleanupButton]）。
  ///
  /// **失败 / 异常时怎么办**：仅 SnackBar 反馈，不抛、不自动 resume——与
  /// [_markConflictsResolved] 同款体验。用户在 cleanup 完成后手动点"继续"。
  Future<void> _runSvnCleanup(String targetWc) async {
    try {
      final result = await _svnService.cleanup(targetWc);
      if (!mounted) return;
      if (result.isSuccess) {
        final probeError = await _svnService.probeSvnLocation(
          targetWc,
          role: '工作副本',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              formatCleanupFeedback(probeError: probeError),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'cleanup 失败: ${result.stderr.isEmpty ? "未知错误" : result.stderr}',
            ),
          ),
        );
      }
    } catch (e) {
      AppLogger.ui.error('执行 svn cleanup 失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('执行 svn cleanup 失败: $e')),
        );
      }
    }
  }

  /// 在 outOfDate 暂停态弹 dialog 让用户临时调高当前任务的 `maxRetries`。
  ///
  /// **触发条件**：仅当 [pausedJob.failureKind] == [SvnFailureKind.outOfDate]
  /// 时 panel 才会渲染按钮（参见 [shouldShowAdjustMaxRetriesButton]）。
  ///
  /// **流程**：
  /// 1. 弹 AlertDialog，TextField 默认填当前 maxRetries；
  /// 2. 用户输入新值 → 校验：必须能 `int.tryParse` 且 `> currentMaxRetries`；
  /// 3. 调 `MergeExecutionState.updateJobMaxRetries(jobId, newMax)`；
  /// 4. true → SnackBar 提示成功并提示用户点"继续"；false → SnackBar 提示无效输入。
  ///
  /// **失败 / 异常时怎么办**：仅 SnackBar 反馈，不抛、不自动 resume——与
  /// [_runSvnCleanup] / [_markConflictsResolved] 同款体验。
  Future<void> _adjustJobMaxRetries(MergeJob job) async {
    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);
    final controller = TextEditingController(text: job.maxRetries.toString());
    final newValue = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('调整任务 #${job.jobId} 重试次数'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前上限：${job.maxRetries}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '新的重试上限',
                  helperText: '只能调高（必须大于当前值）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted) return;
    if (newValue == null) return;
    final ok = await mergeState.updateJobMaxRetries(job.jobId, newValue);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将任务 #${job.jobId} 的重试上限调整为 $newValue，可点击"继续"重试'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('调整失败：新值必须大于当前上限 ${job.maxRetries}'),
        ),
      );
    }
  }

  Future<void> _editJobCommitSupplement(MergeJob job) async {
    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);
    final controller = TextEditingController(text: job.commitSupplement ?? '');
    final supplement = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('补充任务 #${job.jobId} 的 CRID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '提交被服务端 Code Review 规则拦截。请填写 --crid=NNNN 格式的附加信息。',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '提交附加信息',
                  hintText: '例如：--crid=123456 Merge r5: trunk -> b1',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted) return;
    if (supplement == null) return;
    final ok = await mergeState.updateJobCommitSupplement(
      job.jobId,
      supplement,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '已保存提交附加信息，可点击"继续执行"重试提交' : '保存失败：提交附加信息不能为空',
        ),
      ),
    );
  }

  Future<void> _editJobCommitMessage(MergeJob job) async {
    final revision = job.currentRevision;
    if (revision == null) {
      _showInfo('当前任务没有可编辑的提交 revision');
      return;
    }

    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);
    final controller = TextEditingController(
      text: buildCommitMessage(job, revision),
    );
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('修改 r$revision 提交 Message'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('提交信息被服务端规则拦截时，可在这里直接编辑完整原始 message。'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: '完整提交 Message',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || message == null) return;

    final ok = await mergeState.updateJobCommitMessageOverride(
      jobId: job.jobId,
      revision: revision,
      message: message,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '已保存 r$revision 的完整提交 Message，可点击"继续提交"'
              : '保存失败：提交 Message 不能为空',
        ),
        action: ok
            ? SnackBarAction(
                label: '继续提交',
                onPressed: () {
                  _resumePausedJobWithFeedback(mergeState);
                },
              )
            : null,
      ),
    );
  }

  Future<void> _createCodeReviewForPausedJob(MergeJob job) async {
    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);
    _showInfo('正在发起 Code Review...');
    try {
      final result = await _gongfengCrService.createCodeReview(
        targetWc: job.targetWc,
        title: buildGfCrTitle(job),
        description: buildGfCrDescription(job),
      );
      if (!mounted) return;
      final ok = await mergeState.updateJobCommitSupplement(
        job.jobId,
        result.commitSupplement,
      );
      if (!mounted) return;
      final updatedJob = mergeState.pausedJob ?? job;
      await _showCodeReviewCreatedDialog(
        job: updatedJob,
        reviewUrl: result.reviewUrl,
        didUpdateCommitSupplement: ok,
      );
    } on GongfengCrException catch (e) {
      AppLogger.ui.warn('发起 Code Review 失败: ${e.message}');
      if (!mounted) return;
      if (e.loginRequired) {
        await _openGongfengInteractiveLogin(job);
        return;
      }
      final detail = e.output.isEmpty ? '' : '\n${e.output}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发起 Code Review 失败: ${e.message}$detail')),
      );
    } catch (e, stackTrace) {
      AppLogger.ui.error('发起 Code Review 异常', e, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发起 Code Review 失败: $e')),
      );
    }
  }

  Future<void> _showCodeReviewCreatedDialog({
    required MergeJob job,
    required String? reviewUrl,
    required bool didUpdateCommitSupplement,
  }) async {
    if (!mounted) return;

    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);
    final revision = job.currentRevision;
    final controller = TextEditingController(
      text: buildCodeReviewCommitMessage(job),
    );

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Code Review 已发起'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    didUpdateCommitSupplement
                        ? 'CRID 已自动回填到提交 Message。请确认或编辑后点击「继续提交」。'
                        : 'CRID 回填失败，请在下方 Message 中手动补充 --crid= 等信息。',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 8,
                    maxLines: 14,
                    decoration: const InputDecoration(
                      labelText: '完整提交 Message',
                      hintText:
                          '例如：\n[Merge] r5 from svn://...\n\n--crid=9 Merge r5: trunk -> b1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (reviewUrl != null && reviewUrl.isNotEmpty) ...[
                    const Text('Code Review 链接:'),
                    const SizedBox(height: 6),
                    SelectableText(reviewUrl),
                  ] else
                    const Text('未能从 gf 输出中解析到 Code Review 链接。'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭'),
              ),
              if (reviewUrl != null && reviewUrl.isNotEmpty) ...[
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: reviewUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制 Code Review 链接')),
                    );
                  },
                  child: const Text('复制链接'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _openCodeReviewUrl(reviewUrl);
                  },
                  child: const Text('打开链接'),
                ),
              ],
              ElevatedButton.icon(
                onPressed: () async {
                  final message = controller.text.trim();
                  if (message.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('提交 Message 不能为空')),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop();

                  if (revision != null) {
                    final saved =
                        await mergeState.updateJobCommitMessageOverride(
                      jobId: job.jobId,
                      revision: revision,
                      message: message,
                    );
                    if (!mounted) return;
                    if (!saved) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('保存提交 Message 失败')),
                      );
                      return;
                    }
                  } else {
                    final saved = await mergeState.updateJobCommitSupplement(
                      job.jobId,
                      message,
                    );
                    if (!mounted) return;
                    if (!saved) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('保存提交 Message 失败')),
                      );
                      return;
                    }
                  }

                  await _resumePausedJobWithFeedback(mergeState);
                },
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('继续提交'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openCodeReviewUrl(String reviewUrl) async {
    try {
      final command = resolveOpenFileCommand(
        platform: Platform.operatingSystem,
        path: reviewUrl,
      );
      if (command == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('不支持的平台，Code Review 链接: $reviewUrl')),
        );
        return;
      }
      await Process.run(command.executable, command.args);
    } catch (e, stackTrace) {
      AppLogger.ui.error('打开 Code Review 链接失败', e, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开 Code Review 链接失败: $e')),
      );
    }
  }

  Future<void> _openGongfengInteractiveLogin(MergeJob job) async {
    try {
      final command = resolveGfAuthLoginCommand(
        platform: Platform.operatingSystem,
        workingDirectory: job.targetWc,
      );
      if (command == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('不支持的平台，请在工作副本目录执行: gf auth login')),
        );
        return;
      }

      await Process.run(command.executable, command.args);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开工蜂登录终端，登录完成后请重新发起 Code Review')),
      );
    } catch (e, stackTrace) {
      AppLogger.ui.error('打开工蜂登录终端失败', e, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开工蜂登录终端失败: $e')),
      );
    }
  }

  /// 对 network 暂停态做一次轻量 SVN 连通性测试（复用第二十六轮 [SvnService.probeSvnLocation]）。
  ///
  /// **触发条件**：仅当 [pausedJob.failureKind] == [SvnFailureKind.network]
  /// 时 panel 才会渲染按钮（参见 [shouldShowTestConnectivityButton]）。
  ///
  /// **流程**：
  /// 1. 依次 probe `job.sourceUrl` 与 `job.targetWc`（与第二十六轮 `_startMerge` 同款顺序，
  ///    错误信息要明确告诉用户哪一项不通）；
  /// 2. 双 null → SnackBar 绿底提示"连通性正常"；任一非 null → SnackBar 红底提示
  ///    具体失败原因（已由 [formatProbeFailureReason] 翻译为单行文案）。
  ///
  /// **为什么用 pausedJob 自带的 sourceUrl/targetWc 而非主屏 controller**：
  /// 暂停态任务的配置是创建时的副本（与第十轮 `shouldWarnBeforeEditingConfig`
  /// 文案"任务自带配置副本"一致），用主屏 controller 可能测的是用户后改的新配置，
  /// 跟当前任务无关。
  ///
  /// **失败 / 异常时怎么办**：仅 SnackBar 反馈，不抛、不自动 resume——与
  /// [_runSvnCleanup] / [_markConflictsResolved] / [_adjustJobMaxRetries] 同款体验。
  Future<void> _testSvnConnectivity(MergeJob job) async {
    final sourceProbeError = await _svnService.probeSvnLocation(
      job.sourceUrl,
      role: '源 URL',
    );
    if (!mounted) return;
    if (sourceProbeError != null) {
      _showError(sourceProbeError);
      return;
    }
    final targetProbeError = await _svnService.probeSvnLocation(
      job.targetWc,
      role: '目标工作副本',
    );
    if (!mounted) return;
    if (targetProbeError != null) {
      _showError(targetProbeError);
      return;
    }
    _showSuccess('连通性正常，SVN 可访问，可点击"继续"重试');
  }

  /// 用系统默认编辑器打开"暂停态 textConflict 任务"的第一个冲突文件。
  ///
  /// **流程**：
  /// 1. 调 `SvnService.listConflictedFiles(targetWc)` 拿冲突文件相对路径列表；
  /// 2. 空列表 → SnackBar 提示"未发现冲突文件"，不抛异常；
  /// 3. 非空 → 取第一条，用 `p.join(targetWc, relative)` 拼成绝对路径
  ///    （SVN status 输出的路径相对工作副本根，[targetWc] 由 caller 传入；
  ///    `p.join` 在第二段已是绝对路径时会直接使用绝对路径，符合预期）；
  /// 4. 调 [resolveOpenFileCommand] 解析平台命令，null → SnackBar 提示
  ///    "不支持的平台 + 文件路径"；非 null → `Process.run`；
  /// 5. 任意异常 → SnackBar 提示，不抛——与 [_openWorkingCopyDirectory] 同款体验。
  ///
  /// **为什么只开第一条**：textConflict 通常一次只暴露 1 个文件让用户改完再继续，
  /// 一次性打开多个反而难以聚焦。用户改完点"继续"重跑，下一次冲突重新弹一个，
  /// 与 SVN 的串行解决习惯一致。
  Future<void> _openConflictFile(String targetWc) async {
    try {
      final conflicted = await _svnService.listConflictedFiles(targetWc);
      if (!mounted) return;
      if (conflicted.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未发现冲突文件')),
        );
        return;
      }
      final relative = conflicted.first;
      final absolute = p.join(targetWc, relative);
      final command = resolveOpenFileCommand(
        platform: Platform.operatingSystem,
        path: absolute,
      );
      if (command != null) {
        await Process.run(command.executable, command.args);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatOpenConflictFileFeedback(
              totalCount: conflicted.length,
              openedRelative: relative,
            )),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('不支持的平台，冲突文件: $absolute')),
          );
        }
      }
    } catch (e) {
      AppLogger.ui.error('打开冲突文件失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开冲突文件失败: $e')),
        );
      }
    }
  }

  /// 获取当前操作阶段
  OperationPhase _getCurrentPhase(MergeExecutionState mergeState) {
    return resolveOperationPhase(
      isProcessing: mergeState.isProcessing,
      hasPausedJob: mergeState.hasPausedJob,
    );
  }

  /// **R130 cross-provider 通信反模式审计 — 档 3 Consumer2 双 provider 订阅协调点**：
  ///
  /// 这是 lib 内 **2 处 Consumer 站点之一**（另一处 main.dart:259 单 Consumer<AppState> 启动期 loading/error）。
  /// 主屏幕需要同时响应 AppState（log entries / 过滤器 / 配置）和 MergeExecutionState（job phase）的 rebuild，
  /// 故选 Consumer2 而非两个嵌套 Consumer——后者会让 rebuild 责任分裂、调试时难以追踪触发链。
  ///
  /// **档 3 sub-variant 选型判据（R130 首次形式化）**：
  ///   - 单 provider 订阅 → `Consumer<T>`；
  ///   - 多 provider **同等关键** → `Consumer2/3<T1, T2>`（本站）；
  ///   - 仅订阅 provider 内 1-2 字段（防止整个 provider 任一字段变更触发 rebuild）→ `Selector<T, S>`；
  ///   - 简单 inline 订阅（短 build subtree）→ `context.watch<T>()`。
  ///   本 lib 全 Consumer 选型，0 处 Selector / 0 处 watch——**故意保持订阅链显式可见**，
  ///   而非用 watch 的隐式订阅；与 R117 "故意不抽 firstWhereOrNull" / R122 "故意不引 collection package"
  ///   同源——显式优于隐式原则在跨 provider 通信链路的实例。
  ///
  /// **跨档不变量 I3 在档 3 的实例**：Consumer 出现位置必在 widget build() 内、
  /// 不能出现在 provider 类内或 service 内——后者跨界 + framework 误用，会让 ChangeNotifier 自身
  /// 持有 BuildContext 引用、超出 widget tree 生命周期。
  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, MergeExecutionState>(
      builder: (context, appState, mergeState, _) {
        final phase = _getCurrentPhase(mergeState);

        return Scaffold(
          body: Stack(
            children: [
              Column(
                children: [
                  // 顶部配置栏
                  ConfigBar(
                    sourceUrl: _sourceUrlController.text.trim(),
                    targetConfig: _currentTargetConfig(appState),
                    onSourceTap: _showSourceConfigDialog,
                    onTargetTap: _showTargetConfigDialog,
                    onSettingsTap: _openSettings,
                    onSvnOperation: _handleSvnOperation,
                    onTemporarySparseWorkingCopyChanged:
                        appState.setUseTemporarySparseWorkingCopy,
                  ),
                  // 主内容区
                  Expanded(
                    child: phase == OperationPhase.execute
                        ? _buildExecutePhaseView(mergeState)
                        : _buildSelectPhaseView(appState, mergeState),
                  ),
                ],
              ),
              if (_isSvnSwitching)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                      ),
                      child: const Center(
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 18,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('正在切换目标分支，请勿执行其他操作...'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 选择阶段视图
  Widget _buildSelectPhaseView(
      AppState appState, MergeExecutionState mergeState) {
    final sourceUrl = _sourceUrlController.text.trim();
    final targetConfig = _currentTargetConfig(appState);
    final targetStateKey = resolveLogTargetStateKey(targetConfig);

    // 构建已合并 revision 集合
    final mergedRevisions = computeMergedRevisions(
      entries: appState.paginatedLogEntries,
      isMerged: (revision) => appState.isRevisionMergedSync(
        revision,
        sourceUrl: sourceUrl,
        targetWc: targetStateKey,
      ),
    );

    final preloadStatusText = resolvePreloadStatusText(
      sourceUrl: sourceUrl,
      preloadSourceUrl: _preloadProgress.sourceUrl,
      statusDescription: _preloadProgress.statusDescription,
    );

    final boundary = _buildBoundaryDescription(
      sourceUrl: sourceUrl,
      targetWc: targetStateKey,
    );
    final boundaryText = boundary.text;
    final pendingSourceLabel = buildPendingSourceLabel(_pendingSourceUrl);
    final pendingSourceWarning = _buildPendingSourceWarning(sourceUrl);
    final hasPendingSourceMismatch = pendingSourceWarning != null;
    final canLoadMore = resolveCanLoadMore(
      cachedLogCount: _cachedLogCount,
      boundary: boundary,
    );

    final selectableEntryCount = computeSelectableRevisions(
      entries: appState.paginatedLogEntries,
      pendingRevisions: appState.pendingRevisions,
      isMerged: (revision) => appState.isRevisionMergedSync(
        revision,
        sourceUrl: sourceUrl,
        targetWc: targetStateKey,
      ),
    ).length;

    return Row(
      children: [
        // 左侧：日志列表
        Expanded(
          flex: 2,
          child: LogListPanel(
            entries: appState.paginatedLogEntries,
            selectedRevisions: _selectedRevisions,
            pendingRevisions: appState.pendingRevisions.toSet(),
            mergedRevisions: mergedRevisions,
            isLoading: appState.isLoadingData,
            authorController: _filterAuthorController,
            titleController: _filterTitleController,
            messageController: _filterMessageController,
            stopOnCopy: _logListStopOnCopy,
            onStopOnCopyChanged: (value) {
              setState(() => _logListStopOnCopy = value);
              _refreshLogList(value);
            },
            onApplyFilter: _applyFilter,
            onClearFilter: _clearAllLogFilters,
            onRefresh: () => _syncLatestLogs(),
            canSyncLatest: sourceUrl.isNotEmpty,
            onSyncLatest: () => _syncLatestLogs(),
            canLoadMore: canLoadMore,
            onLoadMore: _loadMoreLogs,
            canStopPreload: _preloadProgress.status == PreloadStatus.loading,
            onStopPreload: _stopPreloadWithFeedback,
            canExportCsv:
                appState.paginatedLogEntries.isNotEmpty && sourceUrl.isNotEmpty,
            onExportCsv: () => _exportFilteredAsCsv(sourceUrl),
            cachedCount: _cachedLogCount,
            latestCachedRevision: _latestCachedRevision,
            earliestCachedRevision: _earliestCachedRevision,
            branchPoint: _logListStopOnCopy ? _cachedBranchPoint : null,
            preloadStatusText: preloadStatusText,
            boundaryText: boundaryText,
            currentPage: appState.currentPage,
            totalPages: appState.totalPages,
            hasMore: appState.hasMore,
            selectableEntryCount: selectableEntryCount,
            onSelectAllSelectable: _selectAllSelectableRevisions,
            onClearSelection: _clearSelectedRevisions,
            onPageChanged: (page) {
              if (page > appState.currentPage) {
                appState.nextPage(sourceUrl: sourceUrl);
              } else if (page < appState.currentPage) {
                appState.previousPage(sourceUrl: sourceUrl);
              } else {
                appState.setCurrentPage(page, sourceUrl: sourceUrl);
              }
            },
            onSelectionChanged: (revision, selected) {
              setState(() {
                if (selected) {
                  _selectedRevisions.add(revision);
                } else {
                  // R124 mutator 二档判据：Set.remove(elem) **档 2**——elem
                  // 由用户选择交互决定（外部输入），不是常量。Set 结构身份本
                  // 身就是档位识别信号——不暴露 indexed access、不依赖位置语义，
                  // 与 R123 List.removeAt 档 2 形成对偶（List 档 2 必须保留 List
                  // / Set 档 2 必须保留 Set，原因相反但结构身份契约同强）。
                  _selectedRevisions.remove(revision);
                }
              });
            },
          ),
        ),
        SizedBox(
          width: 280,
          child: PendingPanel(
            pendingRevisions: appState.pendingRevisions,
            selectedCount: _selectedRevisions.length,
            sourceLabel: pendingSourceLabel,
            sourceUrl: _pendingSourceUrl,
            sourceWarning: pendingSourceWarning,
            onAddSelected: _addSelectedToPending,
            canAddSelected: !hasPendingSourceMismatch,
            onClearPending: _clearPendingRevisions,
            onRemove: _removePendingRevision,
            onStartMerge: _startMerge,
            canStartMerge: appState.pendingRevisions.isNotEmpty &&
                !hasPendingSourceMismatch &&
                !_isValidatingMerge,
            commitSupplementController: _commitSupplementController,
          ),
        ),
        SizedBox(
          width: 320,
          child: JobQueuePanel(
            jobs: mergeState.jobs,
            currentJobId: mergeState.currentJob?.jobId,
            onDeleteJob: (jobId) => _deleteQueueJob(mergeState, jobId),
            onRequeueRemainingJob: (jobId) =>
                _requeueRemainingJob(mergeState, jobId),
            onClearPendingJobs: () => _clearPendingJobs(mergeState),
            onClearFinishedJobs: () => _clearFinishedJobs(mergeState),
            onReorderPendingJobs: (oldIndex, newIndex) =>
                mergeState.reorderPendingJobs(oldIndex, newIndex),
          ),
        ),
      ],
    );
  }

  /// 执行阶段视图
  Widget _buildExecutePhaseView(MergeExecutionState mergeState) {
    return Column(
      children: [
        // 主内容区：步骤视图 + 控制面板
        Expanded(
          child: Row(
            children: [
              // 左侧：固定步骤执行视图
              Expanded(
                flex: 2,
                child: StepExecutionView(
                  steps: mergeState.steps,
                  currentStepId: mergeState.currentStepId,
                  status: mergeState.status,
                  snapshots: mergeState.snapshots,
                  selectedStepId: _selectedStepId,
                  onStepSelected: (stepId) {
                    setState(() => _selectedStepId = stepId);
                  },
                ),
              ),
              // 右侧：可拖动宽度的控制面板
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _panelWidth =
                          (_panelWidth - details.delta.dx).clamp(280.0, 600.0);
                    });
                  },
                  child: Container(
                    width: 4,
                    color: Colors.grey.shade300,
                  ),
                ),
              ),
              SizedBox(
                width: _panelWidth,
                child: MergeExecutionPanel(
                  status: mergeState.status,
                  currentStepId: mergeState.currentStepId,
                  currentStepName: mergeState.currentStepTitle,
                  currentJob: mergeState.currentJob,
                  pausedJob: mergeState.pausedJob,
                  onResume: () => _resumePausedJobWithFeedback(mergeState),
                  onSkip: () => _skipCurrentRevisionWithFeedback(mergeState),
                  onCancel: () => _cancelPausedJobWithConfirm(mergeState),
                  selectedSnapshot: _selectedStepId != null
                      ? mergeState.snapshots.get(_selectedStepId!)
                      : null,
                  selectedStepId: _selectedStepId,
                  globalContext: mergeState.snapshots.globalContext,
                  snapshots: mergeState.snapshots.all,
                  onClearSelection: () {
                    setState(() => _selectedStepId = null);
                  },
                  onOpenWorkingCopy: mergeState.pausedJob == null
                      ? null
                      : () => _openWorkingCopyDirectory(
                            mergeState.pausedJob!.targetWc,
                          ),
                  onMarkResolved: mergeState.pausedJob == null
                      ? null
                      : (mode) => _markConflictsResolved(
                            mergeState.pausedJob!.targetWc,
                            mode: mode,
                          ),
                  onOpenConflictFile: mergeState.pausedJob == null
                      ? null
                      : () => _openConflictFile(
                            mergeState.pausedJob!.targetWc,
                          ),
                  onCleanup: mergeState.pausedJob == null
                      ? null
                      : () => _runSvnCleanup(
                            mergeState.pausedJob!.targetWc,
                          ),
                  onAdjustMaxRetries: mergeState.pausedJob == null
                      ? null
                      : () => _adjustJobMaxRetries(
                            mergeState.pausedJob!,
                          ),
                  onEditCommitSupplement: mergeState.pausedJob == null
                      ? null
                      : () => _editJobCommitSupplement(
                            mergeState.pausedJob!,
                          ),
                  onCreateCodeReview: mergeState.pausedJob == null
                      ? null
                      : () => _createCodeReviewForPausedJob(
                            mergeState.pausedJob!,
                          ),
                  onEditCommitMessage: mergeState.pausedJob == null
                      ? null
                      : () => _editJobCommitMessage(
                            mergeState.pausedJob!,
                          ),
                  onTestConnectivity: mergeState.pausedJob == null
                      ? null
                      : () => _testSvnConnectivity(
                            mergeState.pausedJob!,
                          ),
                ),
              ),
            ],
          ),
        ),
        // 底部状态栏
        StatusBar(
          status: mergeState.status,
          hasLog: mergeState.log.isNotEmpty,
          onViewLog: () => _showLogDialog(mergeState),
        ),
      ],
    );
  }
}
