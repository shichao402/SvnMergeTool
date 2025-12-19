# Pipeline 重构设计文档

## 概述

本文档记录 Pipeline 模块的重构设计，目标是实现：
1. 存储格式与代码解耦
2. UI 组件可替换
3. 执行引擎可迁移（如迁移到 C++）
4. 支持用户自定义节点

---

## 架构设计

### 整体分层

```
┌─────────────────────────────────────────────────────────────┐
│                      UI 层 (Flutter)                        │
│  流程编辑器、节点面板、属性面板、进度显示                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     适配层 (Adapter)                         │
│  IFlowEditorAdapter - 隔离 UI 组件依赖                       │
│  VyuhAdapter - vyuh_node_flow 的具体实现                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    注册表 (Registry)                         │
│  NodeTypeRegistry - 管理所有节点类型定义                      │
│  内置节点 + 用户自定义节点 统一注册                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    存储层 (Data)                             │
│  FlowGraphData - 纯数据格式，不依赖任何代码实现                │
│  只存储: typeId + 位置 + 用户配置 + 连接关系                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    执行层 (Engine)                           │
│  FlowEngine - 执行流程图                                     │
│  可替换为 C++/Rust 等其他语言实现                            │
└─────────────────────────────────────────────────────────────┘
```

### 目录结构

```
lib/
├── pipeline/
│   ├── data/                       # 存储格式（纯数据）
│   │   ├── flow_graph_data.dart    # 流程图数据
│   │   ├── node_data.dart          # 节点数据
│   │   └── connection_data.dart    # 连接数据
│   │
│   ├── registry/                   # 节点类型注册
│   │   ├── node_type_registry.dart # 注册表
│   │   ├── node_type_definition.dart # 类型定义
│   │   ├── port_spec.dart          # 端口规格
│   │   └── param_spec.dart         # 参数规格
│   │
│   ├── executors/                  # 执行逻辑
│   │   ├── prepare_executor.dart   # 内置: 准备
│   │   ├── update_executor.dart    # 内置: 更新
│   │   ├── merge_executor.dart     # 内置: 合并
│   │   ├── resolve_executor.dart   # 内置: 解决冲突
│   │   ├── commit_executor.dart    # 内置: 提交
│   │   └── generic_executor.dart   # 通用执行器（用户自定义节点）
│   │
│   ├── engine/                     # 执行引擎
│   │   ├── flow_engine.dart        # 流程执行器
│   │   ├── execution_context.dart  # 执行上下文
│   │   └── node_output.dart        # 节点输出
│   │
│   └── adapter/                    # UI 适配层
│       ├── flow_editor_adapter.dart # 适配器接口
│       └── vyuh_adapter.dart       # vyuh_node_flow 适配器
│
├── ui/
│   ├── flow_editor_page.dart       # 编辑器页面
│   ├── node_palette.dart           # 节点面板
│   └── node_type_manager.dart      # 用户自定义节点管理
```

---

## 核心数据结构

### 存储格式（纯数据，不依赖代码）

```dart
/// 流程图数据
class FlowGraphData {
  final String version;
  final List<NodeData> nodes;
  final List<ConnectionData> connections;
  final Map<String, dynamic>? metadata;
}

/// 节点数据（只存储用户配置，不存储定义）
class NodeData {
  final String id;                // 实例 ID（唯一）
  final String typeId;            // 类型 ID（如 'merge'、'commit'）
  final double x;                 // 位置 X
  final double y;                 // 位置 Y
  final Map<String, dynamic> config;  // 用户配置的参数
}

/// 连接数据
class ConnectionData {
  final String sourceNodeId;
  final String sourcePortId;
  final String targetNodeId;
  final String targetPortId;
}
```

### 节点类型定义（代码中定义，运行时查找）

```dart
/// 节点类型定义
class NodeTypeDefinition {
  final String typeId;            // 类型 ID
  final String name;              // 显示名称
  final String? description;      // 描述
  final IconData icon;            // 图标
  final Color color;              // 颜色
  final List<PortSpec> inputs;    // 输入端口
  final List<PortSpec> outputs;   // 输出端口
  final List<ParamSpec> params;   // 可配置参数
  final NodeExecutor executor;    // 执行器
  final bool isUserDefined;       // 是否用户自定义
}

/// 端口规格
class PortSpec {
  final String id;
  final String name;
  final PortDirection direction;  // input / output
  final PortRole role;            // data / trigger / error
  
  static const defaultInput = PortSpec(id: 'in', name: '输入', direction: PortDirection.input);
  static const success = PortSpec(id: 'success', name: '成功');
  static const failure = PortSpec(id: 'failure', name: '失败', role: PortRole.error);
}

/// 参数规格（用于生成属性面板）
class ParamSpec {
  final String key;
  final String label;
  final ParamType type;           // string / int / bool / select / code / path
  final dynamic defaultValue;
  final List<String>? options;    // for select
  final bool required;
}

/// 执行器类型
typedef NodeExecutor = Future<NodeOutput> Function({
  required Map<String, dynamic> input,
  required Map<String, dynamic> config,
  required ExecutionContext context,
});
```

### 节点输出（控制流程走向）

```dart
/// 节点执行输出
class NodeOutput {
  final String port;              // 触发的端口 ID
  final Map<String, dynamic> data; // 传递给下游的数据
  final String? message;          // 日志消息
  
  // 便捷构造
  factory NodeOutput.success({Map<String, dynamic>? data});
  factory NodeOutput.failure({String? message, Map<String, dynamic>? data});
  factory NodeOutput.port(String port, {Map<String, dynamic>? data});
  factory NodeOutput.cancelled();
}
```

---

## 端口触发机制

### 内置节点：代码返回指定端口

```dart
class MergeExecutor {
  static Future<NodeOutput> execute({...}) async {
    final result = await context.svnService.merge(...);
    
    if (result.hasConflicts) {
      return NodeOutput.port('conflict', data: {'files': result.conflicts});
    } else if (result.success) {
      return NodeOutput.success(data: {'merged': result.files});
    } else {
      return NodeOutput.failure(message: result.error);
    }
  }
}

// 节点定义
NodeTypeRegistry.register(NodeTypeDefinition(
  typeId: 'merge',
  outputs: [
    PortSpec(id: 'success', name: '成功'),
    PortSpec(id: 'conflict', name: '有冲突'),
    PortSpec(id: 'failure', name: '失败'),
  ],
  executor: MergeExecutor.execute,
));
```

### 用户自定义节点：JSON 配置端口映射

```json
{
  "typeId": "my_script",
  "outputs": [
    {"id": "result_a", "name": "结果A"},
    {"id": "result_b", "name": "结果B"},
    {"id": "error", "name": "错误"}
  ],
  "executor": {
    "type": "shell",
    "command": "./my_script.sh",
    "portMapping": {
      "exitCode": {
        "0": "result_a",
        "1": "result_b",
        "*": "error"
      }
    }
  }
}
```

或基于输出内容：

```json
{
  "executor": {
    "type": "shell",
    "command": "./check_status.sh",
    "portMapping": {
      "stdout": {
        "contains:approved": "approved",
        "contains:rejected": "rejected",
        "regex:error.*": "error",
        "*": "unknown"
      }
    }
  }
}
```

### 执行引擎处理

```dart
class FlowEngine {
  Future<void> executeNode(NodeData nodeData) async {
    final typeDef = NodeTypeRegistry.get(nodeData.typeId)!;
    
    // 1. 执行节点逻辑
    final output = await typeDef.executor(
      input: _getInputData(nodeData),
      config: nodeData.config,
      context: _context,
    );
    
    // 2. 根据返回的 port 找到下游节点
    final nextNodes = _graph.getConnectedNodes(
      nodeId: nodeData.id,
      portId: output.port,
    );
    
    // 3. 传递数据，继续执行
    for (final next in nextNodes) {
      _setInputData(next.id, output.data);
      await executeNode(next);
    }
  }
}
```

---

## 适配层设计

### 接口定义

```dart
/// 流图编辑器适配器接口
abstract class IFlowEditorAdapter {
  /// 将业务节点转换为 UI 节点
  dynamic createViewNode(NodeTypeDefinition typeDef, NodeData data);
  
  /// 从 UI 节点提取数据
  NodeData extractNodeData(dynamic viewNode);
  
  /// 构建编辑器 Widget
  Widget buildEditor({
    required dynamic controller,
    required Widget Function(dynamic node) nodeBuilder,
    required void Function(ConnectionData) onConnect,
  });
  
  /// 导出为通用格式
  FlowGraphData exportGraph(dynamic controller);
  
  /// 从通用格式导入
  void importGraph(dynamic controller, FlowGraphData graph);
}
```

### Vyuh 适配器实现

```dart
class VyuhAdapter implements IFlowEditorAdapter {
  @override
  dynamic createViewNode(NodeTypeDefinition typeDef, NodeData data) {
    return Node<FlowNodeData>(
      id: data.id,
      type: data.typeId,
      position: Offset(data.x, data.y),
      data: FlowNodeData(typeId: data.typeId, config: data.config),
      inputPorts: typeDef.inputs.map(_toVyuhPort).toList(),
      outputPorts: typeDef.outputs.map(_toVyuhPort).toList(),
    );
  }
  
  Port _toVyuhPort(PortSpec spec) {
    return Port(
      id: spec.id,
      name: spec.name,
      position: spec.direction == PortDirection.input 
          ? PortPosition.left 
          : PortPosition.right,
    );
  }
  
  // ... 其他方法
}
```

---

## 用户自定义节点

### 存储位置

```
~/.svn_flow/nodes/
├── crid_create.node.json
├── crid_wait.node.json
└── build_check.node.json
```

### JSON 格式

```json
{
  "typeId": "crid_wait",
  "name": "CRID 等待审批",
  "icon": "hourglass_empty",
  "color": "#FF9800",
  "inputs": [
    {"id": "in", "name": "输入"}
  ],
  "outputs": [
    {"id": "approved", "name": "已通过"},
    {"id": "rejected", "name": "已拒绝"},
    {"id": "timeout", "name": "超时"}
  ],
  "params": [
    {"key": "interval", "label": "轮询间隔(秒)", "type": "int", "default": 30},
    {"key": "timeout", "label": "超时(分钟)", "type": "int", "default": 60}
  ],
  "executor": {
    "type": "poll",
    "command": "crid status ${input.crid}",
    "interval": "${params.interval}",
    "timeout": "${params.timeout}",
    "portMapping": {
      "stdout": {
        "contains:approved": "approved",
        "contains:rejected": "rejected"
      },
      "onTimeout": "timeout"
    }
  }
}
```

### 加载机制

```dart
void main() async {
  // 1. 注册内置节点
  NodeTypeRegistry.init();
  
  // 2. 加载用户自定义节点
  await UserNodeLoader.loadUserNodes();
  
  // 3. 启动应用
  runApp(MyApp());
}
```

### 通用执行器

```dart
class GenericExecutor {
  static NodeExecutor fromConfig(Map<String, dynamic> config) {
    final type = config['type'];
    
    return switch (type) {
      'shell' => _shellExecutor(config),
      'poll' => _pollExecutor(config),
      'http' => _httpExecutor(config),
      _ => throw Exception('未知执行器类型: $type'),
    };
  }
  
  /// 变量替换: ${input.xxx}, ${params.xxx}, ${context.xxx}
  static String _resolveVariables(String template, Map input, Map params, ExecutionContext context);
  
  /// 根据 portMapping 决定触发哪个端口
  static String _resolvePort(Map<String, dynamic>? mapping, {int exitCode, String stdout, String stderr});
}
```

---

## 迁移兼容性

### 更换 UI 组件

只需实现新的 `IFlowEditorAdapter`，其他层不变。

### 执行引擎迁移到 C++

```dart
/// 执行引擎接口
abstract class IFlowEngine {
  Future<void> loadGraph(FlowGraphData graph);
  Stream<ExecutionEvent> execute();
  Future<void> pause();
  Future<void> resume();
  Future<void> cancel();
}

// Dart 实现
class DartFlowEngine implements IFlowEngine { ... }

// C++ 实现（通过 FFI）
class CppFlowEngine implements IFlowEngine { ... }
```

### 数据格式升级

```dart
class FlowGraphData {
  final String version;  // 版本号，用于迁移
  
  static FlowGraphData fromJson(Map<String, dynamic> json) {
    final version = json['version'] ?? '1.0';
    
    // 版本迁移
    if (version == '1.0') {
      json = _migrateV1ToV2(json);
    }
    
    return FlowGraphData(...);
  }
}
```

---

## 设计优势总结

| 方面 | 设计决策 | 优势 |
|-----|---------|-----|
| **存储** | 只存 typeId + config | 不依赖代码，历史数据可加载 |
| **UI** | 适配层隔离 | 可替换 vyuh_node_flow |
| **执行** | 接口抽象 | 可迁移到 C++/Rust |
| **扩展** | JSON 配置 + 通用执行器 | 用户无需编译即可自定义节点 |
| **端口** | NodeOutput.port 机制 | 内置/自定义节点统一处理 |
