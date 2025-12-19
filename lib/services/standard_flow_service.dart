/// 标准流程管理服务
///
/// 负责管理内置标准流程的生成和更新。
/// 标准流程是只读的，由程序自动管理。
library;

import 'dart:convert';
import 'dart:io';

import '../pipeline/graph/merge_flow_builder.dart';
import '../pipeline/graph/stage_definition.dart';
import 'logger_service.dart';

/// 标准流程服务
class StandardFlowService {
  /// 当前标准流版本
  /// 当标准流定义发生变化时，需要更新此版本号
  static const String currentVersion = '1.0.0';

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
    // 使用 FlowDefinition 生成标准流程
    final flow = FlowDefinition.standardMergeFlow();
    final controller = MergeFlowBuilder.buildFromDefinition(flow);
    
    // 导出为 JSON
    final json = MergeFlowBuilder.toJson(controller);
    
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
}
