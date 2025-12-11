import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_state.dart';
import '../providers/merge_state.dart';
import '../models/app_config.dart' show PreloadSettings;
import '../models/log_entry.dart';
import '../models/merge_job.dart';
import '../services/svn_service.dart';
import '../services/logger_service.dart';
import '../services/storage_service.dart';
import '../services/log_filter_service.dart';
import '../services/log_file_cache_service.dart';
import '../services/preload_service.dart';
import '../services/log_cache_service.dart';
import 'settings_screen.dart';

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
  final _logCacheService = LogCacheService();
  final _svnService = SvnService();
  
  // 缓存的分支点（避免重复查询）
  int? _cachedBranchPoint;
  
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
    // 初始化日志缓存服务并设置校验错误回调
    _logCacheService.init().then((_) {
      _logCacheService.onValidationError = _handleCacheValidationError;
    }).catchError((e) {
      AppLogger.ui.error('日志缓存服务初始化失败', e);
    });
    // 初始化预加载服务
    _preloadService.init().then((_) {
      _preloadService.onProgressChanged = (progress) {
        if (mounted) {
          setState(() {
            _preloadProgress = progress;
          });
          
          // 同步更新 AppState 的缓存总数（让页数实时更新）
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
    // 加载持久化的预加载设置
    _loadPreloadSettings();
    // 延迟执行自动加载，等待 UI 构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadLogsIfPossible();
    });
  }

  /// 处理缓存校验错误
  void _handleCacheValidationError(CacheValidationError error) {
    AppLogger.ui.error('【严重错误】缓存数据库校验失败: ${error.message}');
    
    // 在 UI 上显示醒目的错误提示
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 8),
              const Text('严重错误：缓存数据库不匹配'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '检测到缓存数据库与当前 URL 不匹配！',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('期望 URL:\n${error.expectedUrl}'),
                      const SizedBox(height: 4),
                      Text('数据库中的 URL:\n${error.actualUrl}'),
                      const SizedBox(height: 4),
                      Text('数据库路径:\n${error.dbPath}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '可能的原因：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• Hash 冲突（极少见）'),
                const Text('• 配置文件被手动修改'),
                const Text('• 数据库文件被移动或替换'),
                const SizedBox(height: 12),
                const Text(
                  '建议操作：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• 删除该数据库文件后重试'),
                const Text('• 或清空所有缓存后重新加载'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    }
  }

  /// 从持久化存储加载预加载设置
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
              stopRevision: settings['stop_revision'] as int? ?? 0,
              stopDate: settings['stop_date'] as String?,
            );
          }
          _maxRetries = maxRetries;
        });
        AppLogger.ui.info('已加载设置: maxRetries=$_maxRetries, preloadEnabled=${_preloadSettings.enabled}, maxDays=${_preloadSettings.maxDays}, maxCount=${_preloadSettings.maxCount}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('加载设置失败', e, stackTrace);
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
  /// 设计：过滤器只负责过滤 db 缓存中的数据
  Future<void> _autoLoadLogsIfPossible() async {
    final sourceUrl = _sourceUrlController.text.trim();

    if (sourceUrl.isNotEmpty) {
      final appState = Provider.of<AppState>(context, listen: false);
      AppLogger.ui.info('=== 自动加载日志（启动时） ===');
      AppLogger.ui.info('  源 URL: $sourceUrl');
      
      // 获取目标工作副本
      final targetWc = _targetWcController.text.trim();
      
      // 如果 stopOnCopy=true，先查询分支点
      int? minRevision;
      if (_logListStopOnCopy && targetWc.isNotEmpty) {
        minRevision = await _getBranchPoint(targetWc);
      }
      
      // 设置过滤条件并刷新
      await appState.setMinRevision(minRevision, sourceUrl: sourceUrl);
      
      // 更新合并状态
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
        appState.refreshLogEntries(sourceUrl);
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
        _cachedBranchPoint = null;
        LogFilterService.clearBranchPointCache(workingDirectory: _lastTargetWc);
      }
      _lastTargetWc = result;
      
      // 立即保存到历史记录，以便下次启动时自动加载
      final appState = Provider.of<AppState>(context, listen: false);
      await appState.saveTargetWcToHistory(result);
      AppLogger.ui.info('已保存目标工作副本到历史: $result');
    }
  }

  /// SVN Update 目标工作副本
  Future<void> _svnUpdate() async {
    final targetWc = _targetWcController.text.trim();
    if (targetWc.isEmpty) {
      _showError('请先选择目标工作副本');
      return;
    }
    
    AppLogger.ui.info('开始 SVN Update: $targetWc');
    _showInfo('正在执行 SVN Update...');
    
    try {
      final svnService = SvnService();
      final result = await svnService.update(targetWc);
      
      if (result.exitCode == 0) {
        AppLogger.ui.info('SVN Update 成功');
        _showSuccess('Update 完成');
        
        // Update 后刷新 mergeinfo（因为本地属性可能已更新）
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

  /// SVN Revert 目标工作副本
  Future<void> _svnRevert() async {
    final targetWc = _targetWcController.text.trim();
    if (targetWc.isEmpty) {
      _showError('请先选择目标工作副本');
      return;
    }
    
    // 确认对话框
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
      final svnService = SvnService();
      final result = await svnService.revert(targetWc, recursive: true);
      
      if (result.exitCode == 0) {
        AppLogger.ui.info('SVN Revert 成功');
        _showSuccess('Revert 完成');
      } else {
        AppLogger.ui.error('SVN Revert 失败: ${result.stderr}');
        _showError('Revert 失败: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      AppLogger.ui.error('SVN Revert 异常', e, stackTrace);
      _showError('Revert 异常: $e');
    }
  }

  /// SVN Cleanup 目标工作副本
  Future<void> _svnCleanup() async {
    final targetWc = _targetWcController.text.trim();
    if (targetWc.isEmpty) {
      _showError('请先选择目标工作副本');
      return;
    }
    
    AppLogger.ui.info('开始 SVN Cleanup: $targetWc');
    _showInfo('正在执行 SVN Cleanup...');
    
    try {
      final svnService = SvnService();
      final result = await svnService.cleanup(targetWc);
      
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

  /// 刷新日志列表（纯本地过滤操作）
  /// 
  /// 新设计：过滤器只负责过滤 db 缓存中的数据，不触发网络请求
  /// stopOnCopy 通过设置 minRevision 来实现
  Future<void> _refreshLogList(bool stopOnCopy) async {
    final sourceUrl = _sourceUrlController.text.trim();

    if (sourceUrl.isEmpty) {
      _showError('请填写源 URL');
      return;
    }

    // 检测路径变化，清除缓存
    if (_lastSourceUrl != null && _lastSourceUrl != sourceUrl) {
      AppLogger.ui.info('源 URL 已变化: $_lastSourceUrl -> $sourceUrl');
      _cachedBranchPoint = null; // 清除分支点缓存
      LogFilterService.clearBranchPointCache(workingDirectory: _lastTargetWc);
    }
    _lastSourceUrl = sourceUrl;
    
    // 保存源 URL 到历史记录（持久化）
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.saveSourceUrlToHistory(sourceUrl);

    // 获取目标工作副本（用于 stopOnCopy 功能）
    final targetWc = _targetWcController.text.trim();
    if (_lastTargetWc != null && _lastTargetWc != targetWc) {
      AppLogger.ui.info('目标工作副本路径已变化: $_lastTargetWc -> $targetWc');
      _cachedBranchPoint = null; // 清除分支点缓存
      LogFilterService.clearBranchPointCache(workingDirectory: _lastTargetWc);
    }
    _lastTargetWc = targetWc;

    try {
      AppLogger.ui.info('=== 刷新日志列表 ===');
      AppLogger.ui.info('源 URL: $sourceUrl');
      AppLogger.ui.info('stopOnCopy: $stopOnCopy');
      
      // 如果 stopOnCopy=true，需要查询分支点
      int? minRevision;
      if (stopOnCopy && targetWc.isNotEmpty) {
        minRevision = await _getBranchPoint(targetWc);
        if (minRevision != null) {
          AppLogger.ui.info('使用分支点过滤: minRevision=r$minRevision');
        }
      }
      
      // 更新过滤条件（包含 minRevision）
      await appState.setMinRevision(minRevision, sourceUrl: sourceUrl);

      // 更新合并状态（如果有目标工作副本）
      // 用户主动刷新时，强制从 SVN 重新获取 mergeinfo
      if (targetWc.isNotEmpty) {
        _updateMergedStatus(sourceUrl, targetWc, forceRefresh: true);
      }

      AppLogger.ui.info('=== 日志列表刷新完成 ===');
    } catch (e, stackTrace) {
      AppLogger.ui.error('刷新日志列表失败', e, stackTrace);
      _showError('刷新日志列表失败：$e');
    }
  }
  
  /// 获取分支点（带缓存）
  Future<int?> _getBranchPoint(String workingDirectory) async {
    // 检查缓存
    if (_cachedBranchPoint != null) {
      return _cachedBranchPoint;
    }
    
    // 检查 LogFilterService 的静态缓存
    final cached = LogFilterService.getCachedBranchPoint(workingDirectory);
    if (cached != null) {
      _cachedBranchPoint = cached;
      return cached;
    }
    
    try {
      AppLogger.ui.info('查询分支点: $workingDirectory');
      // 获取分支 URL
      final branchUrl = await _svnService.getInfo(workingDirectory);
      // 查询分支点
      final branchPoint = await _svnService.findBranchPoint(
        branchUrl,
        workingDirectory: workingDirectory,
      );
      
      if (branchPoint != null) {
        AppLogger.ui.info('找到分支点: r$branchPoint');
        _cachedBranchPoint = branchPoint;
        LogFilterService.cacheBranchPoint(workingDirectory, branchPoint);
      }
      
      return branchPoint;
    } catch (e, stackTrace) {
      AppLogger.ui.error('查询分支点失败', e, stackTrace);
      return null;
    }
  }

  /// 更新合并状态（从 MergeInfoCacheService 获取）
  /// 
  /// 使用 MergeInfoCacheService 统一管理 mergeinfo 缓存
  /// 如果缓存为空，会自动从 SVN 获取
  Future<void> _updateMergedStatus(
    String sourceUrl,
    String targetWc, {
    bool forceRefresh = false,
  }) async {
    if (targetWc.isEmpty || sourceUrl.isEmpty) return;
    
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      
      // 使用 MergeInfoCacheService 获取合并状态
      // 如果 forceRefresh 为 true，会从 SVN 重新获取
      await appState.loadMergeInfo(forceRefresh: forceRefresh);
      
      AppLogger.ui.info('合并状态已更新');
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
    
    // 如果 stopOnCopy=true，先查询分支点
    int? minRevision;
    if (_logListStopOnCopy && targetWc.isNotEmpty) {
      minRevision = await _getBranchPoint(targetWc);
    }
    
    await appState.setFilter(
      author: authorFilter.isEmpty ? null : authorFilter,
      title: _filterTitleController.text.trim().isEmpty 
          ? null 
          : _filterTitleController.text.trim(),
      minRevision: minRevision,
      clearMinRevision: !_logListStopOnCopy,
      sourceUrl: sourceUrl,
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

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.blue),
    );
  }

  /// 构建 SVN 操作按钮组
  Widget _buildSvnOperationButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Update 按钮
        Tooltip(
          message: 'SVN Update - 更新工作副本到最新版本',
          child: OutlinedButton.icon(
            onPressed: _svnUpdate,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Update'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Revert 按钮
        Tooltip(
          message: 'SVN Revert - 撤销所有本地修改',
          child: OutlinedButton.icon(
            onPressed: _svnRevert,
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Revert'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              foregroundColor: Colors.orange,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Cleanup 按钮
        Tooltip(
          message: 'SVN Cleanup - 清理工作副本',
          child: OutlinedButton.icon(
            onPressed: _svnCleanup,
            icon: const Icon(Icons.cleaning_services, size: 16),
            label: const Text('Cleanup'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
        ),
      ],
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
      ],
    );
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
        await appState.refreshLogEntries(sourceUrl);
        
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

  /// 打开设置界面
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
      AppLogger.ui.info('设置已更新: maxRetries=$_maxRetries, preloadEnabled=${_preloadSettings.enabled}');
      
      // 如果启用了预加载且当前没有在加载，自动开始预加载
      final sourceUrl = _sourceUrlController.text.trim();
      final targetWc = _targetWcController.text.trim();
      if (_preloadSettings.enabled && 
          _preloadProgress.status != PreloadStatus.loading &&
          sourceUrl.isNotEmpty) {
        final appState = Provider.of<AppState>(context, listen: false);
        _startBackgroundPreload(sourceUrl, targetWc, appState);
      }
    }
  }

  Widget _buildConfigSection() {
    final appState = Provider.of<AppState>(context, listen: false);
    
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
                  child: _buildAutocompleteTextField(
                    controller: _sourceUrlController,
                    history: appState.sourceUrlHistory,
                    hintText: '输入或选择源 URL',
                  ),
                ),
                const SizedBox(width: 8),
                // 设置按钮
                IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings),
                  tooltip: '设置',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
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
                  child: _buildAutocompleteTextField(
                    controller: _targetWcController,
                    history: appState.targetWcHistory,
                    hintText: '输入或选择目标工作副本',
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _pickTargetWc,
                  child: const Text('选择目录...'),
                ),
                const SizedBox(width: 8),
                // SVN 操作按钮组
                _buildSvnOperationButtons(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建带历史记录下拉的文本输入框
  Widget _buildAutocompleteTextField({
    required TextEditingController controller,
    required List<String> history,
    String? hintText,
  }) {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (history.isEmpty) {
          return const Iterable<String>.empty();
        }
        // 如果输入为空，显示所有历史记录
        if (textEditingValue.text.isEmpty) {
          return history;
        }
        // 否则过滤匹配的历史记录
        return history.where((String option) {
          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController fieldController,
        FocusNode focusNode,
        VoidCallback onFieldSubmitted,
      ) {
        // 同步外部 controller 的值到 fieldController
        if (fieldController.text != controller.text) {
          fieldController.text = controller.text;
        }
        // 监听 fieldController 的变化，同步到外部 controller
        fieldController.addListener(() {
          if (controller.text != fieldController.text) {
            controller.text = fieldController.text;
          }
        });
        
        return TextField(
          controller: fieldController,
          focusNode: focusNode,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: hintText,
            suffixIcon: history.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    onPressed: () {
                      // 触发显示下拉选项
                      focusNode.requestFocus();
                      fieldController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: fieldController.text.length,
                      );
                    },
                    tooltip: '显示历史记录',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                : null,
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<String> onSelected,
        Iterable<String> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 600),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(
                      option,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
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
                              // 使用同步方法检查合并状态
                              final isMerged = appState.isRevisionMergedSync(entry.revision);
                              
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
                                    ? () async => await appState.setCurrentPage(0, sourceUrl: sourceUrl)
                                    : null,
                                tooltip: '第一页',
                              ),
                              IconButton(
                                icon: const Icon(Icons.chevron_left),
                                onPressed: (appState.currentPage > 0 && !appState.isLoadingData)
                                    ? () async => await appState.previousPage(sourceUrl: sourceUrl)
                                    : null,
                                tooltip: '上一页',
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      appState.totalPages > 0
                                          ? '第 ${appState.currentPage + 1} / ${appState.totalPages} 页'
                                          : '第 ${appState.currentPage + 1} 页',
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
                                    ? () async => await appState.nextPage(sourceUrl: sourceUrl)
                                    : null,
                                tooltip: '下一页',
                              ),
                              // 最后一页按钮（跳转到当前缓存的最后一页）
                              IconButton(
                                icon: const Icon(Icons.last_page),
                                // 只有当有数据且不在最后一页时才启用
                                onPressed: (appState.totalPages > 0 && 
                                           appState.currentPage < appState.totalPages - 1 && 
                                           !appState.isLoadingData)
                                    ? () async {
                                        // 直接跳转到最后一页（页码从0开始）
                                        final lastPage = appState.totalPages - 1;
                                        await appState.setCurrentPage(lastPage, sourceUrl: sourceUrl);
                                      }
                                    : null,
                                tooltip: '最后一页',
                              ),
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
                                                appState.setCurrentPage(0, sourceUrl: _sourceUrlController.text.trim());
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
