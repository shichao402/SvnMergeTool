import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../registry/registry.dart';
import 'generic_executor.dart';

/// 用户自定义节点加载器
///
/// 从文件系统加载用户定义的节点类型（JSON 格式）。
class UserNodeLoader {
  /// 默认节点目录
  static String get defaultNodeDir {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return '$home/.svn_flow/nodes';
  }

  /// 加载用户自定义节点
  ///
  /// [nodeDir] 节点定义目录，默认为 ~/.svn_flow/nodes
  static Future<List<NodeTypeDefinition>> loadUserNodes([String? nodeDir]) async {
    final dir = Directory(nodeDir ?? defaultNodeDir);
    final definitions = <NodeTypeDefinition>[];

    if (!dir.existsSync()) {
      return definitions;
    }

    for (final file in dir.listSync()) {
      if (file is File && file.path.endsWith('.node.json')) {
        try {
          final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          final definition = parseNodeDefinition(json);
          definitions.add(definition);
        } catch (e) {
          // 解析失败，跳过
          print('加载节点定义失败: ${file.path}, 错误: $e');
        }
      }
    }

    return definitions;
  }

  /// 加载并注册用户节点
  static Future<int> loadAndRegisterUserNodes([String? nodeDir]) async {
    final definitions = await loadUserNodes(nodeDir);
    final registry = NodeTypeRegistry.instance;

    for (final def in definitions) {
      registry.register(def);
    }

    return definitions.length;
  }

  /// 解析节点定义
  static NodeTypeDefinition parseNodeDefinition(Map<String, dynamic> json) {
    final typeId = json['typeId'] as String;
    final name = json['name'] as String;
    final description = json['description'] as String?;
    final icon = _parseIcon(json['icon']);
    final color = _parseColor(json['color']);
    final category = json['category'] as String?;

    final inputs = (json['inputs'] as List<dynamic>?)
            ?.map((p) => PortSpec.fromJson(p as Map<String, dynamic>))
            .toList() ??
        const [PortSpec.defaultInput];

    final outputs = (json['outputs'] as List<dynamic>?)
            ?.map((p) => PortSpec.fromJson(p as Map<String, dynamic>))
            .toList() ??
        const [PortSpec.success, PortSpec.failure];

    final params = (json['params'] as List<dynamic>?)
            ?.map((p) => ParamSpec.fromJson(p as Map<String, dynamic>))
            .toList() ??
        const [];

    final executorConfig = json['executor'] as Map<String, dynamic>;
    final executor = GenericExecutor.fromConfig(executorConfig);

    return NodeTypeDefinition(
      typeId: typeId,
      name: name,
      description: description,
      icon: icon,
      color: color,
      category: category,
      inputs: inputs,
      outputs: outputs,
      params: params,
      executor: executor,
      isUserDefined: true,
      rawConfig: json,
    );
  }

  /// 解析图标
  static IconData _parseIcon(dynamic iconValue) {
    if (iconValue == null) return Icons.extension;

    if (iconValue is String) {
      // 支持常用图标名称
      return switch (iconValue) {
        'play_arrow' => Icons.play_arrow,
        'stop' => Icons.stop,
        'pause' => Icons.pause,
        'refresh' => Icons.refresh,
        'build' => Icons.build,
        'code' => Icons.code,
        'terminal' => Icons.terminal,
        'input' => Icons.input,
        'output' => Icons.output,
        'upload' => Icons.upload,
        'download' => Icons.download,
        'merge' => Icons.merge,
        'commit' => Icons.commit,
        'check' => Icons.check,
        'close' => Icons.close,
        'error' => Icons.error,
        'warning' => Icons.warning,
        'info' => Icons.info,
        'help' => Icons.help,
        'settings' => Icons.settings,
        'folder' => Icons.folder,
        'file' => Icons.insert_drive_file,
        'http' => Icons.http,
        'api' => Icons.api,
        'cloud' => Icons.cloud,
        'sync' => Icons.sync,
        'timer' => Icons.timer,
        'schedule' => Icons.schedule,
        'hourglass_empty' => Icons.hourglass_empty,
        'hourglass_full' => Icons.hourglass_full,
        'create_new_folder' => Icons.create_new_folder,
        'cleaning_services' => Icons.cleaning_services,
        'extension' => Icons.extension,
        _ => Icons.extension,
      };
    }

    return Icons.extension;
  }

  /// 解析颜色
  static Color _parseColor(dynamic colorValue) {
    if (colorValue == null) return Colors.grey;

    if (colorValue is String) {
      // 支持 #RRGGBB 或 #AARRGGBB 格式
      if (colorValue.startsWith('#')) {
        final hex = colorValue.substring(1);
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        } else if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
      }

      // 支持颜色名称
      return switch (colorValue.toLowerCase()) {
        'red' => Colors.red,
        'pink' => Colors.pink,
        'purple' => Colors.purple,
        'deepPurple' || 'deep_purple' => Colors.deepPurple,
        'indigo' => Colors.indigo,
        'blue' => Colors.blue,
        'lightBlue' || 'light_blue' => Colors.lightBlue,
        'cyan' => Colors.cyan,
        'teal' => Colors.teal,
        'green' => Colors.green,
        'lightGreen' || 'light_green' => Colors.lightGreen,
        'lime' => Colors.lime,
        'yellow' => Colors.yellow,
        'amber' => Colors.amber,
        'orange' => Colors.orange,
        'deepOrange' || 'deep_orange' => Colors.deepOrange,
        'brown' => Colors.brown,
        'grey' || 'gray' => Colors.grey,
        'blueGrey' || 'blue_grey' => Colors.blueGrey,
        _ => Colors.grey,
      };
    }

    return Colors.grey;
  }

  /// 保存节点定义
  static Future<void> saveNodeDefinition(
    NodeTypeDefinition definition, [
    String? nodeDir,
  ]) async {
    final dir = Directory(nodeDir ?? defaultNodeDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final file = File('${dir.path}/${definition.typeId}.node.json');
    final json = _definitionToJson(definition);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// 删除节点定义
  static Future<void> deleteNodeDefinition(
    String typeId, [
    String? nodeDir,
  ]) async {
    final dir = Directory(nodeDir ?? defaultNodeDir);
    final file = File('${dir.path}/$typeId.node.json');
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// 将定义转换为 JSON
  static Map<String, dynamic> _definitionToJson(NodeTypeDefinition definition) {
    // 如果有原始配置，直接返回
    if (definition.rawConfig != null) {
      return definition.rawConfig!;
    }

    return {
      'typeId': definition.typeId,
      'name': definition.name,
      if (definition.description != null) 'description': definition.description,
      'icon': _iconToString(definition.icon),
      'color': _colorToString(definition.color),
      if (definition.category != null) 'category': definition.category,
      'inputs': definition.inputs.map((p) => p.toJson()).toList(),
      'outputs': definition.outputs.map((p) => p.toJson()).toList(),
      'params': definition.params.map((p) => p.toJson()).toList(),
      // executor 配置需要单独处理
    };
  }

  static String _iconToString(IconData icon) {
    // 简化处理，返回默认值
    return 'extension';
  }

  static String _colorToString(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }
}
