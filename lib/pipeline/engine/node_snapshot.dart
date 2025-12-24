/// 节点执行快照
///
/// 记录节点执行时的完整状态，用于事后查看
library;

import 'node_output.dart';

/// 节点执行状态
enum NodeExecutionStatus {
  /// 待执行
  pending,

  /// 执行中
  running,

  /// 已完成
  completed,

  /// 失败
  failed,

  /// 已跳过
  skipped,
}

/// 节点执行快照
///
/// 记录节点执行时的所有信息，包括：
/// - 输入数据
/// - 配置参数
/// - 输出结果
/// - 执行时间
class NodeSnapshot {
  /// 节点 ID
  final String nodeId;

  /// 节点类型 ID
  final String nodeTypeId;

  /// 节点名称
  final String? nodeName;

  /// 执行状态
  final NodeExecutionStatus status;

  /// 输入数据（执行前的上游数据）
  final Map<String, dynamic> inputData;

  /// 节点配置（包含默认值）
  final Map<String, dynamic> config;

  /// 输出结果
  final NodeOutput? output;

  /// 错误信息
  final String? error;

  /// 开始时间
  final DateTime startTime;

  /// 结束时间
  final DateTime? endTime;

  const NodeSnapshot({
    required this.nodeId,
    required this.nodeTypeId,
    this.nodeName,
    required this.status,
    required this.inputData,
    required this.config,
    this.output,
    this.error,
    required this.startTime,
    this.endTime,
  });

  /// 执行耗时（毫秒）
  int? get durationMs {
    if (endTime == null) return null;
    return endTime!.difference(startTime).inMilliseconds;
  }

  /// 是否成功
  bool get isSuccess => status == NodeExecutionStatus.completed && (output?.isSuccess ?? false);

  /// 复制并修改
  NodeSnapshot copyWith({
    String? nodeId,
    String? nodeTypeId,
    String? nodeName,
    NodeExecutionStatus? status,
    Map<String, dynamic>? inputData,
    Map<String, dynamic>? config,
    NodeOutput? output,
    String? error,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return NodeSnapshot(
      nodeId: nodeId ?? this.nodeId,
      nodeTypeId: nodeTypeId ?? this.nodeTypeId,
      nodeName: nodeName ?? this.nodeName,
      status: status ?? this.status,
      inputData: inputData ?? this.inputData,
      config: config ?? this.config,
      output: output ?? this.output,
      error: error ?? this.error,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// 转为 JSON
  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'nodeTypeId': nodeTypeId,
      'nodeName': nodeName,
      'status': status.name,
      'inputData': inputData,
      'config': config,
      'output': output != null
          ? {
              'port': output!.port,
              'data': output!.data,
              'message': output!.message,
              'isSuccess': output!.isSuccess,
            }
          : null,
      'error': error,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
    };
  }

  /// 从 JSON 创建
  factory NodeSnapshot.fromJson(Map<String, dynamic> json) {
    return NodeSnapshot(
      nodeId: json['nodeId'] as String,
      nodeTypeId: json['nodeTypeId'] as String,
      nodeName: json['nodeName'] as String?,
      status: NodeExecutionStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => NodeExecutionStatus.pending,
      ),
      inputData: Map<String, dynamic>.from(json['inputData'] as Map? ?? {}),
      config: Map<String, dynamic>.from(json['config'] as Map? ?? {}),
      output: json['output'] != null
          ? NodeOutput(
              port: json['output']['port'] as String,
              data: Map<String, dynamic>.from(json['output']['data'] as Map? ?? {}),
              message: json['output']['message'] as String?,
              isSuccess: json['output']['isSuccess'] as bool? ?? true,
            )
          : null,
      error: json['error'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
    );
  }

  @override
  String toString() {
    return 'NodeSnapshot(nodeId: $nodeId, status: $status, duration: ${durationMs}ms)';
  }
}

/// 流程执行快照集合
///
/// 管理一次流程执行的所有节点快照
class ExecutionSnapshots {
  /// 节点快照映射（nodeId -> snapshot）
  final Map<String, NodeSnapshot> _snapshots = {};

  /// 默认构造函数
  ExecutionSnapshots();

  /// 获取所有快照
  Map<String, NodeSnapshot> get all => Map.unmodifiable(_snapshots);

  /// 获取指定节点的快照
  NodeSnapshot? get(String nodeId) => _snapshots[nodeId];

  /// 添加或更新快照
  void set(String nodeId, NodeSnapshot snapshot) {
    _snapshots[nodeId] = snapshot;
  }

  /// 清空所有快照
  void clear() {
    _snapshots.clear();
  }

  /// 是否为空
  bool get isEmpty => _snapshots.isEmpty;

  /// 快照数量
  int get length => _snapshots.length;

  /// 转为 JSON
  Map<String, dynamic> toJson() {
    return _snapshots.map((key, value) => MapEntry(key, value.toJson()));
  }

  /// 从 JSON 创建
  factory ExecutionSnapshots.fromJson(Map<String, dynamic> json) {
    final snapshots = ExecutionSnapshots();
    for (final entry in json.entries) {
      snapshots.set(
        entry.key,
        NodeSnapshot.fromJson(entry.value as Map<String, dynamic>),
      );
    }
    return snapshots;
  }
}
