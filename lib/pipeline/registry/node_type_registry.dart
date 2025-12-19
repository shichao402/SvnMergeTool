import 'node_type_definition.dart';

/// 节点类型注册表
///
/// 管理所有节点类型定义，包括内置节点和用户自定义节点。
/// 单例模式，全局访问。
class NodeTypeRegistry {
  NodeTypeRegistry._();

  static final NodeTypeRegistry _instance = NodeTypeRegistry._();

  /// 获取单例实例
  static NodeTypeRegistry get instance => _instance;

  /// 所有注册的节点类型
  final Map<String, NodeTypeDefinition> _types = {};

  /// 注册节点类型
  ///
  /// 如果 typeId 已存在，会覆盖原有定义。
  void register(NodeTypeDefinition definition) {
    _types[definition.typeId] = definition;
  }

  /// 批量注册节点类型
  void registerAll(Iterable<NodeTypeDefinition> definitions) {
    for (final def in definitions) {
      register(def);
    }
  }

  /// 注销节点类型
  void unregister(String typeId) {
    _types.remove(typeId);
  }

  /// 获取节点类型定义
  NodeTypeDefinition? get(String typeId) {
    return _types[typeId];
  }

  /// 检查类型是否已注册
  bool contains(String typeId) {
    return _types.containsKey(typeId);
  }

  /// 获取所有已注册的类型 ID
  Iterable<String> get typeIds => _types.keys;

  /// 获取所有已注册的类型定义
  Iterable<NodeTypeDefinition> get definitions => _types.values;

  /// 获取所有可见的节点类型（用于节点面板）
  List<NodeTypeDefinition> get visibleDefinitions {
    return _types.values.where((d) => !d.isHidden).toList();
  }

  /// 按分类获取节点类型
  Map<String?, List<NodeTypeDefinition>> get definitionsByCategory {
    final result = <String?, List<NodeTypeDefinition>>{};
    for (final def in visibleDefinitions) {
      result.putIfAbsent(def.category, () => []).add(def);
    }
    return result;
  }

  /// 获取内置节点类型
  List<NodeTypeDefinition> get builtinDefinitions {
    return _types.values.where((d) => !d.isUserDefined).toList();
  }

  /// 获取用户自定义节点类型
  List<NodeTypeDefinition> get userDefinitions {
    return _types.values.where((d) => d.isUserDefined).toList();
  }

  /// 清空所有注册
  void clear() {
    _types.clear();
  }

  /// 清空用户自定义节点
  void clearUserDefinitions() {
    _types.removeWhere((_, def) => def.isUserDefined);
  }

  /// 节点类型数量
  int get length => _types.length;

  /// 是否为空
  bool get isEmpty => _types.isEmpty;

  /// 是否非空
  bool get isNotEmpty => _types.isNotEmpty;
}

// ==================== 便捷访问 ====================

/// 获取节点类型注册表实例
NodeTypeRegistry get nodeTypeRegistry => NodeTypeRegistry.instance;

/// 注册节点类型
void registerNodeType(NodeTypeDefinition definition) {
  NodeTypeRegistry.instance.register(definition);
}

/// 获取节点类型定义
NodeTypeDefinition? getNodeType(String typeId) {
  return NodeTypeRegistry.instance.get(typeId);
}
