/// Pipeline 门面类
/// 
/// 采用门面模式 (Facade Pattern)，提供统一的 Pipeline 操作入口
/// 
/// 设计原则：
/// - 单一职责：只负责协调 Pipeline 各组件
/// - 门面模式：隐藏内部复杂性，提供简洁的 API
/// - 依赖注入：支持自定义执行器注册
/// 
/// 使用方式：
/// ```dart
/// final pipeline = PipelineFacade();
/// 
/// // 启动 Pipeline
/// await pipeline.start(
///   config: PipelineConfig.simple(),
///   jobParams: {
///     'targetWc': '/path/to/wc',
///     'sourceUrl': 'svn://...',
///     'revisions': [123, 124, 125],
///   },
/// );
/// 
/// // 监听事件
/// pipeline.events.listen((event) {
///   print('${event.type}: ${event.message}');
/// });
/// 
/// // 暂停时恢复
/// if (pipeline.isPaused) {
///   await pipeline.resume(userInput: 'REVIEW-123');
/// }
/// ```

import 'package:flutter/foundation.dart';

import 'engine/engine.dart';
import 'executors/executors.dart';
import 'models/models.dart';

/// Pipeline 门面类
class PipelineFacade extends ChangeNotifier {
  /// 执行器注册表
  final StageExecutorRegistry _registry = StageExecutorRegistry();

  /// Pipeline 引擎
  late final PipelineEngine _engine;

  /// 是否已初始化
  bool _initialized = false;

  PipelineFacade() {
    _engine = PipelineEngine(_registry);
    _engine.addListener(_onEngineChanged);
  }

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

  /// 当前状态
  PipelineState? get state => _engine.state;

  /// 执行上下文
  PipelineContext? get context => _engine.context;

  /// 事件流
  Stream<PipelineEvent> get events => _engine.events;

  /// 当前用户输入请求
  UserInputRequest? get currentInputRequest => _engine.currentInputRequest;

  /// 是否正在运行
  bool get isRunning => _engine.isRunning;

  /// 是否暂停
  bool get isPaused => _engine.isPaused;

  /// 是否可以继续
  bool get canResume => _engine.canResume;

  /// 是否可以取消
  bool get canCancel => _engine.canCancel;

  /// 是否可以回滚
  bool get canRollback => _engine.canRollback;

  /// 启动 Pipeline
  /// 
  /// [config] Pipeline 配置
  /// [jobParams] 任务参数，必须包含：
  ///   - targetWc: 目标工作副本路径
  ///   - sourceUrl: 源 URL
  ///   - revisions: 要合并的 revision 列表
  /// [env] 环境变量
  Future<void> start({
    required PipelineConfig config,
    required Map<String, dynamic> jobParams,
    Map<String, String>? env,
  }) async {
    if (!_initialized) {
      initialize();
    }

    await _engine.start(config, jobParams: jobParams, env: env);
  }

  /// 恢复执行
  /// 
  /// [userInput] 用户输入（review 阶段需要）
  Future<void> resume({String? userInput}) async {
    await _engine.resume(userInput: userInput);
  }

  /// 跳过当前阶段
  Future<void> skipCurrentStage() async {
    await _engine.skipCurrentStage();
  }

  /// 取消执行
  Future<void> cancel() async {
    await _engine.cancel();
  }

  /// 回滚
  Future<void> rollback() async {
    await _engine.rollback();
  }

  /// 提交用户输入
  void submitUserInput(String value) {
    _engine.submitUserInput(value);
  }

  /// 取消用户输入
  void cancelUserInput() {
    _engine.cancelUserInput();
  }

  /// 重置
  void reset() {
    _engine.reset();
  }

  /// 引擎状态变化回调
  void _onEngineChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    super.dispose();
  }
}

/// 全局 Pipeline 实例
/// 
/// 使用单例模式，确保全局只有一个 Pipeline 实例
class GlobalPipeline {
  static PipelineFacade? _instance;

  static PipelineFacade get instance {
    _instance ??= PipelineFacade()..initialize();
    return _instance!;
  }

  /// 重置全局实例（用于测试）
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
