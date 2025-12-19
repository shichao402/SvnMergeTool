/// Pipeline 模块导出
/// 
/// 使用方式：
/// ```dart
/// import 'package:svn_auto_merge/pipeline/pipeline.dart';
/// 
/// // 使用全局实例
/// final pipeline = GlobalGraphPipeline.instance;
/// 
/// // 或创建新实例
/// final pipeline = GraphPipelineFacade()..initialize();
/// ```
library;

export 'engine/engine.dart';
export 'executors/executors.dart';
export 'graph/graph.dart';
export 'models/models.dart';
export 'widgets/widgets.dart';
