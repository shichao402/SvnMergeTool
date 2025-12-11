/// 应用全局状态管理
///
/// 使用 Provider 管理应用的全局状态，包括：
/// - 配置
/// - 历史记录
/// - 当前选择

import 'package:flutter/foundation.dart';
import '../models/app_config.dart';
import '../models/log_entry.dart';
import '../services/config_service.dart';
import '../services/storage_service.dart';
import '../services/log_filter_service.dart';
import '../services/logger_service.dart';
import '../services/mergeinfo_cache_service.dart';

class AppState extends ChangeNotifier {
  final ConfigService _configService = ConfigService();
  final StorageService _storageService = StorageService();
  final MergeInfoCacheService _mergeInfoService = MergeInfoCacheService();

  AppConfig? _config;
  List<String> _sourceUrlHistory = [];
  List<String> _targetWcHistory = [];
  String? _lastSourceUrl;
  String? _lastTargetWc;
  List<int> _pendingRevisions = [];
  
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
  List<String> get targetWcHistory => _targetWcHistory;
  String? get lastSourceUrl => _lastSourceUrl;
  String? get lastTargetWc => _lastTargetWc;
  List<int> get pendingRevisions => _pendingRevisions;
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
  bool get hasMore => _paginatedResult?.hasMore ?? (currentPage < totalPages - 1);
  
  /// 获取过滤后的总数（优先使用 _paginatedResult，否则使用缓存值）
  int get filteredTotalCount => _paginatedResult?.totalCount ?? _cachedTotalCount;
  
  /// 是否有总页数信息
  bool get hasTotalPages => totalPages > 0;
  
  /// 是否有总数信息
  bool get hasTotalCount => filteredTotalCount > 0;
  
  /// 更新缓存的总数（供预加载服务调用）
  /// 
  /// [sourceUrl] 源 URL（用于验证是否是当前显示的数据源）
  /// [totalCount] 新的总数
  /// [pageSize] 每页大小（用于计算总页数）
  void updateCachedTotalCount(String sourceUrl, int totalCount, {int? pageSize}) {
    // 只有当前显示的数据源才更新
    if (_lastSourceUrl == sourceUrl || _lastSourceUrl == null) {
      _cachedTotalCount = totalCount;
      final effectivePageSize = pageSize ?? _pageSize;
      _cachedTotalPages = totalCount > 0 
          ? ((totalCount - 1) / effectivePageSize).floor() + 1 
          : 0;
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

  /// 初始化应用状态
  Future<void> init() async {
    if (_isInitialized) return;

    _isLoading = true;
    // 不要在 build 期间调用 notifyListeners，使用 Future.microtask 延迟通知
    
    try {
      // 加载配置
      _config = await _configService.loadConfig();

      // 从配置加载分页大小（固定为配置值，用户不可修改）
      _pageSize = _config?.settings.logPageSize ?? 50;
      AppLogger.app.info('从配置加载分页大小: $_pageSize（默认值，用户可修改）');

      // 加载历史记录
      _sourceUrlHistory = await _storageService.getSourceUrlHistory();
      _targetWcHistory = await _storageService.getTargetWcHistory();
      _lastSourceUrl = await _storageService.getLastSourceUrl();
      _lastTargetWc = await _storageService.getLastTargetWc();
      
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
      AppLogger.app.info('【refreshLogEntries】开始从缓存读取日志');
      AppLogger.app.info('  sourceUrl: $sourceUrl');
      AppLogger.app.info('  filter: $_filter');
      AppLogger.app.info('  page: $_currentPage, pageSize: $_pageSize');
      
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
        AppLogger.app.info('  结果: ${_paginatedResult!.entries.length} 条, 总数: $_cachedTotalCount, 总页数: $_cachedTotalPages');
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
  /// [minRevision] 最小版本号（用于 stopOnCopy 过滤）
  /// [sourceUrl] 源 URL（如果提供，会刷新日志列表）
  Future<void> setFilter({
    String? author,
    String? title,
    int? minRevision,
    bool clearMinRevision = false,
    String? sourceUrl,
  }) async {
    _filter = LogFilter(
      author: author, 
      title: title,
      minRevision: clearMinRevision ? null : minRevision,
    );
    _currentPage = 0; // 重置到第一页
    
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      await refreshLogEntries(sourceUrl);
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
    
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      await refreshLogEntries(sourceUrl);
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
  
  /// 同步检查 revision 是否已合并（仅从内存缓存）
  /// 
  /// 这是一个同步方法，用于 UI 渲染时快速判断合并状态
  /// 如果缓存未加载，返回 false
  bool isRevisionMergedSync(int revision) {
    if (_lastSourceUrl == null || _lastTargetWc == null) {
      return false;
    }
    return _mergeInfoService.isRevisionMergedSync(
      _lastSourceUrl!,
      _lastTargetWc!,
      revision,
    );
  }
  
  /// 同步获取已合并的 revision 集合（仅从内存缓存）
  /// 
  /// 这是一个同步方法，用于 UI 渲染
  Set<int> getMergedRevisionsSync() {
    if (_lastSourceUrl == null || _lastTargetWc == null) {
      return {};
    }
    return _mergeInfoService.getMergedRevisionsSync(
      _lastSourceUrl!,
      _lastTargetWc!,
    );
  }
  
  /// 检查 revision 是否已合并
  /// 
  /// 从 MergeInfoCacheService 获取合并状态
  Future<bool> isRevisionMerged(int revision) async {
    if (_lastSourceUrl == null || _lastTargetWc == null) {
      return false;
    }
    return await _mergeInfoService.isRevisionMerged(
      _lastSourceUrl!,
      _lastTargetWc!,
      revision,
    );
  }
  
  /// 批量检查 revision 的合并状态
  /// 
  /// 从 MergeInfoCacheService 获取合并状态
  Future<Map<int, bool>> checkMergedStatus(List<int> revisions) async {
    if (_lastSourceUrl == null || _lastTargetWc == null) {
      return {for (var rev in revisions) rev: false};
    }
    return await _mergeInfoService.checkMergedStatus(
      _lastSourceUrl!,
      _lastTargetWc!,
      revisions,
    );
  }
  
  /// 加载 mergeinfo 缓存
  /// 
  /// 如果缓存为空，会从 SVN 获取
  Future<void> loadMergeInfo({bool forceRefresh = false}) async {
    if (_lastSourceUrl == null || _lastTargetWc == null) {
      return;
    }
    
    _isMergeInfoLoading = true;
    notifyListeners();
    
    try {
      await _mergeInfoService.getMergedRevisions(
        _lastSourceUrl!,
        _lastTargetWc!,
        forceRefresh: forceRefresh,
      );
      AppLogger.app.info('MergeInfo 加载完成');
    } catch (e, stackTrace) {
      AppLogger.app.error('加载 MergeInfo 失败', e, stackTrace);
    } finally {
      _isMergeInfoLoading = false;
      notifyListeners();
    }
  }
  
  /// 添加已合并的 revision（由本程序合并后调用）
  Future<void> addMergedRevision(int revision) async {
    if (_lastSourceUrl == null || _lastTargetWc == null) {
      return;
    }
    await _mergeInfoService.addMergedRevision(
      _lastSourceUrl!,
      _lastTargetWc!,
      revision,
    );
    notifyListeners();
  }
  
  /// 添加多个已合并的 revision
  Future<void> addMergedRevisions(Set<int> revisions) async {
    if (_lastSourceUrl == null || _lastTargetWc == null) {
      return;
    }
    await _mergeInfoService.addMergedRevisions(
      _lastSourceUrl!,
      _lastTargetWc!,
      revisions,
    );
    notifyListeners();
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
    _currentPage = page.clamp(0, 999999);
    
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      await refreshLogEntries(sourceUrl);
    } else {
      notifyListeners();
    }
  }
  
  /// 下一页
  Future<void> nextPage({String? sourceUrl}) async {
    if (hasMore) {
      _currentPage++;
      if (sourceUrl != null && sourceUrl.isNotEmpty) {
        await refreshLogEntries(sourceUrl);
      } else {
        notifyListeners();
      }
    }
  }
  
  /// 上一页
  Future<void> previousPage({String? sourceUrl}) async {
    if (_currentPage > 0) {
      _currentPage--;
      if (sourceUrl != null && sourceUrl.isNotEmpty) {
        await refreshLogEntries(sourceUrl);
      } else {
        notifyListeners();
      }
    }
  }

  /// 添加待合并 revision
  void addPendingRevisions(List<int> revisions) {
    for (final rev in revisions) {
      if (!_pendingRevisions.contains(rev)) {
        _pendingRevisions.add(rev);
      }
    }
    _pendingRevisions.sort();
    notifyListeners();
  }

  /// 移除待合并 revision
  void removePendingRevisions(List<int> revisions) {
    _pendingRevisions.removeWhere((rev) => revisions.contains(rev));
    notifyListeners();
  }

  /// 清空待合并列表
  void clearPendingRevisions() {
    _pendingRevisions.clear();
    notifyListeners();
  }

  /// 保存源 URL 到历史
  Future<void> saveSourceUrlToHistory(String url) async {
    await _storageService.addSourceUrlToHistory(url);
    _sourceUrlHistory = await _storageService.getSourceUrlHistory();
    _lastSourceUrl = url;
    await _storageService.saveLastSourceUrl(url);
    notifyListeners();
  }

  /// 保存工作副本到历史
  Future<void> saveTargetWcToHistory(String wc) async {
    await _storageService.addTargetWcToHistory(wc);
    _targetWcHistory = await _storageService.getTargetWcHistory();
    _lastTargetWc = wc;
    await _storageService.saveLastTargetWc(wc);
    notifyListeners();
  }

  /// 刷新配置
  Future<void> refreshConfig() async {
    _config = await _configService.refreshConfig();
    notifyListeners();
  }
}


