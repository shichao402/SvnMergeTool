/// 持久化存储服务
///
/// 负责管理应用的历史记录、队列等数据的持久化存储
/// 使用 shared_preferences 存储简单数据，使用 JSON 文件存储复杂数据

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import '../models/merge_job.dart';
import 'logger_service.dart';

class StorageService {
  /// 单例模式
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 获取应用数据目录
  Future<String> getDataDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dataDir = Directory(path.join(appDir.path, 'SvnMergeTool'));
    
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    
    return dataDir.path;
  }

  // ===== 历史记录 =====

  /// 获取源 URL 历史记录
  Future<List<String>> getSourceUrlHistory() async {
    await _ensureInit();
    return _prefs!.getStringList('source_url_history') ?? [];
  }

  /// 保存源 URL 历史记录
  Future<void> saveSourceUrlHistory(List<String> urls) async {
    await _ensureInit();
    // 去重并限制数量
    final uniqueUrls = urls.toSet().toList();
    if (uniqueUrls.length > 20) {
      uniqueUrls.removeRange(20, uniqueUrls.length);
    }
    await _prefs!.setStringList('source_url_history', uniqueUrls);
  }

  /// 添加源 URL 到历史记录
  Future<void> addSourceUrlToHistory(String url) async {
    final history = await getSourceUrlHistory();
    history.remove(url);  // 移除旧的
    history.insert(0, url);  // 添加到最前面
    await saveSourceUrlHistory(history);
  }

  /// 获取工作副本历史记录
  Future<List<String>> getTargetWcHistory() async {
    await _ensureInit();
    return _prefs!.getStringList('target_wc_history') ?? [];
  }

  /// 保存工作副本历史记录
  Future<void> saveTargetWcHistory(List<String> wcs) async {
    await _ensureInit();
    final uniqueWcs = wcs.toSet().toList();
    if (uniqueWcs.length > 20) {
      uniqueWcs.removeRange(20, uniqueWcs.length);
    }
    await _prefs!.setStringList('target_wc_history', uniqueWcs);
  }

  /// 添加工作副本到历史记录
  Future<void> addTargetWcToHistory(String wc) async {
    final history = await getTargetWcHistory();
    history.remove(wc);
    history.insert(0, wc);
    await saveTargetWcHistory(history);
  }

  /// 获取最后选择的源 URL
  Future<String?> getLastSourceUrl() async {
    await _ensureInit();
    return _prefs!.getString('last_source_url');
  }

  /// 保存最后选择的源 URL
  Future<void> saveLastSourceUrl(String url) async {
    await _ensureInit();
    await _prefs!.setString('last_source_url', url);
  }

  /// 获取最后选择的工作副本
  Future<String?> getLastTargetWc() async {
    await _ensureInit();
    return _prefs!.getString('last_target_wc');
  }

  /// 保存最后选择的工作副本
  Future<void> saveLastTargetWc(String wc) async {
    await _ensureInit();
    await _prefs!.setString('last_target_wc', wc);
  }

  // ===== 任务队列 =====

  /// 获取队列文件路径
  Future<String> _getQueueFilePath() async {
    final dataDir = await getDataDir();
    return path.join(dataDir, 'queue.json');
  }

  /// 加载任务队列
  Future<List<MergeJob>> loadQueue() async {
    try {
      final queueFile = File(await _getQueueFilePath());
      
      if (!await queueFile.exists()) {
        return [];
      }
      
      final content = await queueFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final jobsData = json['jobs'] as List<dynamic>;
      
      final jobs = jobsData
          .map((item) => MergeJob.fromJson(item as Map<String, dynamic>))
          .toList();
      
      // 程序重启后，将 running 状态重置为 pending
      final resetJobs = jobs.map((job) {
        if (job.status == JobStatus.running) {
          return job.copyWith(status: JobStatus.pending);
        }
        return job;
      }).toList();
      
      AppLogger.storage.info('已加载 ${resetJobs.length} 个任务');
      return resetJobs;
    } catch (e, stackTrace) {
      AppLogger.storage.error('加载队列失败', e, stackTrace);
      return [];
    }
  }

  /// 保存任务队列
  Future<void> saveQueue(List<MergeJob> jobs) async {
    try {
      final queueFile = File(await _getQueueFilePath());
      
      final json = {
        'jobs': jobs.map((job) => job.toJson()).toList(),
      };
      
      final content = const JsonEncoder.withIndent('  ').convert(json);
      await queueFile.writeAsString(content);
      
      AppLogger.storage.info('已保存 ${jobs.length} 个任务');
    } catch (e, stackTrace) {
      AppLogger.storage.error('保存队列失败', e, stackTrace);
    }
  }

  // ===== 设置 =====

  /// 获取默认最大重试次数
  Future<int> getDefaultMaxRetries() async {
    await _ensureInit();
    return _prefs!.getInt('default_max_retries') ?? 5;
  }

  /// 保存默认最大重试次数
  Future<void> saveDefaultMaxRetries(int value) async {
    await _ensureInit();
    await _prefs!.setInt('default_max_retries', value);
  }

  /// 获取单页记录数
  Future<int> getPageSize() async {
    await _ensureInit();
    return _prefs!.getInt('page_size') ?? 500;
  }

  /// 保存单页记录数
  Future<void> savePageSize(int value) async {
    await _ensureInit();
    await _prefs!.setInt('page_size', value);
  }

  // ===== 提交者过滤历史 =====

  /// 获取提交者过滤历史记录（最多5条）
  Future<List<String>> getAuthorFilterHistory() async {
    await _ensureInit();
    final history = _prefs!.getStringList('author_filter_history') ?? [];
    // 限制最多5条
    return history.take(5).toList();
  }

  /// 添加提交者到过滤历史记录
  /// 
  /// [author] 提交者名称（空值不记录）
  Future<void> addAuthorToFilterHistory(String author) async {
    if (author.trim().isEmpty) {
      return; // 空值不记录
    }
    
    await _ensureInit();
    final history = await getAuthorFilterHistory();
    
    // 移除旧的（如果存在）
    history.remove(author.trim());
    
    // 添加到最前面
    history.insert(0, author.trim());
    
    // 限制最多5条
    final limitedHistory = history.take(5).toList();
    
    await _prefs!.setStringList('author_filter_history', limitedHistory);
    AppLogger.storage.info('已添加提交者到过滤历史: ${author.trim()}（共 ${limitedHistory.length} 条）');
  }

  /// 获取最后使用的提交者过滤值
  Future<String?> getLastAuthorFilter() async {
    await _ensureInit();
    return _prefs!.getString('last_author_filter');
  }

  /// 保存最后使用的提交者过滤值
  Future<void> saveLastAuthorFilter(String author) async {
    if (author.trim().isEmpty) {
      return; // 空值不保存
    }
    await _ensureInit();
    await _prefs!.setString('last_author_filter', author.trim());
  }

  // ===== 预加载设置 =====

  /// 获取预加载设置（扁平化存储，不再使用嵌套 JSON）
  Future<Map<String, dynamic>> getPreloadSettings() async {
    await _ensureInit();
    return {
      'enabled': _prefs!.getBool('preload_enabled') ?? true,
      'stop_on_branch_point': _prefs!.getBool('preload_stop_on_branch_point') ?? true,
      'max_days': _prefs!.getInt('preload_max_days') ?? 90,
      'max_count': _prefs!.getInt('preload_max_count') ?? 1000,
      'stop_revision': _prefs!.getInt('preload_stop_revision') ?? 0,
      'stop_date': _prefs!.getString('preload_stop_date'),
    };
  }

  /// 保存预加载设置（扁平化存储，不再使用嵌套 JSON）
  Future<void> savePreloadSettings(Map<String, dynamic> settings) async {
    await _ensureInit();
    
    if (settings.containsKey('enabled')) {
      await _prefs!.setBool('preload_enabled', settings['enabled'] as bool);
    }
    if (settings.containsKey('stop_on_branch_point')) {
      await _prefs!.setBool('preload_stop_on_branch_point', settings['stop_on_branch_point'] as bool);
    }
    if (settings.containsKey('max_days')) {
      await _prefs!.setInt('preload_max_days', settings['max_days'] as int);
    }
    if (settings.containsKey('max_count')) {
      await _prefs!.setInt('preload_max_count', settings['max_count'] as int);
    }
    if (settings.containsKey('stop_revision')) {
      await _prefs!.setInt('preload_stop_revision', settings['stop_revision'] as int);
    }
    if (settings.containsKey('stop_date')) {
      final stopDate = settings['stop_date'];
      if (stopDate != null) {
        await _prefs!.setString('preload_stop_date', stopDate as String);
      } else {
        await _prefs!.remove('preload_stop_date');
      }
    }
    
    // 清理旧的嵌套 JSON 格式数据（如果存在）
    if (_prefs!.containsKey('preload_settings')) {
      await _prefs!.remove('preload_settings');
    }
    
    AppLogger.storage.info('已保存预加载设置');
  }

  /// 获取预加载是否启用
  Future<bool> getPreloadEnabled() async {
    await _ensureInit();
    return _prefs!.getBool('preload_enabled') ?? true;
  }

  /// 保存预加载是否启用
  Future<void> savePreloadEnabled(bool enabled) async {
    await _ensureInit();
    await _prefs!.setBool('preload_enabled', enabled);
  }

  /// 获取预加载停止条件：到达分支点
  Future<bool> getPreloadStopOnBranchPoint() async {
    await _ensureInit();
    return _prefs!.getBool('preload_stop_on_branch_point') ?? true;
  }

  /// 获取预加载停止条件：天数限制
  Future<int> getPreloadMaxDays() async {
    await _ensureInit();
    return _prefs!.getInt('preload_max_days') ?? 90;
  }

  /// 获取预加载停止条件：条数限制
  Future<int> getPreloadMaxCount() async {
    await _ensureInit();
    return _prefs!.getInt('preload_max_count') ?? 1000;
  }

  /// 获取预加载停止条件：指定版本
  Future<int> getPreloadStopRevision() async {
    await _ensureInit();
    return _prefs!.getInt('preload_stop_revision') ?? 0;
  }

  /// 获取预加载停止条件：指定日期
  Future<String?> getPreloadStopDate() async {
    await _ensureInit();
    return _prefs!.getString('preload_stop_date');
  }

  // ===== 私有方法 =====

  Future<void> _ensureInit() async {
    if (_prefs == null) {
      await init();
    }
  }
}

