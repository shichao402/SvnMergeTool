/// 标准流程管理服务
///
/// 负责管理内置标准流程的生成和更新。
/// 标准流程是只读的，由程序自动管理。
library;

import 'dart:convert';
import 'dart:io';

import '../pipeline/data/data.dart';
import 'logger_service.dart';

/// 标准流程服务
class StandardFlowService {
  /// 当前标准流版本
  /// 当标准流定义发生变化时，需要更新此版本号
  static const String currentVersion = '1.1.0';

  /// 标准流文件名
  static const String standardFlowFileName = 'standard.flow.json';

  /// 获取流程目录路径
  static String get flowsDirectory {
    final home = Platform.environment['HOME'] ?? 
                 Platform.environment['USERPROFILE'] ?? '.';
    return '$home/.svn_flow/flows';
  }

  /// 获取标准流文件路径
  static String get standardFlowPath => '$flowsDirectory/$standardFlowFileName';

  /// 检查并初始化标准流
  ///
  /// 如果标准流不存在或版本不匹配，则重新生成。
  /// 返回是否进行了重新生成。
  static Future<bool> ensureStandardFlow() async {
    try {
      final file = File(standardFlowPath);
      
      // 确保目录存在
      final dir = Directory(flowsDirectory);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        AppLogger.app.info('已创建流程目录: $flowsDirectory');
      }

      // 检查文件是否存在
      if (!file.existsSync()) {
        AppLogger.app.info('标准流程文件不存在，正在生成...');
        await _generateStandardFlow();
        return true;
      }

      // 检查版本
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final metadata = json['metadata'] as Map<String, dynamic>?;
      final version = metadata?['standardFlowVersion'] as String?;

      if (version != currentVersion) {
        AppLogger.app.info('标准流程版本不匹配 ($version -> $currentVersion)，正在更新...');
        await _generateStandardFlow();
        return true;
      }

      AppLogger.app.info('标准流程已是最新版本 ($currentVersion)');
      return false;
    } catch (e, stackTrace) {
      AppLogger.app.error('检查标准流程失败', e, stackTrace);
      // 尝试重新生成
      try {
        await _generateStandardFlow();
        return true;
      } catch (e2) {
        AppLogger.app.error('重新生成标准流程也失败', e2);
        return false;
      }
    }
  }

  /// 生成标准流程文件
  static Future<void> _generateStandardFlow() async {
    // 创建标准合并流程
    final graph = _createStandardMergeFlow();
    
    // 转换为 JSON
    final json = graph.toJson();
    
    // 添加元数据
    json['metadata'] = {
      'name': '标准合并流程',
      'description': '内置的标准 SVN 合并流程，包含准备、更新、合并、提交等阶段',
      'standardFlowVersion': currentVersion,
      'isBuiltin': true,
      'readonly': true,
      'generatedAt': DateTime.now().toIso8601String(),
    };

    // 写入文件
    final file = File(standardFlowPath);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    
    AppLogger.app.info('标准流程已生成: $standardFlowPath');
  }

  /// 创建标准合并流程
  static FlowGraphData _createStandardMergeFlow() {
    // 节点定义
    const nodes = [
      NodeData(
        id: 'prepare',
        typeId: 'prepare',
        x: 50,
        y: 100,
        config: {},
      ),
      NodeData(
        id: 'update',
        typeId: 'update',
        x: 250,
        y: 100,
        config: {},
      ),
      NodeData(
        id: 'merge',
        typeId: 'merge',
        x: 450,
        y: 100,
        config: {},
      ),
      NodeData(
        id: 'commit',
        typeId: 'commit',
        x: 650,
        y: 100,
        config: {},
      ),
    ];

    // 连接定义
    const connections = [
      // prepare -> update
      ConnectionData(
        id: 'conn_prepare_update',
        sourceNodeId: 'prepare',
        sourcePortId: 'success',
        targetNodeId: 'update',
        targetPortId: 'in',
      ),
      // update -> merge
      ConnectionData(
        id: 'conn_update_merge',
        sourceNodeId: 'update',
        sourcePortId: 'success',
        targetNodeId: 'merge',
        targetPortId: 'in',
      ),
      // merge -> commit
      ConnectionData(
        id: 'conn_merge_commit',
        sourceNodeId: 'merge',
        sourcePortId: 'success',
        targetNodeId: 'commit',
        targetPortId: 'in',
      ),
      // commit out_of_date -> update (重试)
      ConnectionData(
        id: 'conn_commit_retry',
        sourceNodeId: 'commit',
        sourcePortId: 'out_of_date',
        targetNodeId: 'update',
        targetPortId: 'in',
      ),
    ];

    return const FlowGraphData(
      version: '1.0',
      name: '标准合并流程',
      description: '内置的标准 SVN 合并流程',
      nodes: nodes,
      connections: connections,
    );
  }

  /// 判断是否为标准流程（只读）
  static bool isStandardFlow(String? flowPath) {
    if (flowPath == null) return false;
    return flowPath == standardFlowPath || 
           flowPath.endsWith('/$standardFlowFileName');
  }

  /// 强制重新生成标准流程
  static Future<void> regenerateStandardFlow() async {
    AppLogger.app.info('强制重新生成标准流程...');
    await _generateStandardFlow();
  }

  /// 加载标准流程
  static Future<FlowGraphData?> loadStandardFlow() async {
    try {
      final file = File(standardFlowPath);
      if (!file.existsSync()) {
        await ensureStandardFlow();
      }
      
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return FlowGraphData.fromJson(json);
    } catch (e) {
      AppLogger.app.error('加载标准流程失败: $e');
      return null;
    }
  }
}
