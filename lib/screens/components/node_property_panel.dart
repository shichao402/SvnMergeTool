/// 节点属性编辑面板
///
/// 用于在流程编辑器中编辑选中节点的配置参数。
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../pipeline/registry/registry.dart';
import '../../services/script_path_service.dart';

/// 节点属性编辑面板
class NodePropertyPanel extends StatefulWidget {
  /// 节点类型定义
  final NodeTypeDefinition typeDef;

  /// 当前配置
  final Map<String, dynamic> config;

  /// 配置变更回调
  final void Function(Map<String, dynamic> newConfig) onConfigChanged;

  /// 关闭面板回调
  final VoidCallback? onClose;

  const NodePropertyPanel({
    super.key,
    required this.typeDef,
    required this.config,
    required this.onConfigChanged,
    this.onClose,
  });

  @override
  State<NodePropertyPanel> createState() => _NodePropertyPanelState();
}

class _NodePropertyPanelState extends State<NodePropertyPanel> {
  late Map<String, dynamic> _editingConfig;
  final Map<String, TextEditingController> _textControllers = {};

  @override
  void initState() {
    super.initState();
    _editingConfig = Map.from(widget.config);
    _initTextControllers();
  }

  @override
  void didUpdateWidget(NodePropertyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typeDef.typeId != widget.typeDef.typeId ||
        oldWidget.config != widget.config) {
      _editingConfig = Map.from(widget.config);
      _disposeTextControllers();
      _initTextControllers();
    }
  }

  void _initTextControllers() {
    for (final param in widget.typeDef.params) {
      if (_isTextParam(param.type)) {
        final value = _editingConfig[param.key]?.toString() ??
            param.defaultValue?.toString() ??
            '';
        _textControllers[param.key] = TextEditingController(text: value);
      }
    }
  }

  void _disposeTextControllers() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
  }

  bool _isTextParam(ParamType type) {
    return type == ParamType.string ||
        type == ParamType.text ||
        type == ParamType.code ||
        type == ParamType.path ||
        type == ParamType.directory ||
        type == ParamType.int ||
        type == ParamType.double;
  }

  @override
  void dispose() {
    _disposeTextControllers();
    super.dispose();
  }

  void _updateConfig(String key, dynamic value) {
    setState(() {
      _editingConfig[key] = value;
    });
    widget.onConfigChanged(Map.from(_editingConfig));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // 标题栏
          _buildHeader(),
          const Divider(height: 1),
          // 参数列表
          Expanded(
            child: widget.typeDef.params.isEmpty
                ? _buildEmptyParams()
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: widget.typeDef.params
                        .map((param) => _buildParamField(param))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: widget.typeDef.color.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(widget.typeDef.icon, size: 20, color: widget.typeDef.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.typeDef.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: widget.typeDef.color,
                  ),
                ),
                Text(
                  '节点属性',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyParams() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            '此节点无可配置参数',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildParamField(ParamSpec param) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标签
          Row(
            children: [
              Text(
                param.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              if (param.required)
                Text(
                  ' *',
                  style: TextStyle(color: Colors.red.shade600),
                ),
            ],
          ),
          if (param.description != null) ...[
            const SizedBox(height: 2),
            Text(
              param.description!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          // 输入控件
          _buildInputWidget(param),
        ],
      ),
    );
  }

  Widget _buildInputWidget(ParamSpec param) {
    final currentValue = _editingConfig[param.key] ?? param.defaultValue;

    switch (param.type) {
      case ParamType.string:
        return _buildTextField(param);

      case ParamType.text:
      case ParamType.code:
        return _buildMultilineTextField(param);

      case ParamType.int:
        return _buildIntField(param);

      case ParamType.double:
        return _buildDoubleField(param);

      case ParamType.bool:
        return _buildBoolField(param, currentValue as bool? ?? false);

      case ParamType.select:
        return _buildSelectField(param, currentValue);

      case ParamType.path:
        return _buildPathField(param, isDirectory: false);

      case ParamType.directory:
        return _buildPathField(param, isDirectory: true);

      case ParamType.stringList:
        return _buildStringListField(param);

      case ParamType.json:
        return _buildMultilineTextField(param);
    }
  }

  Widget _buildTextField(ParamSpec param) {
    return TextField(
      controller: _textControllers[param.key],
      decoration: InputDecoration(
        hintText: param.placeholder ?? '输入${param.label}',
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: (value) => _updateConfig(param.key, value),
    );
  }

  Widget _buildMultilineTextField(ParamSpec param) {
    return TextField(
      controller: _textControllers[param.key],
      maxLines: 4,
      decoration: InputDecoration(
        hintText: param.placeholder ?? '输入${param.label}',
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.all(10),
      ),
      style: param.type == ParamType.code
          ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
          : null,
      onChanged: (value) => _updateConfig(param.key, value),
    );
  }

  Widget _buildIntField(ParamSpec param) {
    return TextField(
      controller: _textControllers[param.key],
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: param.placeholder ?? '输入整数',
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        suffixText: param.min != null || param.max != null
            ? '${param.min ?? ''}~${param.max ?? ''}'
            : null,
      ),
      onChanged: (value) {
        final intValue = int.tryParse(value);
        if (intValue != null) {
          _updateConfig(param.key, intValue);
        }
      },
    );
  }

  Widget _buildDoubleField(ParamSpec param) {
    return TextField(
      controller: _textControllers[param.key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: param.placeholder ?? '输入数字',
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      onChanged: (value) {
        final doubleValue = double.tryParse(value);
        if (doubleValue != null) {
          _updateConfig(param.key, doubleValue);
        }
      },
    );
  }

  Widget _buildBoolField(ParamSpec param, bool currentValue) {
    return SwitchListTile(
      value: currentValue,
      onChanged: (value) => _updateConfig(param.key, value),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        currentValue ? '是' : '否',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildSelectField(ParamSpec param, dynamic currentValue) {
    return DropdownButtonFormField<dynamic>(
      initialValue: currentValue,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: param.options?.map((option) {
        return DropdownMenuItem(
          value: option.value,
          child: Text(option.label, style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
      onChanged: (value) => _updateConfig(param.key, value),
    );
  }

  Widget _buildPathField(ParamSpec param, {required bool isDirectory}) {
    final controller = _textControllers[param.key];
    final currentValue = controller?.text ?? '';
    final isRelative = ScriptPathService.isRelativePath(currentValue);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: isDirectory ? '选择目录' : '选择文件或输入 @scripts/xxx.py',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  prefixIcon: isRelative 
                      ? const Icon(Icons.link, size: 18, color: Colors.green)
                      : null,
                ),
                onChanged: (value) => _updateConfig(param.key, value),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(isDirectory ? Icons.folder_open : Icons.file_open),
              onPressed: () async {
                if (isDirectory) {
                  final result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) {
                    controller?.text = result;
                    _updateConfig(param.key, result);
                  }
                } else {
                  final result = await FilePicker.platform.pickFiles();
                  if (result != null && result.files.isNotEmpty) {
                    final path = result.files.first.path;
                    if (path != null) {
                      // 如果文件在脚本目录下，自动转换为相对路径
                      final finalPath = ScriptPathService.toRelativePath(path);
                      controller?.text = finalPath;
                      _updateConfig(param.key, finalPath);
                    }
                  }
                }
              },
              tooltip: isDirectory ? '浏览目录' : '浏览文件',
            ),
          ],
        ),
        // 显示相对路径提示
        if (isRelative && !isDirectory)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '相对路径 → ${ScriptPathService.toAbsolutePath(currentValue)}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        // 显示脚本目录提示
        if (!isDirectory && currentValue.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '提示: 将脚本放入 ~/.svn_flow/scripts/ 可使用相对路径',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStringListField(ParamSpec param) {
    final currentList = (_editingConfig[param.key] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...currentList.asMap().entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  onPressed: () {
                    final newList = List<String>.from(currentList)
                      ..removeAt(entry.key);
                    _updateConfig(param.key, newList);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          );
        }),
        TextButton.icon(
          onPressed: () async {
            final value = await _showAddStringDialog();
            if (value != null && value.isNotEmpty) {
              final newList = List<String>.from(currentList)..add(value);
              _updateConfig(param.key, newList);
            }
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加'),
        ),
      ],
    );
  }

  Future<String?> _showAddStringDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加项'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入值',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
