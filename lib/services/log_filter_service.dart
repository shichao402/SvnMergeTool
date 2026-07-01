/// 日志过滤和分页服务
///
/// 独立模块，负责处理日志的过滤和分页逻辑
/// - 从缓存读取数据（只使用最新区间的数据）
/// - 应用过滤条件（作者、标题）
/// - 处理分页逻辑
/// - 不依赖 UI，纯业务逻辑
/// 
/// 重要设计原则：
/// - 过滤器只负责过滤 db 缓存中的数据
/// - 只展示最新区间内的数据
/// - 不触发任何网络请求
/// - 分支点过滤使用缓存的 minRevision 参数

import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import 'log_cache_service.dart';
import 'logger_service.dart';

/// 分页计算结果。
///
/// 由 [computePaginationPlan] 给出，封装了「总页数 / 实际生效页 / SQL offset / 是否还有下一页」
/// 这四个原本散落在 `getPaginatedEntries` 里的派生量。
@visibleForTesting
class PaginationPlan {
  /// 总页数；`totalCount == 0` 时为 0。
  final int totalPages;

  /// 实际生效的页码（已 clamp 到 `[0, totalPages - 1]`，无数据时回落到 0）。
  final int adjustedPage;

  /// 该页对应的 SQL `offset`，等于 `adjustedPage * pageSize`。
  final int offset;

  /// 是否还有下一页可翻。
  final bool hasMore;

  const PaginationPlan({
    required this.totalPages,
    required this.adjustedPage,
    required this.offset,
    required this.hasMore,
  });
}

/// 把「请求页 + 总条数 + 每页大小」翻译成 [PaginationPlan]。
///
/// 规则（与 `getPaginatedEntries` 内联实现严格等价）：
/// - `totalCount <= 0` → 全部归零，`adjustedPage = 0`、`totalPages = 0`、`hasMore = false`
/// - 否则 `totalPages = ceil(totalCount / pageSize)`，`adjustedPage = requestedPage.clamp(0, totalPages - 1)`
/// - `hasMore = adjustedPage < totalPages - 1`
///
/// 调用方需保证 `pageSize > 0`，否则会抛 `ArgumentError`（避免除以 0 或负数偷偷产生
/// 未定义行为）。
///
/// 当前生产调用方：
/// - [LogFilterService.getPaginatedEntries]（同文件）
/// - [AppState.updateCachedTotalCount]（providers/app_state.dart）——
///   预加载服务回填总数时同样走这套规则，保证两边总页数口径一致。
PaginationPlan computePaginationPlan({
  required int totalCount,
  required int pageSize,
  required int requestedPage,
}) {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be > 0');
  }
  if (totalCount <= 0) {
    return const PaginationPlan(
      totalPages: 0,
      adjustedPage: 0,
      offset: 0,
      hasMore: false,
    );
  }
  final totalPages = ((totalCount - 1) / pageSize).floor() + 1;
  final adjustedPage = requestedPage.clamp(0, totalPages - 1);
  return PaginationPlan(
    totalPages: totalPages,
    adjustedPage: adjustedPage,
    offset: adjustedPage * pageSize,
    hasMore: adjustedPage < totalPages - 1,
  );
}

/// 判断 working directory 字符串是否「可用作缓存键」。
///
/// 与 [LogFilterService.getCachedBranchPoint] / [LogFilterService.clearBranchPointCache]
/// 中的 `wd != null && wd.isNotEmpty` 判断完全一致；抽出来供两处共用并便于测试。
/// 同时也被 [LogSyncService] 中的 COPY_TAIL 缓存使用。
bool isUsableWorkingDirectory(String? workingDirectory) =>
    workingDirectory != null && workingDirectory.isNotEmpty;

/// 跨服务共用的日志分隔线常量。
///
/// **集中管理 `'━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'` 字面值**——这条
/// **恰好 40 个** U+2501（`BOX DRAWINGS HEAVY HORIZONTAL`）字符组成的横线，被
/// 用作"日志段落分隔"。任何一处不小心多打或少打一个字符，UI 日志分组就会错位；
/// 集中到此常量后，即使有人想改样式（比如改成 ASCII `===`）也只动一行。
///
/// **当前调用站（R87 巡检收口，按文件字母序）**：
/// - `services/log_filter_service.dart` ×2：`AppLogger.storage.info(...)`
///   （getPaginatedEntries 步骤 1/3 入参 dump）；
/// - `services/log_sync_service.dart` ×11：`AppLogger.svn.info(...)`
///   （SVN 同步流程的多阶段日志框架）；
/// - `services/preload_service.dart` ×2：`AppLogger.preload.info(...)`
///   （预加载启动 / 完成框架）；
/// - `services/svn_service.dart` ×9：`_log(...)` 私有方法
///   （每条 SVN CLI 命令开始 / 结束、findBranchPoint dump 框架）。
///
/// 合计 **24 处 callsite，跨 4 个文件**。R87 之前 doc 写"三处"，遗漏了
/// `svn_service.dart` 的 9 处——R69 抽 `formatSvnCommandStartLine` 时把
/// svn_service 内的 raw 字面值统一替换为本常量，但 doc 当时未同步更新。
///
/// **放在 log_filter_service 而非 log_sync_service**：
/// - `log_sync_service` 已经 `import 'log_filter_service.dart' show isUsableWorkingDirectory;`，
///   依赖方向 sync → filter；常量放在被依赖端是天然位置。
/// - 命名去掉 `sync` 前缀，因为它服务于全部 logger（preload / storage / merge / svn）。
///
/// **契约**（由 `test/log_filter_service_test.dart` 锁定）：
/// - 字符串长度恒等于 40——任何"少一个 / 多一个"修改都会让 UI 框架错位；
/// - 字符串内**只**包含 U+2501，不混用其他横线字符（如 U+2500 / `-`）。
const String appLogSeparator =
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

/// 把 [LogFilterService.getPaginatedEntries] 步骤 1 的"4 行入参 dump"渲染成字符串列表。
///
/// **契约**：
/// - 4 行顺序固定：sourceUrl / 页码 + 每页（合并一行，与原日志形态一致）/ 过滤条件 / 标题
/// - 标题恒为 `'【过滤服务】获取分页数据（只使用最新区间）'`，作为段落首行，**不**做拼接
/// - `filter` 走其 `toString()`（即 `LogFilter(author: ..., title: ..., minRevision: ...)`）
/// - 行首两空格缩进与 syncLogs 形态保持一致；标题行**不**带缩进（视觉上是段落标题）
@visibleForTesting
List<String> formatPaginatedEntriesHeaderLines({
  required String sourceUrl,
  required int page,
  required int pageSize,
  required LogFilter filter,
}) {
  return [
    '【过滤服务】获取分页数据（只使用最新区间）',
    '  源 URL: $sourceUrl',
    '  页码: $page, 每页: $pageSize',
    '  过滤条件: $filter',
  ];
}

/// 把 [LogFilterService.getPaginatedEntries] 末尾"返回行"渲染成单字符串。
///
/// **契约**：
/// - 形如 `'  返回: 17 条, 第 2/5 页, hasMore=true'`
/// - 页码显示走"1-based"（`adjustedPage + 1`），与用户感知一致；总页数沿用原值
/// - `entriesCount` 与 `adjustedPage` / `totalPages` 由调用方分别计算后传入——本函数
///   只做格式化，不重复 PaginationPlan 的派生
String formatPaginatedEntriesResultLine({
  required int entriesCount,
  required int adjustedPage,
  required int totalPages,
  required bool hasMore,
}) {
  return '  返回: $entriesCount 条, 第 ${adjustedPage + 1}/$totalPages 页, hasMore=$hasMore';
}

/// 渲染 `getPaginatedEntries` 步骤 1 的"最新区间内符合条件的总数"单行日志。
///
/// **契约**：固定模板 `'  最新区间内符合条件的总数: $totalCount'`，前导
/// 2 空格缩进与 `formatPaginatedEntriesHeaderLines` 数据行对齐。
///
/// **不**对 `totalCount < 0` 做防御——`getEntryCountInLatestRange` 返回 SQL
/// `COUNT(*)` 结果，by contract 永远 `>= 0`；如果出现负数应该让异常文案
/// 暴露在日志里而不是被静默修正。**单测覆盖** `0` 与正数两条路径。
@visibleForTesting
String formatPaginatedEntriesTotalCountLine(int totalCount) {
  return '  最新区间内符合条件的总数: $totalCount';
}

/// 渲染 `getPaginatedEntries` 在"用户请求页超界、被 clamp"时输出的页码调整日志。
///
/// **契约**：固定模板 `'  页码调整: $requestedPage -> $adjustedPage (总页数: $totalPages)'`，
/// 前导 2 空格缩进。**调用方负责**在 `requestedPage != adjustedPage` 时才打印
/// 这行——本函数**不**做 if 守卫，让"无调整"和"有调整"两种场景在调用点
/// 一目了然，避免函数内部决策遮蔽日志逻辑。
///
/// **单测覆盖**：超界向上 / 超界向下（负数 clamp 到 0）/ 总页数为 1 边界
/// 三条路径——即便调用方不做 if 守卫直接打印，本函数返回的字符串仍合法。
@visibleForTesting
String formatPageAdjustmentLine({
  required int requestedPage,
  required int adjustedPage,
  required int totalPages,
}) {
  return '  页码调整: $requestedPage -> $adjustedPage (总页数: $totalPages)';
}

/// 渲染 `LogFilterService.cacheBranchPoint` 的写缓存日志单行。
///
/// **契约**：固定模板 `'已缓存分支点: $workingDirectory -> r$branchPoint'`，
/// **不带前导缩进**（与原调用点一致——这是一条独立的"事件"日志，不是某段
/// 落里的子项）。
///
/// `branchPoint == null` 时输出 `'... -> rnull'`：原代码就是这种字面拼接，
/// 调用方有责任避免传 null（或者明确接受这个诊断输出）。**单测显式锁定**
/// `null` 路径，防止后续有人把"`-> rnull`"美化成"`-> 未知`"——那会让
/// 静默改 null 的 bug 从日志里消失。
@visibleForTesting
String formatBranchPointCacheSetLine({
  required String workingDirectory,
  required int? branchPoint,
}) {
  return '已缓存分支点: $workingDirectory -> r$branchPoint';
}

/// 渲染 `LogFilterService.clearBranchPointCache` 的清缓存日志单行。
///
/// **契约**：
/// - `workingDirectory` 通过 [isUsableWorkingDirectory] 判定为 usable
///   （非 null 且非空）→ `'已清除分支点缓存: $workingDirectory'`
/// - 否则（null / 空串）→ `'已清除所有分支点缓存'`
///
/// **关键不变量**：必须复用 [isUsableWorkingDirectory] 的判定，不要写死成
/// `wd != null && wd.isNotEmpty`——否则当 [isUsableWorkingDirectory] 语义
/// 演进（比如未来加入 `wd.trim().isNotEmpty`）时，本函数会出现行为分裂。
/// **单测显式锁定**：`null` / `''` / 非空字符串三条路径。
@visibleForTesting
String formatBranchPointCacheClearLine(String? workingDirectory) {
  if (isUsableWorkingDirectory(workingDirectory)) {
    return '已清除分支点缓存: $workingDirectory';
  }
  return '已清除所有分支点缓存';
}

/// 判定单个字符串过滤器（如 [LogFilter.author] / [LogFilter.title]）是否
/// 视作"未设置"。
///
/// **契约**：`null` 或空串 `''` 都视作"未设置"返回 `true`；非空字符串返回
/// `false`。**不做 trim**——含空白字符的字符串视作"已设置"，与
/// `isMergeInfoArgsValid`（mergeinfo_cache_service.dart）的同源决策一致：
/// 这一层**不**对用户输入做净化，由 UI 层在更上游负责。
///
/// **抽出动机**：`LogFilter.isEmpty` 内重复 2 次 `(field == null || field.isEmpty)`
/// 的精度敏感表达式。任何一处不小心改成 `field?.isEmpty ?? true` 会导致
/// `null` 被错误地当作 "isEmpty=true 但不空"——抽成命名函数后，语义变成
/// 单点。**单测显式锁定** null / 空串 / 单空格 / 非空 4 条路径。
@visibleForTesting
bool isStringFilterEmpty(String? value) {
  return value == null || value.isEmpty;
}

/// 把单个字段值按 RFC 4180 规则做 CSV 转义。
///
/// **契约**：
/// - 字段中**不**含 `,` / `"` / `\n` / `\r` → 原样返回；
/// - 含上述任一字符 → 整字段两侧补 `"`，字段内 `"` 替换为 `""`；
/// - 空字符串 → 原样空串（不加引号），与"无字段值"语义一致；
/// - **不做 trim**：用户日志里可能就是要保留前后空格（比如缩进示例）。
///
/// 测试覆盖：纯文本 / 含逗号 / 含引号 / 含换行 / 引号 + 逗号同时 / 空串。
@visibleForTesting
String escapeCsvField(String value) {
  final needsQuote = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuote) return value;
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

/// 把日志条目列表渲染成 CSV 文本。
///
/// **契约**：
/// - 第 1 行恒为表头：`revision,author,date,title,message`（5 列）。
/// - 数据行顺序与入参 [entries] **完全一致**——不重新排序。调用方应在
///   传入前已经按需求排好序（如"revision 降序"）。
/// - 行分隔符 = `\r\n`（RFC 4180 规范，Excel/Numbers 兼容性最好）。
/// - 字段顺序固定 5 列：revision (int 直接 toString) / author / date / title /
///   message。message 字段会保留其内部的 `\n`（CSV 行内换行靠 `"..."` 包裹）。
/// - 空 `entries` → 仍输出表头行 + 末尾 `\r\n`，**不**返回空串：
///   下游写文件时拿到空文件会让用户误以为"导出失败"，输出"只有表头"明确表明
///   "过滤后 0 条"。
/// - **结尾保留** `\r\n`：与 RFC 4180 一致，最后一条记录后跟 CRLF。
///
/// **不加 @visibleForTesting**：本函数被 `screens/main_screen_v3.dart` 跨库
/// 直接调用（导出 CSV 入口），加注解会触发 `invalid_use_of_visible_for_testing_member`
/// 警告。
String formatLogEntriesAsCsv(Iterable<LogEntry> entries) {
  final buffer = StringBuffer();
  buffer.write('revision,author,date,title,message\r\n');
  for (final e in entries) {
    buffer.write(e.revision.toString());
    buffer.write(',');
    buffer.write(escapeCsvField(e.author));
    buffer.write(',');
    buffer.write(escapeCsvField(e.date));
    buffer.write(',');
    buffer.write(escapeCsvField(e.title));
    buffer.write(',');
    buffer.write(escapeCsvField(e.message));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

/// 生成默认 CSV 导出文件名 `svn-log-{yyyyMMdd-HHmmss}.csv`。
///
/// **契约**：[now] 由调用方传入，便于单测断言精确文件名（不读 `DateTime.now()`）。
/// 仅采用本地时区的 year / month / day / hour / minute / second，零填充至 2 位。
/// **不**做时区后缀——文件名是给用户看的，本地时间最直观。
///
/// **不加 @visibleForTesting**：本函数被 `screens/main_screen_v3.dart` 跨库直接
/// 调用（生成默认文件名），加注解会触发跨库警告。
String formatCsvExportFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return 'svn-log-$stamp.csv';
}

/// 是否存在任意"活跃的文本过滤条件"——即 3 个文本框（提交者 / 标题 / 内容）
/// 中至少有一个 trim 后非空。
///
/// **用途**：log_list_panel 的"清空筛选"按钮渲染谓词——只在用户实际输入了
/// 过滤条件时才启用按钮，避免空状态下按钮可点但不产生任何变化。
///
/// **不**包含 `minRevision`（来自 stopOnCopy checkbox，是独立的 UI 状态，
/// 用户应通过 checkbox 显式切换而非"清空筛选"一键带走）。
///
/// **不**用 `LogFilter` 对象作为入参——caller 在 UI 层只持有
/// `TextEditingController.text` 字符串，先聚合再决定是否启用按钮，避免在
/// `setFilter` 之前先组装一个临时 `LogFilter` 仅为查询是否为空。
bool hasActiveLogTextFilter({
  String? author,
  String? title,
  String? message,
}) {
  return !isStringFilterEmpty(author) ||
      !isStringFilterEmpty(title) ||
      !isStringFilterEmpty(message);
}

/// 过滤条件
class LogFilter {
  final String? author;
  final String? title;
  /// commit message 全文搜索（对 message 列做 LIKE %toLowerCase()% 匹配，不 trim，
  /// 与 title 列同口径——用户在 UI"搜索内容"框输入的原文直接落地）
  final String? message;
  /// 最小版本号（用于 stopOnCopy 过滤，排除此版本之前的记录）
  final int? minRevision;
  const LogFilter({
    this.author,
    this.title,
    this.message,
    this.minRevision,
  });

  /// 是否为空（无过滤条件）
  bool get isEmpty =>
      isStringFilterEmpty(author) &&
      isStringFilterEmpty(title) &&
      isStringFilterEmpty(message) &&
      minRevision == null;

  /// 复制并修改
  LogFilter copyWith({
    String? author,
    String? title,
    String? message,
    int? minRevision,
    bool clearMinRevision = false,
  }) {
    return LogFilter(
      author: author ?? this.author,
      title: title ?? this.title,
      message: message ?? this.message,
      minRevision: clearMinRevision ? null : (minRevision ?? this.minRevision),
    );
  }
  
  @override
  String toString() {
    return 'LogFilter(author: $author, title: $title, message: $message, minRevision: $minRevision)';
  }
}

/// 分页结果
class PaginatedResult {
  final List<LogEntry> entries;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final int totalPages;
  /// 是否还有更多数据
  final bool hasMore;

  const PaginatedResult({
    required this.entries,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    required this.totalPages,
    this.hasMore = true,
  });
}

/// 日志过滤和分页服务
/// 
/// 设计原则：只负责从缓存读取和过滤数据，不触发任何网络请求
class LogFilterService {
  final LogCacheService _cacheService = LogCacheService();
  
  // COPY_TAIL 缓存：key = workingDirectory, value = branchPoint revision（分支分界点）
  // 注意：这是非持久化的内存缓存，应用重启后会自动清空
  static final Map<String, int?> _copyTailCache = {};

  /// 获取过滤后的日志条目（分页）
  /// 
  /// [sourceUrl] 源 URL
  /// [filter] 过滤条件（包含 author、title、minRevision）
  /// [page] 页码（从 0 开始）
  /// [pageSize] 每页大小
  /// 
  /// 返回分页结果
  /// 
  /// 注意：
  /// - 此方法只从缓存读取数据，不触发任何网络请求
  /// - 只展示最新区间内的数据
  Future<PaginatedResult> getPaginatedEntries(
    String sourceUrl,
    LogFilter filter,
    int page,
    int pageSize,
  ) async {
    try {
      AppLogger.storage.info(appLogSeparator);
      for (final line in formatPaginatedEntriesHeaderLines(
        sourceUrl: sourceUrl,
        page: page,
        pageSize: pageSize,
        filter: filter,
      )) {
        AppLogger.storage.info(line);
      }
      
      // 初始化缓存服务
      await _cacheService.init();

      // 1. 获取符合过滤条件的总数（只统计最新区间内的数据）
      final totalCount = await _cacheService.getEntryCountInLatestRange(
        sourceUrl,
        authorFilter: filter.author,
        titleFilter: filter.title,
        messageFilter: filter.message,
        minRevision: filter.minRevision,
      );
      
      AppLogger.storage.info(formatPaginatedEntriesTotalCountLine(totalCount));
      
      // 2. 计算分页方案（总页数 / 生效页 / offset / hasMore）
      final plan = computePaginationPlan(
        totalCount: totalCount,
        pageSize: pageSize,
        requestedPage: page,
      );

      if (plan.adjustedPage != page) {
        AppLogger.storage.info(formatPageAdjustmentLine(
          requestedPage: page,
          adjustedPage: plan.adjustedPage,
          totalPages: plan.totalPages,
        ));
      }

      // 3. 从缓存获取当前页数据（只获取最新区间内的数据）
      final entries = await _cacheService.getEntriesInLatestRange(
        sourceUrl,
        limit: pageSize,
        offset: plan.offset,
        authorFilter: filter.author,
        titleFilter: filter.title,
        messageFilter: filter.message,
        minRevision: filter.minRevision,
      );

      AppLogger.storage.info(formatPaginatedEntriesResultLine(
        entriesCount: entries.length,
        adjustedPage: plan.adjustedPage,
        totalPages: plan.totalPages,
        hasMore: plan.hasMore,
      ));
      AppLogger.storage.info(appLogSeparator);

      return PaginatedResult(
        entries: entries,
        totalCount: totalCount,
        currentPage: plan.adjustedPage,
        pageSize: pageSize,
        totalPages: plan.totalPages,
        hasMore: plan.hasMore,
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取分页日志失败', e, stackTrace);
      return PaginatedResult(
        entries: [],
        totalCount: 0,
        currentPage: 0,
        pageSize: pageSize,
        totalPages: 0,
        hasMore: false,
      );
    }
  }

  /// 获取过滤后的总数（不返回具体条目，只返回数量）
  /// 
  /// 注意：只统计最新区间内的数据
  Future<int> getFilteredCount(
    String sourceUrl,
    LogFilter filter,
  ) async {
    try {
      await _cacheService.init();
      return await _cacheService.getEntryCountInLatestRange(
        sourceUrl,
        authorFilter: filter.author,
        titleFilter: filter.title,
        messageFilter: filter.message,
        minRevision: filter.minRevision,
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取过滤后数量失败', e, stackTrace);
      return 0;
    }
  }

  /// 获取所有符合过滤条件的日志条目（**不分页**），按 revision 降序。
  ///
  /// 与 [getPaginatedEntries] 共用底层 `getEntriesInLatestRange` + 过滤参数，
  /// 但**不**传 `limit` —— 一次性返回所有匹配条目，供 CSV 导出使用。
  ///
  /// **为什么需要独立 API**：[getPaginatedEntries] 受 `pageSize` 约束（典型 50/100），
  /// 用户导出 CSV 时希望拿到"过滤后全部"而非"当前页"。复用 cacheService 的
  /// `limit: null` 路径即可避免分页拼装的 offset 计算开销。
  ///
  /// **失败兜底**：异常时返回空列表（与 [getPaginatedEntries] 的 catch 路径同款），
  /// caller 应通过返回长度判断"无数据"。
  Future<List<LogEntry>> getAllFilteredEntries(
    String sourceUrl,
    LogFilter filter,
  ) async {
    try {
      await _cacheService.init();
      return await _cacheService.getEntriesInLatestRange(
        sourceUrl,
        // limit 留空 = 不分页
        authorFilter: filter.author,
        titleFilter: filter.title,
        messageFilter: filter.message,
        minRevision: filter.minRevision,
      );
    } catch (e, stackTrace) {
      AppLogger.storage.error('获取过滤后全部条目失败', e, stackTrace);
      return [];
    }
  }

  /// 缓存分支点（供外部调用，如 SvnService 查询后缓存）
  static void cacheBranchPoint(String workingDirectory, int? branchPoint) {
    _copyTailCache[workingDirectory] = branchPoint;
    AppLogger.storage.info(formatBranchPointCacheSetLine(
      workingDirectory: workingDirectory,
      branchPoint: branchPoint,
    ));
  }
  
  /// 获取缓存的分支点
  static int? getCachedBranchPoint(String? workingDirectory) {
    if (!isUsableWorkingDirectory(workingDirectory)) {
      return null;
    }
    return _copyTailCache[workingDirectory];
  }
  
  /// 清除分支点缓存
  static void clearBranchPointCache({String? workingDirectory}) {
    if (isUsableWorkingDirectory(workingDirectory)) {
      _copyTailCache.remove(workingDirectory);
    } else {
      _copyTailCache.clear();
    }
    AppLogger.storage.info(formatBranchPointCacheClearLine(workingDirectory));
  }

  /// 获取缓存中的总条目数（不带过滤）
  /// 
  /// 注意：只统计最新区间内的数据
  Future<int> getTotalCount(String sourceUrl) async {
    await _cacheService.init();
    return await _cacheService.getLatestRangeEntryCount(sourceUrl);
  }

  /// 根据 revision 列表获取日志条目
  Future<List<LogEntry>> getEntriesByRevisions(
    String sourceUrl,
    List<int> revisions,
  ) async {
    await _cacheService.init();
    return await _cacheService.getEntriesByRevisions(sourceUrl, revisions);
  }
}

