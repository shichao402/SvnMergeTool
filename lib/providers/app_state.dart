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

class AppState extends ChangeNotifier {
  final ConfigService _configService = ConfigService();
  final StorageService _storageService = StorageService();

  AppConfig? _config;
  List<String> _sourceUrlHistory = [];
  List<String> _targetWcHistory = [];
  String? _lastSourceUrl;
  String? _lastTargetWc;
  List<int> _pendingRevisions = [];
  
  // 合并状态：key 是 revision，value 是是否已合并
  Map<int, bool> _mergedStatus = {};
  
  // 分页相关
  int _currentPage = 0;
  int _pageSize = 50;
  
  // 过滤条件
  LogFilter _filter = const LogFilter();
  
  // 当前分页结果
  PaginatedResult? _paginatedResult;
  
  // 日志过滤服务
  final LogFilterService _filterService = LogFilterService();
  
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;
  bool _isLoadingData = false; // 是否正在从 SVN 获取数据

  // Getters
  AppConfig? get config => _config;
  List<String> get sourceUrlHistory => _sourceUrlHistory;
  List<String> get targetWcHistory => _targetWcHistory;
  String? get lastSourceUrl => _lastSourceUrl;
  String? get lastTargetWc => _lastTargetWc;
  List<int> get pendingRevisions => _pendingRevisions;
  Map<int, bool> get mergedStatus => _mergedStatus;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;
  LogFilter get filter => _filter;
  PaginatedResult? get paginatedResult => _paginatedResult;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoadingData => _isLoadingData; // 是否正在从 SVN 获取数据
  
  /// 获取当前页的日志条目
  List<LogEntry> get paginatedLogEntries => _paginatedResult?.entries ?? [];
  
  /// 获取总页数（-1 表示未知）
  int get totalPages => _paginatedResult?.totalPages ?? -1;
  
  /// 是否还有更多数据（可以翻到下一页）
  bool get hasMore => _paginatedResult?.hasMore ?? false;
  
  /// 获取过滤后的总数（-1 表示未知）
  int get filteredTotalCount => _paginatedResult?.totalCount ?? -1;
  
  /// 是否有总页数信息
  bool get hasTotalPages => totalPages >= 0;
  
  /// 是否有总数信息
  bool get hasTotalCount => filteredTotalCount >= 0;

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
  /// [stopOnCopy] 是否在遇到拷贝/分支点时停止（用于自动获取更多数据）
  /// [workingDirectory] 工作目录（用于 stopOnCopy）
  /// 
  /// 注意：如果请求的数据范围超过缓存范围，会自动从 SVN 获取更多数据
  /// 持续获取直到满足需求或遇到 stopOnCopy 或没有更多数据
  Future<void> refreshLogEntries(
    String sourceUrl, {
    bool stopOnCopy = false,
    String? workingDirectory,
  }) async {
    try {
      // 获取配置中的 fetchLimit（每次从 SVN 获取的最大条数）
      final fetchLimit = _config?.settings.svnLogLimit ?? 200;
      
      // 设置数据加载回调，用于锁定/解锁 UI
      _filterService.setOnDataLoadingCallback((isLoading) {
        if (_isLoadingData != isLoading) {
          _isLoadingData = isLoading;
          notifyListeners();
        }
      });
      
      _paginatedResult = await _filterService.getPaginatedEntries(
        sourceUrl,
        _filter,
        _currentPage,
        _pageSize,
        stopOnCopy: stopOnCopy,
        workingDirectory: workingDirectory,
        fetchLimit: fetchLimit,
      );
      
      // 确保加载状态被清除
      if (_isLoadingData) {
        _isLoadingData = false;
      }
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.app.error('刷新日志列表失败', e, stackTrace);
      // 确保加载状态被清除
      if (_isLoadingData) {
        _isLoadingData = false;
        notifyListeners();
      }
    }
  }

  /// 设置过滤条件
  /// 
  /// [author] 作者过滤
  /// [title] 标题过滤
  /// [sourceUrl] 源 URL（如果提供，会刷新日志列表）
  /// [stopOnCopy] 是否在遇到拷贝/分支点时停止（用于自动获取更多数据）
  /// [workingDirectory] 工作目录（用于 stopOnCopy）
  Future<void> setFilter({
    String? author,
    String? title,
    String? sourceUrl,
    bool stopOnCopy = false,
    String? workingDirectory,
  }) async {
    _filter = LogFilter(author: author, title: title);
    _currentPage = 0; // 重置到第一页
    
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      await refreshLogEntries(
        sourceUrl,
        stopOnCopy: stopOnCopy,
        workingDirectory: workingDirectory,
      );
    } else {
      notifyListeners();
    }
  }
  
  /// 设置合并状态
  /// 
  /// 注意：此方法已废弃，合并状态现在从 MergeState 获取
  @Deprecated('合并状态现在从 MergeState 获取，不再通过 mergeinfo 检查')
  void setMergedStatus(Map<int, bool> status) {
    _mergedStatus = status;
    notifyListeners();
  }

  /// 从 MergeState 更新合并状态
  /// 
  /// 只记录本程序合并过的记录（不再通过 mergeinfo 检查）
  /// 
  /// [mergeState] MergeState 实例
  /// [sourceUrl] 源 URL（可选，用于过滤）
  /// [targetWc] 目标工作副本（可选，用于过滤）
  void updateMergedStatusFromMergeState(
    dynamic mergeState, {
    String? sourceUrl,
    String? targetWc,
  }) {
    try {
      // 从 MergeState 获取已完成的合并记录
      final mergedRevisions = mergeState.getMergedRevisions(
        sourceUrl: sourceUrl,
        targetWc: targetWc,
      );
      
      // 更新合并状态（保留已有的记录，只更新新的）
      _mergedStatus.addAll(mergedRevisions);
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.app.error('从 MergeState 更新合并状态失败', e, stackTrace);
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
  Future<void> setCurrentPage(
    int page, {
    String? sourceUrl,
    bool stopOnCopy = false,
    String? workingDirectory,
  }) async {
    // 不再限制最大页码，允许任意页码
    _currentPage = page.clamp(0, 999999);
    
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      await refreshLogEntries(
        sourceUrl,
        stopOnCopy: stopOnCopy,
        workingDirectory: workingDirectory,
      );
    } else {
      notifyListeners();
    }
  }
  
  /// 下一页
  /// 注意：根据 hasMore 来判断是否可以翻页
  Future<void> nextPage({
    String? sourceUrl,
    bool stopOnCopy = false,
    String? workingDirectory,
  }) async {
    // 如果还有更多数据，才允许翻页
    if (hasMore) {
      _currentPage++;
      if (sourceUrl != null && sourceUrl.isNotEmpty) {
        await refreshLogEntries(
          sourceUrl,
          stopOnCopy: stopOnCopy,
          workingDirectory: workingDirectory,
        );
      } else {
        notifyListeners();
      }
    }
  }
  
  /// 上一页
  Future<void> previousPage({
    String? sourceUrl,
    bool stopOnCopy = false,
    String? workingDirectory,
  }) async {
    if (_currentPage > 0) {
      _currentPage--;
      if (sourceUrl != null && sourceUrl.isNotEmpty) {
        await refreshLogEntries(
          sourceUrl,
          stopOnCopy: stopOnCopy,
          workingDirectory: workingDirectory,
        );
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

