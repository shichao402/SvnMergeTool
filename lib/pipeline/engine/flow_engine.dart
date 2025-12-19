import 'dart:async';

import '../data/data.dart';
import '../registry/registry.dart';
import 'execution_context.dart';

/// 执行事件类型
enum ExecutionEventType {
  /// 流程开始
  flowStarted,

  /// 流程完成
  flowCompleted,

  /// 流程失败
  flowFailed,

  /// 流程取消
  flowCancelled,

  /// 节点开始
  nodeStarted,

  /// 节点完成
  nodeCompleted,

  /// 节点失败
  nodeFailed,

  /// 节点跳过
  nodeSkipped,

  /// 需要用户输入
  inputRequired,
}

/// 执行事件
class ExecutionEvent {
  /// 事件类型
  final ExecutionEventType type;

  /// 节点 ID（节点相关事件）
  final String? nodeId;

  /// 节点类型 ID
  final String? nodeTypeId;

  /// 输出端口
  final String? port;

  /// 事件数据
  final Map<String, dynamic>? data;

  /// 错误消息
  final String? error;

  /// 时间戳
  final DateTime timestamp;

  ExecutionEvent({
    required this.type,
    this.nodeId,
    this.nodeTypeId,
    this.port,
    this.data,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'ExecutionEvent(type: $type, nodeId: $nodeId, port: $port)';
  }
}

/// 流程执行引擎
///
/// 负责：
/// - 加载流程图
/// - 按拓扑顺序执行节点
/// - 根据输出端口决定下一个节点
/// - 发送执行事件
class FlowEngine {
  /// 流程图数据
  FlowGraphData? _graph;

  /// 执行上下文
  ExecutionContext? _context;

  /// 事件流控制器
  final _eventController = StreamController<ExecutionEvent>.broadcast();

  /// 当前执行的节点 ID
  String? _currentNodeId;

  /// 是否正在执行
  bool _isRunning = false;

  /// 事件流
  Stream<ExecutionEvent> get events => _eventController.stream;

  /// 是否正在执行
  bool get isRunning => _isRunning;

  /// 当前节点 ID
  String? get currentNodeId => _currentNodeId;

  /// 加载流程图
  void loadGraph(FlowGraphData graph) {
    _graph = graph;
  }

  /// 执行流程
  ///
  /// [context] 执行上下文
  /// [entryNodeId] 入口节点 ID，如果不指定则自动查找
  Future<bool> execute(
    ExecutionContext context, {
    String? entryNodeId,
  }) async {
    if (_graph == null) {
      throw StateError('未加载流程图');
    }

    _context = context;
    _isRunning = true;

    _emitEvent(ExecutionEvent(type: ExecutionEventType.flowStarted));

    try {
      // 查找入口节点
      final entryNode = entryNodeId != null
          ? _graph!.getNode(entryNodeId)
          : _findEntryNode();

      if (entryNode == null) {
        throw StateError('未找到入口节点');
      }

      // 从入口节点开始执行
      await _executeNode(entryNode, {});

      _emitEvent(ExecutionEvent(type: ExecutionEventType.flowCompleted));
      return true;
    } on ExecutionCancelledException {
      _emitEvent(ExecutionEvent(
        type: ExecutionEventType.flowCancelled,
        error: '用户取消',
      ));
      return false;
    } catch (e, stack) {
      _emitEvent(ExecutionEvent(
        type: ExecutionEventType.flowFailed,
        error: e.toString(),
        data: {'stackTrace': stack.toString()},
      ));
      return false;
    } finally {
      _isRunning = false;
      _currentNodeId = null;
    }
  }

  /// 执行单个节点
  Future<void> _executeNode(
    NodeData nodeData,
    Map<String, dynamic> inputData,
  ) async {
    final context = _context!;
    final graph = _graph!;

    // 检查取消和暂停
    await context.checkPause();
    context.checkCancelled();

    _currentNodeId = nodeData.id;

    // 获取节点类型定义
    final typeDef = NodeTypeRegistry.instance.get(nodeData.typeId);
    if (typeDef == null) {
      _emitEvent(ExecutionEvent(
        type: ExecutionEventType.nodeSkipped,
        nodeId: nodeData.id,
        nodeTypeId: nodeData.typeId,
        error: '未知节点类型: ${nodeData.typeId}',
      ));
      return;
    }

    _emitEvent(ExecutionEvent(
      type: ExecutionEventType.nodeStarted,
      nodeId: nodeData.id,
      nodeTypeId: nodeData.typeId,
    ));

    try {
      // 获取有效配置（填充默认值）
      final effectiveConfig = typeDef.getEffectiveConfig(nodeData.config);

      // 执行节点
      final output = await typeDef.executor(
        input: inputData,
        config: effectiveConfig,
        context: context,
      );

      // 保存执行结果
      context.setNodeResult(nodeData.id, output);

      if (output.isCancelled) {
        throw ExecutionCancelledException(output.message ?? '节点取消');
      }

      _emitEvent(ExecutionEvent(
        type: output.isSuccess
            ? ExecutionEventType.nodeCompleted
            : ExecutionEventType.nodeFailed,
        nodeId: nodeData.id,
        nodeTypeId: nodeData.typeId,
        port: output.port,
        data: output.data,
        error: output.isSuccess ? null : output.message,
      ));

      // 查找下游节点并继续执行
      final downstreamNodes = graph.getDownstreamNodes(nodeData.id, output.port);

      for (final nextNode in downstreamNodes) {
        await _executeNode(nextNode, output.data);
      }
    } catch (e) {
      if (e is ExecutionCancelledException) rethrow;

      _emitEvent(ExecutionEvent(
        type: ExecutionEventType.nodeFailed,
        nodeId: nodeData.id,
        nodeTypeId: nodeData.typeId,
        error: e.toString(),
      ));

      // 查找失败分支
      final failureNodes = graph.getDownstreamNodes(nodeData.id, 'failure');
      if (failureNodes.isNotEmpty) {
        // 有失败处理分支，继续执行
        for (final nextNode in failureNodes) {
          await _executeNode(nextNode, {'error': e.toString()});
        }
      } else {
        // 没有失败处理分支，向上抛出
        rethrow;
      }
    }
  }

  /// 查找入口节点
  NodeData? _findEntryNode() {
    final entryNodes = _graph!.findEntryNodes();
    if (entryNodes.isEmpty) return null;

    // 优先查找 prepare 类型的节点
    for (final node in entryNodes) {
      if (node.typeId == 'prepare') return node;
    }

    // 否则返回第一个入口节点
    return entryNodes.first;
  }

  /// 发送事件
  void _emitEvent(ExecutionEvent event) {
    _eventController.add(event);
  }

  /// 暂停执行
  void pause() {
    _context?.pause();
  }

  /// 恢复执行
  void resume() {
    _context?.resume();
  }

  /// 取消执行
  void cancel() {
    _context?.cancel();
  }

  /// 释放资源
  void dispose() {
    _eventController.close();
  }
}
