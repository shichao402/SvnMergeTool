/// 阶段定义
/// 
/// 这是统一的节点抽象层，用于同时生成：
/// 1. UI 表现层的节点（用于流程图显示）
/// 2. 执行层的节点逻辑（用于实际执行）
/// 
/// 设计原则：
/// - 单一数据源：所有节点信息从这里派生
/// - 解耦表现与执行：UI 和执行器各自从定义生成所需数据
/// - 支持用户自定义：未来可以让用户通过编辑器创建定义

import 'package:flutter/material.dart';
import '../models/stage_type.dart';
import 'stage_data.dart';

/// 端口定义
/// 
/// 定义一个输入或输出端口的元数据
class PortDefinition {
  /// 端口 ID（唯一标识）
  final String id;
  
  /// 端口显示名称
  final String name;
  
  /// 端口描述（可选）
  final String? description;
  
  /// 是否是默认端口（用于自动连接）
  final bool isDefault;
  
  const PortDefinition({
    required this.id,
    required this.name,
    this.description,
    this.isDefault = false,
  });
  
  /// 标准输入端口
  static const input = PortDefinition(
    id: 'in',
    name: '输入',
    isDefault: true,
  );
  
  /// 标准成功输出端口
  static const success = PortDefinition(
    id: 'success',
    name: '成功',
    description: '执行成功后的出口',
    isDefault: true,
  );
  
  /// 标准失败输出端口
  static const failure = PortDefinition(
    id: 'failure',
    name: '失败',
    description: '执行失败后的出口',
  );
}

/// 阶段定义
/// 
/// 定义一个流程阶段的完整信息，包括：
/// - 基本信息（ID、名称、类型）
/// - 端口定义（输入/输出）
/// - 执行配置（脚本、参数等）
class StageDefinition {
  /// 阶段 ID（唯一标识）
  final String id;
  
  /// 阶段类型
  final StageType type;
  
  /// 阶段名称
  final String name;
  
  /// 阶段描述
  final String? description;
  
  /// 是否启用
  final bool enabled;
  
  /// 输入端口列表
  final List<PortDefinition> inputPorts;
  
  /// 输出端口列表
  final List<PortDefinition> outputPorts;
  
  // ==================== 执行配置 ====================
  
  /// 脚本路径
  final String? scriptPath;
  
  /// 脚本参数
  final List<String>? scriptArgs;
  
  /// 提交消息模板
  final String? commitMessageTemplate;
  
  /// Review 输入配置
  final ReviewInputData? reviewInput;
  
  const StageDefinition({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.enabled = true,
    this.inputPorts = const [PortDefinition.input],
    this.outputPorts = const [PortDefinition.success],
    this.scriptPath,
    this.scriptArgs,
    this.commitMessageTemplate,
    this.reviewInput,
  });
  
  /// 获取默认输入端口 ID
  String? get defaultInputPortId {
    for (final port in inputPorts) {
      if (port.isDefault) return port.id;
    }
    return inputPorts.isNotEmpty ? inputPorts.first.id : null;
  }
  
  /// 获取默认输出端口 ID
  String? get defaultOutputPortId {
    for (final port in outputPorts) {
      if (port.isDefault) return port.id;
    }
    return outputPorts.isNotEmpty ? outputPorts.first.id : null;
  }
  
  /// 获取失败端口 ID（如果有）
  String? get failurePortId {
    for (final port in outputPorts) {
      if (port.id == 'failure') return port.id;
    }
    return null;
  }
  
  /// 转换为 StageData（用于执行）
  StageData toStageData() {
    return StageData(
      type: type,
      name: name,
      description: description,
      enabled: enabled,
      scriptPath: scriptPath,
      scriptArgs: scriptArgs,
      commitMessageTemplate: commitMessageTemplate,
      reviewInput: reviewInput,
    );
  }
  
  // ==================== 工厂方法 ====================
  
  /// 创建准备阶段
  factory StageDefinition.prepare({
    String id = 'prepare',
    String name = '准备',
  }) {
    return StageDefinition(
      id: id,
      type: StageType.prepare,
      name: name,
      inputPorts: const [],  // 起始节点无输入
      outputPorts: const [PortDefinition.success],
    );
  }
  
  /// 创建更新阶段
  factory StageDefinition.update({
    String id = 'update',
    String name = '更新',
  }) {
    return StageDefinition(
      id: id,
      type: StageType.update,
      name: name,
      inputPorts: const [PortDefinition.input],
      outputPorts: const [PortDefinition.success],
    );
  }
  
  /// 创建合并阶段
  factory StageDefinition.merge({
    String id = 'merge',
    String name = '合并',
  }) {
    return StageDefinition(
      id: id,
      type: StageType.merge,
      name: name,
      inputPorts: const [PortDefinition.input],
      outputPorts: const [PortDefinition.success],
    );
  }
  
  /// 创建提交阶段（带失败分支）
  factory StageDefinition.commit({
    String id = 'commit',
    String name = '提交',
    String? messageTemplate,
    bool hasFailureBranch = true,
  }) {
    return StageDefinition(
      id: id,
      type: StageType.commit,
      name: name,
      inputPorts: const [PortDefinition.input],
      outputPorts: hasFailureBranch
          ? const [PortDefinition.success, PortDefinition.failure]
          : const [PortDefinition.success],
      commitMessageTemplate: messageTemplate,
    );
  }
  
  /// 创建审核阶段
  factory StageDefinition.review({
    required String id,
    required String name,
    required ReviewInputData input,
  }) {
    return StageDefinition(
      id: id,
      type: StageType.review,
      name: name,
      inputPorts: const [PortDefinition.input],
      outputPorts: const [PortDefinition.success],
      reviewInput: input,
    );
  }
  
  /// 创建脚本阶段
  factory StageDefinition.script({
    required String id,
    required String name,
    required String scriptPath,
    List<String>? args,
    bool hasFailureBranch = false,
  }) {
    return StageDefinition(
      id: id,
      type: StageType.script,
      name: name,
      inputPorts: const [PortDefinition.input],
      outputPorts: hasFailureBranch
          ? const [PortDefinition.success, PortDefinition.failure]
          : const [PortDefinition.success],
      scriptPath: scriptPath,
      scriptArgs: args,
    );
  }
}

/// 连接定义
/// 
/// 定义两个阶段之间的连接关系
class ConnectionDefinition {
  /// 源阶段 ID
  final String sourceStageId;
  
  /// 源端口 ID
  final String sourcePortId;
  
  /// 目标阶段 ID
  final String targetStageId;
  
  /// 目标端口 ID
  final String targetPortId;
  
  const ConnectionDefinition({
    required this.sourceStageId,
    required this.sourcePortId,
    required this.targetStageId,
    required this.targetPortId,
  });
  
  /// 使用默认端口创建连接
  factory ConnectionDefinition.simple({
    required String from,
    required String to,
    String sourcePort = 'success',
    String targetPort = 'in',
  }) {
    return ConnectionDefinition(
      sourceStageId: from,
      sourcePortId: sourcePort,
      targetStageId: to,
      targetPortId: targetPort,
    );
  }
  
  /// 创建失败分支连接
  factory ConnectionDefinition.failure({
    required String from,
    required String to,
    String targetPort = 'in',
  }) {
    return ConnectionDefinition(
      sourceStageId: from,
      sourcePortId: 'failure',
      targetStageId: to,
      targetPortId: targetPort,
    );
  }
  
  /// 生成连接 ID
  String get id => '${sourceStageId}_${sourcePortId}_to_${targetStageId}_${targetPortId}';
}

/// 流程定义
/// 
/// 定义完整的流程图，包括所有阶段和连接
class FlowDefinition {
  /// 流程名称
  final String name;
  
  /// 流程描述
  final String? description;
  
  /// 阶段定义列表
  final List<StageDefinition> stages;
  
  /// 连接定义列表
  final List<ConnectionDefinition> connections;
  
  const FlowDefinition({
    required this.name,
    this.description,
    required this.stages,
    required this.connections,
  });
  
  /// 获取起始阶段（无输入端口或无入边的阶段）
  StageDefinition? get startStage {
    // 首先找无输入端口的
    for (final stage in stages) {
      if (stage.inputPorts.isEmpty) {
        return stage;
      }
    }
    
    // 然后找无入边的
    final targetIds = connections.map((c) => c.targetStageId).toSet();
    for (final stage in stages) {
      if (!targetIds.contains(stage.id)) {
        return stage;
      }
    }
    
    return stages.isNotEmpty ? stages.first : null;
  }
  
  /// 获取阶段的下一个阶段（通过指定端口）
  StageDefinition? getNextStage(String stageId, String portId) {
    for (final conn in connections) {
      if (conn.sourceStageId == stageId && conn.sourcePortId == portId) {
        return stages.firstWhere(
          (s) => s.id == conn.targetStageId,
          orElse: () => throw StateError('找不到阶段: ${conn.targetStageId}'),
        );
      }
    }
    return null;
  }
  
  /// 标准合并流程
  static FlowDefinition standardMergeFlow({
    String? commitMessageTemplate,
  }) {
    return FlowDefinition(
      name: '标准合并流程',
      description: 'prepare → update → merge → commit，失败时输入 CRID 重试',
      stages: [
        StageDefinition.prepare(),
        StageDefinition.update(),
        StageDefinition.merge(),
        StageDefinition.commit(
          messageTemplate: commitMessageTemplate ??
              r'[Merge] r${job.currentRevision} from ${job.sourceUrl}${input.crid_input: --crid=?}',
          hasFailureBranch: true,
        ),
        StageDefinition.review(
          id: 'crid_input',
          name: 'CRID 输入',
          input: const ReviewInputData(
            prompt: '提交失败，请输入 CRID',
            label: 'CRID',
            required: true,
            validationPattern: r'^\d+$',
            validationMessage: 'CRID 必须是数字',
          ),
        ),
      ],
      connections: [
        ConnectionDefinition.simple(from: 'prepare', to: 'update'),
        ConnectionDefinition.simple(from: 'update', to: 'merge'),
        ConnectionDefinition.simple(from: 'merge', to: 'commit'),
        ConnectionDefinition.failure(from: 'commit', to: 'crid_input'),
        ConnectionDefinition.simple(from: 'crid_input', to: 'commit'),
      ],
    );
  }
  
  /// 简单线性流程
  static FlowDefinition simpleFlow() {
    return FlowDefinition(
      name: '简单合并流程',
      description: 'prepare → update → merge → commit，无分支',
      stages: [
        StageDefinition.prepare(),
        StageDefinition.update(),
        StageDefinition.merge(),
        StageDefinition.commit(hasFailureBranch: false),
      ],
      connections: [
        ConnectionDefinition.simple(from: 'prepare', to: 'update'),
        ConnectionDefinition.simple(from: 'update', to: 'merge'),
        ConnectionDefinition.simple(from: 'merge', to: 'commit'),
      ],
    );
  }
}
