/// Pipeline 模块导出
/// 
/// 使用方式：
/// ```dart
/// import 'package:svn_auto_merge/pipeline/pipeline.dart';
/// 
/// // 注册内置节点
/// registerBuiltinNodeTypes();
/// 
/// // 使用 FlowEngine 执行流程
/// final engine = FlowEngine(controller, job);
/// await engine.execute();
/// ```
library;

export 'data/data.dart';
export 'engine/engine.dart';
export 'executors/builtin/builtin.dart';
export 'executors/generic/generic.dart';
export 'registry/registry.dart';
