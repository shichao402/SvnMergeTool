/// 配置管理服务
///
/// 负责加载和管理应用配置文件（config/source_urls.json）

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import '../models/app_config.dart';
import 'logger_service.dart';

class ConfigService {
  /// 单例模式
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  AppConfig? _config;

  /// 获取配置目录
  /// 
  /// 规则：
  /// - 开发环境：项目根目录/config/
  /// - 打包环境：可执行文件所在目录/config/
  String getConfigDir() {
    // 获取可执行文件所在目录
    final executable = Platform.resolvedExecutable;
    final execDir = path.dirname(executable);
    
    // 策略1：尝试项目根目录（开发环境）
    // 从可执行文件目录向上查找，直到找到包含 pubspec.yaml 的目录
    String? findProjectRoot(String startDir) {
      var current = Directory(startDir);
      for (var i = 0; i < 10; i++) {  // 最多向上查找10层
        final pubspec = File(path.join(current.path, 'pubspec.yaml'));
        final configDir = Directory(path.join(current.path, 'config'));
        
        if (pubspec.existsSync() && configDir.existsSync()) {
          return path.join(current.path, 'config');
        }
        
        final parent = current.parent;
        if (parent.path == current.path) break;  // 到达根目录
        current = parent;
      }
      return null;
    }
    
    // 先尝试找项目根目录（开发环境）
    final projectConfig = findProjectRoot(execDir);
    if (projectConfig != null) {
      return projectConfig;
    }
    
    // 策略2：macOS App Bundle 特殊处理（打包环境）
    if (Platform.isMacOS && execDir.contains('.app/Contents/MacOS')) {
      // .app/Contents/MacOS -> .app/Contents/Resources/config
      final appContents = execDir.replaceAll('/MacOS', '');
      final resourcesConfig = path.join(appContents, 'Resources', 'config');
      if (Directory(resourcesConfig).existsSync()) {
        return resourcesConfig;
      }
      // 备用：MacOS 目录下
      return path.join(execDir, 'config');
    }
    
    // 策略3：Windows/Linux 打包环境
    return path.join(execDir, 'config');
  }

  /// 获取配置文件路径
  String getConfigFilePath() {
    return path.join(getConfigDir(), 'source_urls.json');
  }

  /// 加载配置文件
  Future<AppConfig> loadConfig() async {
    if (_config != null) {
      return _config!;
    }
    
    try {
      // 策略1: 尝试从 assets 加载（推荐，避免沙箱权限问题）
      String content;
      try {
        content = await rootBundle.loadString('assets/config/source_urls.json');
        AppLogger.config.info('从 assets 加载配置文件成功');
      } catch (assetsError) {
        AppLogger.config.warn('从 assets 加载配置失败：$assetsError');
        
        // 策略2: 尝试从外部文件加载
        final configFile = File(getConfigFilePath());
        if (await configFile.exists()) {
          content = await configFile.readAsString();
          AppLogger.config.info('从外部文件加载配置：${configFile.path}');
        } else {
          AppLogger.config.warn('配置文件不存在：${configFile.path}');
          throw Exception('配置文件不存在');
        }
      }
      
      final json = jsonDecode(content) as Map<String, dynamic>;
      _config = AppConfig.fromJson(json);
      
      AppLogger.config.info('配置加载成功：${_config!.sourceUrls.length} 个源 URL');
      for (var url in _config!.enabledSourceUrls) {
        AppLogger.config.info('  - ${url.name}: ${url.url}');
      }
      
      return _config!;
    } catch (e, stackTrace) {
      AppLogger.config.warn('加载配置文件失败：$e');
      AppLogger.config.warn('使用默认配置');
      AppLogger.config.error('配置加载异常详情', e, stackTrace);
      _config = AppConfig.defaultConfig();
      return _config!;
    }
  }

  /// 保存配置文件
  Future<void> saveConfig(AppConfig config) async {
    final configFile = File(getConfigFilePath());
    
    try {
      // 确保目录存在
      await configFile.parent.create(recursive: true);
      
      // 写入文件
      final json = config.toJson();
      final content = const JsonEncoder.withIndent('  ').convert(json);
      await configFile.writeAsString(content);
      
      _config = config;
      AppLogger.config.info('配置已保存到：${configFile.path}');
    } catch (e, stackTrace) {
      AppLogger.config.error('保存配置文件失败', e, stackTrace);
      rethrow;
    }
  }

  /// 获取当前配置（如果未加载则先加载）
  Future<AppConfig> getConfig() async {
    if (_config == null) {
      await loadConfig();
    }
    return _config!;
  }

  /// 刷新配置（重新加载）
  Future<AppConfig> refreshConfig() async {
    _config = null;
    return await loadConfig();
  }

  /// 获取所有启用的源 URL
  Future<List<SourceUrlConfig>> getEnabledSourceUrls() async {
    final config = await getConfig();
    return config.enabledSourceUrls;
  }
}

