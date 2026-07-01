/// SVN 日志缓存服务
///
/// 负责管理 SVN 日志的本地缓存
/// - 使用 SQLite 数据库存储（支持百万级数据）
/// - 每个 sourceUrl 对应独立的数据库文件（真正的分库）
/// - 支持增量更新（从缓存最新版本到 HEAD）
/// - 提供高效的查询接口
/// - 支持所有平台（包括 Windows）
/// - 双向校验确保数据库不会用错

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;

import 'app_paths_service.dart';
import '../models/log_entry.dart';
import 'logger_service.dart';

/// 缓存的版本区间
///
/// 表示一段连续缓存的 SVN 日志版本范围
/// [startRevision] 是较大的版本号（新），[endRevision] 是较小的版本号（旧）
class CachedRange {
  final int id;
  final int startRevision; // 区间起点（较大值，新）
  final int endRevision; // 区间终点（较小值，旧）
  final DateTime createdAt;
  final DateTime updatedAt;

  CachedRange({
    required this.id,
    required this.startRevision,
    required this.endRevision,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 检查是否与另一个区间连续（首尾相同才算连续）
  ///
  /// 例如：[200, 100] 和 [100, 50] 是连续的，因为 100 == 100
  /// 但是：[200, 101] 和 [100, 50] 不是连续的，不能用 +1 判断
  bool isContinuousWith(CachedRange other) {
    return endRevision == other.startRevision ||
        other.endRevision == startRevision;
  }

  /// 合并两个连续的区间
  CachedRange mergeWith(CachedRange other) {
    if (!isContinuousWith(other)) {
      throw ArgumentError('区间不连续，无法合并');
    }
    final newStart = startRevision > other.startRevision
        ? startRevision
        : other.startRevision;
    final newEnd =
        endRevision < other.endRevision ? endRevision : other.endRevision;
    return CachedRange(
      id: id, // 保留当前区间的 id
      startRevision: newStart,
      endRevision: newEnd,
      createdAt:
          createdAt.isBefore(other.createdAt) ? createdAt : other.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// 区间包含的版本数量（注意：这是 revision 范围，不是实际记录数）
  int get revisionSpan => startRevision - endRevision + 1;

  @override
  String toString() => 'CachedRange[$startRevision, $endRevision]';
}

/// 缓存校验错误
class CacheValidationError {
  final String message;
  final String expectedUrl;
  final String actualUrl;
  final String dbPath;

  CacheValidationError({
    required this.message,
    required this.expectedUrl,
    required this.actualUrl,
    required this.dbPath,
  });

  @override
  String toString() => message;
}

/// 缓存校验错误回调类型
typedef CacheValidationErrorCallback = void Function(
    CacheValidationError error);

/// 合并相邻区间的纯决策结果。
///
/// - [toDelete]：被吞并、应当从 cached_ranges 表里删除的 row id 集合。
/// - [toUpdate]：(id → 新 end_revision) 的更新指令，对应保留下来的"吸收方"区间。
/// - [merged]：合并后的最终区间列表，按 start 降序，仅用来便于断言。
@visibleForTesting
class MergeAdjacentRangesPlan {
  final List<int> toDelete;
  final List<({int id, int newEnd})> toUpdate;
  final List<({int id, int start, int end})> merged;

  const MergeAdjacentRangesPlan({
    required this.toDelete,
    required this.toUpdate,
    required this.merged,
  });
}

/// 计算合并相邻连续区间后的更新/删除指令——纯函数版本。
///
/// 关键规则与 [_mergeAdjacentRanges] 保持一致：**只有首尾相同的区间才算连续**
/// （例如 [200, 100] 和 [100, 50] 合并为 [200, 50]），不能用 `+1` 推断。
///
/// 输入要求：[ranges] 必须按 `start` 降序排列；调用方负责排序。
/// 这与生产侧 `SELECT ... ORDER BY start_revision DESC` 的查询一致。
///
/// 算法与生产侧逐对扫描合并的语义对齐：从前往后扫，遇到 `current.end == next.start`
/// 就把 `next` 吸并进 `current`、把 next 标记为删除，并继续在原位重新检查（处理链式合并）。
///
/// 返回 [MergeAdjacentRangesPlan]：调用方按 toUpdate 改 end，再按 toDelete 删行即可；
/// merged 是合并后的最终视图，方便单测做整体断言。
@visibleForTesting
MergeAdjacentRangesPlan planMergeAdjacentRanges(
  List<({int id, int start, int end})> ranges,
) {
  if (ranges.length < 2) {
    return MergeAdjacentRangesPlan(
      toDelete: const [],
      toUpdate: const [],
      merged: List.of(ranges),
    );
  }

  // 拷贝一份避免污染调用方
  final working = List.of(ranges);
  final toDelete = <int>[];
  final updatedEnds = <int, int>{}; // id → 最新的 end

  for (int i = 0; i < working.length - 1; i++) {
    final current = working[i];
    final next = working[i + 1];

    // 关键判断：首尾相同才算连续
    if (current.end == next.start) {
      // 把 next 吸并进 current：保留 current.id 与 current.start，
      // 把 end 扩展到 next.end。
      working[i] = (id: current.id, start: current.start, end: next.end);
      updatedEnds[current.id] = next.end;
      toDelete.add(next.id);
      // **R123 removeAt arbitrary-index 二档判据**：`i + 1` 由谓词命中决定，
      // 不是头部 drain——属档 2（任意 index removal），故意保留 List 不改 Queue。
      // Queue 不暴露 `removeAt(int)`，本场景在结构上无法替换。
      working.removeAt(i + 1);
      i--; // 在原位重新检查，支持链式合并 [200,100]+[100,50]+[50,10] → [200,10]
    }
  }

  final toUpdate =
      updatedEnds.entries.map((e) => (id: e.key, newEnd: e.value)).toList();

  return MergeAdjacentRangesPlan(
    toDelete: toDelete,
    toUpdate: toUpdate,
    merged: working,
  );
}

/// [planRangeUpdateAfterInsert] 决策出的动作类型。
enum RangeUpdateAction {
  /// 没有任何区间，或本次数据与现有最新区间不连续——新开一段区间。
  createNewRange,

  /// 从 HEAD 拉到了已有最新区间的更新版本——把最新区间的 start 向上扩展。
  extendStart,

  /// 加载更多旧版本，且与已有最新区间首尾连续——把最新区间的 end 向下扩展。
  extendEnd,

  /// 数据已存在或没有可执行动作——什么都不做。
  noop,
}

/// 对一次插入计算「区间应该怎么动」的纯决策结果。
@visibleForTesting
class RangeUpdatePlan {
  final RangeUpdateAction action;

  /// 仅当 [action] 为 [RangeUpdateAction.createNewRange] 或
  /// [RangeUpdateAction.extendStart] 时有意义。
  final int? newStart;

  /// 仅当 [action] 为 [RangeUpdateAction.createNewRange] 或
  /// [RangeUpdateAction.extendEnd] 时有意义。
  final int? newEnd;

  /// 决策依据的简短描述，方便日志/断言。
  final String reason;

  const RangeUpdatePlan({
    required this.action,
    required this.reason,
    this.newStart,
    this.newEnd,
  });

  @override
  String toString() =>
      'RangeUpdatePlan($action, newStart=$newStart, newEnd=$newEnd, reason=$reason)';
}

/// 决定一批刚插入的日志应该如何更新 cached_ranges。
///
/// 约定与生产逻辑一致：
/// - 若没有任何区间（[latestRange] 为 null），直接新开 [latestRevision, earliestRevision]。
/// - [isFromHead] 为 true（从 HEAD 拉的新数据）：
///   - 若本次的 earliestRevision 与最新区间的 startRevision 首尾相等
///     （**首尾相同才算连续**，不能用 +1 推断）→ extendStart 到 latestRevision；
///   - 否则若本次 latestRevision 严格大于最新区间的 startRevision → 创建新区间；
///   - 否则视为数据已存在，noop。
/// - [isFromHead] 为 false（继续向旧版本加载更多）：
///   - 若本次 latestRevision 与最新区间的 endRevision 首尾相等
///     → extendEnd 到 earliestRevision；
///   - 否则虽然「理论上不应该发生」，但仍会新开一段区间作为兜底。
///
/// 注意：[RangeUpdateAction.extendStart] 与 [RangeUpdateAction.extendEnd] 只是
/// 给出意图，DB 层（`extendLatestRangeStart` / `extendLatestRangeEnd`）会再做
/// 一次 newStart > current.start / newEnd < current.end 的边界守卫，本函数不重复判断。
@visibleForTesting
RangeUpdatePlan planRangeUpdateAfterInsert({
  required CachedRange? latestRange,
  required int latestRevision,
  required int earliestRevision,
  required bool isFromHead,
}) {
  if (latestRange == null) {
    return RangeUpdatePlan(
      action: RangeUpdateAction.createNewRange,
      newStart: latestRevision,
      newEnd: earliestRevision,
      reason: '没有任何区间，新开一段',
    );
  }

  if (isFromHead) {
    if (earliestRevision == latestRange.startRevision) {
      return RangeUpdatePlan(
        action: RangeUpdateAction.extendStart,
        newStart: latestRevision,
        reason: 'fromHead 与最新区间首尾连续，扩展 start',
      );
    }
    if (latestRevision > latestRange.startRevision) {
      return RangeUpdatePlan(
        action: RangeUpdateAction.createNewRange,
        newStart: latestRevision,
        newEnd: earliestRevision,
        reason: 'fromHead 不连续但本次更新，开新区间',
      );
    }
    return const RangeUpdatePlan(
      action: RangeUpdateAction.noop,
      reason: 'fromHead 但本次数据已被现有最新区间覆盖',
    );
  }

  // loadMore（从已缓存最旧版本继续向旧版本拉）
  if (latestRevision == latestRange.endRevision) {
    return RangeUpdatePlan(
      action: RangeUpdateAction.extendEnd,
      newEnd: earliestRevision,
      reason: 'loadMore 与最新区间首尾连续，扩展 end',
    );
  }
  return RangeUpdatePlan(
    action: RangeUpdateAction.createNewRange,
    newStart: latestRevision,
    newEnd: earliestRevision,
    reason: 'loadMore 不连续（异常路径兜底），新开一段',
  );
}

/// [resolveSourceUrlHash] 的纯决策结果。
///
/// 包含最终选定的 [hash]（取 MD5(sourceUrl) 前 16 位，必要时加 `#N` 后缀重试），
/// 以及实际重试次数 [attempts]（首次命中即 0）。
@visibleForTesting
class SourceUrlHashResolution {
  final String hash;
  final int attempts;

  const SourceUrlHashResolution({required this.hash, required this.attempts});
}

/// 不依赖任何状态地、为 [sourceUrl] 决定最终 hash。
///
/// 用 MD5(sourceUrl) 前 16 位；若 [hashToUrlMap] 中已有同一 hash 但指向**不同** url，
/// 则按 `MD5(sourceUrl#1)` / `MD5(sourceUrl#2)` ... 重试，直到没有冲突或同 url 复用为止。
///
/// 行为细节：
/// - [hashToUrlMap] 中已有同一 hash → 同一 url：视为可复用，不冲突；
/// - 该函数 **只读** [hashToUrlMap]，不会修改它；写映射由调用方负责；
/// - 该函数本身没有终止保证之外的限制——理论上 MD5 前 16 位的空间为 16^16，
///   实际工程里冲突极小概率；保留与生产代码一致的行为，不在这里硬编码 max attempts。
@visibleForTesting
SourceUrlHashResolution resolveSourceUrlHash(
  String sourceUrl,
  Map<String, String> hashToUrlMap,
) {
  String hash = _md5Prefix16(sourceUrl);
  int attempts = 0;
  while (hashToUrlMap.containsKey(hash) && hashToUrlMap[hash] != sourceUrl) {
    attempts++;
    hash = _md5Prefix16('$sourceUrl#$attempts');
  }
  return SourceUrlHashResolution(hash: hash, attempts: attempts);
}

String _md5Prefix16(String input) {
  final bytes = utf8.encode(input);
  return md5.convert(bytes).toString().substring(0, 16);
}

/// 一批日志条目里 revision 的最大/最小值。
@visibleForTesting
class RevisionExtremes {
  final int latest;
  final int earliest;

  const RevisionExtremes({required this.latest, required this.earliest});

  @override
  bool operator ==(Object other) =>
      other is RevisionExtremes &&
      other.latest == latest &&
      other.earliest == earliest;

  @override
  int get hashCode => Object.hash(latest, earliest);

  @override
  String toString() => 'RevisionExtremes(latest=$latest, earliest=$earliest)';
}

/// 计算一批 [LogEntry] 的 (latest, earliest) revision。
///
/// **契约**：
/// - [entries] 必须非空——空列表会让 `reduce` 抛 `StateError`，与原 inline 的
///   `entries.map(...).reduce(...)` 表达式行为一致。这里**不**做防御性兜底
///   （比如返回 `(0, 0)`），因为 `insertEntries` 自身已经在更上游有非空守卫，
///   静默吞掉只会把上游 bug 推到下游难定位。
/// - 单元素时 latest == earliest（reduce 直接返回唯一元素）。
/// - 重复 revision 不会被去重——直接走 max/min，等价于 `entries.length` 不影响结果。
@visibleForTesting
RevisionExtremes revisionExtremesOf(List<LogEntry> entries) {
  final revs = entries.map((e) => e.revision);
  final latest = revs.reduce((a, b) => a > b ? a : b);
  final earliest = revs.reduce((a, b) => a < b ? a : b);
  return RevisionExtremes(latest: latest, earliest: earliest);
}

/// 把"本次插入算出的 (latest, earliest)" 与"DB 中已有 metadata 的 (currentLatest,
/// currentEarliest)" 合并成最终要写入 metadata 的 (latest, earliest)。
///
/// **契约**：
/// - 总取 `max(currentLatest, incomingLatest)`、`min(currentEarliest, incomingEarliest)`，
///   即元数据始终向"更宽的范围"扩张，**永远不会缩小**——这是为了让多次 partial
///   load 累积出完整覆盖区间。
/// - `currentLatest == null`（首次插入，metadata 还没行）→ 直接用 incoming 值。
/// - `currentEarliest == null` 但 currentLatest 非空（罕见，metadata 半残）→
///   incoming earliest 直接生效，不与 null 比较。
/// - 入参语义：`latestRevision` 比 `earliestRevision` 大（[earliest, latest] 是
///   闭区间）；本函数**不**校验，调用方负责。
@visibleForTesting
({int latest, int earliest}) mergeMetadataExtremes({
  required int? currentLatest,
  required int? currentEarliest,
  required int incomingLatest,
  required int incomingEarliest,
}) {
  if (currentLatest == null) {
    return (latest: incomingLatest, earliest: incomingEarliest);
  }
  final newLatest =
      currentLatest > incomingLatest ? currentLatest : incomingLatest;
  final newEarliest =
      (currentEarliest != null && currentEarliest < incomingEarliest)
          ? currentEarliest
          : incomingEarliest;
  return (latest: newLatest, earliest: newEarliest);
}

/// `insertEntries` 入口的 3 行启动 dump。
///
/// **契约**：
/// - 第 1 行：`'【insertEntries】插入 N 条日志'`，**不带缩进**（段标题）。
/// - 第 2 行：`'  范围: [latest, earliest]'`，两空格缩进；这里仍然以 `[latest, earliest]`
///   形式写出（latest 在前，与 SQL 查询和现有日志格式一致），不要"修复"成升序。
/// - 第 3 行：`'  isFromHead: true|false'`，两空格缩进。
/// - 不区分 entriesCount=0 / 1 / N；调用方保证非空。
@visibleForTesting
List<String> formatInsertEntriesHeaderLines({
  required int entriesCount,
  required int latestRevision,
  required int earliestRevision,
  required bool isFromHead,
}) {
  return [
    '【insertEntries】插入 $entriesCount 条日志',
    '  范围: [$latestRevision, $earliestRevision]',
    '  isFromHead: $isFromHead',
  ];
}

/// `_updateRangesAfterInsert` 入口的 4 行启动 dump（标题 + 3 行数据 +
/// 不含决策结果那行——决策结果由调用方在 `planRangeUpdateAfterInsert` 之后单独
/// 打）。
///
/// **契约**：
/// - 第 1 行：`'【区间更新】开始'`，**不带缩进**（段标题）。
/// - 第 2 行：`'  本次插入范围: [latest, earliest]'`，两空格缩进。
/// - 第 3 行：`'  isFromHead: true|false'`，两空格缩进。
/// - 第 4 行：`'  当前最新区间: <latestRange.toString() 或 "无">'`，两空格缩进。
///   `latestRange == null` → `'无'`（与原 `?? "无"` 一致）；非空走 `toString()`，
///   **不**做 `isEmpty` / 字段拆开等额外格式化。
@visibleForTesting
List<String> formatRangeUpdateHeaderLines({
  required int latestRevision,
  required int earliestRevision,
  required bool isFromHead,
  required CachedRange? latestRange,
}) {
  return [
    '【区间更新】开始',
    '  本次插入范围: [$latestRevision, $earliestRevision]',
    '  isFromHead: $isFromHead',
    '  当前最新区间: ${latestRange ?? "无"}',
  ];
}

/// 是否应当用 [newEndRevision] 扩展 [latestRange] 的 endRevision。
///
/// **契约**：
/// - `latestRange == null` → `false`（**没有区间可扩展**，DB 层会另外打 warn 日志）。
/// - 否则当且仅当 `newEndRevision < latestRange.endRevision` → `true`
///   （endRevision 是较小的 revision，"扩展终点向旧版本走"——只有更小才有效）。
/// - `newEndRevision == latestRange.endRevision` → `false`（**等值不算扩展**，
///   一个写入对生产 DB 是 noop，提前返回少一次 SQL UPDATE）。
///
/// 与 [planRangeUpdateAfterInsert] 的关系：plan 函数只决定"意图"，**不再重复**
/// 这条边界判断；本守卫由 DB 层（`extendLatestRangeEnd`）持有，本函数把它从
/// inline if 提到顶层方便单测。
@visibleForTesting
bool shouldExtendLatestRangeEnd({
  required CachedRange? latestRange,
  required int newEndRevision,
}) {
  if (latestRange == null) return false;
  return newEndRevision < latestRange.endRevision;
}

/// 是否应当用 [newStartRevision] 扩展 [latestRange] 的 startRevision。
///
/// **契约**（与 [shouldExtendLatestRangeEnd] 镜像对称，但比较方向相反）：
/// - `latestRange == null` → `false`（没有区间可扩展）。
/// - 否则当且仅当 `newStartRevision > latestRange.startRevision` → `true`
///   （startRevision 是较大的 revision，"扩展起点向新版本走"——只有更大才有效）。
/// - `newStartRevision == latestRange.startRevision` → `false`（等值不算扩展）。
///
/// **注意 end 与 start 比较方向相反**：cached_ranges 用 `[start, end]` 表示
/// `[较新 revision, 较旧 revision]`（start 大、end 小），向旧版本扩展 = end 变小、
/// 向新版本扩展 = start 变大。这是项目里"区间用降序表示"约定的延续，单测显式锁定
/// 两个方向（end 用 `<`、start 用 `>`），防止有人误把方向写反。
@visibleForTesting
bool shouldExtendLatestRangeStart({
  required CachedRange? latestRange,
  required int newStartRevision,
}) {
  if (latestRange == null) return false;
  return newStartRevision > latestRange.startRevision;
}

/// `log_entries` 表过滤查询的 author 字段匹配模式。
///
/// **背景 — 发散事实**：本服务在 4 处 SQL 构建调用站对 `author` 字段使用了
/// **不一致的匹配规则**——
/// - `getEntries` / `getEntriesInLatestRange`（**取列表**）：`author = ?`
///   完全匹配 + 入参 `authorFilter.trim()`；
/// - `getEntryCount` / `getEntryCountInLatestRange`（**取计数**）：
///   `LOWER(author) LIKE '%...%'` 大小写无关子串 + 入参 `authorFilter.toLowerCase()`。
///
/// 即对同一 `authorFilter='Alice'`，"列表"与"计数"返回的逻辑集合**理论上不同**：
/// 用户输入 `'al'` 时，列表为空（无人 author 恰好等于 `'al'`）但计数会算上所有
/// 名字含 `'al'` 的条目（含 `'Alice'` / `'Albert'`）；UI 上分页器显示的总条数会
/// 与翻页后实际看到的数据不一致。**这是 pre-existing 行为差异**，根因在
/// `getEntries` 引入 `=` 时早于 `getEntryCount` 引入 `LIKE`，未同步对齐。
///
/// **本轮不修复**——是否统一是产品决策（"列表 = 精确，计数 = 模糊"vs"两者都模糊"
/// vs"两者都精确"），不应在 refactor 顺手改。本 enum 把这条**隐藏在 inline 代码
/// 里的发散显式化**，让任何调整都必须改 enum 或调用站参数，而不是修改
/// `if (authorFilter != null && ...)` 内部的细节。
enum AuthorMatchMode {
  /// `author = ?` 精确匹配 + 入参 trim。
  exact,

  /// `LOWER(author) LIKE '%?%'` 大小写无关子串匹配 + 入参 toLowerCase。
  likeLowercase,
}

/// 构造 `log_entries` 表 WHERE 子句的纯决策结果。
///
/// - [whereClauses]：按调用方传入维度顺序生成的 SQL 片段列表，
///   交给调用方走 `' AND '.join(...)`；空列表表示"没有过滤条件"，调用方此时
///   **不应**输出 `'WHERE'` 关键字（与现有 4 个调用站一致）。
/// - [args]：与 `?` 占位符顺序一一对应的参数列表。
@visibleForTesting
class LogEntryFilterClauses {
  final List<String> whereClauses;
  final List<Object> args;

  const LogEntryFilterClauses({
    required this.whereClauses,
    required this.args,
  });
}

/// 判断字符串过滤维度（author / title）是否「值得拼到 SQL WHERE 子句」。
///
/// **核心契约**：仅当 [filter] 非 null **且** 非空字符串时返回 true。
///
/// **为什么这个谓词单独抽**：原 `buildLogEntryFilterClauses` 在 author 与
/// title 两处各内联了一句 `filter != null && filter.isNotEmpty`——两处共享
/// 同一份"空串视作未启用过滤"决策。任何一处把 `&&` 误改成 `||`、或漏掉
/// `isNotEmpty`，都会让"`titleFilter=''` 也被拼成 `LOWER(title) LIKE '%%'`"
/// 进入 SQL——SQLite 收到 `LIKE '%%'` 会**全表扫描后全部命中**，违背 UI
/// 上"清空搜索框 = 关闭过滤"的语义；更糟的是会让分页计数与列表条数对不上
/// （因为 `%%` 匹配的是非 NULL title 行而非全部行，与不带 WHERE 的全集差一个
/// "title IS NULL" 的子集）。
///
/// **为什么不复用 [isUsableSvnCredential] / [isUsableSourceUrl] /
/// [isUsableWorkingDirectory]**：四者签名同形（`String? -> bool`），实现也
/// 完全相同（`!= null && isNotEmpty`），但**语境完全不同**——
/// - [isUsableSvnCredential]（svn_service.dart）：是否值得加到 svn CLI args
///   的 `--username/--password`；
/// - [isUsableSourceUrl]（app_state.dart）：是否值得调 `refreshLogEntries`；
/// - [isUsableWorkingDirectory]（log_filter_service.dart）：是否值得用作 SVN
///   缓存键；
/// - 本谓词：是否值得拼到 SQL WHERE 的字符串过滤段。
///
/// 跨模块复用一个 `isUsableNonEmptyString` 通名 helper 会让 callsite 失去
/// 语义自描述能力（"这次到底防的是哪种空？"），按设计模式 #9 拒绝合并。
/// 单测通过四谓词等价性反向断言矩阵显式锁定"实现等价但不能合并"。
///
/// **故意不做 trim**：保持与 line 542-543 文档契约一致——"调用方负责 UI 层
/// 去白"。author exact 匹配在 caller 内部用 `authorFilter.trim()` 喂参数，
/// 但**判定**是否启用过滤仍然只看原值，这是为了让"用户输入 ` ` 单空格"
/// 与"用户输入 `'a'` 后又删成空"两种 UI 状态在判定层走相同路径（前者 true、
/// 后者 false），单一可预测。
@visibleForTesting
bool isUsableSqlStringFilter(String? filter) =>
    filter != null && filter.isNotEmpty;

/// 判断 [minRevision] 是否「值得拼到 SQL WHERE 的 `revision >= ?` 段」。
///
/// **核心契约**：仅当 [minRevision] 非 null **且** > 0 时返回 true。
/// **`> 0` 不是 `>= 0`**——SVN revision 从 1 起步，0 是仓库虚拟空版本（与
/// `isHeadRevisionValid` 的 r0 边界判定完全一致），从来没有任何 commit 的
/// `revision == 0`，所以 r0 在过滤语义上等价于"未启用过滤"。
///
/// **为什么这个谓词单独抽**：原 `buildLogEntryFilterClauses` (line 610)
/// 与 `getMinRevisionFromCache` (line 1172) 各内联了一句
/// `minRevision != null && minRevision > 0`——两处共享同一份"r0 视作哨兵"
/// 决策。任何一处把 `> 0` 误改成 `>= 0`、或把 `&&` 误改成 `||`，都会让
/// `WHERE revision >= 0` 进入 SQL——表面上"逻辑通顺"，实际上和"不带 WHERE
/// 的全集"完全等价（因为没有 r0 的行），但**SQL 文本变了**，会让回归 diff
/// 出现在不该出现的地方，且让 SQLite 多算一次 b-tree 遍历。
///
/// **为什么不直接复用 [isHeadRevisionValid]**（log_sync_service.dart）：
/// 两者签名同形（`int? -> bool`），实现也完全相同（`!= null && r > 0`），
/// 但**语境完全不同**——
/// - [isHeadRevisionValid]（log_sync_service.dart）：是否值得作为同步起点
///   （HEAD revision 必须存在才能从 HEAD 往回拉日志）；
/// - 本谓词：是否值得作为过滤下界（minRevision 是 UI 上"只看大于等于此版本
///   的日志"的下限值，r0 等价于不过滤）。
///
/// 两者是项目内**第一次**出现的同形 `int? -> bool` 谓词配对，启动两谓词矩阵。
/// 与四谓词 `String? -> bool` 矩阵（Round 79-81）完全平行：实现等价但
/// callsite 语义自描述能力不同，强行合并为 `isUsablePositiveInt` 通名会
/// 让 review 时多读一次注释。按设计模式 #9 拒绝合并。
///
/// **故意不做上限校验**：与 `isHeadRevisionValid` 一致——`int` 范围内任何
/// 正数都是合法 revision。未来 SVN 即使引入 `r-1` / `r-2` 等魔术值，应该
/// 在 caller 层处理，本谓词只锁"非正整数即无效"。
@visibleForTesting
bool isUsableMinRevision(int? minRevision) =>
    minRevision != null && minRevision > 0;

/// 把 `(minRevision, authorFilter, titleFilter, authorMode)` 4 个过滤维度
/// 翻译成 SQL WHERE 子句片段 + 参数列表。
///
/// **契约（与原 inline 4 处实现严格等价）**：
/// 1. **维度顺序固定** — `minRevision` → `author` → `title`；4 个调用站都是这个
///    顺序，单测显式锁定；调换顺序不会改变查询结果但会让 SQL 文本变化，从而让
///    回归 diff 出现在不该出现的地方。
/// 2. **入参守卫** — 各维度只在"非 null 且有效"时追加：
///    - `minRevision` 走 [isUsableMinRevision]（**`> 0` 不是 `>= 0`**——SVN
///      revision 1 起步，0 视作"未启用"哨兵，与现有所有 caller 一致）；
///    - `authorFilter` 走 [isUsableSqlStringFilter]（**不做 trim 后判空**
///      ——保持与原 inline 一致，调用方负责 UI 层去白）；
///    - `titleFilter` 同样走 [isUsableSqlStringFilter]。
/// 3. **author 走 [authorMode] 切换**（**核心契约**）：
///    - `AuthorMatchMode.exact` → SQL 片段 `'author = ?'` + arg `authorFilter.trim()`；
///    - `AuthorMatchMode.likeLowercase` → SQL 片段 `'LOWER(author) LIKE ?'` +
///      arg `'%${authorFilter.toLowerCase()}%'`（**不做 trim**——保持原行为；
///      `toLowerCase()` 已经规范化，trim 与否对子串匹配影响小）。
/// 4. **title 永远走 LIKE（无 mode 切换）** —— SQL 片段 `'LOWER(title) LIKE ?'` +
///    arg `'%${titleFilter.toLowerCase()}%'`。这是**故意保留 title 不参数化的**：
///    UI 上 title 一直是模糊匹配（用户搜"修复"想看到"修复登录bug"），从来没有
///    "精确匹配"的需求；不引入 TitleMatchMode 是为了**让 title 维度永远是单点决策**，
///    将来如果 title 也出现发散时再添加。
/// 5. **message 全文搜索（第 4 维）** —— 与 title 同口径：SQL 片段
///    `'LOWER(message) LIKE ?'` + arg `'%${messageFilter.toLowerCase()}%'`，**不做 trim**。
///    维度顺序锁定为 `minRevision` → `author` → `title` → `message`——message 排在最后
///    是因为它是 commit body 全文，column 长度通常远大于 title，放在 args 末尾不影响
///    其它维度的回归 diff 形态。
/// 6. **不返回 ORDER BY / LIMIT** —— 这两个由调用方根据"列表 vs 计数 vs 单值聚合"
///    自己决定；本函数只负责 WHERE，单一职责。
/// 7. **空守卫返回不变量** —— 全部维度都被守卫过滤掉时返回 `LogEntryFilterClauses(
///    whereClauses: [], args: [])`，调用方据此跳过 `WHERE` 关键字。
///
/// **不**支持的能力（故意省略）：
/// - 多个 author / title / message 的 OR 组合 — 当前 UI 只支持单值；
/// - 日期范围过滤 — 通过 `minRevision` 与 `latestRange.endRevision` / `startRevision`
///   的 `revision <=` 守卫间接表达，调用方在外层先 push 这些条件再调本函数。
@visibleForTesting
LogEntryFilterClauses buildLogEntryFilterClauses({
  required int? minRevision,
  required String? authorFilter,
  required String? titleFilter,
  required String? messageFilter,
  required AuthorMatchMode authorMode,
}) {
  final whereClauses = <String>[];
  final args = <Object>[];

  if (isUsableMinRevision(minRevision)) {
    whereClauses.add('revision >= ?');
    args.add(minRevision!);
  }

  if (isUsableSqlStringFilter(authorFilter)) {
    switch (authorMode) {
      case AuthorMatchMode.exact:
        whereClauses.add('author = ?');
        args.add(authorFilter!.trim());
        break;
      case AuthorMatchMode.likeLowercase:
        whereClauses.add('LOWER(author) LIKE ?');
        args.add('%${authorFilter!.toLowerCase()}%');
        break;
    }
  }

  if (isUsableSqlStringFilter(titleFilter)) {
    whereClauses.add('LOWER(title) LIKE ?');
    args.add('%${titleFilter!.toLowerCase()}%');
  }

  if (isUsableSqlStringFilter(messageFilter)) {
    whereClauses.add('LOWER(message) LIKE ?');
    args.add('%${messageFilter!.toLowerCase()}%');
  }

  return LogEntryFilterClauses(whereClauses: whereClauses, args: args);
}

/// `log_entries` 查询拼装的纯决策结果。
///
/// - [sql]：完整 SQL 字符串（含可选的 `WHERE` / `ORDER BY` / `LIMIT/OFFSET`）。
/// - [args]：与 SQL 中 `?` 占位符顺序一一对应的参数列表。
///
/// 调用方拿到这两个字段后直接 `db.select(plan.sql, plan.args)` 即可。
/// **不**包含 SELECT 的列名解析、行映射——这两件事由调用方根据"列表 vs 计数"
/// 自己处理（COUNT(*) 只取首列、SELECT 列要 map 成 LogEntry）。
@visibleForTesting
class LogEntriesQueryPlan {
  final String sql;
  final List<Object> args;

  const LogEntriesQueryPlan({
    required this.sql,
    required this.args,
  });
}

/// 把 4 处 `getEntries / getEntryCount / getEntriesInLatestRange /
/// getEntryCountInLatestRange` 的 inline SQL 拼装统一为单一函数。
///
/// **为什么抽**：原 4 个 callsite 各自重复了"WHERE 拼装 + (可选) 范围谓词 +
/// (可选) ORDER BY DESC + (可选) LIMIT/OFFSET"模式。任何一个模式细节走样
/// （比如有人把 `ORDER BY` 写成 `ASC`、把 `LIMIT/OFFSET` 顺序调过来、把
/// rangeBounds 的 `>=`/`<=` 写反），都需要在 4 处分别 review。抽出后
/// 单点决策、4 个 callsite 共享，回归测试只锁一处。
///
/// **契约（与原 4 处 inline 实现严格等价）**：
/// 1. **SQL 拼装顺序固定** —
///    `SELECT $selectColumns FROM log_entries`
///    → `[ WHERE $whereConditions ]`（仅当至少有一个条件时；空则省略 `WHERE`
///       关键字本身——和 `getEntries` 的 inline 行为一致）
///    → `[ ORDER BY revision DESC ]`（仅当 `orderByRevisionDesc=true`）
///    → `[ LIMIT ? OFFSET ? ]`（仅当 `limitOffset != null`）
/// 2. **WHERE 条件顺序锁定**（args 必须与之严格对齐）：
///    - 先 `rangeBounds`（如有）：`revision >= ?`（取 `endRevision`）+
///      `revision <= ?`（取 `startRevision`）。**注意**：`endRevision` 是较小值、
///      `startRevision` 是较大值——这是 `CachedRange` 的命名约定（见 line 23-77），
///      与日常直觉相反；本 helper **直接搬用** caller 已验证的 inline 顺序，不修语义。
///    - 然后 `filterClauses.whereClauses`（按 [buildLogEntryFilterClauses] 的内部维度顺序）。
/// 3. **args 顺序与占位符一一对齐**（关键不变量）：
///    `[rangeBounds.endRevision, rangeBounds.startRevision, ...filterClauses.args, limit, offset]`
///    任何乱序都会让 SQLite 在运行时把 limit 当 revision 比、把 author 当 title 比，
///    本助手用单测显式锁全顺序。
/// 4. **空 WHERE 不写 `WHERE` 关键字** — 当 `rangeBounds == null` 且
///    `filterClauses.whereClauses.isEmpty` 时，SQL 直接接 ORDER BY / LIMIT / 结束，
///    与原 `getEntries` 的 `clauses.whereClauses.isNotEmpty` 守卫等价。
/// 5. **`limitOffset == null` 时不附 LIMIT/OFFSET** — 任何 COUNT 查询都走这条路径
///    （COUNT 不分页，没意义）；`getEntries` / `getEntriesInLatestRange` 的 caller
///    在 `limit==null` 时也走这条路径。
/// 6. **`orderByRevisionDesc=false` 时不附 ORDER BY** — 原 `getEntryCount` /
///    `getEntryCountInLatestRange` 都没有 ORDER BY（COUNT 不需要排序）；本 helper
///    把这一点提到参数层显式表达，而不是由 selectColumns 内容反推。
///
/// **形似但语义不同（设计模式 #9）**：本函数 **不** 与 [buildLogEntryFilterClauses]
/// 合并——前者只管"过滤维度 → SQL 片段"；后者管"完整查询拼装"。两个函数都拼 SQL
/// 字符串，但**层级不同**（filter clauses 是更内层的产物），合并会让本函数同时接
/// 4 个原始过滤参数 + 拼装参数共 8+ 个，签名臃肿且违反单一职责。
///
/// **入参约定**：
/// - [selectColumns]：调用方**自己**给出列名字符串，如 `'revision, author, date,
///   title, message'` 或 `'COUNT(*)'`。本 helper 不维护列名白名单——保持透明。
/// - [rangeBounds]：可选，使用 record 而非两个独立可空参数，避免"传了 endRevision
///   忘传 startRevision"的半截状态；要有就一起有。
/// - [limitOffset]：同样用 record——`limit==null` 时 offset 也不应写入 SQL；用
///   record 把"两个一起 / 都没有"的二态关系编码进类型层。
@visibleForTesting
LogEntriesQueryPlan buildLogEntriesQuery({
  required String selectColumns,
  ({int endRevision, int startRevision})? rangeBounds,
  required LogEntryFilterClauses filterClauses,
  required bool orderByRevisionDesc,
  ({int limit, int offset})? limitOffset,
}) {
  final whereConditions = <String>[];
  final args = <Object>[];

  if (rangeBounds != null) {
    whereConditions.add('revision >= ?');
    whereConditions.add('revision <= ?');
    args.add(rangeBounds.endRevision);
    args.add(rangeBounds.startRevision);
  }

  whereConditions.addAll(filterClauses.whereClauses);
  args.addAll(filterClauses.args);

  var sql = 'SELECT $selectColumns FROM log_entries';

  if (whereConditions.isNotEmpty) {
    sql += ' WHERE ${whereConditions.join(' AND ')}';
  }

  if (orderByRevisionDesc) {
    sql += ' ORDER BY revision DESC';
  }

  if (limitOffset != null) {
    sql += ' LIMIT ? OFFSET ?';
    args.add(limitOffset.limit);
    args.add(limitOffset.offset);
  }

  return LogEntriesQueryPlan(sql: sql, args: args);
}

class LogCacheService {
  /// 单例模式
  static final LogCacheService _instance = LogCacheService._internal();
  factory LogCacheService() => _instance;
  LogCacheService._internal();

  /// 数据库缓存目录
  String? _cacheDir;

  final AppPathsService _paths = AppPathsService();

  /// 当前打开的数据库（按 sourceUrl hash 索引）
  final Map<String, Database> _databases = {};

  /// URL 到 hash 的映射（持久化存储）
  final Map<String, String> _urlToHashMap = {};

  /// hash 到 URL 的映射（用于反向查找）
  final Map<String, String> _hashToUrlMap = {};

  /// SharedPreferences 实例
  SharedPreferences? _prefs;

  /// 数据库版本
  static const int _dbVersion = 4;

  /// 映射存储的 key
  static const String _urlHashMapKey = 'log_cache_url_hash_map';

  /// 缓存校验错误回调
  CacheValidationErrorCallback? onValidationError;

  /// 初始化服务
  ///
  /// R126 启动序列约束（4-step 顺序锁，对偶 R125 close 释放方向 handle→memory→file→log）：
  /// step 1（path）：`_cacheDir = await _paths.getCacheDir()` —— 必须最先；后续步骤
  ///   都隐式依赖 _cacheDir 已就绪（_prefs 加载映射后用户调 getOrCreateHash 会用到）。
  /// step 2（handle）：`_prefs = await SharedPreferences.getInstance()` —— 必须先于
  ///   step 3 的 _loadUrlHashMap（后者从 _prefs 读 JSON）。`_prefs?.getString(...)`
  ///   的 `?.` 在 _prefs 还是 null 时短路返回 null —— 不会抛、但 mapping 全丢。
  /// step 3（memory）：`await _loadUrlHashMap()` —— 把磁盘 JSON 加载到内存 _urlToHashMap
  ///   / _hashToUrlMap 双结构。**必须先于** step 4 的 log（日志反映系统状态而非意图，
  ///   此原则与 R125 close 步骤 3 → 步骤 4 同形）。
  /// step 4（log）：`AppLogger.storage.info('...初始化成功: $_cacheDir')` —— 表达
  ///   "服务已就绪可用"的对外契约。错误路径有 catch + rethrow（不吞）—— rethrow 让
  ///   caller (main_screen_v3._initServices) 的 catchError 接住记日志后让后续 init
  ///   不被阻塞（R119 档 3）。
  ///
  /// **R126 启动方向单调原则**：path → handle → memory → log。R125 的 release 方向
  /// 是 handle → memory → file → log（依赖性强 → 持久性强），R126 是其逆——init 必
  /// 须按"资源构造依赖链"正向走（先有 path 才能打开 handle、先有 handle 才能 populate
  /// memory）；reverse 任意一对会让前序状态尚未就绪时被消费，触发 NPE 或静默丢数据。
  Future<void> init() async {
    try {
      if (_cacheDir != null && _prefs != null) {
        return;
      }
      _cacheDir = await _paths.getCacheDir();

      // 加载 URL 到 hash 的映射
      _prefs = await SharedPreferences.getInstance();
      await _loadUrlHashMap();

      AppLogger.storage.info('日志缓存服务初始化成功: $_cacheDir');
    } catch (e, stackTrace) {
      AppLogger.storage.error('日志缓存服务初始化失败', e, stackTrace);
      rethrow;
    }
  }

  /// 加载 URL 到 hash 的映射
  Future<void> _loadUrlHashMap() async {
    try {
      final json = _prefs?.getString(_urlHashMapKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _urlToHashMap.clear();
        _hashToUrlMap.clear();
        for (final entry in map.entries) {
          _urlToHashMap[entry.key] = entry.value as String;
          _hashToUrlMap[entry.value as String] = entry.key;
        }
        AppLogger.storage.info('已加载 ${_urlToHashMap.length} 个 URL-hash 映射');
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('加载 URL-hash 映射失败', e, stackTrace);
    }
  }

  /// 保存 URL 到 hash 的映射
  Future<void> _saveUrlHashMap() async {
    try {
      final json = jsonEncode(_urlToHashMap);
      await _prefs?.setString(_urlHashMapKey, json);
    } catch (e, stackTrace) {
      AppLogger.storage.error('保存 URL-hash 映射失败', e, stackTrace);
    }
  }

  /// 获取或创建 sourceUrl 对应的 hash
  Future<String> _getOrCreateHash(String sourceUrl) async {
    // 先检查是否已有映射
    if (_urlToHashMap.containsKey(sourceUrl)) {
      return _urlToHashMap[sourceUrl]!;
    }

    // 纯函数算 hash + 处理冲突重试
    final resolution = resolveSourceUrlHash(sourceUrl, _hashToUrlMap);
    final hash = resolution.hash;
    if (resolution.attempts > 0) {
      AppLogger.storage
          .warn('检测到 hash 冲突，重试 ${resolution.attempts} 次: $sourceUrl');
    }

    // 保存映射
    _urlToHashMap[sourceUrl] = hash;
    _hashToUrlMap[hash] = sourceUrl;
    await _saveUrlHashMap();

    AppLogger.storage.info('创建新的 URL-hash 映射: $sourceUrl -> $hash');
    return hash;
  }

  /// 获取数据库文件路径
  String _getDbPath(String hash) {
    return path.join(_cacheDir!, 'cache_$hash.db');
  }

  /// 获取或打开指定 sourceUrl 的数据库
  Future<Database> _getDatabase(String sourceUrl) async {
    await _ensureInit();

    final hash = await _getOrCreateHash(sourceUrl);

    // 检查是否已打开
    if (_databases.containsKey(hash)) {
      return _databases[hash]!;
    }

    // 打开或创建数据库
    final dbPath = _getDbPath(hash);
    final dbExists = await File(dbPath).exists();

    final db = sqlite3.open(dbPath);

    // 性能优化设置
    try {
      db.execute('PRAGMA synchronous = NORMAL');
      db.execute('PRAGMA cache_size = -64000'); // 64MB 缓存
      db.execute('PRAGMA temp_store = MEMORY');
    } catch (e) {
      AppLogger.storage.warn('部分性能优化设置失败: $e');
    }

    if (!dbExists) {
      // 创建新数据库
      await _createTables(db, sourceUrl);
    } else {
      // 校验现有数据库
      final isValid = await _validateDatabase(db, sourceUrl, dbPath);
      if (!isValid) {
        // R125 关闭序列约束：**dispose-before-throw 不可互换**——必须先 dispose
        // 再 throw，否则 throw 抛出后 db handle 泄漏（外层 catch 不持有 db
        // 引用，无法兜底 dispose）。这是 try-with-resources 的手动展开，对应
        // RAII 析构早于 unwind。**反例**：颠倒成 `throw ...; db.dispose();`
        // 会导致 dead code（unreachable 后置语句）+ handle 永远不释放。
        // **为什么不用 try/finally**：本块没有 try（throw 是兜底失败信号），
        // 若改 try/finally 包裹会让 caller catch 行为更复杂（调用方都 try-catch
        // 兜底了），与 R98 doc"throw 是诊断信号、不是契约"原则一致。
        db.dispose();
        // R98 anti-symmetric throw 标记（参见 feedback_audit_dimension_switch.md
        // "throw 对称性审计"维度）：本 throw 会被 _getDatabase 所有调用方
        // （getLatestRevision/getEarliestRevision 等十余处）的外层 catch 吞掉，
        // 各 caller 写日志后回退到 0 / 空集等兜底值。即没有外部 caller 把此
        // Exception 暴露给业务流程——throw 是诊断信号（DB 损坏需 ops 介入），
        // 不是契约。**刻意不补单测断言**：要测的是各 caller 的兜底输出（如
        // getLatestRevision 返回 0），不是路径上的 throw。
        throw Exception('数据库校验失败: $dbPath');
      }
      // 检查并升级
      await _checkAndUpgrade(db);
    }

    _databases[hash] = db;
    AppLogger.storage.info('已打开数据库: $dbPath (sourceUrl: $sourceUrl)');

    return db;
  }

  /// 创建数据库表
  Future<void> _createTables(Database db, String sourceUrl) async {
    // 源信息表（用于校验）
    db.execute('''
      CREATE TABLE source_info (
        id INTEGER PRIMARY KEY,
        source_url TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 插入源 URL 信息
    db.execute(
      'INSERT INTO source_info (id, source_url, created_at) VALUES (1, ?, ?)',
      [sourceUrl, DateTime.now().millisecondsSinceEpoch],
    );

    // 日志条目表（简化版，不再需要 source_url_hash）
    db.execute('''
      CREATE TABLE log_entries (
        revision INTEGER PRIMARY KEY,
        author TEXT NOT NULL,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 创建索引
    db.execute('CREATE INDEX idx_revision ON log_entries(revision DESC)');
    db.execute('CREATE INDEX idx_author ON log_entries(author)');
    db.execute('CREATE INDEX idx_date ON log_entries(date DESC)');

    // 缓存元数据表
    db.execute('''
      CREATE TABLE cache_metadata (
        id INTEGER PRIMARY KEY,
        latest_revision INTEGER NOT NULL,
        earliest_revision INTEGER,
        last_updated INTEGER NOT NULL
      )
    ''');

    // 初始化元数据
    db.execute(
      'INSERT INTO cache_metadata (id, latest_revision, earliest_revision, last_updated) VALUES (1, 0, NULL, ?)',
      [DateTime.now().millisecondsSinceEpoch],
    );

    // 版本表
    db.execute('''
      CREATE TABLE db_version (
        version INTEGER PRIMARY KEY
      )
    ''');
    db.execute('INSERT INTO db_version (version) VALUES (?)', [_dbVersion]);

    // 缓存区间表（版本4新增）
    db.execute('''
      CREATE TABLE cached_ranges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_revision INTEGER NOT NULL,
        end_revision INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute(
        'CREATE INDEX idx_ranges_start ON cached_ranges(start_revision DESC)');

    AppLogger.storage.info('数据库表创建完成');
  }

  /// 校验数据库（双向校验）
  Future<bool> _validateDatabase(
      Database db, String expectedUrl, String dbPath) async {
    try {
      // 检查 source_info 表是否存在
      final tableResult = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='source_info'",
      );

      if (tableResult.isEmpty) {
        // 旧版本数据库，需要迁移
        AppLogger.storage.warn('检测到旧版本数据库，需要迁移: $dbPath');
        return await _migrateOldDatabase(db, expectedUrl);
      }

      // 读取存储的 source_url
      final result =
          db.select('SELECT source_url FROM source_info WHERE id = 1');
      if (result.isEmpty) {
        AppLogger.storage.error('数据库中缺少 source_info 记录: $dbPath');
        return false;
      }

      final storedUrl = result.first.columnAt(0) as String;

      // 校验 URL 是否匹配
      if (storedUrl != expectedUrl) {
        final error = CacheValidationError(
          message: '【严重错误】数据库 URL 不匹配！\n'
              '期望: $expectedUrl\n'
              '实际: $storedUrl\n'
              '数据库: $dbPath\n'
              '这可能是由于 hash 冲突或配置错误导致的。',
          expectedUrl: expectedUrl,
          actualUrl: storedUrl,
          dbPath: dbPath,
        );

        AppLogger.storage.error(error.message);

        // 触发错误回调
        onValidationError?.call(error);

        return false;
      }

      AppLogger.storage.info('数据库校验通过: $dbPath');
      return true;
    } catch (e, stackTrace) {
      AppLogger.storage.error('数据库校验失败', e, stackTrace);
      return false;
    }
  }

  /// 迁移旧版本数据库
  Future<bool> _migrateOldDatabase(Database db, String sourceUrl) async {
    try {
      // 创建 source_info 表
      db.execute('''
        CREATE TABLE source_info (
          id INTEGER PRIMARY KEY,
          source_url TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');

      db.execute(
        'INSERT INTO source_info (id, source_url, created_at) VALUES (1, ?, ?)',
        [sourceUrl, DateTime.now().millisecondsSinceEpoch],
      );

      AppLogger.storage.info('旧数据库迁移完成: 已添加 source_info 表');
      return true;
    } catch (e, stackTrace) {
      AppLogger.storage.error('旧数据库迁移失败', e, stackTrace);
      return false;
    }
  }

  /// 检查并升级数据库
  Future<void> _checkAndUpgrade(Database db) async {
    try {
      final versionResult = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='db_version'",
      );

      if (versionResult.isEmpty) {
        // 创建版本表
        db.execute('CREATE TABLE db_version (version INTEGER PRIMARY KEY)');
        db.execute('INSERT INTO db_version (version) VALUES (1)');
        await _onUpgrade(db, 1, _dbVersion);
        db.execute('UPDATE db_version SET version = ?', [_dbVersion]);
      } else {
        final versionRows = db.select('SELECT version FROM db_version LIMIT 1');
        if (versionRows.isNotEmpty) {
          final currentVersion = versionRows.first.columnAt(0) as int;
          if (currentVersion < _dbVersion) {
            await _onUpgrade(db, currentVersion, _dbVersion);
            db.execute('UPDATE db_version SET version = ?', [_dbVersion]);
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.storage.warn('检查数据库版本失败: $e');
      AppLogger.storage.debug('详情', stackTrace);
    }
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // 版本 3：添加 date 索引
      try {
        db.execute(
            'CREATE INDEX IF NOT EXISTS idx_date ON log_entries(date DESC)');
        AppLogger.storage.info('已添加 date 索引（数据库升级）');
      } catch (e) {
        AppLogger.storage.warn('添加 date 索引失败（可能已存在）: $e');
      }
    }

    if (oldVersion < 4) {
      // 版本 4：添加缓存区间表
      try {
        db.execute('''
          CREATE TABLE IF NOT EXISTS cached_ranges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_revision INTEGER NOT NULL,
            end_revision INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        db.execute(
            'CREATE INDEX IF NOT EXISTS idx_ranges_start ON cached_ranges(start_revision DESC)');
        AppLogger.storage.info('已添加 cached_ranges 表（数据库升级）');

        // 迁移现有数据：根据现有的 log_entries 创建初始区间
        await _migrateExistingDataToRanges(db);
      } catch (e) {
        AppLogger.storage.warn('添加 cached_ranges 表失败: $e');
      }
    }
  }

  /// 迁移现有数据到区间表
  ///
  /// 对于升级的数据库，根据现有的 log_entries 创建一个初始区间
  Future<void> _migrateExistingDataToRanges(Database db) async {
    try {
      // 获取现有数据的最大和最小 revision
      final maxResult = db.select('SELECT MAX(revision) FROM log_entries');
      final minResult = db.select('SELECT MIN(revision) FROM log_entries');

      final maxRev = maxResult.first.columnAt(0) as int?;
      final minRev = minResult.first.columnAt(0) as int?;

      if (maxRev != null && minRev != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          'INSERT INTO cached_ranges (start_revision, end_revision, created_at, updated_at) VALUES (?, ?, ?, ?)',
          [maxRev, minRev, now, now],
        );
        AppLogger.storage.info('已迁移现有数据到区间: [$maxRev, $minRev]');
      }
    } catch (e) {
      AppLogger.storage.warn('迁移现有数据到区间失败: $e');
    }
  }

  /// 确保服务已初始化
  Future<void> _ensureInit() async {
    if (_cacheDir == null) {
      await init();
    }
  }

  /// 获取缓存中指定 sourceUrl 的最新版本号
  Future<int> getLatestRevision(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result =
          db.select('SELECT latest_revision FROM cache_metadata WHERE id = 1');

      if (result.isEmpty) {
        return 0;
      }

      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取缓存中指定 sourceUrl 的最早版本号
  Future<int> getEarliestRevision(String sourceUrl, {int? minRevision}) async {
    try {
      final db = await _getDatabase(sourceUrl);

      var query = 'SELECT MIN(revision) FROM log_entries';
      final args = <Object>[];

      if (isUsableMinRevision(minRevision)) {
        query += ' WHERE revision >= ?';
        args.add(minRevision!);
      }

      final result = db.select(query, args);

      if (result.isEmpty) {
        return 0;
      }

      final value = result.first.columnAt(0);
      return value != null ? value as int : 0;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最早版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 批量插入日志条目
  ///
  /// [sourceUrl] 源 URL
  /// [entries] 日志条目列表
  /// [isFromHead] 是否从 HEAD 开始获取的数据（用于区间管理）
  ///   - true: 从 HEAD 向旧版本获取，需要创建新区间或扩展起点
  ///   - false: 从缓存最旧版本继续向旧版本获取，扩展区间终点
  ///
  /// **R135 sqlite transaction boundary 协议 — 档 2 BEGIN/COMMIT batch-loop**：
  /// 本方法内层（[_, ..., entries.length] 切批后的 `BEGIN TRANSACTION` ... `COMMIT`/
  /// `ROLLBACK`）是 R135 4 档分类中的 **档 2**——多 row 写包在单一事务内、
  /// stmt 复用、commit/rollback 二选一。`package:sqlite3` 是同步 FFI（不是
  /// async sqflite），单 isolate 模型下 `BEGIN`...`COMMIT` 之间无 `await`、
  /// SQLite 本身保证 ACID，整段是真原子区。
  ///
  /// **R135 sqlite transaction boundary 4 档分类**（service 内 sqlite 子维度，
  /// 三档框架第 15 次复用）：
  /// - **档 1 sync-isolate-atomic-block**：单条 `db.execute/select` 在同步上下文
  ///   内自动提交，原子性由 SQLite + Dart 单 isolate 双层保证。lib 内全部
  ///   `db.select` 读 + 单 `db.execute` 写均属此档。**关键**：sync sqlite3 不是
  ///   async sqflite——`db.x()` 调用在同一 microtask 内同步返回，无任何 `await`
  ///   切回事件循环的窗口；只要"读 + 决策 + 写"全部在同一同步段内（无 `await`
  ///   隔断），档 1 与档 3 在 sync sqlite3 下等价。
  /// - **档 2 explicit BEGIN/COMMIT batch-loop**：本方法 + `mergeinfo_cache_service.
  ///   saveToCache` 的 prepare-stmt loop。多 row 写需事务保证以避免部分写入
  ///   状态（COMMIT 前 ROLLBACK 路径回滚已 stmt.execute 的 N 行）。
  /// - **档 3 cross-await read-then-write decision**：方法内有 `await` 切回事件循环
  ///   后再做 DB 写决策——本档**潜在 cross-call race**，需要靠 caller-side
  ///   串行化（同 isolate Future.then 链）兜底。本方法尾部 `_updateRangesAfterInsert`
  ///   是档 3 实例（`await getLatestRange` → 决策 → 多个 `await addOrUpdateRange/
  ///   extendLatestRangeXxx` 串联）。
  /// - **档 4 schema/PRAGMA bootstrap**：`_createTables` / `_upgradeDatabase` /
  ///   `PRAGMA synchronous = NORMAL` 等——一次性 setup，不存在并发竞争（受
  ///   `_getDatabase` 内 `_databases` Map 缓存保证 per-hash 单次）。
  ///
  /// **跨档 4 不变量 L1/L2/L3/L4**：
  /// - **L1 (sync-block atomicity)**：单一同步段内的多个 `db.x()` 是原子的；只要
  ///   不跨 `await`，sqlite3 保证组内顺序 + Dart 单 isolate 保证不被抢占。
  /// - **L2 (BEGIN/COMMIT 必配对)**：档 2 的 `BEGIN TRANSACTION` 必有 try/catch
  ///   包裹 + try 分支 COMMIT、catch 分支 ROLLBACK；二选一不可遗漏（否则连接
  ///   被永久 stuck 在 transaction 状态）。本方法 1288-1322 是 L2 范式。
  /// - **L3 (stmt.dispose 必在 COMMIT 之前)**：见 R125 doc + 1306-1317 注释；
  ///   prepared statement 在 transaction 期间持有内部锁，dispose 顺序错会让
  ///   sqlite3 抛 `LIBRARY_USED_INCORRECTLY`。catch 分支 ROLLBACK 隐式释放
  ///   stmt state、不需要显式 dispose（rollback 自带 cleanup）。
  /// - **L4 (cross-await 写序列由 caller 串行化)**：档 3 的多 `await` 写决策**不在
  ///   sqlite3 transaction 内**，依赖 Dart 单 isolate + caller 不并发调用兜底。
  ///   lib 内现状：`log_sync_service` 是唯一调用方，串行 `await insertEntries`，
  ///   不存在并发；若未来引入并行 caller 必须改档 2（包 db.transaction）或
  ///   外层加 Mutex。**R135 doc 化此潜在升档触发器**——任何并发 caller 引入
  ///   即为档 3 → 档 2 升档强信号。
  ///
  /// **R135 与 R125/R134 接合面**：R125 锁单服务**关闭**序列、R134 锁跨服务
  /// **缓存策略**、R135 锁单服务**事务边界**——三轮闭合 service-level 数据
  /// 完整性接合面（关闭 × 策略 × 事务）。三档框架第 15 次复用证明 framework
  /// 在 service 内可继续按子维度细分（cache 策略 × transaction boundary 是
  /// 同一 service-level 层面的姊妹子维度）。
  Future<void> insertEntries(
    String sourceUrl,
    List<LogEntry> entries, {
    bool isFromHead = false,
  }) async {
    if (entries.isEmpty) return;

    try {
      final db = await _getDatabase(sourceUrl);
      const batchSize = 1000;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < entries.length; i += batchSize) {
        final batch = entries.sublist(
          i,
          (i + batchSize).clamp(0, entries.length),
        );

        db.execute('BEGIN TRANSACTION');
        try {
          final stmt = db.prepare('''
            INSERT OR REPLACE INTO log_entries 
            (revision, author, date, title, message, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
          ''');

          for (final entry in batch) {
            stmt.execute([
              entry.revision,
              entry.author,
              entry.date,
              entry.title,
              entry.message,
              now,
            ]);
          }
          // R125 关闭序列约束：**stmt.dispose() 必须在 COMMIT 之前**——sqlite3
          // prepared statement 在事务期间持有内部锁/状态；如果 COMMIT 先调，
          // statement 仍持有 cursor 引用、可能与 commit 的 schema 锁冲突
          // （sqlite3 native 层会 SQLITE_BUSY）。当前顺序保证：
          //   step a: stmt.dispose()  释放 prepared statement handle
          //   step b: db.execute('COMMIT')  事务提交
          // **catch 路径同序约束**：catch 块中 ROLLBACK 不显式 dispose stmt——
          // 故意，因为 sqlite3 ROLLBACK 会隐式释放 statement state（rollback
          // 语义清空 prepared cache），重复 dispose 反而可能 double-free。
          // **dispose 在 commit 前 vs 在 commit 后的危险演化**：未来若有人按
          // "commit 后清理" 直觉调换顺序，会看似 ok（小数据量）但在并发或大
          // batch 场景偶发 SQLITE_BUSY——保留 doc 锁定当前顺序。
          stmt.dispose();
          db.execute('COMMIT');
        } catch (e) {
          db.execute('ROLLBACK');
          rethrow;
        }
      }

      // 更新元数据（保持向后兼容）
      final extremes = revisionExtremesOf(entries);
      final latestRevision = extremes.latest;
      final earliestRevision = extremes.earliest;

      for (final line in formatInsertEntriesHeaderLines(
        entriesCount: entries.length,
        latestRevision: latestRevision,
        earliestRevision: earliestRevision,
        isFromHead: isFromHead,
      )) {
        AppLogger.storage.info(line);
      }

      // 获取当前元数据
      final currentMeta = db.select(
          'SELECT latest_revision, earliest_revision FROM cache_metadata WHERE id = 1');
      int newLatest;
      int? newEarliest;

      if (currentMeta.isNotEmpty) {
        final merged = mergeMetadataExtremes(
          currentLatest: currentMeta.first.columnAt(0) as int,
          currentEarliest: currentMeta.first.columnAt(1) as int?,
          incomingLatest: latestRevision,
          incomingEarliest: earliestRevision,
        );
        newLatest = merged.latest;
        newEarliest = merged.earliest;
      } else {
        newLatest = latestRevision;
        newEarliest = earliestRevision;
      }

      db.execute(
        'UPDATE cache_metadata SET latest_revision = ?, earliest_revision = ?, last_updated = ? WHERE id = 1',
        [newLatest, newEarliest, now],
      );

      // 更新区间
      await _updateRangesAfterInsert(
          sourceUrl, latestRevision, earliestRevision, isFromHead);

      AppLogger.storage.info(
          '已插入 ${entries.length} 条日志到缓存: $sourceUrl (区间: [$latestRevision, $earliestRevision])');
    } catch (e, stackTrace) {
      AppLogger.storage.error('插入日志条目失败', e, stackTrace);
      rethrow;
    }
  }

  /// 从缓存获取日志条目
  Future<List<LogEntry>> getEntries(
    String sourceUrl, {
    int? limit,
    int offset = 0,
    String? authorFilter,
    String? titleFilter,
    String? messageFilter,
    int? minRevision,
  }) async {
    try {
      final db = await _getDatabase(sourceUrl);

      final clauses = buildLogEntryFilterClauses(
        minRevision: minRevision,
        authorFilter: authorFilter,
        titleFilter: titleFilter,
        messageFilter: messageFilter,
        authorMode: AuthorMatchMode.exact,
      );

      final plan = buildLogEntriesQuery(
        selectColumns: 'revision, author, date, title, message',
        filterClauses: clauses,
        orderByRevisionDesc: true,
        limitOffset: limit != null ? (limit: limit, offset: offset) : null,
      );

      final results = db.select(plan.sql, plan.args);
      return results
          .map((row) => LogEntry(
                revision: row.columnAt(0) as int,
                author: row.columnAt(1) as String,
                date: row.columnAt(2) as String,
                title: row.columnAt(3) as String,
                message: row.columnAt(4) as String,
              ))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取日志条目失败', e, stackTrace);
      return [];
    }
  }

  /// 获取缓存中的日志总数
  Future<int> getEntryCount(
    String sourceUrl, {
    String? authorFilter,
    String? titleFilter,
    String? messageFilter,
    int? minRevision,
  }) async {
    try {
      final db = await _getDatabase(sourceUrl);

      final clauses = buildLogEntryFilterClauses(
        minRevision: minRevision,
        authorFilter: authorFilter,
        titleFilter: titleFilter,
        messageFilter: messageFilter,
        authorMode: AuthorMatchMode.likeLowercase,
      );

      final plan = buildLogEntriesQuery(
        selectColumns: 'COUNT(*)',
        filterClauses: clauses,
        orderByRevisionDesc: false,
      );

      final result = db.select(plan.sql, plan.args);
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取日志数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取缓存中的日志总数（不带过滤条件）
  Future<int> getTotalCount(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select('SELECT COUNT(*) FROM log_entries');
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取日志总数失败', e, stackTrace);
      return 0;
    }
  }

  /// 清空指定 sourceUrl 的缓存
  ///
  /// **R125 关闭序列约束：dispose → map.remove → file.delete 三阶段顺序锁**
  /// 函数体的释放顺序必须严格按当前阶段：
  ///   阶段 1: `_databases[hash]!.dispose()` + `_databases.remove(hash)`（先释放
  ///           handle 再 drop map 引用——同 R125 close() 中的 dispose-before-clear
  ///           约束，避免 use-after-free）；
  ///   阶段 2: `dbFile.delete()`（OS 层删文件，**必须**在 step 1 之后）；
  ///   阶段 3: `AppLogger.storage.info('已清空缓存: ...')`（异步日志最后）。
  /// **为什么阶段 1 → 阶段 2 不可互换**：sqlite3 在 Windows 上对 db handle 持有
  /// 文件锁，**先 delete 后 dispose 会因 OS 文件锁而失败**（PathAccessException
  /// "file in use by another process"）；macOS/Linux unix unlink 语义允许，但
  /// 跨平台一致性要求统一按 Windows 严格顺序。
  /// **为什么 _databases[hash]!.dispose() 必须先于 _databases.remove(hash)**：
  /// `_databases[hash]!` 是 map.lookup + non-null 断言；如果 remove 在 dispose
  /// 前调，`_databases[hash]!` 在第二行会触发 `Null check operator used on a
  /// null value` —— 当前两行表达式必须按"读 → 释放 → 删 key" 顺序。
  /// **catch 兜底**：try/catch 包裹整段保证任意阶段失败不抛到 caller（与
  /// `clearAllCache` 同策略），UI 层只看错误日志。
  Future<void> clearCache(String sourceUrl) async {
    try {
      final hash = await _getOrCreateHash(sourceUrl);

      // 关闭数据库
      if (_databases.containsKey(hash)) {
        _databases[hash]!.dispose();
        _databases.remove(hash);
      }

      // 删除数据库文件
      final dbPath = _getDbPath(hash);
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      AppLogger.storage.info('已清空缓存: $sourceUrl');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空缓存失败', e, stackTrace);
    }
  }

  /// 根据 revision 列表获取日志条目
  Future<List<LogEntry>> getEntriesByRevisions(
    String sourceUrl,
    List<int> revisions,
  ) async {
    if (revisions.isEmpty) {
      return [];
    }

    try {
      final db = await _getDatabase(sourceUrl);

      final placeholders = List.filled(revisions.length, '?').join(',');
      final query = '''
        SELECT revision, author, date, title, message 
        FROM log_entries 
        WHERE revision IN ($placeholders)
        ORDER BY revision DESC
      ''';

      final results = db.select(query, revisions);

      return results
          .map((row) => LogEntry(
                revision: row.columnAt(0) as int,
                author: row.columnAt(1) as String,
                date: row.columnAt(2) as String,
                title: row.columnAt(3) as String,
                message: row.columnAt(4) as String,
              ))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.storage.error('根据 revision 获取日志条目失败', e, stackTrace);
      return [];
    }
  }

  /// 获取缓存中最早的日期
  Future<DateTime?> getEarliestDate(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select('SELECT MIN(date) FROM log_entries');

      if (result.isEmpty) {
        return null;
      }

      final value = result.first.columnAt(0);
      if (value == null) {
        return null;
      }

      try {
        return DateTime.parse(value as String);
      } catch (_) {
        return null;
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最早日期失败', e, stackTrace);
      return null;
    }
  }

  /// 清空所有缓存
  ///
  /// **R134 档 3 unbounded-manual-nuke-all**：本函数与 `MergeInfoCacheService.clearAllCache`
  /// 同档——sqlite-backed 服务无容量上限（K1 满足）、淘汰由用户显式触发（"清缓存"
  /// 按钮）、清空粒度=全部数据库文件 + 内存映射 + 持久化映射。与档 2
  /// `clearCache(sourceUrl)` 的差异是粒度（全部 vs 单 sourceUrl），与档 1
  /// `LogFileCacheService.clearCache()` 的差异是触发方式（手动 vs 自动 LRU + 满即驱逐）。
  /// 详见 [LogFileCacheService] 类 doc 的 R134 章节。
  ///
  /// **R125 关闭序列约束：四阶段顺序锁（dispose → file → mapping → log）**
  /// 函数体分为四阶段，**必须严格按当前顺序**：
  ///   阶段 1: 全量 dispose + `_databases.clear()`（释放所有 sqlite handle）；
  ///   阶段 2: 遍历 `_cacheDir!` 删 *.db 文件（OS 文件层清理）；
  ///   阶段 3: `_urlToHashMap.clear()` + `_hashToUrlMap.clear()` + 持久化映射
  ///           （logical mapping 清空 + saveUrlHashMap）；
  ///   阶段 4: `AppLogger.storage.info('已清空所有缓存')`（最终日志）。
  /// **为什么阶段 1 → 阶段 2 不可互换**：与 `clearCache` 单 hash 同形约束——
  /// Windows 下 sqlite handle 未 dispose 前删文件会失败。
  /// **为什么阶段 2 → 阶段 3 不可互换**：阶段 3 清空 _urlToHashMap 后，
  /// `_getDbPath(hash)` 派生的路径仍然有效（hash 是文件名直接组件），但**未来若
  /// 演化成 mapping-derived 路径生成**会导致阶段 2 找不到文件——为保持顺序对
  /// 演化稳定，先删文件再清 mapping。
  /// **为什么 `_saveUrlHashMap()` 在 mapping clear 之后**：保存空 map 才能让重启
  /// 后看到"已清空"状态；如果 saveUrlHashMap 在 clear 之前，重启后会从磁盘加载
  /// 旧 mapping，**清空操作部分丢失**（mapping 文件还原 = 看似有缓存但 db 文件
  /// 没了 = ghost mapping）。
  Future<void> clearAllCache() async {
    try {
      // 关闭所有数据库
      for (final db in _databases.values) {
        db.dispose();
      }
      _databases.clear();

      // 删除所有缓存文件
      if (_cacheDir != null) {
        final cacheDir = Directory(_cacheDir!);
        if (await cacheDir.exists()) {
          await for (final entity in cacheDir.list()) {
            if (entity is File && entity.path.endsWith('.db')) {
              await entity.delete();
            }
          }
        }
      }

      // 清空映射
      _urlToHashMap.clear();
      _hashToUrlMap.clear();
      await _saveUrlHashMap();

      AppLogger.storage.info('已清空所有缓存');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空所有缓存失败', e, stackTrace);
    }
  }

  /// 关闭所有数据库
  ///
  /// **R121 资源释放协议档 2：伪异步同步释放型**
  /// 与 `mergeinfo_cache_service.close()` 同形——签名 `Future<void> close()
  /// async` 但函数体无 `await`（`db.dispose()` 与 `_databases.clear()` 同步）。
  /// 详细的"为什么保留 async / 没有 IO 落盘语义 / 幂等机制 / 不抽 helper"参见
  /// `mergeinfo_cache_service.close()` 的 R121 doc，本处不重复。**与 R121 档 1
  /// （`logger_service.close()`）的区分**：档 1 polling-await 保证物理落盘，本
  /// 档仅保证 handle 释放——**对称释放语义不可互换**：caller 不能假设 close 后
  /// 文件已 fsync。
  ///
  /// **R125 关闭序列约束：与 mergeinfo_cache_service.close 三步顺序同形锁**
  /// 函数体三步严格按 dispose-before-clear-before-log 顺序，不可互换：
  ///   step 1: 遍历 dispose（释放 sqlite handle）
  ///   step 2: `_databases.clear()`（map 清空）
  ///   step 3: `AppLogger.storage.info(...)`（已关闭日志）
  /// 详细 step 间反例（map.clear 先调导致 use-after-free / 日志顺序锁）参见
  /// `mergeinfo_cache_service.close()` R125 doc，本处不重复。**同形锁**：本函数
  /// 与 mergeinfo close 必须保持完全相同的三步顺序，否则会破坏 R59 helper-vs-
  /// inline 决策（"两 callsite 完全同形所以保留 inline"），同形不再成立时必须
  /// 立即抽 helper 或重新评估。
  Future<void> close() async {
    for (final db in _databases.values) {
      db.dispose();
    }
    _databases.clear();
    AppLogger.storage.info('日志缓存数据库已关闭');
  }

  /// 获取所有已缓存的 URL 列表
  List<String> getCachedUrls() {
    return _urlToHashMap.keys.toList();
  }

  /// 获取缓存目录路径
  String? getCacheDir() => _cacheDir;

  // ===== 区间管理方法 =====

  /// 获取所有缓存区间（按 startRevision 降序排列）
  Future<List<CachedRange>> getAllRanges(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final result = db.select(
        'SELECT id, start_revision, end_revision, created_at, updated_at FROM cached_ranges ORDER BY start_revision DESC',
      );

      return result
          .map((row) => CachedRange(
                id: row.columnAt(0) as int,
                startRevision: row.columnAt(1) as int,
                endRevision: row.columnAt(2) as int,
                createdAt:
                    DateTime.fromMillisecondsSinceEpoch(row.columnAt(3) as int),
                updatedAt:
                    DateTime.fromMillisecondsSinceEpoch(row.columnAt(4) as int),
              ))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取缓存区间失败', e, stackTrace);
      return [];
    }
  }

  /// 获取最新的区间（startRevision 最大的那个）
  Future<CachedRange?> getLatestRange(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);

      // 先查询所有区间，用于调试
      final allRanges = db.select(
        'SELECT id, start_revision, end_revision FROM cached_ranges ORDER BY start_revision DESC',
      );
      if (allRanges.isNotEmpty) {
        AppLogger.storage.info('【getLatestRange】所有区间:');
        for (final row in allRanges) {
          AppLogger.storage.info(
              '  - id=${row.columnAt(0)}, [${row.columnAt(1)}, ${row.columnAt(2)}]');
        }
      } else {
        AppLogger.storage.info('【getLatestRange】没有任何区间');
      }

      final result = db.select(
        'SELECT id, start_revision, end_revision, created_at, updated_at FROM cached_ranges ORDER BY start_revision DESC LIMIT 1',
      );

      if (result.isEmpty) {
        return null;
      }

      final row = result.first;
      final range = CachedRange(
        id: row.columnAt(0) as int,
        startRevision: row.columnAt(1) as int,
        endRevision: row.columnAt(2) as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.columnAt(3) as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.columnAt(4) as int),
      );
      AppLogger.storage.info('【getLatestRange】返回最新区间: $range');
      return range;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间失败', e, stackTrace);
      return null;
    }
  }

  /// 添加或更新区间
  ///
  /// 插入新区间后会自动检查并合并连续的区间
  Future<void> addOrUpdateRange(
      String sourceUrl, int startRevision, int endRevision) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final now = DateTime.now().millisecondsSinceEpoch;

      // 插入新区间
      db.execute(
        'INSERT INTO cached_ranges (start_revision, end_revision, created_at, updated_at) VALUES (?, ?, ?, ?)',
        [startRevision, endRevision, now, now],
      );

      AppLogger.storage.info('已添加新区间: [$startRevision, $endRevision]');

      // 合并连续区间
      await _mergeAdjacentRanges(db);
    } catch (e, stackTrace) {
      AppLogger.storage.error('添加区间失败', e, stackTrace);
    }
  }

  /// 插入数据后更新区间
  ///
  /// [latestRevision] 本次插入的最新版本
  /// [earliestRevision] 本次插入的最旧版本
  /// [isFromHead] 是否从 HEAD 开始获取的数据
  ///
  /// 决策见纯函数 [planRangeUpdateAfterInsert]，本方法只负责按 plan 调对应的 DB 操作。
  ///
  /// **R135 档 3 cross-await read-then-write decision 实例**：
  /// `await getLatestRange` (1770) → 决策（同步 [planRangeUpdateAfterInsert]）→
  /// 多个 `await` 写（1788-1801 switch 各 case 调 addOrUpdateRange /
  /// extendLatestRangeStart / extendLatestRangeEnd）。读与写跨 `await`，**不在**
  /// sqlite3 transaction 内。L4 不变量保证：**唯一调用方** [insertEntries] 内
  /// 串行 await `_updateRangesAfterInsert`，[insertEntries] 自身唯一调用方
  /// `log_sync_service` 内串行——caller-side 串行化兜底。若未来引入并发
  /// `_updateRangesAfterInsert` 调用必须改档 2 包 db.transaction 或加 Mutex。
  Future<void> _updateRangesAfterInsert(
    String sourceUrl,
    int latestRevision,
    int earliestRevision,
    bool isFromHead,
  ) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      for (final line in formatRangeUpdateHeaderLines(
        latestRevision: latestRevision,
        earliestRevision: earliestRevision,
        isFromHead: isFromHead,
        latestRange: latestRange,
      )) {
        AppLogger.storage.info(line);
      }

      final plan = planRangeUpdateAfterInsert(
        latestRange: latestRange,
        latestRevision: latestRevision,
        earliestRevision: earliestRevision,
        isFromHead: isFromHead,
      );
      AppLogger.storage.info('  → 决策: $plan');

      switch (plan.action) {
        case RangeUpdateAction.createNewRange:
          await addOrUpdateRange(sourceUrl, plan.newStart!, plan.newEnd!);
          break;
        case RangeUpdateAction.extendStart:
          await extendLatestRangeStart(sourceUrl, plan.newStart!);
          break;
        case RangeUpdateAction.extendEnd:
          await extendLatestRangeEnd(sourceUrl, plan.newEnd!);
          break;
        case RangeUpdateAction.noop:
          // 数据已存在，无需更新
          break;
      }
      AppLogger.storage.info('【区间更新】完成');
    } catch (e, stackTrace) {
      AppLogger.storage.error('更新区间失败', e, stackTrace);
    }
  }

  /// 扩展最新区间的终点（向旧版本扩展）
  ///
  /// [newEndRevision] 新的终点（较小的 revision）
  Future<void> extendLatestRangeEnd(
      String sourceUrl, int newEndRevision) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final latestRange = await getLatestRange(sourceUrl);

      if (latestRange == null) {
        AppLogger.storage.warn('没有最新区间可扩展');
        return;
      }

      // 决策见纯函数 [shouldExtendLatestRangeEnd]，本方法只负责按结果调 DB。
      if (shouldExtendLatestRangeEnd(
        latestRange: latestRange,
        newEndRevision: newEndRevision,
      )) {
        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          'UPDATE cached_ranges SET end_revision = ?, updated_at = ? WHERE id = ?',
          [newEndRevision, now, latestRange.id],
        );
        AppLogger.storage
            .info('已扩展最新区间: [${latestRange.startRevision}, $newEndRevision]');

        // 检查是否需要合并
        await _mergeAdjacentRanges(db);
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('扩展区间失败', e, stackTrace);
    }
  }

  /// 扩展最新区间的起点（向新版本扩展）
  ///
  /// [newStartRevision] 新的起点（较大的 revision）
  Future<void> extendLatestRangeStart(
      String sourceUrl, int newStartRevision) async {
    try {
      final db = await _getDatabase(sourceUrl);
      final latestRange = await getLatestRange(sourceUrl);

      if (latestRange == null) {
        AppLogger.storage.warn('没有最新区间可扩展');
        return;
      }

      // 决策见纯函数 [shouldExtendLatestRangeStart]，本方法只负责按结果调 DB。
      if (shouldExtendLatestRangeStart(
        latestRange: latestRange,
        newStartRevision: newStartRevision,
      )) {
        final now = DateTime.now().millisecondsSinceEpoch;
        db.execute(
          'UPDATE cached_ranges SET start_revision = ?, updated_at = ? WHERE id = ?',
          [newStartRevision, now, latestRange.id],
        );
        AppLogger.storage
            .info('已扩展最新区间起点: [$newStartRevision, ${latestRange.endRevision}]');
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('扩展区间起点失败', e, stackTrace);
    }
  }

  /// 合并相邻的连续区间
  ///
  /// 关键规则：只有首尾相同的区间才算连续
  /// 例如：[200, 100] 和 [100, 50] 是连续的（100 == 100）
  ///
  /// 决策部分见纯函数 [planMergeAdjacentRanges]，本方法只负责
  /// 把决策应用到 SQLite。
  ///
  /// **R135 档 1 sync-isolate-atomic-block 实例**：本方法体内 `db.select` (1885)
  /// → `planMergeAdjacentRanges`（纯函数，同步）→ for 循环 `db.execute UPDATE`
  /// (1908-1912) → for 循环 `db.execute DELETE` (1915-1917) **全部在同一同步段
  /// 内、无 `await`**，由 L1 不变量保证原子（sqlite3 sync FFI + Dart 单 isolate
  /// 不可抢占）。两 for 循环之间的"中间状态"对 isolate 内任何 observer 不可见
  /// （observer 必走 `await db op`，但本同步段不让出事件循环）。**故意不包
  /// `db.transaction`**：单 isolate 同步段已等价于 transaction 隔离级别；包
  /// transaction 反而让 stmt 路径多一层 BEGIN/COMMIT overhead 而无增益。
  Future<void> _mergeAdjacentRanges(Database db) async {
    try {
      // 获取所有区间，按 startRevision 降序
      final result = db.select(
        'SELECT id, start_revision, end_revision FROM cached_ranges ORDER BY start_revision DESC',
      );

      if (result.length < 2) {
        return; // 少于2个区间，无需合并
      }

      final ranges = result
          .map((row) => (
                id: row.columnAt(0) as int,
                start: row.columnAt(1) as int,
                end: row.columnAt(2) as int,
              ))
          .toList();

      final plan = planMergeAdjacentRanges(ranges);

      // 执行更新和删除
      if (plan.toDelete.isEmpty && plan.toUpdate.isEmpty) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      for (final update in plan.toUpdate) {
        db.execute(
          'UPDATE cached_ranges SET end_revision = ?, updated_at = ? WHERE id = ?',
          [update.newEnd, now, update.id],
        );
      }

      for (final id in plan.toDelete) {
        db.execute('DELETE FROM cached_ranges WHERE id = ?', [id]);
      }

      AppLogger.storage.info('已合并 ${plan.toDelete.length} 个连续区间');
    } catch (e, stackTrace) {
      AppLogger.storage.error('合并区间失败', e, stackTrace);
    }
  }

  /// 获取最新区间内的日志条目数量
  Future<int> getLatestRangeEntryCount(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }

      final db = await _getDatabase(sourceUrl);
      final result = db.select(
        'SELECT COUNT(*) FROM log_entries WHERE revision >= ? AND revision <= ?',
        [latestRange.endRevision, latestRange.startRevision],
      );

      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间条目数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取最新区间内的日志条目
  Future<List<LogEntry>> getEntriesInLatestRange(
    String sourceUrl, {
    int? limit,
    int offset = 0,
    String? authorFilter,
    String? titleFilter,
    String? messageFilter,
    int? minRevision,
  }) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      AppLogger.storage
          .info('【getEntriesInLatestRange】最新区间: ${latestRange ?? "无"}');
      if (latestRange == null) {
        AppLogger.storage.info('  → 没有区间，返回空列表');
        return [];
      }

      final db = await _getDatabase(sourceUrl);

      final clauses = buildLogEntryFilterClauses(
        minRevision: minRevision,
        authorFilter: authorFilter,
        titleFilter: titleFilter,
        messageFilter: messageFilter,
        authorMode: AuthorMatchMode.exact,
      );

      final plan = buildLogEntriesQuery(
        selectColumns: 'revision, author, date, title, message',
        rangeBounds: (
          endRevision: latestRange.endRevision,
          startRevision: latestRange.startRevision,
        ),
        filterClauses: clauses,
        orderByRevisionDesc: true,
        limitOffset: limit != null ? (limit: limit, offset: offset) : null,
      );

      final results = db.select(plan.sql, plan.args);
      return results
          .map((row) => LogEntry(
                revision: row.columnAt(0) as int,
                author: row.columnAt(1) as String,
                date: row.columnAt(2) as String,
                title: row.columnAt(3) as String,
                message: row.columnAt(4) as String,
              ))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间日志条目失败', e, stackTrace);
      return [];
    }
  }

  /// 获取最新区间内符合过滤条件的日志数量
  Future<int> getEntryCountInLatestRange(
    String sourceUrl, {
    String? authorFilter,
    String? titleFilter,
    String? messageFilter,
    int? minRevision,
  }) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }

      final db = await _getDatabase(sourceUrl);

      final clauses = buildLogEntryFilterClauses(
        minRevision: minRevision,
        authorFilter: authorFilter,
        titleFilter: titleFilter,
        messageFilter: messageFilter,
        authorMode: AuthorMatchMode.likeLowercase,
      );

      final plan = buildLogEntriesQuery(
        selectColumns: 'COUNT(*)',
        rangeBounds: (
          endRevision: latestRange.endRevision,
          startRevision: latestRange.startRevision,
        ),
        filterClauses: clauses,
        orderByRevisionDesc: false,
      );

      final result = db.select(plan.sql, plan.args);
      return result.first.columnAt(0) as int;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间日志数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 清空所有区间（用于重建缓存）
  Future<void> clearAllRanges(String sourceUrl) async {
    try {
      final db = await _getDatabase(sourceUrl);
      db.execute('DELETE FROM cached_ranges');
      AppLogger.storage.info('已清空所有区间');
    } catch (e, stackTrace) {
      AppLogger.storage.error('清空区间失败', e, stackTrace);
    }
  }

  /// 获取最新区间的最早版本号
  Future<int> getEarliestRevisionInLatestRange(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }
      return latestRange.endRevision;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间最早版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取最新区间的最新版本号
  Future<int> getLatestRevisionInLatestRange(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return 0;
      }
      return latestRange.startRevision;
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间最新版本号失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取最新区间的最早日期
  Future<DateTime?> getEarliestDateInLatestRange(String sourceUrl) async {
    try {
      final latestRange = await getLatestRange(sourceUrl);
      if (latestRange == null) {
        return null;
      }

      final db = await _getDatabase(sourceUrl);
      final result = db.select(
        'SELECT MIN(date) FROM log_entries WHERE revision >= ? AND revision <= ?',
        [latestRange.endRevision, latestRange.startRevision],
      );

      if (result.isEmpty) {
        return null;
      }

      final value = result.first.columnAt(0);
      if (value == null) {
        return null;
      }

      try {
        return DateTime.parse(value as String);
      } catch (_) {
        return null;
      }
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取最新区间最早日期失败', e, stackTrace);
      return null;
    }
  }
}
