/// 节点数据
///
/// 纯数据结构，用于存储流程图中的节点信息。
/// 只存储 typeId + 位置 + 用户配置，不存储类型定义（端口、图标等）。
/// 类型定义在运行时从 NodeTypeRegistry 查找。
class NodeData {
  /// 节点实例 ID（唯一标识）
  final String id;

  /// 节点类型 ID（对应 NodeTypeRegistry 中的 typeId）
  final String typeId;

  /// 节点位置 X
  final double x;

  /// 节点位置 Y
  final double y;

  /// 用户配置的参数
  /// key 对应 NodeTypeDefinition.params 中的 ParamSpec.key
  final Map<String, dynamic> config;

  const NodeData({
    required this.id,
    required this.typeId,
    required this.x,
    required this.y,
    this.config = const {},
  });

  /// 从 JSON 反序列化
  factory NodeData.fromJson(Map<String, dynamic> json) {
    return NodeData(
      id: json['id'] as String,
      typeId: json['typeId'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      config: json['config'] != null
          ? Map<String, dynamic>.from(json['config'] as Map)
          : const {},
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'typeId': typeId,
      'x': x,
      'y': y,
      if (config.isNotEmpty) 'config': config,
    };
  }

  /// 复制并修改
  NodeData copyWith({
    String? id,
    String? typeId,
    double? x,
    double? y,
    Map<String, dynamic>? config,
  }) {
    return NodeData(
      id: id ?? this.id,
      typeId: typeId ?? this.typeId,
      x: x ?? this.x,
      y: y ?? this.y,
      config: config ?? this.config,
    );
  }

  /// 更新位置
  NodeData withPosition(double x, double y) {
    return copyWith(x: x, y: y);
  }

  /// 更新配置
  NodeData withConfig(Map<String, dynamic> config) {
    return copyWith(config: {...this.config, ...config});
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NodeData &&
        other.id == id &&
        other.typeId == typeId &&
        other.x == x &&
        other.y == y &&
        _mapEquals(other.config, config);
  }

  @override
  int get hashCode {
    return Object.hash(id, typeId, x, y, Object.hashAll(config.entries));
  }

  @override
  String toString() {
    return 'NodeData(id: $id, typeId: $typeId, position: ($x, $y), config: $config)';
  }
}

bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}
