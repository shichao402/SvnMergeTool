/// 应用全局状态管理
///
/// 使用 Provider 管理应用的全局状态，包括：
/// - 配置
/// - 历史记录
/// - 当前选择

import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import '../models/log_entry.dart';
import '../models/merge_config.dart';
import '../services/config_service.dart';
import '../services/storage_service.dart';
import '../services/log_filter_service.dart';
import '../services/logger_service.dart';
import '../services/mergeinfo_cache_service.dart';

@visibleForTesting
class MergeInfoSelection {
  final String sourceUrl;
  final String targetWc;

  const MergeInfoSelection({
    required this.sourceUrl,
    required this.targetWc,
  });
}

@visibleForTesting
MergeInfoSelection? resolveMergeInfoSelection({
  required String? currentSourceUrl,
  required String? currentTargetWc,
  String? sourceUrl,
  String? targetWc,
}) {
  final resolvedSourceUrl = (sourceUrl ?? currentSourceUrl ?? '').trim();
  final resolvedTargetWc = (targetWc ?? currentTargetWc ?? '').trim();

  if (resolvedSourceUrl.isEmpty || resolvedTargetWc.isEmpty) {
    return null;
  }

  return MergeInfoSelection(
    sourceUrl: resolvedSourceUrl,
    targetWc: resolvedTargetWc,
  );
}

/// 把 `incoming` 增量合入 `existing` 后返回升序去重的 revision 列表。
///
/// 行为契约（与原 `addPendingRevisions` 完全一致）：
/// - 不修改入参（纯函数，返回新 list）。
/// - 已经存在的 revision 不会重复添加。
/// - 结果总是升序，**不保留** existing 原本的相对顺序——
///   原实现是 `add then sort()`，因此此处也直接全量排序。
/// - existing 自身若已有重复，结果同样会去重（防御性）。
///
/// `existing` 与 `incoming` 都允许为空 list；任一为空时仍走同一逻辑。
@visibleForTesting
List<int> mergePendingRevisions(List<int> existing, List<int> incoming) {
  final merged = <int>{...existing, ...incoming}.toList()..sort();
  return merged;
}

/// 从 `existing` 中移除 `toRemove` 中出现的 revision，返回新 list。
///
/// 行为契约（与原 `removePendingRevisions` 完全一致）：
/// - 不修改入参。
/// - 保留 existing 中未被移除项的原有顺序（不做排序）。
/// - `toRemove` 为空时返回 existing 的浅拷贝。
@visibleForTesting
List<int> removeRevisionsFromPending(List<int> existing, List<int> toRemove) {
  if (toRemove.isEmpty) {
    return List<int>.from(existing);
  }
  final removeSet = toRemove.toSet();
  return existing.where((rev) => !removeSet.contains(rev)).toList();
}

/// `setCurrentPage` 的页号上限——防御性 clamp 上界。
///
/// 选 999999 而非 `int.maxValue`：日志已经在万级页码就完全失去可用性，
/// 保留一个"显然异常"的上界让 hot-loop 类的页码错误能被发现而不是默默累积。
@visibleForTesting
const int maxPageIndex = 999999;

/// 把任意外部传入的 `page` 参数夹到 `[0, maxPageIndex]`。
///
/// 与原 `_currentPage = page.clamp(0, 999999)` 完全等价；抽出来后可以单测覆盖
/// 负数 / 超大值 / 边界三类输入，并把"为什么不是 int.maxValue"这条决策落到
/// 文档里。
@visibleForTesting
int clampPageIndex(int page) => page.clamp(0, maxPageIndex);

/// `AppState.hasMore` 在 `_paginatedResult == null` 时的兜底公式。
///
/// **契约**：当还没有任何分页结果（首次加载前 / 失败后）时，仅依据"当前页 +
/// 总页数"判断是否能翻下一页。
///
/// **边界决策**：
/// - `totalPages = 0`（还没有数据）→ 公式 `currentPage < -1` 永远 false → 返回 false。
///   这一行为锁死：任何把 `-1` 改成 `0`、或者把 `<` 改成 `<=` 的"修复"都会让
///   `hasMore` 在空数据时错误地返回 true，触发空翻页。
/// - `totalPages = 1, currentPage = 0` → `0 < 0` = false（已经在唯一一页）。
/// - `totalPages = 5, currentPage = 4` → `4 < 4` = false（已经是最后一页）。
/// - `totalPages = 5, currentPage = 3` → `3 < 4` = true（还能翻）。
@visibleForTesting
bool computeFallbackHasMore({
  required int currentPage,
  required int totalPages,
}) =>
    currentPage < totalPages - 1;

/// `updateCachedTotalCount` 中的"是否要更新当前 source 缓存"守卫。
///
/// **契约**：仅当 `incomingUrl` 与 `currentLastUrl` 一致，**或**当前还没有
/// `currentLastUrl`（应用刚启动 / 切换源后的瞬态）时，才允许写入。这是为了避免
/// **预加载服务回填总数时把别的源的数字写到当前 source 上**——典型场景：
/// 用户切换 source 的同时上一个源的预加载还没结束，此时应该忽略迟到的数据。
///
/// 不允许把 `null` `incomingUrl` 当通配符——上游所有调用方都明确传入了 source URL。
@visibleForTesting
bool shouldUpdateCachedCountForSource({
  required String? currentLastUrl,
  required String incomingUrl,
}) =>
    currentLastUrl == incomingUrl || currentLastUrl == null;

/// 计算"下一页"的页号；返回 `null` 表示没有下一页可翻（调用方应跳过状态变更）。
///
/// 与 `AppState.nextPage` 内联条件 `if (hasMore) _currentPage++;` 严格等价，
/// 但把"加一"和"是否能翻"两件事分成了纯函数 + 命令式 IO 两段。
@visibleForTesting
int? nextPageIndex({required int currentPage, required bool hasMore}) =>
    hasMore ? currentPage + 1 : null;

/// 计算"上一页"的页号；返回 `null` 表示已经在第 0 页（调用方应跳过状态变更）。
///
/// **契约**：仅依据 `currentPage > 0` 判断——**不**与 `hasMore` / `totalPages`
/// 关联。如果用户当前停在 page 5 而 totalPages 后来缩到 3，`previousPage` 仍能
/// 正常往回翻；这与原 `if (_currentPage > 0) _currentPage--;` 一致。
@visibleForTesting
int? previousPageIndex({required int currentPage}) =>
    currentPage > 0 ? currentPage - 1 : null;

/// 把 `refreshLogEntries` 入口的 4 行 `info('  ...')` dump 渲染成字符串列表。
///
/// **契约**：4 行顺序固定（标题 / sourceUrl / filter / page+pageSize 合并）；
/// 标题恒为 `'【refreshLogEntries】开始从缓存读取日志'` 且**不带缩进**——与
/// `formatPaginatedEntriesHeaderLines` 同构（段标题 + 缩进列表）；`filter`
/// 走 `toString()`，不做 `isEmpty` 分支。
@visibleForTesting
List<String> formatRefreshLogEntriesHeaderLines({
  required String sourceUrl,
  required LogFilter filter,
  required int page,
  required int pageSize,
}) {
  return [
    '【refreshLogEntries】开始从缓存读取日志',
    '  sourceUrl: $sourceUrl',
    '  filter: $filter',
    '  page: $page, pageSize: $pageSize',
  ];
}

/// 判断 [sourceUrl] 是否「可用作刷新日志的源」。
///
/// **核心契约**：仅当 [sourceUrl] 非 null **且** 非空字符串时返回 true。
///
/// **为什么这个谓词单独抽**：原 `app_state.dart` 在 5 个 setter
/// （`updateFilter` / `setMinRevision` / `setCurrentPage` / `nextPage` / `previousPage`）
/// 内联了同一句 `sourceUrl != null && sourceUrl.isNotEmpty` 反向表达——这 5 处
/// 共享同一份"是否值得调 [refreshLogEntries] vs 仅 [notifyListeners]"决策。
/// 任何一处把 `&&` 误改成 `||`、或把 `isNotEmpty` 漏掉，都会让"页码 setter
/// 在源 URL 为空时也去做磁盘 I/O"——尤其是 `setCurrentPage` 在 UI 拖滑动条
/// 时高频触发，回归风险面 ×5。
///
/// **R88 漏迁巡检收口**：R86 标记 `screens/main_screen_v3.dart:690` 的 `_initializeFields`
/// 也内联了同一形态判定（`appState.lastSourceUrl != null && appState.lastSourceUrl!.isNotEmpty`，
/// 决定"用 lastSourceUrl 还是 fallback 到 config preset 填表单"），与本谓词
/// 行为完全等价但当时因 `@visibleForTesting` 跨库分析警告未迁。R88 主动放弃
/// `@visibleForTesting`（详见下方），把第 6 处 callsite 收回——此后 callsite
/// 数为 6（app_state.dart × 5 + main_screen_v3.dart × 1）。
///
/// **为什么不直接复用 [isUsableWorkingDirectory]**：两者签名同形（`String? -> bool`），
/// 但语义不同——
/// - `isUsableWorkingDirectory` 用作 SVN 工作副本路径的"可用作缓存键"判定；
/// - `isUsableSourceUrl` 用作"日志刷新触发条件"判定。
///
/// 跨模块复用一个 `isUsableNonEmptyString` 之类的通名 helper 会让 callsite
/// 失去语义自描述能力（"这次到底防的是哪种空？"），按设计模式 #9 拒绝合并。
///
/// **为什么主动放弃 `@visibleForTesting`（R88）**：跨库 caller `main_screen_v3.dart`
/// 在生产代码中调用本谓词后，`@visibleForTesting` 会触发 analyzer
/// `invalid_use_of_visible_for_testing_member`（与 R84 `clampedCompletedRevisionCount`
/// 同坑）。本谓词已经是公认的"可用 SourceUrl"判定标准，跨库用是设计本意。
/// 单测仍可通过普通 import 访问。
bool isUsableSourceUrl(String? sourceUrl) =>
    sourceUrl != null && sourceUrl.isNotEmpty;

/// R128 provider notifyListeners 触发协议三档分类（AppState 维度）
///
/// 全部 21 处 `notifyListeners()` 调用按"是否同步 / 是否条件化 / 是否在 finally"
/// 三个轴分到三档：
///
/// - **档 1 sync 直接 notify**（最常见，约 12 处）：同步路径改字段后无条件
///   notify。形态：`_field = value; notifyListeners();` 或 `await persist(); _field
///   = value; notifyListeners();`（await 之后已经是新一轮事件，每段 await 后的
///   notify 等同于一次 sync mutator + notify）。例子：`addPendingRevisions` /
///   `removePendingRevisions` / `clearPendingRevisions` / `setPageSize` /
///   `saveSourceUrlToHistory` / `saveTargetWcToHistory` / `refreshConfig` 等。
///
/// - **档 2 conditional notify (guard-skip 或 guard-delegate)**（约 7 处）：
///   同步路径，但通过条件判断决定 notify / 跳过 / 委托。三种 sub-variant:
///   * **skip-on-noop**: 值未变就不 notify（例：`setLoadingData`——`if
///     (_isLoadingData != isLoading)` 包裹）。无变化时无 notify，避免 listener
///     无效抖动。
///   * **guard-delegate**: 满足条件走 await 路径（路径内含 notify），否则同步
///     notify（例：`setFilter` / `setMinRevision` / `setCurrentPage` / `nextPage`
///     / `previousPage`——若 `isUsableSourceUrl(sourceUrl)` 则 await
///     `refreshLogEntries`，否则 else 分支 notify）。两路径都最终 notify、不会
///     双 notify、不会漏 notify。
///   * **guard-on-relevance**: 外部参数与当前不匹配就不 notify（例：
///     `updateCachedTotalCount`——`shouldUpdateCachedCountForSource` 守卫）。
///
/// - **档 3 async bracket (loading-flag 进入态 + finally 完成态)**（2 处）：
///   async 工作前 set loading=true + notify、finally set loading=false + notify。
///   双 notify 形态，UI 通过 loading 标志切换 spinner。例子：`init`（finally
///   `Future.microtask(notifyListeners)`，与档 3 略有差异——init 没有"进入态
///   notify"因为构造期 listener 还没 attach）/ `loadMergeInfo`（标准档 3：
///   `_isMergeInfoLoading = true; notify; try { await ... } finally {
///   _isMergeInfoLoading = false; notify; }`）。
///
/// **判据**（拿到一处 notify 站点反向判档）：
/// 1. 在 try-finally 的 finally 块？→ 档 3。
/// 2. 紧跟 if 守卫且只在条件成立时执行？→ 档 2。
/// 3. 同步路径无条件执行？→ 档 1。
///
/// **跨档不变量**（所有档共同律）：
/// - **notify 之前 mutator 必须已写完**（永远先改字段、后 notify；与 R127 init
///   "log < notify" 律同形——状态固化先于对外动作）。
/// - **notify 之后不再写"会被 listener 立即读"的字段**（避免 listener 链中
///   读到 stale 值，多档下 notify 应放方法体末位或 finally 末位）。
/// - **每个 mutator 至少有一条到达 notify 的路径**（档 1 必 notify、档 2 双路径
///   都终结于 notify、档 3 finally 必 notify）。
///
/// 顺序锁见 `test/app_state_notify_protocol_test.dart`。
class AppState extends ChangeNotifier {
  final ConfigService _configService;
  final StorageService _storageService;
  final MergeInfoCacheService _mergeInfoService;

  AppState({
    ConfigService? configService,
    StorageService? storageService,
    MergeInfoCacheService? mergeInfoService,
  })  : _configService = configService ?? ConfigService(),
        _storageService = storageService ?? StorageService(),
        _mergeInfoService = mergeInfoService ?? MergeInfoCacheService();

  AppConfig? _config;
  List<String> _sourceUrlHistory = [];
  List<String> _switchBranchHistory = [];
  List<String> _targetWcHistory = [];
  List<String> _targetUrlHistory = [];
  String? _lastSourceUrl;
  String? _lastTargetWc;
  String? _lastTargetUrl;
  List<int> _pendingRevisions = [];
  bool _useTemporarySparseWorkingCopy = false;
  int _sourceUrlMutationVersion = 0;
  int _switchBranchMutationVersion = 0;
  int _targetWcMutationVersion = 0;
  int _targetUrlMutationVersion = 0;
  int _temporarySparseModeMutationVersion = 0;

  // 分页相关
  int _currentPage = 0;
  int _pageSize = 50;

  // 过滤条件（包含 author、title、minRevision）
  LogFilter _filter = const LogFilter();

  // 当前分页结果
  PaginatedResult? _paginatedResult;

  // 独立维护的总数和总页数（用于预加载时同步更新）
  int _cachedTotalCount = 0;
  int _cachedTotalPages = 0;

  // 日志过滤服务（纯本地操作，不触发网络请求）
  final LogFilterService _filterService = LogFilterService();

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;
  bool _isLoadingData = false; // 是否正在从 SVN 获取数据（由外部设置）
  bool _isMergeInfoLoading = false; // 是否正在加载 mergeinfo

  // Getters
  AppConfig? get config => _config;
  List<String> get sourceUrlHistory => _sourceUrlHistory;
  List<String> get switchBranchHistory => _switchBranchHistory;
  List<String> get targetWcHistory => _targetWcHistory;
  List<String> get targetUrlHistory => _targetUrlHistory;
  String? get lastSourceUrl => _lastSourceUrl;
  String? get lastTargetWc => _lastTargetWc;
  String? get lastTargetUrl => _lastTargetUrl;
  SourceConfig get sourceConfig => SourceConfig(url: _lastSourceUrl ?? '');
  TargetConfig get targetConfig => _useTemporarySparseWorkingCopy
      ? TargetConfig.sparseTemporary(_lastTargetUrl ?? '')
      : TargetConfig.fullWorkingCopy(_lastTargetWc ?? '');
  List<int> get pendingRevisions => _pendingRevisions;
  bool get useTemporarySparseWorkingCopy => _useTemporarySparseWorkingCopy;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  LogFilter get filter => _filter;
  PaginatedResult? get paginatedResult => _paginatedResult;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoadingData => _isLoadingData; // 是否正在从 SVN 获取数据
  bool get isMergeInfoLoading => _isMergeInfoLoading; // 是否正在加载 mergeinfo
  MergeInfoCacheService get mergeInfoService => _mergeInfoService;

  /// 获取当前页的日志条目
  List<LogEntry> get paginatedLogEntries => _paginatedResult?.entries ?? [];

  /// 获取总页数（优先使用 _paginatedResult，否则使用缓存值）
  int get totalPages => _paginatedResult?.totalPages ?? _cachedTotalPages;

  /// 是否还有更多数据（可以翻到下一页）
  bool get hasMore =>
      _paginatedResult?.hasMore ??
      computeFallbackHasMore(currentPage: currentPage, totalPages: totalPages);

  /// 获取过滤后的总数（优先使用 _paginatedResult，否则使用缓存值）
  int get filteredTotalCount =>
      _paginatedResult?.totalCount ?? _cachedTotalCount;

  /// 是否有总页数信息
  bool get hasTotalPages => totalPages > 0;

  /// 是否有总数信息
  bool get hasTotalCount => filteredTotalCount > 0;

  /// 更新缓存的总数（供预加载服务调用）
  ///
  /// [sourceUrl] 源 URL（用于验证是否是当前显示的数据源）
  /// [totalCount] 新的总数
  /// [pageSize] 每页大小（用于计算总页数）
  ///
  /// 总页数计算复用 `log_filter_service.computePaginationPlan` 的规则，
  /// 与 `LogFilterService.getPaginatedEntries` 保持口径一致；调用者必须保证
  /// `effectivePageSize > 0`（这是 AppState 的内部不变量）。
  void updateCachedTotalCount(String sourceUrl, int totalCount,
      {int? pageSize}) {
    // 只有当前显示的数据源才更新
    if (shouldUpdateCachedCountForSource(
        currentLastUrl: _lastSourceUrl, incomingUrl: sourceUrl)) {
      _cachedTotalCount = totalCount;
      final effectivePageSize = pageSize ?? _pageSize;
      _cachedTotalPages = computePaginationPlan(
        totalCount: totalCount,
        pageSize: effectivePageSize,
        requestedPage: 0,
      ).totalPages;
      notifyListeners();
    }
  }

  /// 根据 revision 列表获取日志条目
  ///
  /// [sourceUrl] 源 URL
  /// [revisions] revision 列表
  ///
  /// 返回匹配的日志条目列表（按 revision 降序排列）
  ///
  /// 注意：只从缓存读取，不触发远端获取
  Future<List<LogEntry>> getEntriesByRevisions(
    String sourceUrl,
    List<int> revisions,
  ) async {
    return await _filterService.getEntriesByRevisions(sourceUrl, revisions);
  }

  /// 获取所有符合**当前过滤器**的日志条目（不分页），按 revision 降序。
  ///
  /// 用于"导出 CSV"等需要拿到全集而非当前页的场景。复用 [filter] 状态，
  /// 调用方不必关心 page / pageSize。
  Future<List<LogEntry>> getAllFilteredEntries(String sourceUrl) async {
    return await _filterService.getAllFilteredEntries(sourceUrl, _filter);
  }

  /// 初始化应用状态
  ///
  /// R127 启动方向单调原则（provider 维度）: **load → derive → delegate →
  /// flag → log → notify** —— 与 R126 service 维度 `path → handle → memory →
  /// log` 同一族律（数据流入向单调），但 provider 的特化形式：
  ///
  /// 1. **load** (config + history) —— 从 service 拉数据，必须在所有 derive 前。
  /// 2. **derive** (`_pageSize ← config.settings.logPageSize`) —— 依赖第 1
  ///    步的载入结果，绝不能跑在 `loadConfig()` 之前。
  /// 3. **delegate** (`_mergeInfoService.init()`) —— provider 自己 load 完才
  ///    去 init 下游 service；与 R126 服务自身的 init 顺序衔接（service 维度的
  ///    init 是被 provider 维度 init 嵌套调用的，两层 R126/R127 共组成完整启动栈）。
  /// 4. **flag** (`_isInitialized = true`) —— 必须在最终 success log 之前，
  ///    否则成功日志记录的状态与 flag 不一致。
  /// 5. **log** "应用初始化成功" —— flag 已立后再宣告（与 R126 共享末位 log
  ///    定律：末位是"对外宣告状态"）。
  /// 6. **notify** (`Future.microtask(notifyListeners)`) —— 末位中的末位，
  ///    必须放 finally 里、必须 microtask 化（避开 build 期），与 R119 档 1
  ///    的 fire-and-forget 思路同源。
  ///
  /// 顺序锁见 `test/app_state_init_sequence_test.dart`。
  Future<void> init() async {
    if (_isInitialized) return;

    _isLoading = true;
    final sourceUrlLoadVersion = _sourceUrlMutationVersion;
    final switchBranchLoadVersion = _switchBranchMutationVersion;
    final targetWcLoadVersion = _targetWcMutationVersion;
    final targetUrlLoadVersion = _targetUrlMutationVersion;
    final temporarySparseModeLoadVersion = _temporarySparseModeMutationVersion;
    // 不要在 build 期间调用 notifyListeners，使用 Future.microtask 延迟通知

    try {
      // 加载配置
      _config = await _configService.loadConfig();

      // 从配置加载分页大小（固定为配置值，用户不可修改）
      _pageSize = _config?.settings.logPageSize ?? kDefaultLogPageSize;
      AppLogger.app.info('从配置加载分页大小: $_pageSize');

      // 加载历史记录。字段级版本保护用于避免 init 的旧快照覆盖用户刚输入的新值。
      final loadedSourceUrlHistory =
          await _storageService.getSourceUrlHistory();
      final loadedSwitchBranchHistory =
          await _storageService.getSwitchBranchHistory();
      final loadedTargetWcHistory = await _storageService.getTargetWcHistory();
      final loadedTargetUrlHistory =
          await _storageService.getTargetUrlHistory();
      final loadedLastSourceUrl = await _storageService.getLastSourceUrl();
      final loadedLastTargetWc = await _storageService.getLastTargetWc();
      final loadedLastTargetUrl = await _storageService.getLastTargetUrl();
      final loadedUseTemporarySparseWorkingCopy =
          await _storageService.getUseTemporarySparseWorkingCopy();
      if (sourceUrlLoadVersion == _sourceUrlMutationVersion) {
        _sourceUrlHistory = loadedSourceUrlHistory;
        _lastSourceUrl = loadedLastSourceUrl;
      }
      if (switchBranchLoadVersion == _switchBranchMutationVersion) {
        _switchBranchHistory = loadedSwitchBranchHistory;
      }
      if (targetWcLoadVersion == _targetWcMutationVersion) {
        _targetWcHistory = loadedTargetWcHistory;
        _lastTargetWc = loadedLastTargetWc;
      }
      if (targetUrlLoadVersion == _targetUrlMutationVersion) {
        _targetUrlHistory = loadedTargetUrlHistory;
        _lastTargetUrl = loadedLastTargetUrl;
      }
      if (temporarySparseModeLoadVersion ==
          _temporarySparseModeMutationVersion) {
        _useTemporarySparseWorkingCopy = loadedUseTemporarySparseWorkingCopy;
      }

      // 初始化 MergeInfo 缓存服务
      await _mergeInfoService.init();

      _isInitialized = true;
      _error = null;
      AppLogger.app.info('应用初始化成功');
    } catch (e, stackTrace) {
      _error = '初始化失败：$e';
      AppLogger.app.error('应用初始化失败', e, stackTrace);
    } finally {
      _isLoading = false;
      // 延迟通知，避免在 build 期间调用
      Future.microtask(() => notifyListeners());
    }
  }

  /// 刷新日志列表（从缓存读取并应用过滤和分页）
  ///
  /// [sourceUrl] 源 URL
  ///
  /// 注意：此方法只从缓存读取数据，不触发任何网络请求
  /// 过滤条件（包括 minRevision）已经在 _filter 中设置
  Future<void> refreshLogEntries(String sourceUrl) async {
    try {
      for (final line in formatRefreshLogEntriesHeaderLines(
        sourceUrl: sourceUrl,
        filter: _filter,
        page: _currentPage,
        pageSize: _pageSize,
      )) {
        AppLogger.app.info(line);
      }

      _paginatedResult = await _filterService.getPaginatedEntries(
        sourceUrl,
        _filter,
        _currentPage,
        _pageSize,
      );

      // 同步更新缓存的总数和总页数
      if (_paginatedResult != null) {
        _cachedTotalCount = _paginatedResult!.totalCount;
        _cachedTotalPages = _paginatedResult!.totalPages;
        AppLogger.app.info(
            '  结果: ${_paginatedResult!.entries.length} 条, 总数: $_cachedTotalCount, 总页数: $_cachedTotalPages');
      } else {
        AppLogger.app.info('  结果: null');
      }

      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.app.error('刷新日志列表失败', e, stackTrace);
    }
  }

  /// 设置过滤条件
  ///
  /// [author] 作者过滤
  /// [title] 标题过滤
  /// [message] commit 内容全文搜索
  /// [minRevision] 最小版本号（用于 stopOnCopy 过滤）
  /// [sourceUrl] 源 URL（如果提供，会刷新日志列表）
  Future<void> setFilter({
    String? author,
    String? title,
    String? message,
    int? minRevision,
    bool clearMinRevision = false,
    String? sourceUrl,
  }) async {
    _filter = LogFilter(
      author: author,
      title: title,
      message: message,
      minRevision: clearMinRevision ? null : minRevision,
    );
    _currentPage = 0; // 重置到第一页

    if (isUsableSourceUrl(sourceUrl)) {
      await refreshLogEntries(sourceUrl!);
    } else {
      notifyListeners();
    }
  }

  /// 更新 minRevision（保留其他过滤条件）
  Future<void> setMinRevision(int? minRevision, {String? sourceUrl}) async {
    _filter = _filter.copyWith(
      minRevision: minRevision,
      clearMinRevision: minRevision == null,
    );
    _currentPage = 0; // 重置到第一页

    if (isUsableSourceUrl(sourceUrl)) {
      await refreshLogEntries(sourceUrl!);
    } else {
      notifyListeners();
    }
  }

  /// 设置数据加载状态（供外部调用）
  void setLoadingData(bool isLoading) {
    if (_isLoadingData != isLoading) {
      _isLoadingData = isLoading;
      notifyListeners();
    }
  }

  MergeInfoSelection? _resolveMergeInfoSelection({
    String? sourceUrl,
    String? targetWc,
  }) {
    return resolveMergeInfoSelection(
      currentSourceUrl: _lastSourceUrl,
      currentTargetWc: _lastTargetWc,
      sourceUrl: sourceUrl,
      targetWc: targetWc,
    );
  }

  /// 同步检查 revision 是否已合并（仅从内存缓存）
  ///
  /// 这是一个同步方法，用于 UI 渲染时快速判断合并状态
  /// 如果缓存未加载，返回 false
  bool isRevisionMergedSync(
    int revision, {
    String? sourceUrl,
    String? targetWc,
  }) {
    final selection =
        _resolveMergeInfoSelection(sourceUrl: sourceUrl, targetWc: targetWc);
    if (selection == null) {
      return false;
    }
    return _mergeInfoService.isRevisionMergedSync(
      selection.sourceUrl,
      selection.targetWc,
      revision,
    );
  }

  /// 同步获取已合并的 revision 集合（仅从内存缓存）
  ///
  /// 这是一个同步方法，用于 UI 渲染
  Set<int> getMergedRevisionsSync({
    String? sourceUrl,
    String? targetWc,
  }) {
    final selection =
        _resolveMergeInfoSelection(sourceUrl: sourceUrl, targetWc: targetWc);
    if (selection == null) {
      return {};
    }
    return _mergeInfoService.getMergedRevisionsSync(
      selection.sourceUrl,
      selection.targetWc,
    );
  }

  /// 检查 revision 是否已合并
  ///
  /// 从 MergeInfoCacheService 获取合并状态
  Future<bool> isRevisionMerged(
    int revision, {
    String? sourceUrl,
    String? targetWc,
  }) async {
    final selection =
        _resolveMergeInfoSelection(sourceUrl: sourceUrl, targetWc: targetWc);
    if (selection == null) {
      return false;
    }
    return await _mergeInfoService.isRevisionMerged(
      selection.sourceUrl,
      selection.targetWc,
      revision,
    );
  }

  /// 批量检查 revision 的合并状态
  ///
  /// 从 MergeInfoCacheService 获取合并状态
  Future<Map<int, bool>> checkMergedStatus(
    List<int> revisions, {
    String? sourceUrl,
    String? targetWc,
  }) async {
    final selection =
        _resolveMergeInfoSelection(sourceUrl: sourceUrl, targetWc: targetWc);
    if (selection == null) {
      return {for (var rev in revisions) rev: false};
    }
    return await _mergeInfoService.checkMergedStatus(
      selection.sourceUrl,
      selection.targetWc,
      revisions,
    );
  }

  /// 加载 mergeinfo 缓存
  ///
  /// 如果缓存为空，会从 SVN 获取
  ///
  /// [forceRefresh] 强制从 SVN 重新获取（保留缓存作为增量）
  /// [fullRefresh] 完整刷新：清空缓存后重新获取（用于 revert 后刷新）
  Future<void> loadMergeInfo({
    bool forceRefresh = false,
    bool fullRefresh = false,
    String? sourceUrl,
    String? targetWc,
  }) async {
    final selection =
        _resolveMergeInfoSelection(sourceUrl: sourceUrl, targetWc: targetWc);
    if (selection == null) {
      return;
    }

    _isMergeInfoLoading = true;
    notifyListeners();

    try {
      await _mergeInfoService.getMergedRevisions(
        selection.sourceUrl,
        selection.targetWc,
        forceRefresh: forceRefresh,
        fullRefresh: fullRefresh,
      );
      AppLogger.app.info(
          'MergeInfo 加载完成${fullRefresh ? "（完整刷新）" : forceRefresh ? "（强制刷新）" : ""}');
    } catch (e, stackTrace) {
      AppLogger.app.error('加载 MergeInfo 失败', e, stackTrace);
    } finally {
      _isMergeInfoLoading = false;
      notifyListeners();
    }
  }

  /// 设置分页大小
  ///
  /// [size] 新的分页大小（必须大于0）
  void setPageSize(int size) {
    if (size > 0) {
      _pageSize = size;
      AppLogger.app.info('分页大小已修改为: $_pageSize');
      notifyListeners();
    } else {
      AppLogger.app.warn('分页大小必须大于0，当前值: $size');
    }
  }

  /// 设置当前页
  Future<void> setCurrentPage(int page, {String? sourceUrl}) async {
    _currentPage = clampPageIndex(page);

    if (isUsableSourceUrl(sourceUrl)) {
      await refreshLogEntries(sourceUrl!);
    } else {
      notifyListeners();
    }
  }

  /// 下一页
  Future<void> nextPage({String? sourceUrl}) async {
    final next = nextPageIndex(currentPage: _currentPage, hasMore: hasMore);
    if (next == null) return;
    _currentPage = next;
    if (isUsableSourceUrl(sourceUrl)) {
      await refreshLogEntries(sourceUrl!);
    } else {
      notifyListeners();
    }
  }

  /// 上一页
  Future<void> previousPage({String? sourceUrl}) async {
    final prev = previousPageIndex(currentPage: _currentPage);
    if (prev == null) return;
    _currentPage = prev;
    if (isUsableSourceUrl(sourceUrl)) {
      await refreshLogEntries(sourceUrl!);
    } else {
      notifyListeners();
    }
  }

  /// 添加待合并 revision
  void addPendingRevisions(List<int> revisions) {
    _pendingRevisions = mergePendingRevisions(_pendingRevisions, revisions);
    notifyListeners();
  }

  /// 移除待合并 revision
  void removePendingRevisions(List<int> revisions) {
    _pendingRevisions =
        removeRevisionsFromPending(_pendingRevisions, revisions);
    notifyListeners();
  }

  /// 清空待合并列表
  void clearPendingRevisions() {
    _pendingRevisions.clear();
    notifyListeners();
  }

  /// 保存是否默认使用临时精简工作副本。
  Future<void> setUseTemporarySparseWorkingCopy(bool value) async {
    if (_useTemporarySparseWorkingCopy == value) {
      return;
    }
    _temporarySparseModeMutationVersion++;
    _useTemporarySparseWorkingCopy = value;
    await _storageService.saveUseTemporarySparseWorkingCopy(value);
    notifyListeners();
  }

  /// 保存目标模式。
  Future<void> setTargetMode(TargetMode mode) async {
    await setUseTemporarySparseWorkingCopy(
      mode == TargetMode.temporarySparseWorkingCopy,
    );
  }

  /// 保存源 URL 到历史
  Future<void> saveSourceUrlToHistory(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      return;
    }

    _sourceUrlMutationVersion++;
    await _storageService.addSourceUrlToHistory(trimmedUrl);
    _sourceUrlHistory = await _storageService.getSourceUrlHistory();
    _lastSourceUrl = trimmedUrl;
    await _storageService.saveLastSourceUrl(trimmedUrl);
    notifyListeners();
  }

  /// 保存 switch 目标分支到历史。
  ///
  /// 独立于 sourceUrlHistory，避免切换目标分支时污染合并源分支的 last_source_url。
  Future<void> saveSwitchBranchToHistory(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      return;
    }

    _switchBranchMutationVersion++;
    await _storageService.addSwitchBranchToHistory(trimmedUrl);
    _switchBranchHistory = await _storageService.getSwitchBranchHistory();
    notifyListeners();
  }

  /// 保存工作副本到历史
  Future<void> saveTargetWcToHistory(String wc) async {
    final trimmedWc = wc.trim();
    if (trimmedWc.isEmpty) {
      return;
    }

    _targetWcMutationVersion++;
    await _storageService.addTargetWcToHistory(trimmedWc);
    _targetWcHistory = await _storageService.getTargetWcHistory();
    _lastTargetWc = trimmedWc;
    await _storageService.saveLastTargetWc(trimmedWc);
    notifyListeners();
  }

  /// 保存精简模式目标 SVN URL 到历史。
  ///
  /// 独立于 sourceUrlHistory 和 switchBranchHistory，避免“目标 URL”污染源分支或
  /// 完整工作副本模式的 svn switch 历史。
  Future<void> saveTargetUrlToHistory(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      return;
    }

    _targetUrlMutationVersion++;
    await _storageService.addTargetUrlToHistory(trimmedUrl);
    _targetUrlHistory = await _storageService.getTargetUrlHistory();
    _lastTargetUrl = trimmedUrl;
    await _storageService.saveLastTargetUrl(trimmedUrl);
    notifyListeners();
  }

  /// 保存结构化目标配置到底层兼容 key。
  Future<void> saveTargetConfig(TargetConfig config) async {
    switch (config.mode) {
      case TargetMode.fullWorkingCopy:
        await saveTargetWcToHistory(config.workingCopyPath);
        break;
      case TargetMode.temporarySparseWorkingCopy:
        await saveTargetUrlToHistory(config.svnUrl);
        break;
    }
  }

  /// 刷新配置
  Future<void> refreshConfig() async {
    _config = await _configService.refreshConfig();
    notifyListeners();
  }
}
