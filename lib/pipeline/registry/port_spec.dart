/// 端口方向
enum PortDirection {
  /// 输入端口
  input,

  /// 输出端口
  output,
}

/// 端口角色
enum PortRole {
  /// 数据端口（传递数据）
  data,

  /// 触发端口（控制流程）
  trigger,

  /// 错误端口（错误处理分支）
  error,
}

/// 端口规格
///
/// 定义节点的输入/输出端口。
/// 用于 NodeTypeDefinition 中定义节点的端口结构。
class PortSpec {
  /// 端口 ID（在节点内唯一）
  final String id;

  /// 端口显示名称
  final String name;

  /// 端口方向
  final PortDirection direction;

  /// 端口角色
  final PortRole role;

  /// 端口描述
  final String? description;

  /// 是否允许多连接
  final bool multiConnections;

  /// 最大连接数（0 表示无限制）
  final int maxConnections;

  const PortSpec({
    required this.id,
    required this.name,
    this.direction = PortDirection.output,
    this.role = PortRole.data,
    this.description,
    this.multiConnections = false,
    this.maxConnections = 1,
  });

  /// 从 JSON 反序列化
  factory PortSpec.fromJson(Map<String, dynamic> json) {
    return PortSpec(
      id: json['id'] as String,
      name: json['name'] as String,
      direction: json['direction'] != null
          ? PortDirection.values.firstWhere(
              (e) => e.name == json['direction'],
              orElse: () => PortDirection.output,
            )
          : PortDirection.output,
      role: json['role'] != null
          ? PortRole.values.firstWhere(
              (e) => e.name == json['role'],
              orElse: () => PortRole.data,
            )
          : PortRole.data,
      description: json['description'] as String?,
      multiConnections: json['multiConnections'] as bool? ?? false,
      maxConnections: json['maxConnections'] as int? ?? 1,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'direction': direction.name,
      'role': role.name,
      if (description != null) 'description': description,
      if (multiConnections) 'multiConnections': multiConnections,
      if (maxConnections != 1) 'maxConnections': maxConnections,
    };
  }

  // ==================== 预定义端口 ====================

  /// 默认输入端口
  static const defaultInput = PortSpec(
    id: 'in',
    name: '输入',
    direction: PortDirection.input,
    role: PortRole.trigger,
  );

  /// 成功输出端口
  static const success = PortSpec(
    id: 'success',
    name: '成功',
    direction: PortDirection.output,
    role: PortRole.trigger,
  );

  /// 失败输出端口
  static const failure = PortSpec(
    id: 'failure',
    name: '失败',
    direction: PortDirection.output,
    role: PortRole.error,
  );

  /// 创建自定义输出端口
  static PortSpec output(String id, String name, {PortRole role = PortRole.trigger}) {
    return PortSpec(
      id: id,
      name: name,
      direction: PortDirection.output,
      role: role,
    );
  }

  /// 创建自定义输入端口
  static PortSpec input(String id, String name, {PortRole role = PortRole.trigger}) {
    return PortSpec(
      id: id,
      name: name,
      direction: PortDirection.input,
      role: role,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PortSpec &&
        other.id == id &&
        other.name == name &&
        other.direction == direction &&
        other.role == role;
  }

  @override
  int get hashCode => Object.hash(id, name, direction, role);

  @override
  String toString() => 'PortSpec(id: $id, name: $name, direction: $direction, role: $role)';
}
