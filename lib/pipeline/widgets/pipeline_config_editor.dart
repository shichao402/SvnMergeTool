import 'package:flutter/material.dart';

import '../models/models.dart';

/// Pipeline 配置编辑器
/// 
/// 可视化编辑 Pipeline 配置
class PipelineConfigEditor extends StatefulWidget {
  /// 初始配置
  final PipelineConfig? initialConfig;

  /// 保存回调
  final void Function(PipelineConfig config)? onSave;

  /// 取消回调
  final VoidCallback? onCancel;

  const PipelineConfigEditor({
    super.key,
    this.initialConfig,
    this.onSave,
    this.onCancel,
  });

  @override
  State<PipelineConfigEditor> createState() => _PipelineConfigEditorState();
}

class _PipelineConfigEditorState extends State<PipelineConfigEditor> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late List<StageConfig> _stages;
  int _nextStageId = 1;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig ?? PipelineConfig.simple();
    _nameController = TextEditingController(text: config.name);
    _descriptionController = TextEditingController(text: config.description ?? '');
    _stages = List.from(config.stages);
    _nextStageId = _stages.length + 1;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 基本信息
        _buildBasicInfo(),
        const SizedBox(height: 16),
        const Divider(),
        // 阶段列表
        Expanded(
          child: _buildStageList(),
        ),
        const Divider(),
        // 操作按钮
        _buildActions(),
      ],
    );
  }

  Widget _buildBasicInfo() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pipeline 配置',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '描述',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildStageList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text(
                '阶段配置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              PopupMenuButton<StageType>(
                icon: const Icon(Icons.add),
                tooltip: '添加阶段',
                onSelected: _addStage,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: StageType.script,
                    child: ListTile(
                      leading: Icon(Icons.code),
                      title: Text('脚本'),
                      subtitle: Text('执行自定义脚本'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: StageType.check,
                    child: ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('检查'),
                      subtitle: Text('编译/测试检查'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: StageType.review,
                    child: ListTile(
                      leading: Icon(Icons.rate_review),
                      title: Text('审核'),
                      subtitle: Text('等待用户输入'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: StageType.postScript,
                    child: ListTile(
                      leading: Icon(Icons.cleaning_services),
                      title: Text('后置脚本'),
                      subtitle: Text('清理/通知'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _stages.length,
            onReorder: _reorderStages,
            itemBuilder: (context, index) {
              final stage = _stages[index];
              return _StageListTile(
                key: ValueKey(stage.id),
                stage: stage,
                onEdit: () => _editStage(index),
                onDelete: stage.type.isBuiltin ? null : () => _deleteStage(index),
                onToggle: (enabled) => _toggleStage(index, enabled),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (widget.onCancel != null)
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('取消'),
            ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _addStage(StageType type) {
    final id = 'stage_${_nextStageId++}';
    StageConfig newStage;

    switch (type) {
      case StageType.script:
        newStage = StageConfig.script(
          id: id,
          name: '脚本',
          script: '',
        );
        break;
      case StageType.check:
        newStage = StageConfig.check(
          id: id,
          name: '检查',
          script: '',
        );
        break;
      case StageType.review:
        newStage = StageConfig.review(
          id: id,
          name: '审核',
          input: const ReviewInputConfig(label: '输入'),
        );
        break;
      case StageType.postScript:
        newStage = StageConfig.postScript(
          id: id,
          name: '后置脚本',
          script: '',
        );
        break;
      default:
        return;
    }

    // 找到合适的插入位置
    int insertIndex = _stages.length;
    if (type == StageType.postScript) {
      // 后置脚本放在最后
      insertIndex = _stages.length;
    } else {
      // 其他阶段放在 commit 之前
      for (int i = 0; i < _stages.length; i++) {
        if (_stages[i].type == StageType.commit) {
          insertIndex = i;
          break;
        }
      }
    }

    setState(() {
      _stages.insert(insertIndex, newStage);
    });

    // 立即编辑新阶段
    _editStage(insertIndex);
  }

  void _editStage(int index) async {
    final stage = _stages[index];
    final result = await showDialog<StageConfig>(
      context: context,
      builder: (context) => _StageEditDialog(stage: stage),
    );

    if (result != null) {
      setState(() {
        _stages[index] = result;
      });
    }
  }

  void _deleteStage(int index) {
    setState(() {
      _stages.removeAt(index);
    });
  }

  void _toggleStage(int index, bool enabled) {
    setState(() {
      _stages[index] = _stages[index].copyWith(enabled: enabled);
    });
  }

  void _reorderStages(int oldIndex, int newIndex) {
    // 不允许移动内置阶段的相对顺序
    final stage = _stages[oldIndex];
    if (stage.type.isBuiltin) {
      return;
    }

    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _stages.removeAt(oldIndex);
      _stages.insert(newIndex, item);
    });
  }

  void _save() {
    final config = PipelineConfig(
      id: widget.initialConfig?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      stages: _stages,
    );

    // 验证
    final errors = config.validate();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('配置错误: ${errors.join(', ')}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    widget.onSave?.call(config);
  }
}

/// 阶段列表项
class _StageListTile extends StatelessWidget {
  final StageConfig stage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(bool enabled)? onToggle;

  const _StageListTile({
    super.key,
    required this.stage,
    this.onEdit,
    this.onDelete,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isBuiltin = stage.type.isBuiltin;

    return Card(
      child: ListTile(
        leading: _buildTypeIcon(),
        title: Text(stage.name),
        subtitle: Text(
          stage.type.isScriptType
              ? stage.script ?? '未配置脚本'
              : stage.type.displayName,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 启用/禁用开关
            if (!isBuiltin)
              Switch(
                value: stage.enabled,
                onChanged: onToggle,
              ),
            // 编辑按钮
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: onEdit,
              tooltip: '编辑',
            ),
            // 删除按钮
            if (!isBuiltin)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: onDelete,
                tooltip: '删除',
              ),
            // 拖动手柄
            if (!isBuiltin)
              ReorderableDragStartListener(
                index: 0,
                child: const Icon(Icons.drag_handle),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeIcon() {
    IconData icon;
    Color color;

    switch (stage.type) {
      case StageType.prepare:
        icon = Icons.cleaning_services;
        color = Colors.blue;
        break;
      case StageType.update:
        icon = Icons.download;
        color = Colors.green;
        break;
      case StageType.merge:
        icon = Icons.merge;
        color = Colors.purple;
        break;
      case StageType.script:
        icon = Icons.code;
        color = Colors.orange;
        break;
      case StageType.check:
        icon = Icons.check_circle_outline;
        color = Colors.teal;
        break;
      case StageType.review:
        icon = Icons.rate_review;
        color = Colors.amber;
        break;
      case StageType.commit:
        icon = Icons.upload;
        color = Colors.indigo;
        break;
      case StageType.postScript:
        icon = Icons.cleaning_services;
        color = Colors.grey;
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
    );
  }
}

/// 阶段编辑对话框
class _StageEditDialog extends StatefulWidget {
  final StageConfig stage;

  const _StageEditDialog({required this.stage});

  @override
  State<_StageEditDialog> createState() => _StageEditDialogState();
}

class _StageEditDialogState extends State<_StageEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _scriptController;
  late TextEditingController _labelController;
  late TextEditingController _hintController;
  late FailureAction _onFail;
  late CaptureMode _captureMode;
  late int _maxRetries;
  late int _timeoutSeconds;
  late bool _required;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.stage.name);
    _scriptController = TextEditingController(text: widget.stage.script ?? '');
    _labelController = TextEditingController(
        text: widget.stage.reviewInput?.label ?? '');
    _hintController = TextEditingController(
        text: widget.stage.reviewInput?.hint ?? '');
    _onFail = widget.stage.onFail;
    _captureMode = widget.stage.captureMode;
    _maxRetries = widget.stage.maxRetries;
    _timeoutSeconds = widget.stage.timeoutSeconds;
    _required = widget.stage.reviewInput?.required ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scriptController.dispose();
    _labelController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('编辑阶段: ${widget.stage.type.displayName}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名称
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 脚本类型的配置
              if (widget.stage.type.isScriptType) ...[
                TextField(
                  controller: _scriptController,
                  decoration: const InputDecoration(
                    labelText: '脚本路径',
                    border: OutlineInputBorder(),
                    hintText: './scripts/xxx.sh',
                  ),
                ),
                const SizedBox(height: 16),

                // 捕获模式
                DropdownButtonFormField<CaptureMode>(
                  value: _captureMode,
                  decoration: const InputDecoration(
                    labelText: '输出捕获',
                    border: OutlineInputBorder(),
                  ),
                  items: CaptureMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _captureMode = value);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // 超时
                TextField(
                  decoration: const InputDecoration(
                    labelText: '超时（秒，0 表示无限制）',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: '$_timeoutSeconds'),
                  onChanged: (value) {
                    _timeoutSeconds = int.tryParse(value) ?? 0;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Review 类型的配置
              if (widget.stage.type == StageType.review) ...[
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: '输入标签',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hintController,
                  decoration: const InputDecoration(
                    labelText: '输入提示',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('必填'),
                  value: _required,
                  onChanged: (value) {
                    setState(() => _required = value);
                  },
                ),
                const SizedBox(height: 16),
              ],

              // 失败处理
              DropdownButtonFormField<FailureAction>(
                value: _onFail,
                decoration: const InputDecoration(
                  labelText: '失败时',
                  border: OutlineInputBorder(),
                ),
                items: FailureAction.values.map((action) {
                  return DropdownMenuItem(
                    value: action,
                    child: Text(action.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _onFail = value);
                  }
                },
              ),

              // 重试次数
              if (_onFail == FailureAction.retry) ...[
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '最大重试次数',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  controller: TextEditingController(text: '$_maxRetries'),
                  onChanged: (value) {
                    _maxRetries = int.tryParse(value) ?? 3;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    ReviewInputConfig? reviewInput;
    if (widget.stage.type == StageType.review) {
      reviewInput = ReviewInputConfig(
        label: _labelController.text.trim(),
        hint: _hintController.text.trim().isEmpty
            ? null
            : _hintController.text.trim(),
        required: _required,
      );
    }

    final result = widget.stage.copyWith(
      name: _nameController.text.trim(),
      script: _scriptController.text.trim().isEmpty
          ? null
          : _scriptController.text.trim(),
      captureMode: _captureMode,
      onFail: _onFail,
      maxRetries: _maxRetries,
      timeoutSeconds: _timeoutSeconds,
      reviewInput: reviewInput,
    );

    Navigator.of(context).pop(result);
  }
}
