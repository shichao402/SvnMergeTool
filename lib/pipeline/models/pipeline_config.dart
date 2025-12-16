import 'stage_config.dart';
import 'stage_type.dart';

/// Pipeline 配置
class PipelineConfig {
  /// 唯一标识
  final String id;

  /// 显示名称
  final String name;

  /// 描述
  final String? description;

  /// 阶段列表
  final List<StageConfig> stages;

  /// 是否为默认配置
  final bool isDefault;

  const PipelineConfig({
    required this.id,
    required this.name,
    this.description,
    required this.stages,
    this.isDefault = false,
  });

  /// 创建默认的简单合并 Pipeline
  factory PipelineConfig.simple() {
    return PipelineConfig(
      id: 'simple',
      name: '简单合并',
      description: '仅包含基本的 SVN 合并操作',
      isDefault: true,
      stages: [
        StageConfig.prepare(),
        StageConfig.update(),
        StageConfig.merge(),
        StageConfig.commit(),
      ],
    );
  }

  /// 创建带检查的合并 Pipeline
  factory PipelineConfig.withCheck({
    required String checkScript,
    String? checkName,
  }) {
    return PipelineConfig(
      id: 'with_check',
      name: '带检查的合并',
      description: '合并后执行检查脚本',
      stages: [
        StageConfig.prepare(),
        StageConfig.update(),
        StageConfig.merge(),
        StageConfig.check(
          id: 'check',
          name: checkName ?? '检查',
          script: checkScript,
        ),
        StageConfig.commit(),
      ],
    );
  }

  /// 从 JSON 创建
  factory PipelineConfig.fromJson(Map<String, dynamic> json) {
    return PipelineConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      stages: (json['stages'] as List<dynamic>)
          .map((e) => StageConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      'stages': stages.map((e) => e.toJson()).toList(),
      if (isDefault) 'isDefault': isDefault,
    };
  }

  /// 复制并修改
  PipelineConfig copyWith({
    String? id,
    String? name,
    String? description,
    List<StageConfig>? stages,
    bool? isDefault,
  }) {
    return PipelineConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      stages: stages ?? this.stages,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  /// 获取启用的阶段列表
  List<StageConfig> get enabledStages {
    return stages.where((s) => s.enabled).toList();
  }

  /// 根据 ID 查找阶段
  StageConfig? findStageById(String id) {
    try {
      return stages.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 验证配置是否有效
  List<String> validate() {
    final errors = <String>[];

    // 检查必须的内置阶段
    final hasPrep = stages.any((s) => s.type == StageType.prepare);
    final hasUpdate = stages.any((s) => s.type == StageType.update);
    final hasMerge = stages.any((s) => s.type == StageType.merge);
    final hasCommit = stages.any((s) => s.type == StageType.commit);

    if (!hasPrep) errors.add('缺少准备阶段');
    if (!hasUpdate) errors.add('缺少更新阶段');
    if (!hasMerge) errors.add('缺少合并阶段');
    if (!hasCommit) errors.add('缺少提交阶段');

    // 检查阶段 ID 唯一性
    final ids = <String>{};
    for (final stage in stages) {
      if (ids.contains(stage.id)) {
        errors.add('阶段 ID 重复: ${stage.id}');
      }
      ids.add(stage.id);
    }

    // 检查脚本阶段必须有脚本路径
    for (final stage in stages) {
      if (stage.type.isScriptType && stage.script == null) {
        errors.add('阶段 "${stage.name}" 缺少脚本路径');
      }
      if (stage.type == StageType.review && stage.reviewInput == null) {
        errors.add('阶段 "${stage.name}" 缺少输入配置');
      }
    }

    return errors;
  }
}
