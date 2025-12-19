/// 基于 Graph 的 Pipeline 门面类
///
/// 使用 vyuh_node_flow 的 NodeGraph 作为流程定义，
/// 使用 GraphExecutor 执行流程。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';

import '../engine/pipeline_context.dart';
import '../engine/stage_executor.dart';
import '../executors/executors.dart';
import '../models/stage_type.dart';
import 'graph_executor.dart';
import 'merge_flow_builder.dart';
import 'stage_data.dart';

/// Pipeline 事件类型
enum GraphPipelineEventType {
  /// 日志
  log,
  /// 状态变化
  statusChanged,
  /// 节点开始
  nodeStarted,
  /// 节点完成
  nodeCompleted,
  /// 需要用户输入
  needUserInput,
}

/// Pipeline 事件
class GraphPipelineEvent {
  final GraphPipelineEventType type;
  final String? message;
  final Node<StageData>? node;
  final GraphExecutorStatus? status;

  GraphPipelineEvent({
    required this.type,
    this.message,
    this.node,
    this.status,
  });

  factory GraphPipelineEvent.log(String message) => GraphPipelineEvent(
        type: GraphPipelineEventType.log,
        message: message,
      );

  factory GraphPipelineEvent.statusChanged(GraphExecutorStatus status) =>
      GraphPipelineEvent(
        type: GraphPipelineEventType.statusChanged,
        status: status,
      );

  factory GraphPipelineEvent.nodeStarted(Node<StageData> node) =>
      GraphPipelineEvent(
        type: GraphPipelineEventType.nodeStarted,
        node: node,
      );

  factory GraphPipelineEvent.needUserInput(Node<StageData> node) =>
      GraphPipelineEvent(
        type: GraphPipelineEventType.needUserInput,
        node: node,
      );
}

/// 基于 Graph 的 Pipeline 门面类
class GraphPipelineFacade extends ChangeNotifier {
  /// 执行器注册表
  final StageExecutorRegistry _registry = StageExecutorRegistry();

  /// 流程控制器
  NodeFlowController<StageData>? _controller;

  /// 图执行器
  GraphExecutor? _executor;

  /// 执行上下文
  PipelineContext? _context;

  /// 是否已初始化
  bool _initialized = false;

  /// 事件流控制器
  final StreamController<GraphPipelineEvent> _eventController =
      StreamController<GraphPipelineEvent>.broadcast();

  /// 用户输入 Completer
  Completer<String?>? _userInputCompleter;

  // ==================== Getters ====================

  /// 流程控制器
  NodeFlowController<StageData>? get controller => _controller;

  /// 执行上下文
  PipelineContext? get context => _context;

  /// 事件流
  Stream<GraphPipelineEvent> get events => _eventController.stream;

  /// 当前状态
  GraphExecutorStatus get status =>
      _executor?.status ?? GraphExecutorStatus.idle;

  /// 当前节点
  Node<StageData>? get currentNode => _executor?.currentNode;

  /// 是否正在运行
  bool get isRunning => status == GraphExecutorStatus.running;

  /// 是否暂停（等待用户输入）
  bool get isPaused => status == GraphExecutorStatus.paused;

  /// 是否等待用户输入
  bool get isWaitingInput => isPaused && _userInputCompleter != null;

  /// 等待输入的节点
  Node<StageData>? get waitingInputNode => isPaused ? currentNode : null;

  /// 是否可以继续
  bool get canResume => isPaused;

  /// 是否可以取消
  bool get canCancel => isRunning || isPaused;

  // ==================== 初始化 ====================

  /// 初始化（注册默认执行器）
  void initialize() {
    if (_initialized) return;

    // 注册内置执行器
    _registry.register(StageType.prepare, PrepareExecutor());
    _registry.register(StageType.update, UpdateExecutor());
    _registry.register(StageType.merge, MergeExecutor());
    _registry.register(StageType.commit, CommitExecutor());
    _registry.register(StageType.review, ReviewExecutor());

    // 脚本类型共用 ScriptExecutor
    final scriptExecutor = ScriptExecutor();
    _registry.register(StageType.script, scriptExecutor);
    _registry.register(StageType.check, scriptExecutor);
    _registry.register(StageType.postScript, scriptExecutor);

    _initialized = true;
  }

  /// 注册自定义执行器
  void registerExecutor(StageType type, StageExecutor executor) {
    _registry.register(type, executor);
  }

  // ==================== 流程操作 ====================

  /// 启动 Pipeline
  ///
  /// [controller] 流程控制器，如果为 null 则使用默认流程
  /// [jobParams] 任务参数
  /// [env] 环境变量
  Future<bool> start({
    NodeFlowController<StageData>? controller,
    required Map<String, dynamic> jobParams,
    Map<String, String>? env,
  }) async {
    if (!_initialized) {
      initialize();
    }

    // 使用传入的控制器或创建默认流程
    _controller = controller ?? MergeFlowBuilder.buildStandardFlow();

    // 创建执行上下文
    _context = PipelineContext(
      jobParams: jobParams,
      env: env ?? {},
    );

    // 创建执行器
    _executor = GraphExecutor(
      registry: _registry,
      context: _context!,
      onLog: _onLog,
      onStatusChange: _onStatusChange,
      onNeedUserInput: _onNeedUserInput,
    );

    // 执行
    _emit(GraphPipelineEvent.log('[INFO] 开始执行 Pipeline...'));
    final result = await _executor!.execute(_controller!);

    if (result) {
      _emit(GraphPipelineEvent.log('[INFO] Pipeline 执行成功'));
    } else {
      _emit(GraphPipelineEvent.log('[WARN] Pipeline 执行失败或被取消'));
    }

    return result;
  }

  /// 提交用户输入
  Future<void> submitUserInput(String value) async {
    if (_userInputCompleter != null && !_userInputCompleter!.isCompleted) {
      _userInputCompleter!.complete(value);
      _userInputCompleter = null;
    }
  }

  /// 取消用户输入
  void cancelUserInput() {
    if (_userInputCompleter != null && !_userInputCompleter!.isCompleted) {
      _userInputCompleter!.complete(null);
      _userInputCompleter = null;
    }
  }

  /// 取消执行
  void cancel() {
    _executor?.cancel();
    cancelUserInput();
  }

  /// 重置
  void reset() {
    _executor = null;
    _context = null;
    _userInputCompleter = null;
    
    // 重置所有节点状态
    if (_controller != null) {
      for (final node in _controller!.nodes.values) {
        node.data?.reset();
      }
    }
    
    notifyListeners();
  }

  // ==================== 流程配置 ====================

  /// 加载流程配置
  Future<void> loadFlow(Map<String, dynamic> json) async {
    _controller = MergeFlowBuilder.fromJson(json);
    notifyListeners();
  }

  /// 导出流程配置
  Map<String, dynamic>? exportFlow() {
    if (_controller == null) return null;
    return MergeFlowBuilder.toJson(_controller!);
  }

  /// 使用标准流程
  void useStandardFlow({String? commitMessageTemplate}) {
    _controller = MergeFlowBuilder.buildStandardFlow(
      commitMessageTemplate: commitMessageTemplate,
    );
    notifyListeners();
  }

  /// 使用简单流程
  void useSimpleFlow() {
    _controller = MergeFlowBuilder.buildSimpleFlow();
    notifyListeners();
  }

  // ==================== 私有方法 ====================

  void _onLog(String message) {
    _emit(GraphPipelineEvent.log(message));
  }

  void _onStatusChange(GraphExecutorStatus status) {
    _emit(GraphPipelineEvent.statusChanged(status));
    notifyListeners();
  }

  Future<String?> _onNeedUserInput(Node<StageData> node) async {
    _emit(GraphPipelineEvent.needUserInput(node));
    _userInputCompleter = Completer<String?>();
    notifyListeners();
    return _userInputCompleter!.future;
  }

  void _emit(GraphPipelineEvent event) {
    _eventController.add(event);
  }

  @override
  void dispose() {
    _eventController.close();
    super.dispose();
  }
}

/// 全局 Graph Pipeline 实例
class GlobalGraphPipeline {
  static GraphPipelineFacade? _instance;

  static GraphPipelineFacade get instance {
    _instance ??= GraphPipelineFacade()..initialize();
    return _instance!;
  }

  /// 重置全局实例（用于测试）
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
