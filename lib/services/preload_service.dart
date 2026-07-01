/// 预加载服务
///
/// 负责后台静默预加载 SVN 日志数据
/// 
/// 功能：
/// - 后台静默加载日志到缓存
/// - 支持多种停止条件（分支点、天数、条数、版本、日期）
/// - 提供加载进度回调
/// - 支持手动触发"加载全部到分支点"
/// - 使用区间管理：每次启动从 HEAD 开始
///
/// ============================================================================
/// **R142 异步时间轴协议审计：Future.delayed/Timer/Timer.periodic 全集穷尽闭合**
/// ============================================================================
/// **审计范围**：lib/ 下所有"按时间触发的延迟动作" API。
/// **API 全集**（dart:async / dart:io 提供）：
/// 1. `Future.delayed(d, [computation])` —— 一次性延迟 future
/// 2. `Timer(d, callback)` —— 一次性定时回调（可 cancel）
/// 3. `Timer.periodic(d, callback)` —— 周期性定时回调（必 cancel）
/// 4. `Stream.periodic(d)` —— 周期性 Stream（必须 listen.cancel）
/// 5. `sleep(d)`（dart:io，**同步阻塞**）—— Flutter UI thread 严禁使用
/// 6. `scheduleMicrotask(fn)` —— 0-delay 微任务调度（不在本协议范围内：
///    无延迟参数、无 cancel handle，属于"同帧让出"而非"按时间触发"）
///
/// **lib/ 实际使用全集**（仅 1 / 6 API + scheduleMicrotask）：
/// - `Future.delayed`：**2 个站点**
/// - `Timer / Timer.periodic / Stream.periodic / sleep`：**0 个站点**
/// - `scheduleMicrotask`：1 个站点（logger_service.dart:715，不在本协议范围）
///
/// **2 个 Future.delayed 站点矩阵**：
/// | 站点 | 文件:行 | 时长 | trigger 语义 | 退出条件 | R120 档位 | cancel 机制 |
/// |------|---------|------|--------------|----------|-----------|-------------|
/// | A | logger_service.dart:771 | 10ms | polling tick | `_writeQueue.isEmpty && !_isWriting` | **档 2** | while 循环条件 |
/// | B | preload_service.dart:638 | 100ms | throttle/yield | `_shouldStop` 或 数据耗尽 | **档 3** | `_shouldStop` flag |
///
/// ----------------------------------------------------------------------------
/// **三档框架（cancel 机制维度）**：
/// ----------------------------------------------------------------------------
/// **档 1：no-cancel 一次性延迟** —— 不需取消、await 即可消费的纯延迟。
///   - lib/ 中 **0 个**（一旦出现，需评估是否需升档）。
///   - 触发判据："这个 delay 能 await 完整结束、上下文结束前一定到点"。
///
/// **档 2：cancel-by-loop-condition 循环内延迟** —— 延迟嵌入 while/for 循环，
/// 取消由循环条件触发（loop guard 在下一轮检查 cancel flag / 状态变化）。
///   - 站点 A（logger close polling）+ 站点 B（preload throttle）。
///   - **关键不变量**：delay 时长必须 ≤ "可接受的关闭/取消延迟"；档 2 站点取消
///     不是即时的，而是"下一轮 tick 时退出"。
///   - **A**: 10ms tick → close 最多多等 10ms；
///   - **B**: 100ms throttle → 用户停止后最多多走一轮 SVN 请求 + 100ms。
///
/// **档 3：cancel-by-Timer-handle 句柄式延迟** —— Timer/Timer.periodic 持有
/// 句柄、外部 dispose 时显式 `_timer?.cancel()`。
///   - lib/ 中 **0 个**（无 Timer / Timer.periodic 使用）。
///   - 触发判据："延迟动作脱离当前 await 调用栈，需独立生命周期管理"。
///
/// ----------------------------------------------------------------------------
/// **U 系四协议律**（unique invariants）：
/// ----------------------------------------------------------------------------
/// **U1 API 单一律**：lib/ 仅使用 `Future.delayed`，禁止引入 `Timer` / `Timer.periodic`
/// / `Stream.periodic` / `dart:io sleep` 而无对应档位文档说明。新增任一上列 API
/// 必须更新本协议矩阵。
///
/// **U2 退出条件单点律**：每个 Future.delayed 站点必须有**唯一**退出信号源：
/// - 站点 A：`_writeQueue.isEmpty && !_isWriting`（while 头）
/// - 站点 B：`_shouldStop` 或 `newCount == 0` / stopReason（while 头与中段 break）
/// 禁止"delay 自身充当退出条件"（=档 1 在生产代码中要谨慎引入）。
///
/// **U3 时长选值理由律**：每个 Future.delayed 的毫秒数必须有 doc 说明依据：
/// - 站点 A：10ms = polling 间隔常用下界，与 IOSink flush 量级匹配
/// - 站点 B：100ms = SVN RTT 同量级，限速 I/O 不显著拖慢
/// 禁止"凭感觉的魔术数字"。
///
/// **U4 档位标注双向律**：每个站点的档位标注（R120 档 2 / 档 3）必须双向闭合：
/// - 行内注释指向 R120 档位 + 列出"区分锁"
/// - 本 R142 矩阵列出该站点的档位 + 行号
/// 漏一边即视为协议未闭合。
///
/// ----------------------------------------------------------------------------
/// **故意不做（R142 边界）**：
/// ----------------------------------------------------------------------------
/// - **不引入 Timer / Timer.periodic**：当前 2 站点都嵌在 while 循环、自然 cancel；
///   引入 Timer 只会增加状态机复杂度。
/// - **不抽公共 helper（如 `delayWithCheck(d, () => _shouldStop)`）**：
///   2 站点退出条件不同（A: 双布尔与，B: flag 或数据耗尽），抽 helper 反而要传
///   2~3 个回调，比 inline 更冗长（与 R121 / R141 故意不做同源）。
/// - **不审计 scheduleMicrotask**：0-delay 不属于"按时间触发"，不在本协议范围；
///   logger_service.dart:715 的 scheduleMicrotask 是 trampoline 模式，由 R120
///   档 2 close polling 兜底。
/// - **不审计测试代码中的 Future.delayed**：测试是 mock 时钟之外的人造场景，
///   不参与生产协议审计。
///
/// ----------------------------------------------------------------------------
/// **R120 ↔ R142 正交叠加**：
/// ----------------------------------------------------------------------------
/// - **R120**（等待协议）：从"等待语义"维度切分（信号驱动 / polling / throttle）；
/// - **R142**（异步时间轴协议）：从"API 全集 + cancel 机制"维度切分；
/// - 同一站点同时受两个协议约束（站点 A：R120 档 2 + R142 档 2；站点 B：R120 档 3
///   + R142 档 2，因为 throttle 也是嵌在 while 中、靠循环条件 cancel）。
/// - 两协议不冲突：R120 回答"为什么要 sleep"，R142 回答"用哪个 API + 如何 cancel"。
///
/// **N-tuple 不变量模板第 22 次复用 / 第 6 次维度切换**（首次"时间轴"维度切换）。
/// **doc-only 审计 R85+ 第 N+19 次复用**（R85-R89 / R94-R96 / R98-R100 / R102-R130
/// / R133-R142）。
/// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import 'log_sync_service.dart';
import 'log_filter_service.dart' show appLogSeparator;
import 'log_cache_service.dart';
import 'logger_service.dart';

/// 根据"最近 N 天"配置计算预加载的天数截止日期。
///
/// - `maxDays > 0` → `now.subtract(Duration(days: maxDays))`
/// - `maxDays <= 0` → `null`，表示**未启用**天数限制（与 `startPreload` 原
///   `settings.maxDays > 0 ? ... : null` 行为一致；负数同样归为"不限制"）
///
/// 把 `DateTime.now()` 作为显式参数传入而非内部读取，便于单元测试在不 mock
/// 时钟的前提下断言精确的截止日期。
@visibleForTesting
DateTime? computeDaysLimitDate({
  required DateTime now,
  required int maxDays,
}) {
  if (maxDays <= 0) return null;
  return now.subtract(Duration(days: maxDays));
}

/// 评估预加载是否应停止的纯函数。
///
/// 输入当前缓存快照与设置，返回应该停止的原因；不应停止时返回
/// [PreloadStopReason.none]。判定顺序与原 `_checkStopConditions` 严格一致：
/// 条数 → 版本 → 天数 → 日期 → 分支点。该函数不读取任何全局状态，
/// 也不写日志，方便单元测试覆盖每条停止路径。
///
/// - [totalCount]：当前最新区间已缓存的条数。
/// - [earliestRevision]：当前最新区间的最早 revision；`<= 0` 视为未知。
/// - [earliestDate]：当前最新区间最早条目的日期；`null` 视为未知。
/// - [settings]：用户配置；`maxCount` / `stopRevision` / `maxDays` 为 `0`
///   或 `stopDate` 为 null 时表示对应维度不限制。
/// - [daysLimitDate]：根据 `settings.maxDays` 计算出的截止日期，避免函数
///   依赖 `DateTime.now()`；`null` 表示未启用天数限制。
/// - [stopDate]：直接来自 `settings.stopDateTime` 的截止日期；`null`
///   表示未启用日期限制。
/// - [branchPoint]：当前 `LogSyncService.getCopyTailCache(...)` 给出的分支点；
///   `null` 表示尚未解析或不需要按分支点停止。
@visibleForTesting
PreloadStopReason evaluatePreloadStopReason({
  required int totalCount,
  required int earliestRevision,
  required DateTime? earliestDate,
  required PreloadSettings settings,
  required DateTime? daysLimitDate,
  required DateTime? stopDate,
  required int? branchPoint,
}) {
  // 1. 条数限制
  if (settings.maxCount > 0 && totalCount >= settings.maxCount) {
    return PreloadStopReason.countLimit;
  }
  // 2. 版本限制
  if (settings.stopRevision > 0 &&
      earliestRevision > 0 &&
      earliestRevision <= settings.stopRevision) {
    return PreloadStopReason.revisionLimit;
  }
  // 3. 天数限制
  if (daysLimitDate != null &&
      earliestDate != null &&
      earliestDate.isBefore(daysLimitDate)) {
    return PreloadStopReason.daysLimit;
  }
  // 4. 日期限制
  if (stopDate != null &&
      earliestDate != null &&
      earliestDate.isBefore(stopDate)) {
    return PreloadStopReason.dateLimit;
  }
  // 5. 分支点
  if (settings.stopOnBranchPoint &&
      branchPoint != null &&
      earliestRevision > 0 &&
      earliestRevision <= branchPoint) {
    return PreloadStopReason.branchPoint;
  }
  return PreloadStopReason.none;
}

/// 把 [PreloadStopReason] 翻译成面向用户的中文描述。
///
/// - [loadedCount]：用于 `countLimit` 的占位数量；其它原因不引用此值。
/// - [branchPoint]：用于 `branchPoint` 的占位 revision；其它原因不引用此值。
/// - [errorMessage]：用于 `error` 的兜底说明，`null` 时显示 `"未知错误"`。
@visibleForTesting
String describePreloadStopReason(
  PreloadStopReason reason, {
  int loadedCount = 0,
  int? branchPoint,
  String? errorMessage,
}) {
  switch (reason) {
    case PreloadStopReason.none:
      return '已完成';
    case PreloadStopReason.branchPoint:
      return '已到达分支点 r$branchPoint';
    case PreloadStopReason.daysLimit:
      return '已到达天数限制';
    case PreloadStopReason.countLimit:
      return '已到达条数限制 ($loadedCount 条)';
    case PreloadStopReason.revisionLimit:
      return '已到达指定版本';
    case PreloadStopReason.dateLimit:
      return '已到达指定日期';
    case PreloadStopReason.noMoreData:
      return '已加载全部数据';
    case PreloadStopReason.userStopped:
      return '用户停止';
    case PreloadStopReason.error:
      return formatPreloadErrorMessage(errorMessage);
  }
}

/// 把 [PreloadStatus] + [PreloadStopReason] 翻译成 UI 状态描述。
///
/// 对应原 `PreloadProgress.statusDescription` getter 的全部分支：
/// - `idle` → `'空闲'`
/// - `loading` → `'加载中...'`（基线兜底）；当 [loadedCount] > 0 时附加
///   `' (已 N 条, 最早 rXXX)'`（[earliestRevision] 经 [normalizeOptionalRevision]
///   归一化后非 null 才追加最早 rev 段，否则只有条数段：
///   `'加载中... (已 N 条)'`）
/// - `paused` → `'已暂停'`
/// - `completed` → 委托 [describePreloadStopReason]，由 [stopReason] 决定文案
/// - `error` → `'出错: ${errorMessage ?? "未知错误"}'`（与
///   `describePreloadStopReason(PreloadStopReason.error, ...)` 文案**一致**，
///   但走的是不同代码路径——`status==error` 时本函数 inline 返回，不查 [stopReason]）
@visibleForTesting
String describePreloadStatusDescription({
  required PreloadStatus status,
  required PreloadStopReason stopReason,
  int loadedCount = 0,
  int? earliestRevision,
  int? branchPoint,
  String? errorMessage,
}) {
  switch (status) {
    case PreloadStatus.idle:
      return '空闲';
    case PreloadStatus.loading:
      if (loadedCount <= 0) return '加载中...';
      final normalizedEarliest = earliestRevision == null
          ? null
          : normalizeOptionalRevision(earliestRevision);
      if (normalizedEarliest == null) {
        return '加载中... (已 $loadedCount 条)';
      }
      return '加载中... (已 $loadedCount 条, 最早 r$normalizedEarliest)';
    case PreloadStatus.paused:
      return '已暂停';
    case PreloadStatus.completed:
      return describePreloadStopReason(
        stopReason,
        loadedCount: loadedCount,
        branchPoint: branchPoint,
        errorMessage: errorMessage,
      );
    case PreloadStatus.error:
      return formatPreloadErrorMessage(errorMessage);
  }
}

/// 把 `int` 形式的 revision 归一化成 `int?`：`<= 0` 视为"未知/未启用"。
///
/// **消除 preload_service.dart 内 3 处一致语义**：
/// - `evaluatePreloadStopReason` 内部 `earliestRevision > 0 && earliestRevision <= ...`
///   两段守卫（revisionLimit / branchPoint 分支）—— 调用方传入的 `earliestRevision`
///   依然是原始 int（保持两条件 `&&` 紧凑），但**调用方**侧 line 355 / line 420
///   两处 `earliestRevision > 0 ? earliestRevision : null` 现在统一委托。
/// - `LogCacheService.getEarliestRevisionInLatestRange` 返回 0 表示"未缓存任何
///   条目"，与"已缓存但 revision 真的等于 0"在 SVN 实践中没有冲突（仓库 r0
///   是初始空 commit，永远不会作为日志条目返回）。本函数把这个"0 视作未知"
///   语义显式化为契约。
/// - **不修改入参**（int 是值类型）。
@visibleForTesting
int? normalizeOptionalRevision(int revision) {
  return revision > 0 ? revision : null;
}

/// 渲染预加载错误的统一面向用户文案：`"出错: <msg>"` 或 `"出错: 未知错误"`。
///
/// **消除文件内 2 处完全相同的字面表达式**：
/// - `describePreloadStopReason(error, ...)` (原 line 126)
/// - `describePreloadStatusDescription` 内 `status == error` 分支 (原 line 163)
///
/// 这两处必须保持文案一致——否则 `PreloadProgress.statusDescription` 在
/// `status==error` 与 `status==completed && stopReason==error` 两种代码路径
/// 下输出会悄悄不一致。原代码靠两处独立维护的 raw string 同步，本函数把
/// 同步责任落在单点。
@visibleForTesting
String formatPreloadErrorMessage(String? errorMessage) {
  return '出错: ${errorMessage ?? "未知错误"}';
}

/// 把预加载设置渲染成日志输出的多行列表（每行不含前导 `'  '` 的"步骤段"缩进，
/// 但**包含** `'    - '` 的子项缩进，与原 `startPreload` 内 5 行 `info(...)` 调用
/// 输出的字符串完全等价）。
///
/// **契约**：
/// - 返回 5 行字符串，顺序固定：stopOnBranchPoint / maxDays / maxCount /
///   stopRevision / stopDate。顺序由单测显式锁定。
/// - 数值类阈值（maxDays / maxCount / stopRevision）`> 0` 时显示"<值><单位>"，
///   否则显示`'无限制'`。负数与 0 同视作"无限制"，与 `computeDaysLimitDate` /
///   `evaluatePreloadStopReason` 的 `> 0` 守卫一致。
/// - `stopDate` 直接 `?? '无限制'`：原代码用的是 `?? "无限制"`，行为一致。
///   注意 `PreloadSettings.stopDate` 是 `String?`，本函数不做日期解析。
/// - **不**包含开头的 `'  设置:'` 标题行——那行没有动态值，由调用方决定是否输出。
/// - 不带前缀的"步骤"缩进（原 `startPreload` 的 `'    - '` 已包含在每行），
///   方便调用方直接 `for (line in lines) AppLogger.preload.info(line)`。
@visibleForTesting
List<String> formatPreloadSettingsDumpLines(PreloadSettings settings) {
  return [
    '    - 到达分支点停止: ${settings.stopOnBranchPoint}',
    '    - 天数限制: ${settings.maxDays > 0 ? "${settings.maxDays} 天" : "无限制"}',
    '    - 条数限制: ${settings.maxCount > 0 ? "${settings.maxCount} 条" : "无限制"}',
    '    - 版本限制: ${settings.stopRevision > 0 ? "r${settings.stopRevision}" : "无限制"}',
    '    - 日期限制: ${settings.stopDate ?? "无限制"}',
  ];
}

/// `startPreload` 入口的 3 行启动 dump（不含分隔符行——分隔符走
/// `appLogSeparator` 常量、由调用方独立打印；不含 `formatPreloadSettingsDumpLines`
/// 的设置项明细——那是另一个函数）。
///
/// **契约**：
/// - 3 行顺序固定：标题 / 源 URL / `'  设置:'` 子标题。
/// - 标题恒为 `'【预加载服务】开始后台预加载'` 且**不带前导缩进**（与
///   `formatRefreshLogEntriesHeaderLines` / `formatFindBranchPointHeaderLines`
///   等同构）；2 个数据行带 `'  '` 前缀。
/// - **不**对 `sourceUrl` 做 trim / 空串守卫——上层 `startPreload` 入参契约
///   要求非空，传入空串会得到 `'  源 URL: '` 这种字面输出，**这是好事**：
///   能在日志里直接暴露上游"传了空 URL"的异常调用。
@visibleForTesting
List<String> formatPreloadStartHeaderLines({required String sourceUrl}) {
  return [
    '【预加载服务】开始后台预加载',
    '  源 URL: $sourceUrl',
    '  设置:',
  ];
}

/// 渲染 `startPreload` 步骤 1（从 HEAD 同步）的结果行。
///
/// **契约**：
/// - `newDataCount > 0` → `'  从 HEAD 获取了 $newDataCount 条新数据'`
/// - `newDataCount <= 0` → `'  没有新数据'`
///
/// 与原 `if (newDataCount > 0) ... else ...` 完全等价；负数虽然在 `syncFromHead`
/// 的契约下不会出现，但仍归入"没有新数据"分支，避免 `'获取了 -3 条'` 这种
/// 异常文案外泄到 UI 日志。**单测显式锁定** `newDataCount = 0` 与 `< 0`
/// 都走"没有新数据"分支。
@visibleForTesting
String formatPreloadFromHeadResultLine(int newDataCount) {
  if (newDataCount > 0) {
    return '  从 HEAD 获取了 $newDataCount 条新数据';
  }
  return '  没有新数据';
}

/// 渲染"当前最新区间缓存状态"的 1~2 行 dump。
///
/// **契约**：
/// - 第 1 行恒输出 `'  当前最新区间缓存: $totalCount 条'`（即使 `totalCount == 0`
///   也输出，让"刚开始预加载、缓存还空"的状态在日志里可见）。
/// - `earliestRevision > 0` 时追加第 2 行 `'  最早版本: r$earliestRevision'`；
///   `<= 0` 时不追加第 2 行（与原 `if (earliestRevision > 0)` 守卫一致——
///   `LogCacheService.getEarliestRevisionInLatestRange` 返回 0 表示"未缓存"，
///   这种情况下打印 `'最早版本: r0'` 会误导）。
/// - 返回 `List<String>`：长度恒为 1 或 2，调用方直接 `for (line in lines) info(line)`
///   即可；**不做** "if (lines.isNotEmpty)" 守卫的诱因（lines 永远非空）。
/// - **单测显式锁定**：`earliestRevision == 0` → 仅 1 行；`earliestRevision == 1`
///   → 2 行（边界 +1）；`earliestRevision < 0` → 仅 1 行（防御性，原代码 `> 0`
///   守卫覆盖此路径）。
@visibleForTesting
List<String> formatPreloadCacheStatusLines({
  required int totalCount,
  required int earliestRevision,
}) {
  final lines = <String>['  当前最新区间缓存: $totalCount 条'];
  if (earliestRevision > 0) {
    lines.add('  最早版本: r$earliestRevision');
  }
  return lines;
}

/// 渲染预加载循环中"已加载 + 最早版本"的进度行。
///
/// **契约**：固定模板 `'  已加载: $loadedCount 条, 最早: r$earliestRevision'`，
/// 与原 `startPreload` 内 line 481 的 `info(...)` 输出**完全等价**——包括
/// "前导 2 空格 + 中文逗号 + 半角逗号"这种轻微不一致都保留（原文：`'  已加载: ',`
/// 后跟 `, 最早: r'`，本函数照搬）。
///
/// **不**对 `earliestRevision <= 0` 做防御性分支：
/// - 该函数的调用点（`startPreload` 主循环内）紧跟 `_cacheService.getEarliestRevisionInLatestRange`
///   的非空场景（`syncLogs(loadMore: true)` 刚返回 newCount > 0，缓存里至少有
///   一条数据，earliestRevision 必然 > 0）。
/// - 如果调用方在错误场景下传 0 或负数，进度行会显示 `'最早: r0'`，这是
///   **可接受的诊断输出**——比静默吞掉更利于排查。
/// - 单测覆盖 `earliestRevision = 1`（最小合法值）和 `0`（防御性路径）两条。
@visibleForTesting
String formatPreloadProgressLine({
  required int loadedCount,
  required int earliestRevision,
}) {
  return '  已加载: $loadedCount 条, 最早: r$earliestRevision';
}

/// 预加载状态
enum PreloadStatus {
  /// 空闲（未开始或已完成）
  idle,
  /// 正在加载
  loading,
  /// 已暂停
  paused,
  /// 已完成（到达停止条件）
  completed,
  /// 出错
  error,
}

/// 预加载停止原因
enum PreloadStopReason {
  /// 未停止
  none,
  /// 到达分支点
  branchPoint,
  /// 到达天数限制
  daysLimit,
  /// 到达条数限制
  countLimit,
  /// 到达指定版本
  revisionLimit,
  /// 到达指定日期
  dateLimit,
  /// 没有更多数据
  noMoreData,
  /// 用户手动停止
  userStopped,
  /// 发生错误
  error,
}

/// 评估预加载是否应当从 [LogSyncService.getCopyTailCache] 获取分支点。
///
/// 这是个纯决策守卫——**只有当 [stopOnBranchPoint] 启用 且 [workingDirectory]
/// 非 null** 时才需要去取分支点；任何一边不满足都直接返回 false，避免：
/// 1. **不必要的 I/O**：缓存查询本身轻，但当前位置在每轮预加载循环都会执行，
///    成本累积；
/// 2. **null deref 风险**：`getCopyTailCache(workingDirectory)` 的 `workingDirectory!`
///    在 caller 端会因为这个守卫前置而安全。
///
/// **为什么抽**：原 `_checkStopConditions` 内联三元
/// `(settings.stopOnBranchPoint && workingDirectory != null) ? cache : null`
/// 把"两 flag AND"埋在表达式里，未来有人加第三个 flag（如 `cacheReady`）会很
/// 容易写歪——抽出后单测显式锁 4 真值表，新增维度强制 review。
///
/// **入参约定**：
/// - [stopOnBranchPoint] 取自 `PreloadSettings.stopOnBranchPoint`，约定 caller 已
///   经从 settings 读出（不接 settings 本身——保持单一职责）；
/// - [workingDirectory] 任何非 null 字符串都视为可用，**不**额外做 isNotEmpty
///   判定——本助手只锁"两 flag AND"语义；caller 如果接收 UI 输入需要先 trim
///   再传。这与 [LogSyncService.getCopyTailCache] 内部已有的 isUsableWorkingDirectory
///   守卫互补：本谓词只防 null，真实"空字符串"由 getCopyTailCache 自己再过滤一次。
@visibleForTesting
bool shouldFetchBranchPoint({
  required bool stopOnBranchPoint,
  required String? workingDirectory,
}) {
  return stopOnBranchPoint && workingDirectory != null;
}

/// 评估在 `_checkStopConditions` 末尾是否应当把 [branchPoint] 写入 progress。
///
/// **核心契约**：只有当**停止原因恰好是 [PreloadStopReason.branchPoint]** 且
/// **[branchPoint] 已知（非 null）** 时才记录。
///
/// 9 个 [PreloadStopReason] 中只有 `branchPoint` 这一个走 true 路径——其他 8 个
/// （none / daysLimit / countLimit / revisionLimit / dateLimit / noMoreData /
/// userStopped / error）即使 caller 误传了非 null 的 branchPoint 值也**不**写入，
/// 避免"因 daysLimit 停止 但 progress.branchPoint 被同时写上"这种语义错配。
///
/// **为什么抽**：原 `_checkStopConditions` 内联条件
/// `if (reason == PreloadStopReason.branchPoint && branchPoint != null)`
/// 把"reason 必须 is branchPoint"和"branchPoint 必须非 null"两个条件埋成 AND；
/// 未来 [PreloadStopReason] 增态时（比如新增 `customLimit`），这条 AND 不会
/// 编译报错——本助手用 `.values.length == 9` 防漏配测试 + 9 个 reason 的反向
/// 断言锁定，新增态时强制 review。
///
/// **设计模式 #9**：本谓词与 [shouldFetchBranchPoint] 形似（都 2-flag AND
/// 返回 bool），但**前者是"是否应当 I/O 取数据"、后者是"是否应当写入 progress"**——
/// 两个语义完全不同，不能合并；caller 链式使用：先 `shouldFetchBranchPoint` 决定
/// 是否取，取到的 branchPoint 再喂给 [evaluatePreloadStopReason] 与
/// `shouldUpdateBranchPointInProgress` 判断是否写入。
@visibleForTesting
bool shouldUpdateBranchPointInProgress({
  required PreloadStopReason reason,
  required int? branchPoint,
}) {
  return reason == PreloadStopReason.branchPoint && branchPoint != null;
}

/// 预加载进度信息
class PreloadProgress {
  /// 当前状态
  final PreloadStatus status;
  
  /// 停止原因
  final PreloadStopReason stopReason;
  
  /// 已加载条数
  final int loadedCount;
  
  /// 最早加载的日期
  final DateTime? earliestDate;
  
  /// 最早加载的版本
  final int? earliestRevision;
  
  /// 分支点版本（如果已知）
  final int? branchPoint;
  
  /// 错误信息（如果有）
  final String? errorMessage;
  
  /// 当前加载的源 URL
  final String? sourceUrl;

  const PreloadProgress({
    this.status = PreloadStatus.idle,
    this.stopReason = PreloadStopReason.none,
    this.loadedCount = 0,
    this.earliestDate,
    this.earliestRevision,
    this.branchPoint,
    this.errorMessage,
    this.sourceUrl,
  });

  PreloadProgress copyWith({
    PreloadStatus? status,
    PreloadStopReason? stopReason,
    int? loadedCount,
    DateTime? earliestDate,
    int? earliestRevision,
    int? branchPoint,
    String? errorMessage,
    String? sourceUrl,
  }) {
    return PreloadProgress(
      status: status ?? this.status,
      stopReason: stopReason ?? this.stopReason,
      loadedCount: loadedCount ?? this.loadedCount,
      earliestDate: earliestDate ?? this.earliestDate,
      earliestRevision: earliestRevision ?? this.earliestRevision,
      branchPoint: branchPoint ?? this.branchPoint,
      errorMessage: errorMessage ?? this.errorMessage,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
  
  /// 获取状态描述
  String get statusDescription {
    return describePreloadStatusDescription(
      status: status,
      stopReason: stopReason,
      loadedCount: loadedCount,
      earliestRevision: earliestRevision,
      branchPoint: branchPoint,
      errorMessage: errorMessage,
    );
  }
}

/// 预加载服务
class PreloadService {
  /// 单例模式
  static final PreloadService _instance = PreloadService._internal();
  factory PreloadService() => _instance;
  PreloadService._internal();

  final LogSyncService _syncService = LogSyncService();
  final LogCacheService _cacheService = LogCacheService();
  
  /// 当前进度
  PreloadProgress _progress = const PreloadProgress();
  PreloadProgress get progress => _progress;
  
  /// 进度回调
  void Function(PreloadProgress)? onProgressChanged;
  
  /// 是否应该停止
  bool _shouldStop = false;
  
  /// 初始化
  Future<void> init() async {
    await _cacheService.init();
  }
  
  /// 开始后台预加载
  /// 
  /// [sourceUrl] 源 URL
  /// [settings] 预加载设置
  /// [workingDirectory] 目标工作副本（仅用于 stopOnCopy 分支点判断）
  /// [fetchLimit] 每次从 SVN 获取的条数
  Future<void> startPreload({
    required String sourceUrl,
    required PreloadSettings settings,
    String? workingDirectory,
    int fetchLimit = 200,
  }) async {
    if (_progress.status == PreloadStatus.loading) {
      AppLogger.preload.warn('预加载已在进行中，忽略重复请求');
      return;
    }
    
    _shouldStop = false;
    
    AppLogger.preload.info(appLogSeparator);
    for (final line in formatPreloadStartHeaderLines(sourceUrl: sourceUrl)) {
      AppLogger.preload.info(line);
    }
    for (final line in formatPreloadSettingsDumpLines(settings)) {
      AppLogger.preload.info(line);
    }
    
    _updateProgress(_progress.copyWith(
      status: PreloadStatus.loading,
      stopReason: PreloadStopReason.none,
      sourceUrl: sourceUrl,
    ));
    
    try {
      // 【重要】首先从 HEAD 同步新数据（使用新的 syncFromHead 方法）
      AppLogger.preload.info('  步骤1: 从 HEAD 同步新数据...');
      final newDataCount = await _syncService.syncFromHead(
        sourceUrl: sourceUrl,
        limit: fetchLimit,
      );
      AppLogger.preload.info(formatPreloadFromHeadResultLine(newDataCount));
      
      // 获取当前缓存状态（使用最新区间）
      final totalCount = await _cacheService.getLatestRangeEntryCount(sourceUrl);
      final earliestRevision = await _cacheService.getEarliestRevisionInLatestRange(sourceUrl);
      final earliestDate = await _cacheService.getEarliestDateInLatestRange(sourceUrl);
      
      _updateProgress(_progress.copyWith(
        loadedCount: totalCount,
        earliestRevision: normalizeOptionalRevision(earliestRevision),
        earliestDate: earliestDate,
      ));
      
      for (final line in formatPreloadCacheStatusLines(
        totalCount: totalCount,
        earliestRevision: earliestRevision,
      )) {
        AppLogger.preload.info(line);
      }
      
      // 步骤2: 继续加载更旧的数据
      AppLogger.preload.info('  步骤2: 继续加载更旧的数据...');
      
      // 计算停止条件
      final daysLimitDate = computeDaysLimitDate(
        now: DateTime.now(),
        maxDays: settings.maxDays,
      );
      final stopDate = settings.stopDateTime;
      
      // 循环加载直到满足停止条件
      while (!_shouldStop) {
        // 检查停止条件
        final stopReason = await _checkStopConditions(
          sourceUrl: sourceUrl,
          settings: settings,
          workingDirectory: workingDirectory,
          daysLimitDate: daysLimitDate,
          stopDate: stopDate,
        );
        
        if (stopReason != PreloadStopReason.none) {
          _updateProgress(_progress.copyWith(
            status: PreloadStatus.completed,
            stopReason: stopReason,
          ));
          AppLogger.preload.info('✓ 预加载完成: ${_progress.statusDescription}');
          break;
        }
        
        // 加载更多数据
        AppLogger.preload.info('  加载更多数据...');
        final newCount = await _syncService.syncLogs(
          sourceUrl: sourceUrl,
          limit: fetchLimit,
          stopOnCopy: settings.stopOnBranchPoint,
          targetWorkingDirectory: workingDirectory,
          loadMore: true,
        );
        
        if (newCount == 0) {
          _updateProgress(_progress.copyWith(
            status: PreloadStatus.completed,
            stopReason: PreloadStopReason.noMoreData,
          ));
          AppLogger.preload.info('✓ 预加载完成: 没有更多数据');
          break;
        }
        
        // 更新进度（使用最新区间的统计）
        final updatedCount = await _cacheService.getLatestRangeEntryCount(sourceUrl);
        final updatedEarliestRev = await _cacheService.getEarliestRevisionInLatestRange(sourceUrl);
        final updatedEarliestDate = await _cacheService.getEarliestDateInLatestRange(sourceUrl);
        
        _updateProgress(_progress.copyWith(
          loadedCount: updatedCount,
          earliestRevision: normalizeOptionalRevision(updatedEarliestRev),
          earliestDate: updatedEarliestDate,
        ));
        
        AppLogger.preload.info(formatPreloadProgressLine(
          loadedCount: updatedCount,
          earliestRevision: updatedEarliestRev,
        ));
        
        // 短暂延迟，避免过度占用资源
        // R120 等待协议档 3：节流型 sleep（throttle/yield，非信号等待）
        // 此 sleep 不在等待任何外部事件 —— 唯一作用是给主线程让出 CPU + 限速 I/O
        // （SVN 服务器 + 本地 sqlite 写入压力）。退出条件靠 `_shouldStop` / 数据耗尽
        // 信号决定（while 头与中段的两处 break），而不是这个 delay。**与档 2（polling
        // sleep）的区分锁**：档 2 sleep 是为了等到布尔条件变化；档 3 sleep 是即使没有
        // 任何状态变化也要降速 —— 删掉档 3 sleep 不会让循环卡死、只会让吞吐爆冲。
        // 100ms 选值原因：与 SVN 远程请求 RTT 同量级，不至于显著拖慢预加载。
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      if (_shouldStop && _progress.status == PreloadStatus.loading) {
        _updateProgress(_progress.copyWith(
          status: PreloadStatus.completed,
          stopReason: PreloadStopReason.userStopped,
        ));
        AppLogger.preload.info('✓ 预加载已停止（用户请求）');
      }
      
    } catch (e, stackTrace) {
      AppLogger.preload.error('预加载失败', e, stackTrace);
      _updateProgress(_progress.copyWith(
        status: PreloadStatus.error,
        stopReason: PreloadStopReason.error,
        errorMessage: e.toString(),
      ));
    }
    
    AppLogger.preload.info(appLogSeparator);
  }
  
  /// 检查停止条件
  Future<PreloadStopReason> _checkStopConditions({
    required String sourceUrl,
    required PreloadSettings settings,
    String? workingDirectory,
    DateTime? daysLimitDate,
    DateTime? stopDate,
  }) async {
    // 获取当前缓存状态（使用最新区间的统计）
    final totalCount = await _cacheService.getLatestRangeEntryCount(sourceUrl);
    final earliestRevision = await _cacheService.getEarliestRevisionInLatestRange(sourceUrl);
    final earliestDate = await _cacheService.getEarliestDateInLatestRange(sourceUrl);

    final branchPoint = shouldFetchBranchPoint(
      stopOnBranchPoint: settings.stopOnBranchPoint,
      workingDirectory: workingDirectory,
    )
        ? LogSyncService.getCopyTailCache(workingDirectory)
        : null;

    final reason = evaluatePreloadStopReason(
      totalCount: totalCount,
      earliestRevision: earliestRevision,
      earliestDate: earliestDate,
      settings: settings,
      daysLimitDate: daysLimitDate,
      stopDate: stopDate,
      branchPoint: branchPoint,
    );

    if (shouldUpdateBranchPointInProgress(
      reason: reason,
      branchPoint: branchPoint,
    )) {
      _updateProgress(_progress.copyWith(branchPoint: branchPoint));
    }
    return reason;
  }
  
  /// 停止预加载
  void stopPreload() {
    _shouldStop = true;
    AppLogger.preload.info('请求停止预加载...');
  }
  
  /// 加载全部到分支点
  /// 
  /// 忽略其他停止条件，直接加载到分支点
  Future<void> loadAllToBranchPoint({
    required String sourceUrl,
    String? workingDirectory,
    int fetchLimit = 200,
  }) async {
    await startPreload(
      sourceUrl: sourceUrl,
      settings: const PreloadSettings(
        enabled: true,
        stopOnBranchPoint: true,
        maxDays: 0,      // 不限制
        maxCount: 0,     // 不限制
        stopRevision: 0, // 不限制
        stopDate: null,  // 不限制
      ),
      workingDirectory: workingDirectory,
      fetchLimit: fetchLimit,
    );
  }
  
  /// 更新进度并通知
  void _updateProgress(PreloadProgress newProgress) {
    _progress = newProgress;
    onProgressChanged?.call(_progress);
  }
  
  /// 重置状态
  void reset() {
    _shouldStop = false;
    _progress = const PreloadProgress();
  }
}
