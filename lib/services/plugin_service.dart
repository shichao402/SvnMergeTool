/// 插件管理服务
/// 
/// 负责加载和执行合并后插件
/// 
/// 注意：Flutter 中的插件系统需要简化，因为无法像 Python 那样动态导入
/// 建议将插件编译为 Dart 代码并注册到插件管理器中

import 'dart:io';
import 'logger_service.dart';
import 'package:path/path.dart' as path;

/// 插件基类
abstract class PostMergePlugin {
  /// 插件名称
  String get name;

  /// 执行插件逻辑
  /// 
  /// [workingCopy] 工作副本路径
  /// 
  /// 如果失败请抛出异常
  Future<void> run(String workingCopy);
}

/// 插件管理器
class PluginService {
  /// 单例模式
  static final PluginService _instance = PluginService._internal();
  factory PluginService() => _instance;
  PluginService._internal();

  /// 已注册的插件列表
  final List<PostMergePlugin> _plugins = [];

  /// 注册插件
  /// 
  /// 开发者需要手动注册自定义插件：
  /// ```dart
  /// PluginService().registerPlugin(MyCustomPlugin());
  /// ```
  void registerPlugin(PostMergePlugin plugin) {
    _plugins.add(plugin);
    AppLogger.plugin.info('已注册插件：${plugin.name}');
  }

  /// 取消注册插件
  void unregisterPlugin(String name) {
    _plugins.removeWhere((p) => p.name == name);
    AppLogger.plugin.info('已取消注册插件：$name');
  }

  /// 获取所有插件
  List<PostMergePlugin> getPlugins() {
    return List.unmodifiable(_plugins);
  }

  /// 执行所有插件
  /// 
  /// [workingCopy] 工作副本路径
  /// 
  /// 如果任何插件失败，整个过程失败
  Future<void> runAllPlugins(String workingCopy) async {
    if (_plugins.isEmpty) {
      AppLogger.plugin.info('没有注册的插件');
      return;
    }

    AppLogger.plugin.info('开始执行 ${_plugins.length} 个插件...');

    for (final plugin in _plugins) {
      try {
        AppLogger.plugin.info('执行插件：${plugin.name}...');
        await plugin.run(workingCopy);
        AppLogger.plugin.info('插件 ${plugin.name} 执行完成');
      } catch (e, stackTrace) {
        AppLogger.plugin.error('插件 ${plugin.name} 执行失败', e, stackTrace);
        rethrow;
      }
    }

    AppLogger.plugin.info('所有插件执行完成');
  }

  /// 清空所有插件
  void clearPlugins() {
    _plugins.clear();
    AppLogger.plugin.info('已清空所有插件');
  }
}

/// 示例插件：构建脚本
/// 
/// 用法：
/// ```dart
/// PluginService().registerPlugin(BuildPlugin(
///   buildCommand: 'make all',
/// ));
/// ```
class BuildPlugin extends PostMergePlugin {
  final String buildCommand;

  BuildPlugin({required this.buildCommand});

  @override
  String get name => 'Build';

  @override
  Future<void> run(String workingCopy) async {
    AppLogger.plugin.info('执行构建命令：$buildCommand');

    final parts = buildCommand.split(' ');
    final executable = parts[0];
    final args = parts.sublist(1);

    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingCopy,
    );

    if (result.exitCode != 0) {
      throw Exception('构建失败（退出码 ${result.exitCode}）：\n${result.stderr}');
    }

    AppLogger.plugin.info('构建成功');
  }
}

/// 示例插件：执行脚本文件
/// 
/// 用法：
/// ```dart
/// PluginService().registerPlugin(ScriptPlugin(
///   scriptPath: '/path/to/script.sh',
/// ));
/// ```
class ScriptPlugin extends PostMergePlugin {
  final String scriptPath;
  final List<String> arguments;

  ScriptPlugin({
    required this.scriptPath,
    this.arguments = const [],
  });

  @override
  String get name => path.basename(scriptPath);

  @override
  Future<void> run(String workingCopy) async {
    final script = File(scriptPath);

    if (!await script.exists()) {
      throw Exception('脚本文件不存在：$scriptPath');
    }

    AppLogger.plugin.info('执行脚本：$scriptPath');

    // 根据平台选择执行方式
    final executable = Platform.isWindows ? 'cmd' : 'bash';
    final args = Platform.isWindows 
        ? ['/c', scriptPath, ...arguments]
        : [scriptPath, ...arguments];

    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingCopy,
    );

    if (result.exitCode != 0) {
      throw Exception('脚本执行失败（退出码 ${result.exitCode}）：\n${result.stderr}');
    }

    AppLogger.plugin.info('脚本执行成功');
  }
}

