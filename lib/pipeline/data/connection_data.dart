/// 连接数据
///
/// 纯数据结构，用于存储流程图中节点之间的连接关系。
/// 不依赖任何 UI 组件或执行逻辑。
class ConnectionData {
  /// 连接 ID（唯一标识）
  final String id;

  /// 源节点 ID
  final String sourceNodeId;

  /// 源端口 ID
  final String sourcePortId;

  /// 目标节点 ID
  final String targetNodeId;

  /// 目标端口 ID
  final String targetPortId;

  const ConnectionData({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePortId,
    required this.targetNodeId,
    required this.targetPortId,
  });

  /// 从 JSON 反序列化
  factory ConnectionData.fromJson(Map<String, dynamic> json) {
    return ConnectionData(
      id: json['id'] as String,
      sourceNodeId: json['sourceNodeId'] as String,
      sourcePortId: json['sourcePortId'] as String,
      targetNodeId: json['targetNodeId'] as String,
      targetPortId: json['targetPortId'] as String,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceNodeId': sourceNodeId,
      'sourcePortId': sourcePortId,
      'targetNodeId': targetNodeId,
      'targetPortId': targetPortId,
    };
  }

  /// 复制并修改
  ConnectionData copyWith({
    String? id,
    String? sourceNodeId,
    String? sourcePortId,
    String? targetNodeId,
    String? targetPortId,
  }) {
    return ConnectionData(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      sourcePortId: sourcePortId ?? this.sourcePortId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      targetPortId: targetPortId ?? this.targetPortId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionData &&
        other.id == id &&
        other.sourceNodeId == sourceNodeId &&
        other.sourcePortId == sourcePortId &&
        other.targetNodeId == targetNodeId &&
        other.targetPortId == targetPortId;
  }

  @override
  int get hashCode {
    return Object.hash(id, sourceNodeId, sourcePortId, targetNodeId, targetPortId);
  }

  @override
  String toString() {
    return 'ConnectionData(id: $id, $sourceNodeId:$sourcePortId -> $targetNodeId:$targetPortId)';
  }
}
