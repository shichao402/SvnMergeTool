/// SVN 日志文件列表缓存服务
///
/// 缓存 revision 涉及的文件列表，最多缓存 50 条
/// 使用 LRU（最近最少使用）策略管理缓存

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'logger_service.dart';

class LogFileCacheService {
  /// 单例模式
  static final LogFileCacheService _instance = LogFileCacheService._internal();
  factory LogFileCacheService() => _instance;
  LogFileCacheService._internal();

  /// 最大缓存数量
  static const int maxCacheSize = 50;

  /// 缓存数据：key 是 "sourceUrl:revision"，value 是文件列表
  final Map<String, List<String>> _cache = {};

  /// 访问顺序：用于实现 LRU
  final List<String> _accessOrder = [];

  /// 缓存文件路径
  String? _cacheFilePath;

  /// 初始化
  Future<void> init() async {
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(path.join(appDir.path, 'SvnMergeTool', 'cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheFilePath = path.join(cacheDir.path, 'log_files_cache.json');
    await _loadCache();
  }

  /// 加载缓存
  Future<void> _loadCache() async {
    if (_cacheFilePath == null) {
      await init();
    }

    try {
      final file = File(_cacheFilePath!);
      if (!await file.exists()) {
        return;
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      
      _cache.clear();
      _accessOrder.clear();
      
      for (final entry in json.entries) {
        final key = entry.key;
        final files = (entry.value as List<dynamic>)
            .map((e) => e.toString())
            .toList();
        _cache[key] = files;
        _accessOrder.add(key);
      }
      
      AppLogger.storage.info('已加载 ${_cache.length} 条文件列表缓存');
    } catch (e, stackTrace) {
      AppLogger.storage.error('加载文件列表缓存失败', e, stackTrace);
    }
  }

  /// 保存缓存
  Future<void> _saveCache() async {
    if (_cacheFilePath == null) {
      await init();
    }

    try {
      final file = File(_cacheFilePath!);
      final json = <String, dynamic>{};
      
      for (final entry in _cache.entries) {
        json[entry.key] = entry.value;
      }
      
      final content = const JsonEncoder.withIndent('  ').convert(json);
      await file.writeAsString(content);
      
      AppLogger.storage.info('已保存 ${_cache.length} 条文件列表缓存');
    } catch (e, stackTrace) {
      AppLogger.storage.error('保存文件列表缓存失败', e, stackTrace);
    }
  }

  /// 获取缓存 key
  String _getCacheKey(String sourceUrl, int revision) {
    return '$sourceUrl:$revision';
  }

  /// 更新访问顺序（LRU）
  void _updateAccessOrder(String key) {
    _accessOrder.remove(key);
    _accessOrder.add(key);
  }

  /// 移除最旧的缓存项（LRU）
  void _evictOldest() {
    if (_accessOrder.isEmpty) return;
    
    final oldestKey = _accessOrder.removeAt(0);
    _cache.remove(oldestKey);
    AppLogger.storage.debug('移除最旧的缓存项: $oldestKey');
  }

  /// 获取文件列表（优先从缓存读取）
  /// 
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  /// 
  /// 返回文件列表，如果缓存中没有则返回 null
  List<String>? getFiles(String sourceUrl, int revision) {
    final key = _getCacheKey(sourceUrl, revision);
    
    if (_cache.containsKey(key)) {
      _updateAccessOrder(key);
      AppLogger.storage.debug('从缓存获取文件列表: r$revision (${_cache[key]!.length} 个文件)');
      return _cache[key]!;
    }
    
    return null;
  }

  /// 保存文件列表到缓存
  /// 
  /// [sourceUrl] 源 URL
  /// [revision] 版本号
  /// [files] 文件列表
  Future<void> saveFiles(String sourceUrl, int revision, List<String> files) async {
    final key = _getCacheKey(sourceUrl, revision);
    
    // 如果已存在，更新访问顺序
    if (_cache.containsKey(key)) {
      _updateAccessOrder(key);
      _cache[key] = files;
    } else {
      // 如果缓存已满，移除最旧的
      if (_cache.length >= maxCacheSize) {
        _evictOldest();
      }
      
      _cache[key] = files;
      _accessOrder.add(key);
    }
    
    await _saveCache();
    AppLogger.storage.debug('已保存文件列表到缓存: r$revision (${files.length} 个文件)');
  }

  /// 清除缓存
  Future<void> clearCache() async {
    _cache.clear();
    _accessOrder.clear();
    await _saveCache();
    AppLogger.storage.info('已清除文件列表缓存');
  }

  /// 获取缓存统计信息
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _cache.length,
      'maxSize': maxCacheSize,
      'keys': _accessOrder.toList(),
    };
  }
}

