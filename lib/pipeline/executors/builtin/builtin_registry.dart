import '../../registry/node_type_registry.dart';
import 'commit_executor.dart';
import 'debug_executor.dart';
import 'merge_executor.dart';
import 'pause_executor.dart';
import 'prepare_executor.dart';
import 'review_executor.dart';
import 'script_executor.dart';
import 'update_executor.dart';

/// 注册所有内置节点类型
void registerBuiltinNodeTypes() {
  final registry = NodeTypeRegistry.instance;

  // SVN 操作节点
  registry.register(PrepareExecutor.definition);
  registry.register(UpdateExecutor.definition);
  registry.register(MergeExecutor.definition);
  registry.register(CommitExecutor.definition);

  // 交互节点
  registry.register(ReviewExecutor.definition);

  // 流程控制节点
  registry.register(PauseExecutor.definition);
  registry.register(DebugExecutor.definition);

  // 工具节点
  registry.register(ScriptExecutor.definition);
}
