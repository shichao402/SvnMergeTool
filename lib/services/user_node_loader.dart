import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../pipeline/executors/builtin/script_executor.dart';
import '../pipeline/registry/node_type_definition.dart';
import '../pipeline/registry/node_type_registry.dart';
import '../pipeline/registry/param_spec.dart';
import '../pipeline/registry/port_spec.dart';
import 'logger_service.dart';

/// 用户自定义节点加载器
///
/// 从 `~/.svn_flow/nodes/` 目录加载用户定义的蓝图节点。
/// 节点定义文件格式为 `*.node.json`。
class UserNodeLoader {
  UserNodeLoader._();
  static final UserNodeLoader instance = UserNodeLoader._();

  /// 获取用户节点目录路径
  String get nodesDirectory {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.svn_flow/nodes';
  }

  /// 加载所有用户节点
  ///
  /// 返回成功加载的节点数量。
  Future<int> loadAllNodes() async {
    final dir = Directory(nodesDirectory);
    if (!await dir.exists()) {
      AppLogger.app.info('用户节点目录不存在: $nodesDirectory');
      return 0;
    }

    int loadedCount = 0;
    final registry = NodeTypeRegistry.instance;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.node.json')) {
        try {
          final definition = await _loadNodeFromFile(entity);
          if (definition != null) {
            registry.register(definition);
            loadedCount++;
            AppLogger.app.info('加载用户节点: ${definition.typeId} (${definition.name})');
          }
        } catch (e, stackTrace) {
          AppLogger.app.error('加载节点文件失败: ${entity.path}', e, stackTrace);
        }
      }
    }

    return loadedCount;
  }

  /// 从文件加载单个节点定义
  Future<NodeTypeDefinition?> _loadNodeFromFile(File file) async {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    final typeId = json['typeId'] as String?;
    if (typeId == null || typeId.isEmpty) {
      AppLogger.app.warn('节点定义缺少 typeId: ${file.path}');
      return null;
    }

    // 解析执行器配置
    final executorConfig = json['executor'] as Map<String, dynamic>?;
    if (executorConfig == null) {
      AppLogger.app.warn('节点定义缺少 executor 配置: ${file.path}');
      return null;
    }

    final executorType = executorConfig['type'] as String?;
    if (executorType != 'script') {
      AppLogger.app.warn('暂不支持的执行器类型: $executorType');
      return null;
    }

    // 解析端口
    final inputs = (json['inputs'] as List<dynamic>?)
            ?.map((e) => PortSpec.fromJson({
                  ...e as Map<String, dynamic>,
                  'direction': 'input',
                }))
            .toList() ??
        [PortSpec.defaultInput];

    final outputs = (json['outputs'] as List<dynamic>?)
            ?.map((e) => PortSpec.fromJson({
                  ...e as Map<String, dynamic>,
                  'direction': 'output',
                }))
            .toList() ??
        [PortSpec.success, PortSpec.failure];

    // 解析参数
    final params = (json['params'] as List<dynamic>?)
            ?.map((e) => ParamSpec.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    // 添加脚本执行器需要的隐藏参数
    final scriptPath = executorConfig['scriptPath'] as String? ?? '';
    final entryFunction = executorConfig['entryFunction'] as String? ?? 'main';
    final timeout = executorConfig['timeout'] as int? ?? 300;

    // 解析图标
    final iconName = json['icon'] as String? ?? 'extension';
    final icon = _parseIcon(iconName);

    // 解析颜色
    final colorName = json['color'] as String? ?? 'blue';
    final color = _parseColor(colorName);

    // 创建执行器
    final executor = _createScriptExecutor(scriptPath, entryFunction, timeout);

    return NodeTypeDefinition(
      typeId: typeId,
      name: json['name'] as String? ?? typeId,
      description: json['description'] as String?,
      icon: icon,
      color: color,
      category: json['category'] as String?,
      inputs: inputs,
      outputs: outputs,
      params: params,
      executor: executor,
      isUserDefined: true,
      rawConfig: json,
    );
  }

  /// 创建脚本执行器
  NodeExecutor _createScriptExecutor(
      String scriptPath, String entryFunction, int timeout) {
    return ({
      required Map<String, dynamic> input,
      required Map<String, dynamic> config,
      required context,
    }) {
      return ScriptExecutor.execute(
        input: input,
        config: {
          ...config,
          'scriptPath': scriptPath,
          'entryFunction': entryFunction,
          'timeout': timeout,
        },
        context: context,
      );
    };
  }

  /// 解析图标名称
  IconData _parseIcon(String name) {
    const iconMap = <String, IconData>{
      // 常用图标
      'play_arrow': Icons.play_arrow,
      'settings': Icons.settings,
      'code': Icons.code,
      'terminal': Icons.terminal,
      'folder': Icons.folder,
      'file_copy': Icons.file_copy,
      'cloud_upload': Icons.cloud_upload,
      'cloud_download': Icons.cloud_download,
      'sync': Icons.sync,
      'refresh': Icons.refresh,
      'check_circle': Icons.check_circle,
      'error': Icons.error,
      'warning': Icons.warning,
      'info': Icons.info,
      'help': Icons.help,
      'build': Icons.build,
      'extension': Icons.extension,
      'widgets': Icons.widgets,
      'api': Icons.api,
      'webhook': Icons.webhook,
      'send': Icons.send,
      'mail': Icons.mail,
      'notifications': Icons.notifications,
      'schedule': Icons.schedule,
      'timer': Icons.timer,
      'pause': Icons.pause,
      'stop': Icons.stop,
      'replay': Icons.replay,
      'loop': Icons.loop,
      'merge_type': Icons.merge_type,
      'call_split': Icons.call_split,
      'device_hub': Icons.device_hub,
      'account_tree': Icons.account_tree,
      'fork_right': Icons.fork_right,
      'alt_route': Icons.alt_route,
      'commit': Icons.commit,
      'edit': Icons.edit,
      'save': Icons.save,
      'delete': Icons.delete,
      'backup': Icons.backup,
      'restore': Icons.restore,
      'history': Icons.history,
      'update': Icons.update,
      'download': Icons.download,
      'upload': Icons.upload,
      'search': Icons.search,
      'find_replace': Icons.find_replace,
      'compare': Icons.compare,
      'difference': Icons.difference,
      'rule': Icons.rule,
      'gavel': Icons.gavel,
      'verified': Icons.verified,
      'policy': Icons.policy,
      'security': Icons.security,
      'lock': Icons.lock,
      'lock_open': Icons.lock_open,
      'key': Icons.key,
      'vpn_key': Icons.vpn_key,
      'fingerprint': Icons.fingerprint,
      'face': Icons.face,
      'person': Icons.person,
      'people': Icons.people,
      'group': Icons.group,
      'groups': Icons.groups,
      'rate_review': Icons.rate_review,
      'reviews': Icons.reviews,
      'comment': Icons.comment,
      'chat': Icons.chat,
      'forum': Icons.forum,
      'question_answer': Icons.question_answer,
      'bug_report': Icons.bug_report,
      'report': Icons.report,
      'flag': Icons.flag,
      'bookmark': Icons.bookmark,
      'star': Icons.star,
      'favorite': Icons.favorite,
      'thumb_up': Icons.thumb_up,
      'thumb_down': Icons.thumb_down,
      'done': Icons.done,
      'done_all': Icons.done_all,
      'close': Icons.close,
      'cancel': Icons.cancel,
      'add': Icons.add,
      'remove': Icons.remove,
      'add_circle': Icons.add_circle,
      'remove_circle': Icons.remove_circle,
      'expand': Icons.expand,
      'compress': Icons.compress,
      'fullscreen': Icons.fullscreen,
      'fullscreen_exit': Icons.fullscreen_exit,
      'zoom_in': Icons.zoom_in,
      'zoom_out': Icons.zoom_out,
      'visibility': Icons.visibility,
      'visibility_off': Icons.visibility_off,
      'light_mode': Icons.light_mode,
      'dark_mode': Icons.dark_mode,
      'palette': Icons.palette,
      'format_paint': Icons.format_paint,
      'brush': Icons.brush,
      'draw': Icons.draw,
      'design_services': Icons.design_services,
      'architecture': Icons.architecture,
      'engineering': Icons.engineering,
      'construction': Icons.construction,
      'handyman': Icons.handyman,
      'precision_manufacturing': Icons.precision_manufacturing,
      'science': Icons.science,
      'biotech': Icons.biotech,
      'psychology': Icons.psychology,
      'memory': Icons.memory,
      'dns': Icons.dns,
      'storage': Icons.storage,
      'database': Icons.storage,
      'cloud': Icons.cloud,
      'cloud_queue': Icons.cloud_queue,
      'cloud_done': Icons.cloud_done,
      'cloud_off': Icons.cloud_off,
      'computer': Icons.computer,
      'desktop_windows': Icons.desktop_windows,
      'laptop': Icons.laptop,
      'phone_android': Icons.phone_android,
      'phone_iphone': Icons.phone_iphone,
      'tablet': Icons.tablet,
      'watch': Icons.watch,
      'tv': Icons.tv,
      'router': Icons.router,
      'devices': Icons.devices,
      'developer_mode': Icons.developer_mode,
      'developer_board': Icons.developer_board,
      'bug': Icons.bug_report,
      'adb': Icons.adb,
      'usb': Icons.usb,
      'bluetooth': Icons.bluetooth,
      'wifi': Icons.wifi,
      'signal_cellular_alt': Icons.signal_cellular_alt,
      'network_check': Icons.network_check,
      'speed': Icons.speed,
      'trending_up': Icons.trending_up,
      'trending_down': Icons.trending_down,
      'trending_flat': Icons.trending_flat,
      'analytics': Icons.analytics,
      'insights': Icons.insights,
      'leaderboard': Icons.leaderboard,
      'assessment': Icons.assessment,
      'bar_chart': Icons.bar_chart,
      'pie_chart': Icons.pie_chart,
      'show_chart': Icons.show_chart,
      'timeline': Icons.timeline,
      'receipt': Icons.receipt,
      'receipt_long': Icons.receipt_long,
      'description': Icons.description,
      'article': Icons.article,
      'note': Icons.note,
      'sticky_note_2': Icons.sticky_note_2,
      'task': Icons.task,
      'task_alt': Icons.task_alt,
      'checklist': Icons.checklist,
      'assignment': Icons.assignment,
      'assignment_turned_in': Icons.assignment_turned_in,
      'pending': Icons.pending,
      'pending_actions': Icons.pending_actions,
      'hourglass_empty': Icons.hourglass_empty,
      'hourglass_full': Icons.hourglass_full,
      'access_time': Icons.access_time,
      'event': Icons.event,
      'calendar_today': Icons.calendar_today,
      'date_range': Icons.date_range,
    };

    return iconMap[name] ?? Icons.extension;
  }

  /// 解析颜色名称
  Color _parseColor(String name) {
    const colorMap = <String, Color>{
      'red': Colors.red,
      'pink': Colors.pink,
      'purple': Colors.purple,
      'deepPurple': Colors.deepPurple,
      'indigo': Colors.indigo,
      'blue': Colors.blue,
      'lightBlue': Colors.lightBlue,
      'cyan': Colors.cyan,
      'teal': Colors.teal,
      'green': Colors.green,
      'lightGreen': Colors.lightGreen,
      'lime': Colors.lime,
      'yellow': Colors.yellow,
      'amber': Colors.amber,
      'orange': Colors.orange,
      'deepOrange': Colors.deepOrange,
      'brown': Colors.brown,
      'grey': Colors.grey,
      'blueGrey': Colors.blueGrey,
      'black': Colors.black,
      'white': Colors.white,
    };

    return colorMap[name] ?? Colors.blue;
  }

  /// 重新加载所有用户节点
  ///
  /// 清除现有的用户节点，然后重新加载。
  Future<int> reloadAllNodes() async {
    NodeTypeRegistry.instance.clearUserDefinitions();
    return loadAllNodes();
  }
}

/// 加载所有用户节点（便捷方法）
Future<int> loadUserNodes() => UserNodeLoader.instance.loadAllNodes();

/// 重新加载所有用户节点（便捷方法）
Future<int> reloadUserNodes() => UserNodeLoader.instance.reloadAllNodes();
