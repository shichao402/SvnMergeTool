import 'connection_data.dart';
import 'node_data.dart';

/// 流程图数据
///
/// 纯数据结构，用于存储完整的流程图。
/// 不依赖任何 UI 组件或执行逻辑，可直接序列化为 JSON。
class FlowGraphData {
  /// 数据格式版本（用于迁移）
  final String version;

  /// 流程图名称
  final String? name;

  /// 流程图描述
  final String? description;

  /// 所有节点
  final List<NodeData> nodes;

  /// 所有连接
  final List<ConnectionData> connections;

  /// 元数据（可扩展字段）
  final Map<String, dynamic>? metadata;

  const FlowGraphData({
    this.version = '1.0',
    this.name,
    this.description,
    this.nodes = const [],
    this.connections = const [],
    this.metadata,
  });

  /// 从 JSON 反序列化
  factory FlowGraphData.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String? ?? '1.0';

    // 版本迁移
    final migratedJson = _migrate(json, version);

    return FlowGraphData(
      version: migratedJson['version'] as String? ?? '1.0',
      name: migratedJson['name'] as String?,
      description: migratedJson['description'] as String?,
      nodes: (migratedJson['nodes'] as List<dynamic>?)
              ?.map((n) => NodeData.fromJson(n as Map<String, dynamic>))
              .toList() ??
          const [],
      connections: (migratedJson['connections'] as List<dynamic>?)
              ?.map((c) => ConnectionData.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
      metadata: migratedJson['metadata'] as Map<String, dynamic>?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'connections': connections.map((c) => c.toJson()).toList(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// 版本迁移
  static Map<String, dynamic> _migrate(Map<String, dynamic> json, String fromVersion) {
    var result = Map<String, dynamic>.from(json);

    // 未来版本迁移逻辑
    // if (fromVersion == '1.0') {
    //   result = _migrateV1ToV2(result);
    // }

    return result;
  }

  /// 复制并修改
  FlowGraphData copyWith({
    String? version,
    String? name,
    String? description,
    List<NodeData>? nodes,
    List<ConnectionData>? connections,
    Map<String, dynamic>? metadata,
  }) {
    return FlowGraphData(
      version: version ?? this.version,
      name: name ?? this.name,
      description: description ?? this.description,
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
      metadata: metadata ?? this.metadata,
    );
  }

  // ==================== 查询方法 ====================

  /// 根据 ID 获取节点
  NodeData? getNode(String nodeId) {
    try {
      return nodes.firstWhere((n) => n.id == nodeId);
    } catch (_) {
      return null;
    }
  }

  /// 根据 ID 获取连接
  ConnectionData? getConnection(String connectionId) {
    try {
      return connections.firstWhere((c) => c.id == connectionId);
    } catch (_) {
      return null;
    }
  }

  /// 获取节点的所有输入连接
  List<ConnectionData> getInputConnections(String nodeId) {
    return connections.where((c) => c.targetNodeId == nodeId).toList();
  }

  /// 获取节点的所有输出连接
  List<ConnectionData> getOutputConnections(String nodeId) {
    return connections.where((c) => c.sourceNodeId == nodeId).toList();
  }

  /// 获取从指定端口出发的连接
  List<ConnectionData> getConnectionsFromPort(String nodeId, String portId) {
    return connections
        .where((c) => c.sourceNodeId == nodeId && c.sourcePortId == portId)
        .toList();
  }

  /// 获取连接到指定端口的连接
  List<ConnectionData> getConnectionsToPort(String nodeId, String portId) {
    return connections
        .where((c) => c.targetNodeId == nodeId && c.targetPortId == portId)
        .toList();
  }

  /// 获取下游节点（从指定节点的指定端口出发）
  List<NodeData> getDownstreamNodes(String nodeId, String portId) {
    final conns = getConnectionsFromPort(nodeId, portId);
    return conns
        .map((c) => getNode(c.targetNodeId))
        .whereType<NodeData>()
        .toList();
  }

  /// 获取上游节点（连接到指定节点的指定端口）
  List<NodeData> getUpstreamNodes(String nodeId, String portId) {
    final conns = getConnectionsToPort(nodeId, portId);
    return conns
        .map((c) => getNode(c.sourceNodeId))
        .whereType<NodeData>()
        .toList();
  }

  /// 查找入口节点（没有输入连接的节点）
  List<NodeData> findEntryNodes() {
    return nodes.where((n) => getInputConnections(n.id).isEmpty).toList();
  }

  /// 查找出口节点（没有输出连接的节点）
  List<NodeData> findExitNodes() {
    return nodes.where((n) => getOutputConnections(n.id).isEmpty).toList();
  }

  // ==================== 修改方法（返回新实例） ====================

  /// 添加节点
  FlowGraphData addNode(NodeData node) {
    return copyWith(nodes: [...nodes, node]);
  }

  /// 移除节点（同时移除相关连接）
  FlowGraphData removeNode(String nodeId) {
    return copyWith(
      nodes: nodes.where((n) => n.id != nodeId).toList(),
      connections: connections
          .where((c) => c.sourceNodeId != nodeId && c.targetNodeId != nodeId)
          .toList(),
    );
  }

  /// 更新节点
  FlowGraphData updateNode(String nodeId, NodeData Function(NodeData) updater) {
    return copyWith(
      nodes: nodes.map((n) => n.id == nodeId ? updater(n) : n).toList(),
    );
  }

  /// 添加连接
  FlowGraphData addConnection(ConnectionData connection) {
    return copyWith(connections: [...connections, connection]);
  }

  /// 移除连接
  FlowGraphData removeConnection(String connectionId) {
    return copyWith(
      connections: connections.where((c) => c.id != connectionId).toList(),
    );
  }

  /// 清空所有节点和连接
  FlowGraphData clear() {
    return copyWith(nodes: [], connections: []);
  }

  // ==================== 验证方法 ====================

  /// 验证流程图完整性
  FlowGraphValidationResult validate() {
    final errors = <String>[];
    final warnings = <String>[];

    // 检查是否有节点
    if (nodes.isEmpty) {
      errors.add('流程图没有节点');
    }

    // 检查是否有入口节点
    final entryNodes = findEntryNodes();
    if (entryNodes.isEmpty && nodes.isNotEmpty) {
      warnings.add('没有入口节点（所有节点都有输入连接）');
    }

    // 检查连接的有效性
    for (final conn in connections) {
      if (getNode(conn.sourceNodeId) == null) {
        errors.add('连接 ${conn.id} 的源节点 ${conn.sourceNodeId} 不存在');
      }
      if (getNode(conn.targetNodeId) == null) {
        errors.add('连接 ${conn.id} 的目标节点 ${conn.targetNodeId} 不存在');
      }
    }

    // 检查孤立节点
    for (final node in nodes) {
      final hasInput = getInputConnections(node.id).isNotEmpty;
      final hasOutput = getOutputConnections(node.id).isNotEmpty;
      if (!hasInput && !hasOutput && nodes.length > 1) {
        warnings.add('节点 ${node.id} 是孤立的（没有任何连接）');
      }
    }

    return FlowGraphValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  @override
  String toString() {
    return 'FlowGraphData(version: $version, name: $name, nodes: ${nodes.length}, connections: ${connections.length})';
  }
}

/// 流程图验证结果
class FlowGraphValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const FlowGraphValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  @override
  String toString() {
    return 'FlowGraphValidationResult(isValid: $isValid, errors: ${errors.length}, warnings: ${warnings.length})';
  }
}
