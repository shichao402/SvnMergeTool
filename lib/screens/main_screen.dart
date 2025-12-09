import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_state.dart';
import '../providers/merge_state.dart';
import '../models/log_entry.dart';
import '../models/merge_job.dart';
import '../services/svn_service.dart';
import '../services/logger_service.dart';
import '../services/storage_service.dart';
import '../services/log_filter_service.dart';
import '../services/log_file_cache_service.dart';
import '../services/preload_service.dart';
import '../services/storage_service.dart' show StorageService;
import '../widgets/preload_settings_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Controllers
  final _sourceUrlController = TextEditingController();
  final _targetWcController = TextEditingController();
  final _filterAuthorController = TextEditingController();
  final _filterTitleController = TextEditingController();
  final _pageSizeController = TextEditingController();
  
  // 提交者过滤历史记录
  List<String> _authorFilterHistory = [];

  // State
  int _maxRetries = 5;
  // 日志列表界面的 stopOnCopy 开关（是否排除拉分支前的记录）
  bool _logListStopOnCopy = true;
  // 跟踪上次的路径，用于检测变化并清除缓存
  String? _lastSourceUrl;
  String? _lastTargetWc;
  final Set<int> _selectedRevisions = {};
  
  // 服务实例
  // 注意：只保留 UI 层需要的服务（文件列表缓存）
  // 数据访问必须通过 AppState，遵循分级数据请求模式
  final _logFileCacheService = LogFileCacheService();
  final _preloadService = PreloadService();
  
  // 预加载状态
  PreloadProgress _preloadProgress = const PreloadProgress();
  
  // 当前的预加载设置（从持久化存储加载）
  PreloadSettings _preloadSettings = const PreloadSettings();

  // 分割线位置（相对于父容器的比例，0.0-1.0）
  double _horizontalSplitRatio = 0.67; // 水平分割：左侧日志占 67%，右侧待合并占 33%
  double _verticalSplitRatio = 0.75;   // 垂直分割：上部主内容占 75%，底部任务占 25%

  // 分割线宽度
  static const double _dividerThickness = 8.0;

  @override
  void initState() {
    super.initState();
    _initializeFields();
    // 异步初始化服务
    _logFileCacheService.init().catchError((e) {
      AppLogger.ui.error('文件缓存服务初始化失败', e);
    });
    // 初始化预加载服务
    _preloadService.init().then((_) {
      _preloadService.onProgressChanged = (progress) {
        if (mounted) {
          setState(() {
            _preloadProgress = progress;
          });
        }
      };
    }).catchError((e) {
      AppLogger.ui.error('预加载服务初始化失败', e);
    });
    // 加载持久化的预加载设置
    _loadPreloadSettings();
    // 延迟执行自动加载，等待 UI 构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadLogsIfPossible();
    });
  }

  /// 从持久化存储加载预加载设置
  Future<void> _loadPreloadSettings() async {
    try {
      final storageService = StorageService();
      final settings = await storageService.getPreloadSettings();
      if (settings.isNotEmpty && mounted) {
        setState(() {
          _preloadSettings = PreloadSettings(
            enabled: settings['enabled'] as bool? ?? true,
            stopOnBranchPoint: settings['stop_on_branch_point'] as bool? ?? true,
            maxDays: settings['max_days'] as int? ?? 90,
            maxCount: settings['max_count'] as int? ?? 1000,
            stopRevision: settings['stop_revision'] as int? ?? 0,
            stopDate: settings['stop_date'] as String?,
          );
        });
        AppLogger.ui.info('已加载预加载设置: enabled=${_preloadSettings.enabled}, maxDays=${_preloadSettings.maxDays}, maxCount=${_preloadSettings.maxCount}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('加载预加载设置失败', e, stackTrace);
    }
  }

  @override
  void dispose() {
    _sourceUrlController.dispose();
    _targetWcController.dispose();
    _filterAuthorController.dispose();
    _filterTitleController.dispose();
    _pageSizeController.dispose();
    super.dispose();
  }

  /// 初始化字段
  void _initializeFields() {
    final appState = Provider.of<AppState>(context, listen: false);

    // 策略1: 优先恢复上次选择
    if (appState.lastSourceUrl != null && appState.lastSourceUrl!.isNotEmpty) {
      _sourceUrlController.text = appState.lastSourceUrl!;
      AppLogger.ui.info('自动加载上次使用的源 URL: ${appState.lastSourceUrl}');
    } 
    // 策略2: 如果没有历史记录，从配置文件中获取第一个启用的 URL
    else if (appState.config != null && appState.config!.enabledSourceUrls.isNotEmpty) {
      _sourceUrlController.text = appState.config!.enabledSourceUrls.first.url;
      AppLogger.ui.info('从配置加载默认源 URL: ${appState.config!.enabledSourceUrls.first.url}');
    }
    
    // 恢复目标工作副本
    if (appState.lastTargetWc != null) {
      _targetWcController.text = appState.lastTargetWc!;
      _lastTargetWc = appState.lastTargetWc!;
      AppLogger.ui.info('自动加载上次使用的目标工作副本: ${appState.lastTargetWc}');
    }
    
    // 初始化路径跟踪（用于检测变化并清除缓存）
    _lastSourceUrl = _sourceUrlController.text.trim();
    if (_lastSourceUrl!.isEmpty && appState.config != null && appState.config!.enabledSourceUrls.isNotEmpty) {
      _lastSourceUrl = appState.config!.enabledSourceUrls.first.url;
    }
    
    // 加载提交者过滤历史记录和上次使用的值
    _loadAuthorFilterHistory();
    
    // 初始化每页条数输入框
    _pageSizeController.text = appState.pageSize.toString();
  }

  /// 自动加载日志（如果条件满足）
  /// 
  /// 符合设计流程：只请求数据，由数据模块在缓存未命中时自动获取
  Future<void> _autoLoadLogsIfPossible() async {
    final sourceUrl = _sourceUrlController.text.trim();

    // 只要有源 URL 就自动请求数据（不主动同步，由数据模块决定是否需要获取）
    if (sourceUrl.isNotEmpty) {
      final appState = Provider.of<AppState>(context, listen: false);
      AppLogger.ui.info('=== 自动加载日志（启动时） ===');
      AppLogger.ui.info('检测到有效的源 URL，自动请求数据');
      AppLogger.ui.info('  源 URL: $sourceUrl');
      AppLogger.ui.info('  pageSize: ${appState.pageSize}');
      AppLogger.ui.info('  说明: 由数据模块检查缓存，缓存未命中时自动获取');
      
      // 获取目标工作副本
      final targetWc = _targetWcController.text.trim();
      
      // 只请求数据，不主动同步
      // LogFilterService 会检查缓存是否足够，如果不够会自动调用 LogSyncService
      // 启动时默认不跨越分支点（stopOnCopy=true）
      await appState.refreshLogEntries(
        sourceUrl,
        stopOnCopy: true,
        workingDirectory: targetWc.isNotEmpty ? targetWc : null,
      );
      
      // 数据加载完成后，更新合并状态（如果有目标工作副本）
      // 只记录本程序合并过的记录（不再通过 mergeinfo 检查）
      if (targetWc.isNotEmpty) {
        _updateMergedStatus(sourceUrl, targetWc);
      }
      
      AppLogger.ui.info('=== 自动加载日志完成 ===');
      
      // 启动后台预加载（如果配置启用）
      _startBackgroundPreload(sourceUrl, targetWc, appState);
    } else {
      AppLogger.ui.info('源 URL 为空，跳过自动加载');
    }
  }

  /// 启动后台预加载
  void _startBackgroundPreload(String sourceUrl, String targetWc, AppState appState) {
    // 使用本地保存的预加载设置（优先使用持久化的设置）
    final preloadSettings = _preloadSettings;
    if (!preloadSettings.enabled) {
      AppLogger.ui.info('后台预加载未启用，跳过');
      return;
    }
    
    AppLogger.ui.info('=== 启动后台预加载 ===');
    AppLogger.ui.info('  配置:');
    AppLogger.ui.info('    - 到达分支点停止: ${preloadSettings.stopOnBranchPoint}');
    AppLogger.ui.info('    - 天数限制: ${preloadSettings.maxDays > 0 ? "${preloadSettings.maxDays} 天" : "无限制"}');
    AppLogger.ui.info('    - 条数限制: ${preloadSettings.maxCount > 0 ? "${preloadSettings.maxCount} 条" : "无限制"}');
    
    // 异步启动预加载，不阻塞 UI
    _preloadService.startPreload(
      sourceUrl: sourceUrl,
      settings: preloadSettings,
      workingDirectory: targetWc.isNotEmpty ? targetWc : null,
      fetchLimit: appState.config?.settings.svnLogLimit ?? 200,
    ).then((_) {
      // 预加载完成后刷新日志列表（如果还在当前页面）
      if (mounted && _preloadProgress.status == PreloadStatus.completed) {
        AppLogger.ui.info('后台预加载完成，刷新日志列表');
        appState.refreshLogEntries(
          sourceUrl,
          stopOnCopy: _logListStopOnCopy,
          workingDirectory: targetWc.isNotEmpty ? targetWc : null,
        );
      }
    }).catchError((e, stackTrace) {
      AppLogger.ui.error('后台预加载失败', e, stackTrace);
    });
  }

  /// 选择目标工作副本目录
  Future<void> _pickTargetWc() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _targetWcController.text = result;
      });
      
      // 检测路径变化，清除缓存
      if (_lastTargetWc != null && _lastTargetWc != result) {
        AppLogger.ui.info('目标工作副本路径已变化: $_lastTargetWc -> $result');
        AppLogger.ui.info('清除COPY_TAIL和边界标记缓存');
        LogFilterService.clearTailCache(workingDirectory: _lastTargetWc);
        LogFilterService.clearBoundaryCache(workingDirectory: _lastTargetWc);
        LogFilterService.clearBoundaryCache(workingDirectory: _lastTargetWc);
      }
      _lastTargetWc = result;
      
      // 立即保存到历史记录，以便下次启动时自动加载
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.saveTargetWcToHistory(result);
      AppLogger.ui.info('已保存目标工作副本到历史: $result');
    }
  }

  /// 刷新日志列表（触发分层请求日志）
  /// 
  /// 符合分级数据请求模式：
  /// UI -> AppState -> LogFilterService -> LogSyncService (缓存未命中时)
  Future<void> _refreshLogList(bool stopOnCopy) async {
    final sourceUrl = _sourceUrlController.text.trim();

    if (sourceUrl.isEmpty) {
      _showError('请填写源 URL');
      return;
    }

    // 检测路径变化，清除缓存
    if (_lastSourceUrl != null && _lastSourceUrl != sourceUrl) {
      AppLogger.ui.info('源 URL 已变化: $_lastSourceUrl -> $sourceUrl');
      AppLogger.ui.info('清除ROOT_TAIL缓存');
        LogFilterService.clearTailCache(sourceUrl: _lastSourceUrl);
        LogFilterService.clearBoundaryCache(sourceUrl: _lastSourceUrl);
    }
    _lastSourceUrl = sourceUrl;
    
    // 保存源 URL 到历史记录（持久化）
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.saveSourceUrlToHistory(sourceUrl);

    // 获取目标工作副本（用于 stopOnCopy 功能）
    final targetWc = _targetWcController.text.trim();
    if (_lastTargetWc != null && _lastTargetWc != targetWc) {
      AppLogger.ui.info('目标工作副本路径已变化: $_lastTargetWc -> $targetWc');
      AppLogger.ui.info('清除COPY_TAIL缓存');
      LogFilterService.clearTailCache(workingDirectory: _lastTargetWc);
    }
    _lastTargetWc = targetWc;

    try {
      AppLogger.ui.info('=== 刷新日志列表 ===');
      AppLogger.ui.info('源 URL: $sourceUrl');
      AppLogger.ui.info('stopOnCopy: $stopOnCopy');
      AppLogger.ui.info('说明: 由数据模块检查缓存，缓存未命中时自动获取');
      if (stopOnCopy && targetWc.isNotEmpty) {
        AppLogger.ui.info('stopOnCopy=true，将使用目标工作副本路径: $targetWc');
      } else if (stopOnCopy && targetWc.isEmpty) {
        AppLogger.ui.warn('stopOnCopy=true 但目标工作副本为空');
      }

      // 请求数据（遵循分级数据请求模式）
      // AppState -> LogFilterService -> LogSyncService (缓存未命中时)
      await appState.refreshLogEntries(
        sourceUrl,
        stopOnCopy: stopOnCopy,
        workingDirectory: targetWc.isNotEmpty ? targetWc : null,
      );

      // 更新合并状态（如果有目标工作副本）
      // 只记录本程序合并过的记录（不再通过 mergeinfo 检查）
      if (targetWc.isNotEmpty) {
        _updateMergedStatus(sourceUrl, targetWc);
      }

      AppLogger.ui.info('=== 日志列表刷新完成 ===');
    } catch (e, stackTrace) {
      AppLogger.ui.error('刷新日志列表失败', e, stackTrace);
      _showError('刷新日志列表失败：$e');
    }
  }

  /// 更新合并状态（从 MergeState 获取）
  /// 
  /// 只记录本程序合并过的记录（不再通过 mergeinfo 检查）
  void _updateMergedStatus(
    String sourceUrl,
    String targetWc,
  ) {
    if (targetWc.isEmpty) return;
    
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final mergeState = Provider.of<MergeState>(context, listen: false);
      
      // 从 MergeState 获取已完成的合并记录
      appState.updateMergedStatusFromMergeState(
        mergeState,
        sourceUrl: sourceUrl,
        targetWc: targetWc,
      );
    } catch (e, stackTrace) {
      AppLogger.ui.error('更新合并状态失败', e, stackTrace);
    }
  }

  /// 从缓存获取指定 revision 的日志条目
  /// 
  /// 符合分级数据请求模式：通过 AppState 获取数据
  Future<List<LogEntry>> _getEntriesForRevisions(String sourceUrl, List<int> revisions) async {
    if (revisions.isEmpty || sourceUrl.isEmpty) {
      return [];
    }
    
    try {
      // 通过 AppState 获取数据（遵循分级数据请求模式）
      final appState = Provider.of<AppState>(context, listen: false);
      return await appState.getEntriesByRevisions(sourceUrl, revisions);
    } catch (e, stackTrace) {
      AppLogger.ui.error('获取日志条目失败', e, stackTrace);
      return [];
    }
  }

  /// 显示文件列表弹窗
  /// 注意：SVN 鉴权完全依赖 SVN 自身管理，不传递用户名密码
  Future<void> _showFileListDialog(LogEntry entry, String sourceUrl) async {
    // 先从缓存读取
    List<String>? files = _logFileCacheService.getFiles(sourceUrl, entry.revision);
    
    if (files == null) {
      // 缓存中没有，从 SVN 获取
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在获取文件列表...'),
                ],
              ),
            ),
          ),
        ),
      );
      
      try {
        final svnService = SvnService();
        files = await svnService.getRevisionFiles(
          sourceUrl: sourceUrl,
          revision: entry.revision,
        );
        
        // 保存到缓存
        await _logFileCacheService.saveFiles(sourceUrl, entry.revision, files);
      } catch (e, stackTrace) {
        AppLogger.ui.error('获取文件列表失败', e, stackTrace);
        files = [];
      } finally {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('r${entry.revision} 涉及的文件 (${files?.length ?? 0} 个)'),
        content: SizedBox(
          width: double.maxFinite,
          child: files == null || files.isEmpty
              ? const Text('无文件信息')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        files![index],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 加载提交者过滤历史记录和上次使用的值
  Future<void> _loadAuthorFilterHistory() async {
    final storageService = StorageService();
    _authorFilterHistory = await storageService.getAuthorFilterHistory();
    final lastAuthor = await storageService.getLastAuthorFilter();
    if (lastAuthor != null && lastAuthor.isNotEmpty) {
      _filterAuthorController.text = lastAuthor;
    }
    setState(() {}); // 更新 UI 以显示历史记录
  }

  /// 应用过滤
  Future<void> _applyFilter() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final sourceUrl = _sourceUrlController.text.trim();
    final targetWc = _targetWcController.text.trim();
    final authorFilter = _filterAuthorController.text.trim();
    
    // 保存提交者过滤值到历史记录
    if (authorFilter.isNotEmpty) {
      final storageService = StorageService();
      await storageService.addAuthorToFilterHistory(authorFilter);
      await storageService.saveLastAuthorFilter(authorFilter);
      // 重新加载历史记录
      _authorFilterHistory = await storageService.getAuthorFilterHistory();
      setState(() {}); // 更新 UI
    }
    
    await appState.setFilter(
      author: authorFilter.isEmpty ? null : authorFilter,
      title: _filterTitleController.text.trim().isEmpty 
          ? null 
          : _filterTitleController.text.trim(),
      sourceUrl: sourceUrl,
      stopOnCopy: _logListStopOnCopy,
      workingDirectory: targetWc.isNotEmpty ? targetWc : null,
    );
  }

  /// 添加选中的 revision 到待合并列表
  void _addSelectedToPending() {
    if (_selectedRevisions.isEmpty) {
      _showError('请先选择要合并的 revision');
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    appState.addPendingRevisions(_selectedRevisions.toList());

    setState(() {
      _selectedRevisions.clear();
    });

    _showSuccess('已添加 ${_selectedRevisions.length} 个 revision');
  }

  /// 开始合并
  Future<void> _startMerge() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final mergeState = Provider.of<MergeState>(context, listen: false);

    final sourceUrl = _sourceUrlController.text.trim();
    final targetWc = _targetWcController.text.trim();

    if (sourceUrl.isEmpty || targetWc.isEmpty) {
      _showError('请填写源 URL 和目标工作副本');
      return;
    }

    if (appState.pendingRevisions.isEmpty) {
      _showError('待合并列表为空');
      return;
    }

    // 添加任务到队列
    // 注意：SVN 鉴权完全依赖 SVN 自身管理，不传递用户名密码
    await mergeState.addJob(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      revisions: appState.pendingRevisions.toList(),
      maxRetries: _maxRetries,
    );

    // 保存到历史
    await appState.saveTargetWcToHistory(targetWc);

    // 清空待合并列表
    appState.clearPendingRevisions();

    _showSuccess('任务已添加到队列');
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

  /// 构建预加载状态 Widget
  Widget _buildPreloadStatusWidget(String sourceUrl) {
    final isLoading = _preloadProgress.status == PreloadStatus.loading;
    final targetWc = _targetWcController.text.trim();
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 预加载状态显示
        if (_preloadProgress.loadedCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLoading ? Colors.blue.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isLoading ? Colors.blue.shade200 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading) ...[
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '已缓存 ${_preloadProgress.loadedCount} 条',
                  style: TextStyle(
                    fontSize: 11,
                    color: isLoading ? Colors.blue.shade700 : Colors.grey.shade700,
                  ),
                ),
                if (_preloadProgress.earliestRevision != null) ...[
                  Text(
                    ' (r${_preloadProgress.earliestRevision})',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        // 加载全部按钮
        if (!isLoading)
          TextButton.icon(
            onPressed: sourceUrl.isEmpty
                ? null
                : () => _loadAllToBranchPoint(sourceUrl, targetWc),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('加载全部', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
          )
        else
          TextButton.icon(
            onPressed: _preloadService.stopPreload,
            icon: const Icon(Icons.stop, size: 16),
            label: const Text('停止', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              foregroundColor: Colors.red,
            ),
          ),
        // 预加载设置按钮
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => _showPreloadSettingsDialog(sourceUrl, targetWc),
          icon: const Icon(Icons.settings, size: 18),
          tooltip: '预加载设置',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  /// 显示预加载设置对话框
  Future<void> _showPreloadSettingsDialog(String sourceUrl, String targetWc) async {
    final newSettings = await PreloadSettingsDialog.show(context, _preloadSettings);
    if (newSettings != null && mounted) {
      setState(() {
        _preloadSettings = newSettings;
      });
      AppLogger.ui.info('预加载设置已更新: enabled=${newSettings.enabled}, maxDays=${newSettings.maxDays}, maxCount=${newSettings.maxCount}');
      
      // 如果启用了预加载且当前没有在加载，自动开始预加载
      if (newSettings.enabled && 
          _preloadProgress.status != PreloadStatus.loading &&
          sourceUrl.isNotEmpty) {
        final appState = Provider.of<AppState>(context, listen: false);
        _startBackgroundPreload(sourceUrl, targetWc, appState);
      }
    }
  }

  /// 加载全部日志到分支点
  Future<void> _loadAllToBranchPoint(String sourceUrl, String targetWc) async {
    if (sourceUrl.isEmpty) {
      _showError('请先填写源 URL');
      return;
    }
    
    AppLogger.ui.info('开始加载全部日志到分支点');
    AppLogger.ui.info('  源 URL: $sourceUrl');
    AppLogger.ui.info('  目标工作副本: ${targetWc.isEmpty ? "未指定" : targetWc}');
    
    try {
      await _preloadService.loadAllToBranchPoint(
        sourceUrl: sourceUrl,
        workingDirectory: targetWc.isEmpty ? null : targetWc,
        fetchLimit: 200,
      );
      
      // 加载完成后刷新日志列表
      if (mounted) {
        final appState = Provider.of<AppState>(context, listen: false);
        await appState.refreshLogEntries(
          sourceUrl,
          stopOnCopy: _logListStopOnCopy,
          workingDirectory: targetWc.isEmpty ? null : targetWc,
        );
        
        if (_preloadProgress.status == PreloadStatus.completed) {
          _showSuccess('加载完成: ${_preloadProgress.statusDescription}');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('加载全部日志失败', e, stackTrace);
      _showError('加载失败: $e');
    }
  }

  /// 构建水平分割线（左右拖动调整水平分割比例）
  Widget _buildHorizontalDivider(double totalWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        setState(() {
          _horizontalSplitRatio += delta / totalWidth;
          _horizontalSplitRatio = _horizontalSplitRatio.clamp(0.2, 0.8);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Container(
          width: _dividerThickness,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            border: Border.symmetric(
              horizontal: BorderSide(color: Colors.grey.shade400, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建垂直分割线（上下拖动调整垂直分割比例）
  Widget _buildVerticalDivider(double totalHeight) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        final delta = details.primaryDelta ?? 0;
        setState(() {
          _verticalSplitRatio += delta / totalHeight;
          _verticalSplitRatio = _verticalSplitRatio.clamp(0.2, 0.9);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Container(
          height: _dividerThickness,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            border: Border.symmetric(
              vertical: BorderSide(color: Colors.grey.shade400, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 配置区域（固定在顶部）
          _buildConfigSection(),

          // 可拖动的主内容区域
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalHeight = constraints.maxHeight;
                final mainHeight = totalHeight * _verticalSplitRatio;
                final bottomHeight = totalHeight - mainHeight - _dividerThickness;

                return Column(
                  children: [
                    // 上部：主内容区域（水平分割）
                    SizedBox(
                      height: mainHeight,
                      child: Row(
                        children: [
                          // 左侧：日志列表
                          SizedBox(
                            width: constraints.maxWidth * _horizontalSplitRatio,
                            child: _buildLogSection(),
                          ),
                          // 水平分割线
                          _buildHorizontalDivider(constraints.maxWidth),
                          // 右侧：待合并列表
                          Expanded(
                            child: _buildPendingSection(),
                          ),
                        ],
                      ),
                    ),
                    // 垂直分割线
                    _buildVerticalDivider(totalHeight),
                    // 下部：任务队列和操作日志
                    SizedBox(
                      height: bottomHeight,
                      child: _buildBottomSection(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 源 URL
            Row(
              children: [
                const SizedBox(width: 100, child: Text('源 URL:')),
                Expanded(
                  child: TextField(
                    controller: _sourceUrlController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 目标工作副本
            Row(
              children: [
                const SizedBox(width: 100, child: Text('目标工作副本:')),
                Expanded(
                  child: TextField(
                    controller: _targetWcController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _pickTargetWc,
                  child: const Text('选择目录...'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 设置行 - 使用 Wrap 避免溢出
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 最大重试次数
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('最大重试次数:'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          _maxRetries = int.tryParse(value) ?? 5;
                        },
                        controller: TextEditingController(text: _maxRetries.toString()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogSection() {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue.shade300, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          margin: const EdgeInsets.all(4),
          child: Column(
            children: [
              // 标题栏（醒目）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.list_alt, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'SVN 日志列表',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const Spacer(),
                    // 刷新按钮（移到原来总数的位置）
                    ElevatedButton.icon(
                      onPressed: appState.isLoadingData
                          ? null
                          : () async {
                              // 获取当前的 stopOnCopy 状态（从局部状态）
                              final stopOnCopy = _logListStopOnCopy;
                              await _refreshLogList(stopOnCopy);
                            },
                      icon: appState.isLoadingData
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: const Text('刷新'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              
              // 控制栏已移除，刷新按钮移到标题栏，stopOnCopy移到过滤条件栏

              // 过滤栏
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('提交者:'),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: Consumer<AppState>(
                            builder: (context, appState, _) {
                              return Autocomplete<String>(
                                optionsBuilder: (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return _authorFilterHistory;
                                  }
                                  return _authorFilterHistory.where((option) =>
                                    option.toLowerCase().contains(textEditingValue.text.toLowerCase())
                                  ).toList();
                                },
                                onSelected: (String selection) {
                                  _filterAuthorController.text = selection;
                                },
                                fieldViewBuilder: (
                                  BuildContext context,
                                  TextEditingController textEditingController,
                                  FocusNode focusNode,
                                  VoidCallback onFieldSubmitted,
                                ) {
                                  // 同步 Autocomplete 的 controller 和我们的 controller
                                  // 初始化时同步
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (textEditingController.text != _filterAuthorController.text) {
                                      textEditingController.text = _filterAuthorController.text;
                                    }
                                  });
                                  
                                  return TextField(
                                    controller: textEditingController, // 使用 Autocomplete 提供的 controller
                                    focusNode: focusNode,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                    onChanged: (value) {
                                      // 同步到我们的 controller
                                      _filterAuthorController.text = value;
                                    },
                                    onSubmitted: appState.isLoadingData ? null : (_) => _applyFilter(),
                                    enabled: !appState.isLoadingData,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('标题:'),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _filterTitleController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 是否跨越分支点开关（移到过滤条件栏）
                    Consumer<AppState>(
                      builder: (context, appState, _) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _logListStopOnCopy,
                              onChanged: appState.isLoadingData
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _logListStopOnCopy = value ?? false;
                                      });
                                      // 切换开关后自动刷新
                                      final sourceUrl = _sourceUrlController.text.trim();
                                      if (sourceUrl.isNotEmpty) {
                                        _refreshLogList(_logListStopOnCopy);
                                      }
                                    },
                            ),
                            const Text('排除拉分支前的记录'),
                          ],
                        );
                      },
                    ),
                    Consumer<AppState>(
                      builder: (context, appState, _) {
                        return ElevatedButton(
                          onPressed: appState.isLoadingData ? null : _applyFilter,
                          child: const Text('过滤'),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // 日志列表
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, appState, _) {
                    final paginatedEntries = appState.paginatedLogEntries;
                    final mergedStatus = appState.mergedStatus;
                    final sourceUrl = _sourceUrlController.text.trim();
                    
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            itemCount: paginatedEntries.length,
                            // 增加缓存范围，提升滚动性能
                            cacheExtent: 500,
                            itemBuilder: (context, index) {
                              final entry = paginatedEntries[index];
                              final isSelected = _selectedRevisions.contains(entry.revision);
                              final isPending = appState.pendingRevisions.contains(entry.revision);
                              final isMerged = mergedStatus[entry.revision] ?? false;
                              
                              // 隔行样式
                              final isEven = index % 2 == 0;
                              Color? tileColor;
                              if (isPending) {
                                tileColor = Colors.green.shade100;
                              } else if (isMerged) {
                                tileColor = Colors.grey.shade200;
                              } else if (isEven) {
                                tileColor = Colors.grey.shade50;
                              }

                              // 使用 ValueKey 优化 ListView 性能，帮助 Flutter 识别哪些 item 需要重建
                              return InkWell(
                                key: ValueKey('log_entry_${entry.revision}'),
                                onTap: appState.isLoadingData
                                    ? null
                                    : () {
                                        // 单击选中/取消
                                        if (!isMerged && !isPending) {
                                          setState(() {
                                            if (isSelected) {
                                              _selectedRevisions.remove(entry.revision);
                                            } else {
                                              _selectedRevisions.add(entry.revision);
                                            }
                                          });
                                        }
                                      },
                                onDoubleTap: () {
                                  // 双击查看文件列表
                                  if (!isMerged) {
                                    _showFileListDialog(entry, sourceUrl);
                                  }
                                },
                                child: ListTile(
                                  selected: isSelected,
                                  selectedTileColor: Colors.blue.shade50,
                                  tileColor: tileColor,
                                  enabled: !isMerged && !isPending,
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (!isMerged && !isPending && !appState.isLoadingData)
                                        ? (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedRevisions.add(entry.revision);
                                              } else {
                                                _selectedRevisions.remove(entry.revision);
                                              }
                                            });
                                          }
                                        : null,
                                  ),
                                  title: Row(
                                    children: [
                                      Text('r${entry.revision} | ${entry.author} | ${entry.date}'),
                                      if (isMerged) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade400,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            '已合并',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Text(
                                    entry.title,
                                    style: TextStyle(
                                      color: isMerged ? Colors.grey.shade600 : null,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // 分页控件
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border(
                              top: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.first_page),
                                onPressed: (appState.currentPage > 0 && !appState.isLoadingData)
                                    ? () async => await appState.setCurrentPage(
                                          0,
                                          sourceUrl: sourceUrl,
                                          stopOnCopy: _logListStopOnCopy,
                                          workingDirectory: _targetWcController.text.trim().isNotEmpty
                                              ? _targetWcController.text.trim()
                                              : null,
                                        )
                                    : null,
                                tooltip: '第一页',
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_left),
                                onPressed: (appState.currentPage > 0 && !appState.isLoadingData)
                                    ? () async => await appState.previousPage(
                                          sourceUrl: sourceUrl,
                                          stopOnCopy: _logListStopOnCopy,
                                          workingDirectory: _targetWcController.text.trim().isNotEmpty
                                              ? _targetWcController.text.trim()
                                              : null,
                                        )
                                    : null,
                                tooltip: '上一页',
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '第 ${appState.currentPage + 1} 页',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    if (appState.isLoadingData) ...[
                                      const SizedBox(width: 8),
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                // 如果还有更多数据且不在加载中，才允许翻到下一页
                                onPressed: (appState.hasMore && !appState.isLoadingData)
                                    ? () async => await appState.nextPage(
                                          sourceUrl: sourceUrl,
                                          stopOnCopy: _logListStopOnCopy,
                                          workingDirectory: _targetWcController.text.trim().isNotEmpty
                                              ? _targetWcController.text.trim()
                                              : null,
                                        )
                                    : null,
                                tooltip: '下一页',
                              ),
                              // 移除"最后一页"按钮，因为不知道总共有多少页
                              const SizedBox(width: 16),
                              // 每页条数输入框（允许用户修改）
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('每页:', style: TextStyle(fontSize: 12)),
                                  const SizedBox(width: 4),
                                  SizedBox(
                                    width: 60,
                                    child: TextField(
                                      controller: _pageSizeController,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontSize: 12),
                                      enabled: !appState.isLoadingData,
                                      onSubmitted: appState.isLoadingData
                                          ? null
                                          : (value) {
                                              final newPageSize = int.tryParse(value);
                                              if (newPageSize != null && newPageSize > 0) {
                                                appState.setPageSize(newPageSize);
                                                // 修改页数后重置到第一页
                                                appState.setCurrentPage(
                                                  0,
                                                  sourceUrl: _sourceUrlController.text.trim(),
                                                  stopOnCopy: _logListStopOnCopy,
                                                  workingDirectory: _targetWcController.text.trim().isNotEmpty
                                                      ? _targetWcController.text.trim()
                                                      : null,
                                                );
                                              } else {
                                                // 恢复原值
                                                _pageSizeController.text = appState.pageSize.toString();
                                              }
                                            },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text('条', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                              // 预加载状态和按钮
                              const SizedBox(width: 16),
                              _buildPreloadStatusWidget(sourceUrl),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // 操作按钮
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: ElevatedButton.icon(
                  onPressed: _addSelectedToPending,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('>> 添加到待合并 >>'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingSection() {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final pendingRevisions = appState.pendingRevisions;
        
        // 从缓存获取待合并 revision 对应的日志条目
        final sourceUrl = _sourceUrlController.text.trim();
        
        if (pendingRevisions.isEmpty || sourceUrl.isEmpty) {
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green.shade300, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            margin: const EdgeInsets.all(4),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.merge_type, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Text(
                        '待合并 revision',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${pendingRevisions.length} 个',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          '暂无待合并项',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始合并'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 40),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return FutureBuilder<List<LogEntry>>(
          future: _getEntriesForRevisions(sourceUrl, pendingRevisions),
          builder: (context, snapshot) {
            final entries = snapshot.data ?? [];

            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green.shade300, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              margin: const EdgeInsets.all(4),
              child: Column(
            children: [
              // 标题栏（醒目）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.merge_type, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      '待合并 revision',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${pendingRevisions.length} 个',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),

              // 待合并列表
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: pendingRevisions.length,
                        itemBuilder: (context, index) {
                          final rev = pendingRevisions[index];
                          // 查找对应的日志条目
                          final entry = entries.firstWhere(
                            (e) => e.revision == rev,
                            orElse: () => LogEntry(
                              revision: rev,
                              author: '未知',
                              date: '',
                              title: '未找到详情',
                              message: '',
                            ),
                          );
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                child: Text('${index + 1}'),
                              ),
                              title: Text(
                                'r${entry.revision} | ${entry.author}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.date,
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    entry.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  appState.removePendingRevisions([rev]);
                                },
                                tooltip: '移除',
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // 开始合并按钮
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: ElevatedButton.icon(
                  onPressed: pendingRevisions.isEmpty ? null : _startMerge,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始合并'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),
            ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomSection() {
    return Consumer<MergeState>(
      builder: (context, mergeState, _) {
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange.shade300, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          margin: const EdgeInsets.all(4),
          child: Column(
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.task, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '任务队列与操作日志',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.drag_handle,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    Text(
                      ' 拖动调整大小',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),

              // 内容区域（任务列表 + 日志）
              Expanded(
                child: Row(
                  children: [
                    // 左侧：任务列表
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                '任务列表',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: mergeState.activeJobs.isEmpty
                                  ? Center(
                                      child: Text(
                                        '暂无任务',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: mergeState.activeJobs.length,
                                      itemBuilder: (context, index) {
                                        final job = mergeState.activeJobs[index];
                                        return ListTile(
                                          dense: true,
                                          visualDensity: VisualDensity.compact,
                                          title: Text(
                                            job.description,
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          trailing: job.status == JobStatus.failed
                                              ? const Icon(Icons.error, color: Colors.red, size: 16)
                                              : job.status == JobStatus.done
                                                  ? const Icon(Icons.check, color: Colors.green, size: 16)
                                                  : job.status == JobStatus.running
                                                      ? const SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child: CircularProgressIndicator(strokeWidth: 2),
                                                        )
                                                      : const Icon(Icons.schedule, color: Colors.grey, size: 16),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 右侧：操作日志
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.black87,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 标题栏（带清理按钮）
                            Row(
                              children: [
                                Text(
                                  '操作日志',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade400,
                                  ),
                                ),
                                const Spacer(),
                                // 清理按钮
                                IconButton(
                                  icon: const Icon(Icons.clear_all, size: 16),
                                  color: Colors.grey.shade400,
                                  tooltip: '清空操作日志',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  onPressed: () {
                                    mergeState.clearLog();
                                    AppLogger.ui.info('已清空操作日志');
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  mergeState.log.isEmpty ? '暂无日志' : mergeState.log,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
