/// 配置管理服务
///
/// 负责加载和管理应用配置文件
/// 
/// 配置文件策略：
/// - 预置配置（只读）：打包在 assets/config/source_urls.json
/// - 用户配置（可写）：保存在 Application Support 目录
/// - 读取优先级：用户配置 > 预置配置

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';
import 'logger_service.dart';

class ConfigService {
  /// 单例模式
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  AppConfig? _config;
  
  /// 用户配置文件路径缓存
  String? _userConfigPath;

  /// 获取用户配置目录（可写）
  /// 
  /// 路径：
  /// - Windows: %APPDATA%/com.example.SvnMergeTool/config/
  /// - macOS: ~/Library/Application Support/com.example.SvnMergeTool/config/
  /// - Linux: ~/.local/share/com.example.SvnMergeTool/config/
  Future<String> getUserConfigDir() async {
    final appDir = await getApplicationSupportDirectory();
    return path.join(appDir.path, 'config');
  }

  /// 获取用户配置文件路径
  Future<String> getUserConfigFilePath() async {
    if (_userConfigPath != null) {
      return _userConfigPath!;
    }
    final configDir = await getUserConfigDir();
    _userConfigPath = path.join(configDir, 'source_urls.json');
    return _userConfigPath!;
  }

  /// 加载配置文件
  /// 
  /// 优先级：
  /// 1. 用户配置（Application Support 目录）
  /// 2. 预置配置（assets）
  Future<AppConfig> loadConfig() async {
    if (_config != null) {
      return _config!;
    }
    
    try {
      String content;
      String source;
      
      // 策略1: 优先从用户配置目录加载
      final userConfigPath = await getUserConfigFilePath();
      final userConfigFile = File(userConfigPath);
      
      if (await userConfigFile.exists()) {
        content = await userConfigFile.readAsString();
        source = '用户配置';
        AppLogger.config.info('从用户配置加载：$userConfigPath');
      } else {
        // 策略2: 从 assets 加载预置配置
        try {
          content = await rootBundle.loadString('assets/config/source_urls.json');
          source = '预置配置';
          AppLogger.config.info('从预置配置加载（assets）');
        } catch (assetsError) {
          AppLogger.config.warn('预置配置加载失败：$assetsError');
          throw Exception('无法加载配置文件');
        }
      }
      
      final json = jsonDecode(content) as Map<String, dynamic>;
      _config = AppConfig.fromJson(json);
      
      AppLogger.config.info('配置加载成功（$source）：${_config!.sourceUrls.length} 个源 URL');
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

  /// 保存配置文件（始终保存到用户配置目录）
  Future<void> saveConfig(AppConfig config) async {
    final configPath = await getUserConfigFilePath();
    final configFile = File(configPath);
    
    try {
      // 确保目录存在
      await configFile.parent.create(recursive: true);
      
      // 写入文件
      final json = config.toJson();
      final content = const JsonEncoder.withIndent('  ').convert(json);
      await configFile.writeAsString(content);
      
      _config = config;
      AppLogger.config.info('配置已保存到用户目录：$configPath');
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

