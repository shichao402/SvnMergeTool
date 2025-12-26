/// SVN 自动合并工具 - 主界面 V3
///
/// 重构版本：组件化设计
/// - 主屏幕只负责组装各组件和管理状态
/// - UI 组件独立，易于替换和测试
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/pipeline_merge_state.dart';
import '../models/app_config.dart' show PreloadSettings;
import '../services/svn_service.dart';
import '../services/logger_service.dart';
import '../services/storage_service.dart';
import '../services/log_filter_service.dart';
import '../services/log_file_cache_service.dart';
import '../services/preload_service.dart';
import '../services/log_cache_service.dart';
import '../services/working_copy_manager.dart';
import 'settings_screen.dart';

// 组件导入
import 'components/config_bar.dart';
import 'components/flow_execution_view.dart';
import 'components/log_list_panel.dart';
import 'components/pending_panel.dart';
import 'components/pipeline_panel.dart';
import 'components/status_bar.dart';
import 'components/dialogs/config_dialog.dart';
import 'components/dialogs/log_dialog.dart';

/// 操作阶段枚举
enum OperationPhase {
  /// 选择阶段：浏览日志、选择 revision
  select,
  /// 执行阶段：Pipeline 执行中
  execute,
}

class MainScreenV3 extends StatefulWidget {
  const MainScreenV3({super.key});

  @override
  State<MainScreenV3> createState() => _MainScreenV3State();
}

class _MainScreenV3State extends State<MainScreenV3> {
  // ============ Controllers ============
  final _sourceUrlController = TextEditingController();
  final _targetWcController = TextEditingController();
  final _filterAuthorController = TextEditingController();
  final _filterTitleController = TextEditingController();

  // ============ State ============
  int _maxRetries = 5;
  bool _logListStopOnCopy = true;
  String? _lastSourceUrl;
  String? _lastTargetWc;
  final Set<int> _selectedRevisions = {};
  int? _cachedBranchPoint;
  PreloadProgress _preloadProgress = const PreloadProgress();
  PreloadSettings _preloadSettings = const PreloadSettings();
  String? _selectedNodeId; // 流程图中选中的节点 ID
  double _panelWidth = 320.0; // 右侧面板宽度

  // ============ Services ============
  final _logFileCacheService = LogFileCacheService();
  final _preloadService = PreloadService();
  final _logCacheService = LogCacheService();
  final _svnService = SvnService();
  final _wcManager = WorkingCopyManager();

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _initServices();
  }

  void _initServices() async {
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
        if (mounted) {
          setState(() => _preloadProgress = progress);
          if (progress.sourceUrl != null && progress.loadedCount > 0) {
            final appState = Provider.of<AppState>(context, listen: false);
            appState.updateCachedTotalCount(
              progress.sourceUrl!,
              progress.loadedCount,
              pageSize: appState.pageSize,
            );
          }
        }
      };
    }).catchError((e) {
      AppLogger.ui.error('预加载服务初始化失败', e);
    });
    await _loadPreloadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
      final settings = await storageService.getPreloadSettings();
      final maxRetries = await storageService.getDefaultMaxRetries();
      if (mounted) {
        setState(() {
          if (settings.isNotEmpty) {
            _preloadSettings = PreloadSettings(
              enabled: settings['enabled'] as bool? ?? true,
              stopOnBranchPoint: settings['stop_on_branch_point'] as bool? ?? true,
              maxDays: settings['max_days'] as int? ?? 90,
              maxCount: settings['max_count'] as int? ?? 1000,
            );
          }
          _maxRetries = maxRetries;
        });
      }
    } catch (e) {
      AppLogger.ui.error('加载设置失败', e);
    }
  }

  @override
  void dispose() {
    _sourceUrlController.dispose();
    _targetWcController.dispose();
    _filterAuthorController.dispose();
    _filterTitleController.dispose();
    super.dispose();
  }

  void _initializeFields() {
    final appState = Provider.of<AppState>(context, listen: false);

    if (appState.lastSourceUrl != null && appState.lastSourceUrl!.isNotEmpty) {
      _sourceUrlController.text = appState.lastSourceUrl!;
    } else if (appState.config != null && appState.config!.enabledSourceUrls.isNotEmpty) {
      _sourceUrlController.text = appState.config!.enabledSourceUrls.first.url;
    }

    if (appState.lastTargetWc != null) {
      _targetWcController.text = appState.lastTargetWc!;
      _lastTargetWc = appState.lastTargetWc!;
    }

    _lastSourceUrl = _sourceUrlController.text.trim();
    _loadAuthorFilterHistory();
  }

  Future<void> _loadAuthorFilterHistory() async {
    final storageService = StorageService();
    final lastAuthor = await storageService.getLastAuthorFilter();
    if (lastAuthor != null && lastAuthor.isNotEmpty) {
      _filterAuthorController.text = lastAuthor;
    }
  }

  Future<void> _autoLoadLogsIfPossible() async {
    final sourceUrl = _sourceUrlController.text.trim();
    if (sourceUrl.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final targetWc = _targetWcController.text.trim();

    int? minRevision;
    if (_logListStopOnCopy && targetWc.isNotEmpty) {
      minRevision = await _getBranchPoint(targetWc);
    }

    await appState.setMinRevision(minRevision, sourceUrl: sourceUrl);

    if (targetWc.isNotEmpty) {
      _updateMergedStatus(sourceUrl, targetWc);
    }

    _startBackgroundPreload(sourceUrl, targetWc, appState);
  }

  void _startBackgroundPreload(String sourceUrl, String targetWc, AppState appState) {
    if (!_preloadSettings.enabled) return;

    _preloadService.startPreload(
      sourceUrl: sourceUrl,
      settings: _preloadSettings,
      workingDirectory: targetWc.isNotEmpty ? targetWc : null,
      fetchLimit: appState.config?.settings.svnLogLimit ?? 200,
    ).then((_) {
      if (mounted && _preloadProgress.status == PreloadStatus.completed) {
        appState.refreshLogEntries(sourceUrl);
      }
    }).catchError((e) {
      AppLogger.ui.error('后台预加载失败', e);
    });
  }

  Future<int?> _getBranchPoint(String workingDirectory) async {
    if (_cachedBranchPoint != null) return _cachedBranchPoint;
    final cached = LogFilterService.getCachedBranchPoint(workingDirectory);
    if (cached != null) {
      _cachedBranchPoint = cached;
      return cached;
    }
    try {
      final branchUrl = await _svnService.getInfo(workingDirectory);
      final branchPoint = await _svnService.findBranchPoint(
        branchUrl,
        workingDirectory: workingDirectory,
      );
      if (branchPoint != null) {
        _cachedBranchPoint = branchPoint;
        LogFilterService.cacheBranchPoint(workingDirectory, branchPoint);
      }
      return branchPoint;
    } catch (e) {
      AppLogger.ui.error('查询分支点失败', e);
      return null;
    }
  }

  Future<void> _updateMergedStatus(String sourceUrl, String targetWc, {bool forceRefresh = false}) async {
    if (targetWc.isEmpty || sourceUrl.isEmpty) return;
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.loadMergeInfo(forceRefresh: forceRefresh);
    } catch (e) {
      AppLogger.ui.error('更新合并状态失败', e);
    }
  }

  // ============ 事件处理 ============

  Future<void> _refreshLogList(bool stopOnCopy) async {
    final sourceUrl = _sourceUrlController.text.trim();
    if (sourceUrl.isEmpty) {
      _showError('请填写源 URL');
      return;
    }

    if (_lastSourceUrl != null && _lastSourceUrl != sourceUrl) {
      _cachedBranchPoint = null;
      LogFilterService.clearBranchPointCache(workingDirectory: _lastTargetWc);
    }
    _lastSourceUrl = sourceUrl;

    final appState = Provider.of<AppState>(context, listen: false);
    await appState.saveSourceUrlToHistory(sourceUrl);

    final targetWc = _targetWcController.text.trim();
    if (_lastTargetWc != null && _lastTargetWc != targetWc) {
      _cachedBranchPoint = null;
      LogFilterService.clearBranchPointCache(workingDirectory: _lastTargetWc);
    }
    _lastTargetWc = targetWc;

    int? minRevision;
    if (stopOnCopy && targetWc.isNotEmpty) {
      minRevision = await _getBranchPoint(targetWc);
    }

    await appState.setMinRevision(minRevision, sourceUrl: sourceUrl);

    if (targetWc.isNotEmpty) {
      _updateMergedStatus(sourceUrl, targetWc, forceRefresh: true);
    }
  }

  Future<void> _applyFilter() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final sourceUrl = _sourceUrlController.text.trim();
    final targetWc = _targetWcController.text.trim();
    final authorFilter = _filterAuthorController.text.trim();

    if (authorFilter.isNotEmpty) {
      final storageService = StorageService();
      await storageService.addAuthorToFilterHistory(authorFilter);
      await storageService.saveLastAuthorFilter(authorFilter);
    }

    int? minRevision;
    if (_logListStopOnCopy && targetWc.isNotEmpty) {
      minRevision = await _getBranchPoint(targetWc);
    }

    await appState.setFilter(
      author: authorFilter.isEmpty ? null : authorFilter,
      title: _filterTitleController.text.trim().isEmpty ? null : _filterTitleController.text.trim(),
      minRevision: minRevision,
      clearMinRevision: !_logListStopOnCopy,
      sourceUrl: sourceUrl,
    );
  }

  void _addSelectedToPending() {
    if (_selectedRevisions.isEmpty) {
      _showError('请先选择要合并的 revision');
      return;
    }
    final appState = Provider.of<AppState>(context, listen: false);
    final count = _selectedRevisions.length;
    appState.addPendingRevisions(_selectedRevisions.toList());
    setState(() => _selectedRevisions.clear());
    _showSuccess('已添加 $count 个 revision');
  }

  Future<void> _startMerge() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final mergeState = Provider.of<PipelineMergeState>(context, listen: false);

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

    if (mergeState.isLocked) {
      _showError('有暂停的任务需要处理');
      return;
    }

    await mergeState.addJob(
      sourceUrl: sourceUrl,
      targetWc: targetWc,
      revisions: appState.pendingRevisions.toList(),
      maxRetries: _maxRetries,
    );

    await appState.saveTargetWcToHistory(targetWc);
    appState.clearPendingRevisions();
    _showSuccess('任务已添加');
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

  // ============ SVN 操作 ============

  Future<void> _handleSvnOperation(SvnOperation operation) async {
    switch (operation) {
      case SvnOperation.update:
        await _svnUpdate();
        break;
      case SvnOperation.revert:
        await _svnRevert();
        break;
      case SvnOperation.cleanup:
        await _svnCleanup();
        break;
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
      _showError('工作副本正在执行 ${lockInfo?.operationType}，请稍后再试');
      return;
    }

    AppLogger.ui.info('开始 SVN Update: $targetWc');
    _showInfo('正在执行 SVN Update...');

    try {
      final result = await _wcManager.update(targetWc);

      if (result.exitCode == 0) {
        AppLogger.ui.info('SVN Update 成功');
        _showSuccess('Update 完成');

        final sourceUrl = _sourceUrlController.text.trim();
        if (sourceUrl.isNotEmpty) {
          _updateMergedStatus(sourceUrl, targetWc, forceRefresh: true);
        }
      } else {
        AppLogger.ui.error('SVN Update 失败: ${result.stderr}');
        _showError('Update 失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('SVN Update 异常', e, stackTrace);
      _showError('Update 异常: $e');
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
      _showError('工作副本正在执行 ${lockInfo?.operationType}，请稍后再试');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认 Revert'),
        content: Text('确定要 Revert "$targetWc" 吗？\n\n这将撤销所有本地修改！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Revert'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    AppLogger.ui.info('开始 SVN Revert: $targetWc');
    _showInfo('正在执行 SVN Revert...');

    try {
      final sourceUrl = _sourceUrlController.text.trim();
      final result = await _wcManager.revert(
        targetWc,
        recursive: true,
        sourceUrl: sourceUrl,
        refreshMergeInfo: true,
      );

      if (result.exitCode == 0) {
        AppLogger.ui.info('SVN Revert 成功');
        _showSuccess('Revert 完成');

        if (mounted && sourceUrl.isNotEmpty) {
          final appState = Provider.of<AppState>(context, listen: false);
          await appState.loadMergeInfo(fullRefresh: true);
        }
      } else {
        AppLogger.ui.error('SVN Revert 失败: ${result.stderr}');
        _showError('Revert 失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('SVN Revert 异常', e, stackTrace);
      _showError('Revert 异常: $e');
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
      _showError('工作副本正在执行 ${lockInfo?.operationType}，请稍后再试');
      return;
    }

    AppLogger.ui.info('开始 SVN Cleanup: $targetWc');
    _showInfo('正在执行 SVN Cleanup...');

    try {
      final result = await _wcManager.cleanup(targetWc);

      if (result.exitCode == 0) {
        AppLogger.ui.info('SVN Cleanup 成功');
        _showSuccess('Cleanup 完成');
      } else {
        AppLogger.ui.error('SVN Cleanup 失败: ${result.stderr}');
        _showError('Cleanup 失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('SVN Cleanup 异常', e, stackTrace);
      _showError('Cleanup 异常: $e');
    }
  }

  Future<void> _openSettings() async {
    final result = await SettingsScreen.show(
      context,
      currentPreloadSettings: _preloadSettings,
      currentMaxRetries: _maxRetries,
    );
    if (result != null && mounted) {
      setState(() {
        _preloadSettings = result.preloadSettings;
        _maxRetries = result.maxRetries;
      });
      
      // 通知 PipelineMergeState 重新加载流程
      final mergeState = Provider.of<PipelineMergeState>(context, listen: false);
      await mergeState.reloadFlow();
    }
  }

  void _showConfigDialog() {
    final appState = Provider.of<AppState>(context, listen: false);
    ConfigDialog.show(
      context: context,
      sourceUrlController: _sourceUrlController,
      targetWcController: _targetWcController,
      sourceUrlHistory: appState.sourceUrlHistory,
      targetWcHistory: appState.targetWcHistory,
      onConfirm: () {
        setState(() {});
        _refreshLogList(_logListStopOnCopy);
      },
    );
  }

  void _showLogDialog(PipelineMergeState mergeState) {
    LogDialog.show(
      context: context,
      log: mergeState.log,
      onClear: () => mergeState.clearLog(),
    );
  }

  /// 获取当前操作阶段
  OperationPhase _getCurrentPhase(PipelineMergeState mergeState) {
    // 只有在真正执行中或暂停时才进入执行阶段
    // pending 状态的任务不算执行阶段
    if (mergeState.isProcessing || mergeState.hasPausedJob) {
      return OperationPhase.execute;
    }
    return OperationPhase.select;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppState, PipelineMergeState>(
      builder: (context, appState, mergeState, _) {
        final phase = _getCurrentPhase(mergeState);

        return Scaffold(
          body: Column(
            children: [
              // 顶部配置栏
              ConfigBar(
                sourceUrl: _sourceUrlController.text.trim(),
                targetWc: _targetWcController.text.trim(),
                onConfigTap: _showConfigDialog,
                onSettingsTap: _openSettings,
                onSvnOperation: _handleSvnOperation,
              ),
              // 主内容区
              Expanded(
                child: phase == OperationPhase.execute
                    ? _buildExecutePhaseView(mergeState)
                    : _buildSelectPhaseView(appState),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 选择阶段视图
  Widget _buildSelectPhaseView(AppState appState) {
    final sourceUrl = _sourceUrlController.text.trim();
    
    // 构建已合并 revision 集合
    final mergedRevisions = <int>{};
    for (final entry in appState.paginatedLogEntries) {
      if (appState.isRevisionMergedSync(entry.revision)) {
        mergedRevisions.add(entry.revision);
      }
    }

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
            stopOnCopy: _logListStopOnCopy,
            onStopOnCopyChanged: (value) {
              setState(() => _logListStopOnCopy = value);
              _refreshLogList(value);
            },
            onApplyFilter: _applyFilter,
            onRefresh: () => _refreshLogList(_logListStopOnCopy),
            currentPage: appState.currentPage,
            totalPages: appState.totalPages,
            hasMore: appState.hasMore,
            cachedCount: _preloadProgress.loadedCount,
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
                  _selectedRevisions.remove(revision);
                }
              });
            },
          ),
        ),
        // 右侧：待合并面板
        SizedBox(
          width: 280,
          child: PendingPanel(
            pendingRevisions: appState.pendingRevisions,
            selectedCount: _selectedRevisions.length,
            onAddSelected: _addSelectedToPending,
            onRemove: (rev) => appState.removePendingRevisions([rev]),
            onStartMerge: _startMerge,
            canStartMerge: appState.pendingRevisions.isNotEmpty,
          ),
        ),
      ],
    );
  }

  /// 执行阶段视图
  Widget _buildExecutePhaseView(PipelineMergeState mergeState) {
    return Column(
      children: [
        // 主内容区：流程图 + 控制面板
        Expanded(
          child: Row(
            children: [
              // 左侧：流程图只读视图
              Expanded(
                flex: 2,
                child: mergeState.flowGraph != null
                    ? FlowExecutionView(
                        flowGraph: mergeState.flowGraph!,
                        currentNodeId: mergeState.currentNodeId,
                        status: mergeState.status,
                        snapshots: mergeState.snapshots,
                        selectedNodeId: _selectedNodeId,
                        onNodeSelected: (nodeId) {
                          setState(() => _selectedNodeId = nodeId);
                        },
                      )
                    : const Center(child: Text('加载流程图...')),
              ),
              // 右侧：可拖动宽度的控制面板
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _panelWidth = (_panelWidth - details.delta.dx).clamp(280.0, 600.0);
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
                child: PipelinePanel(
                  status: mergeState.status,
                  currentNodeId: mergeState.currentNodeId,
                  pausedJob: mergeState.pausedJob,
                  isWaitingInput: mergeState.isWaitingInput,
                  inputConfig: mergeState.waitingInputConfig,
                  onResume: () => mergeState.resumePausedJob(),
                  onSkip: () => mergeState.skipCurrentRevision(),
                  onCancel: () => mergeState.cancelPausedJob(),
                  onSubmitInput: (value) => mergeState.submitUserInput(value),
                  selectedSnapshot: _selectedNodeId != null
                      ? mergeState.snapshots.get(_selectedNodeId!)
                      : null,
                  selectedNodeId: _selectedNodeId,
                  globalContext: mergeState.snapshots.globalContext,
                  onClearSelection: () {
                    setState(() => _selectedNodeId = null);
                  },
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
