/// 流程编辑器界面
///
/// 允许用户创建、编辑和保存自定义流程
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart' hide NodeData;

import '../pipeline/adapter/vyuh_adapter.dart';
import '../pipeline/data/data.dart';
import '../pipeline/graph/merge_flow_builder.dart';
import '../pipeline/graph/stage_data.dart';
import '../pipeline/models/stage_type.dart';
import '../pipeline/registry/registry.dart';
import '../services/logger_service.dart';
import '../services/standard_flow_service.dart';

/// 流程编辑器界面
class FlowEditorScreen extends StatefulWidget {
  /// 要编辑的流程文件路径（可选，新建时为空）
  final String? flowFilePath;

  const FlowEditorScreen({super.key, this.flowFilePath});

  @override
  State<FlowEditorScreen> createState() => _FlowEditorScreenState();

  /// 显示流程编辑器
  static Future<void> show(BuildContext context, {String? flowFilePath}) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlowEditorScreen(flowFilePath: flowFilePath),
      ),
    );
  }
}

class _FlowEditorScreenState extends State<FlowEditorScreen> {
  /// Vyuh 适配器（节点创建的唯一入口）
  final _adapter = VyuhAdapter();
  late NodeFlowController<VyuhNodeData> _controller;
  String? _currentFilePath;
  bool _isDirty = false;
  String _flowName = '未命名流程';
  bool _isReadonly = false;  // 标准流程只读

  // 节点面板状态
  bool _showNodePanel = true;
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _controller = _adapter.createController();
    _currentFilePath = widget.flowFilePath;
    if (_currentFilePath != null) {
      _loadFlow(_currentFilePath!);
    }
  }

  @override
  void dispose() {
    _adapter.disposeController(_controller);
    super.dispose();
  }

  /// 加载流程
  Future<void> _loadFlow(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        _showError('文件不存在: $path');
        return;
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      
      // 检查是否为只读（标准流程）
      final metadata = json['metadata'] as Map<String, dynamic>?;
      final isBuiltin = metadata?['isBuiltin'] as bool? ?? false;
      final isReadonly = metadata?['readonly'] as bool? ?? false;
      _isReadonly = isBuiltin || isReadonly || StandardFlowService.isStandardFlow(path);
      
      // 检查格式版本
      final version = metadata?['version'] as String?;
      final isNewFormat = version == '2.0' || 
                          metadata?['standardFlowVersion'] != null ||
                          json.containsKey('nodes') && (json['nodes'] as List?)?.isNotEmpty == true &&
                          (json['nodes'] as List).first is Map && 
                          ((json['nodes'] as List).first as Map).containsKey('data');

      _controller.clearGraph();

      if (isNewFormat) {
        // 新格式：NodeGraph<StageData>
        await _loadNewFormat(json);
      } else {
        // 旧格式：FlowGraphData
        await _loadOldFormat(json);
      }

      setState(() {
        _flowName = metadata?['name'] as String? ?? 
            path.split('/').last.replaceAll('.flow.json', '');
        _isDirty = false;
      });

      AppLogger.ui.info('已加载流程: $path (${isNewFormat ? "新格式" : "旧格式"}, ${_isReadonly ? "只读" : "可编辑"})');
    } catch (e) {
      _showError('加载流程失败: $e');
      AppLogger.ui.error('加载流程失败', e);
    }
  }

  /// 加载新格式（NodeGraph<StageData>）
  Future<void> _loadNewFormat(Map<String, dynamic> json) async {
    final stageController = MergeFlowBuilder.fromJson(json);
    final registry = NodeTypeRegistry.instance;

    // 转换为编辑器节点（通过 adapter）
    for (final node in stageController.nodes.values) {
      final stageData = node.data;
      final typeDef = registry.get(stageData.type.name);
      
      if (typeDef != null) {
        final nodeData = NodeData(
          id: node.id,
          typeId: stageData.type.name,
          x: node.position.value.dx,
          y: node.position.value.dy,
          config: _stageDataToConfig(stageData),
        );
        final editorNode = _adapter.createViewNode(typeDef, nodeData);
        _controller.addNode(editorNode);
      }
    }

    // 添加连接
    for (final conn in stageController.connections) {
      _controller.addConnection(conn);
    }
  }

  /// 加载旧格式（FlowGraphData）
  Future<void> _loadOldFormat(Map<String, dynamic> json) async {
    final graphData = FlowGraphData.fromJson(json);

    // 添加节点（通过 adapter）
    for (final nodeData in graphData.nodes) {
      final typeDef = NodeTypeRegistry.instance.get(nodeData.typeId);
      if (typeDef != null) {
        final node = _adapter.createViewNode(typeDef, nodeData);
        _controller.addNode(node);
      }
    }

    // 添加连接
    for (final connData in graphData.connections) {
      final connection = Connection(
        id: connData.id,
        sourceNodeId: connData.sourceNodeId,
        sourcePortId: connData.sourcePortId,
        targetNodeId: connData.targetNodeId,
        targetPortId: connData.targetPortId,
      );
      _controller.addConnection(connection);
    }
  }

  /// 将 StageData 转换为配置 Map
  Map<String, dynamic> _stageDataToConfig(StageData data) {
    return {
      if (data.enabled != true) 'enabled': data.enabled,
      if (data.scriptPath != null) 'scriptPath': data.scriptPath,
      if (data.scriptArgs != null) 'scriptArgs': data.scriptArgs,
      if (data.commitMessageTemplate != null) 'commitMessageTemplate': data.commitMessageTemplate,
      if (data.reviewInput != null) 'reviewInput': data.reviewInput!.toJson(),
    };
  }

  /// 保存流程
  Future<void> _saveFlow() async {
    // 只读流程强制另存为
    if (_isReadonly || _currentFilePath == null) {
      await _saveFlowAs();
      return;
    }

    try {
      // 转换为完整的 NodeGraph<StageData> 格式（离线重建）
      final stageController = _convertToStageController();
      final json = MergeFlowBuilder.toJson(stageController);
      
      // 添加元数据
      json['metadata'] = {
        'name': _flowName,
        'savedAt': DateTime.now().toIso8601String(),
        'version': '2.0',  // 标记为新格式
      };

      final file = File(_currentFilePath!);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));

      setState(() => _isDirty = false);
      _showSuccess('流程已保存');
      AppLogger.ui.info('已保存流程: $_currentFilePath');
    } catch (e) {
      _showError('保存失败: $e');
      AppLogger.ui.error('保存流程失败', e);
    }
  }

  /// 另存为
  Future<void> _saveFlowAs() async {
    final name = await _showNameDialog();
    if (name == null || name.isEmpty) return;

    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.svn_flow/flows');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final path = '${dir.path}/$name.flow.json';
    
    // 检查是否已存在
    if (File(path).existsSync()) {
      final confirm = await _showConfirmDialog('文件已存在', '是否覆盖 $name.flow.json？');
      if (confirm != true) return;
    }

    setState(() {
      _currentFilePath = path;
      _flowName = name;
    });

    await _saveFlow();
  }

  /// 新建流程
  Future<void> _newFlow() async {
    if (_isDirty) {
      final save = await _showConfirmDialog('未保存的更改', '是否保存当前流程？');
      if (save == true) {
        await _saveFlow();
      } else if (save == null) {
        return; // 取消
      }
    }

    _controller.clearGraph();
    setState(() {
      _currentFilePath = null;
      _flowName = '未命名流程';
      _isDirty = false;
    });
  }

  /// 导出图数据
  FlowGraphData _exportGraph() {
    return _adapter.exportGraph(_controller);
  }

  /// 转换为 StageData 控制器（用于保存完整格式）
  NodeFlowController<StageData> _convertToStageController() {
    final stageController = NodeFlowController<StageData>();
    final graph = _controller.exportGraph();
    final registry = NodeTypeRegistry.instance;

    // 转换节点
    for (final node in graph.nodes) {
      final typeDef = registry.get(node.data.typeId);
      if (typeDef == null) {
        throw Exception('未知的节点类型: ${node.data.typeId}');
      }

      // 从 NodeTypeDefinition 构建 StageData
      final stageData = _buildStageData(typeDef, node.data.config);

      // 创建完整的节点
      final stageNode = Node<StageData>(
        id: node.id,
        type: node.type,
        position: node.position.value,
        data: stageData,
        size: node.size.value,
        inputPorts: node.inputPorts.toList(),
        outputPorts: node.outputPorts.toList(),
      );

      stageController.addNode(stageNode);
    }

    // 转换连接
    for (final conn in graph.connections) {
      stageController.addConnection(conn);
    }

    return stageController;
  }

  /// 从节点类型定义构建 StageData
  StageData _buildStageData(NodeTypeDefinition typeDef, Map<String, dynamic> config) {
    // 解析 StageType
    final stageType = _parseStageType(typeDef.typeId);

    return StageData(
      type: stageType,
      name: typeDef.name,
      description: typeDef.description,
      enabled: config['enabled'] as bool? ?? true,
      scriptPath: config['scriptPath'] as String?,
      scriptArgs: (config['scriptArgs'] as List<dynamic>?)?.cast<String>(),
      commitMessageTemplate: config['commitMessageTemplate'] as String?,
      reviewInput: config['reviewInput'] != null
          ? ReviewInputData.fromJson(config['reviewInput'] as Map<String, dynamic>)
          : null,
    );
  }

  /// 解析 StageType
  StageType _parseStageType(String typeId) {
    // 尝试直接匹配
    for (final type in StageType.values) {
      if (type.name == typeId) {
        return type;
      }
    }
    // 默认为 script 类型
    return StageType.script;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Row(
        children: [
          // 节点面板
          if (_showNodePanel) _buildNodePanel(),
          // 编辑器主区域
          Expanded(child: _buildEditor()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Text(_flowName),
          if (_isDirty) const Text(' *', style: TextStyle(color: Colors.orange)),
          if (_isReadonly) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('只读', style: TextStyle(fontSize: 11, color: Colors.black54)),
            ),
          ],
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () async {
          if (_isDirty) {
            final save = await _showConfirmDialog('未保存的更改', '是否保存当前流程？');
            if (save == true) {
              await _saveFlow();
            } else if (save == null) {
              return;
            }
          }
          if (mounted) Navigator.of(context).pop();
        },
      ),
      actions: [
        // 切换节点面板
        IconButton(
          icon: Icon(_showNodePanel ? Icons.view_sidebar : Icons.view_sidebar_outlined),
          onPressed: () => setState(() => _showNodePanel = !_showNodePanel),
          tooltip: '节点面板',
        ),
        const VerticalDivider(),
        // 新建
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: _newFlow,
          tooltip: '新建流程',
        ),
        // 打开
        IconButton(
          icon: const Icon(Icons.folder_open),
          onPressed: _openFlow,
          tooltip: '打开流程',
        ),
        // 保存（只读时显示为另存为）
        IconButton(
          icon: Icon(_isReadonly ? Icons.save_as : Icons.save),
          onPressed: _isDirty ? _saveFlow : null,
          tooltip: _isReadonly ? '另存为（只读流程）' : '保存',
        ),
        // 另存为
        IconButton(
          icon: const Icon(Icons.save_as),
          onPressed: _saveFlowAs,
          tooltip: '另存为',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildNodePanel() {
    final registry = NodeTypeRegistry.instance;
    final definitions = registry.visibleDefinitions.toList();
    
    // 获取所有分类
    final categories = <String>{};
    for (final def in definitions) {
      categories.add(def.category ?? '未分类');
    }

    // 过滤节点
    var filteredDefs = definitions;
    if (_searchQuery.isNotEmpty) {
      filteredDefs = filteredDefs.where((d) =>
        d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        d.typeId.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (d.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }
    if (_selectedCategory != null) {
      filteredDefs = filteredDefs.where((d) => 
        (d.category ?? '未分类') == _selectedCategory
      ).toList();
    }

    // 按分类分组
    final grouped = <String, List<NodeTypeDefinition>>{};
    for (final def in filteredDefs) {
      final cat = def.category ?? '未分类';
      grouped.putIfAbsent(cat, () => []).add(def);
    }

    return Container(
      width: 280,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索节点...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // 分类过滤
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 4),
                ...categories.map((cat) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilterChip(
                    label: Text(cat),
                    selected: _selectedCategory == cat,
                    onSelected: (_) => setState(() => 
                      _selectedCategory = _selectedCategory == cat ? null : cat
                    ),
                  ),
                )),
              ],
            ),
          ),
          const Divider(),
          // 节点列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: grouped.entries.map((entry) => _buildCategorySection(
                entry.key, 
                entry.value,
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String category, List<NodeTypeDefinition> definitions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            category,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
              fontSize: 12,
            ),
          ),
        ),
        ...definitions.map((def) => _buildNodeTile(def)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildNodeTile(NodeTypeDefinition def) {
    final tileContent = Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: def.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(def.icon, size: 18, color: def.color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.name,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  if (def.description != null)
                    Text(
                      def.description!,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (def.isUserDefined)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '自定义',
                  style: TextStyle(fontSize: 9, color: Colors.purple.shade700),
                ),
              ),
          ],
        ),
      ),
    );

    // 支持拖放
    return Draggable<NodeTypeDefinition>(
      data: def,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 120,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: def.color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(def.icon, size: 16, color: Colors.white),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  def.name,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: tileContent),
      child: tileContent,
    );
  }

  /// 编辑器主题（启用端口标签显示）
  static final _editorTheme = NodeFlowTheme.light.copyWith(
    portTheme: PortTheme.light.copyWith(
      showLabel: true,
      labelTextStyle: const TextStyle(
        fontSize: 10.0,
        color: Color(0xFF333333),
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  /// 编辑器区域的 GlobalKey，用于计算拖放位置
  final _editorKey = GlobalKey();

  Widget _buildEditor() {
    return DragTarget<NodeTypeDefinition>(
      key: _editorKey,
      onAcceptWithDetails: (details) {
        // 计算拖放位置（相对于编辑器）
        final renderBox = _editorKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final localPosition = renderBox.globalToLocal(details.offset);
          // 转换为画布坐标
          final viewport = _controller.viewport;
          final canvasX = (localPosition.dx - viewport.x) / viewport.zoom;
          final canvasY = (localPosition.dy - viewport.y) / viewport.zoom;
          _addNodeAtPosition(details.data, Offset(canvasX, canvasY));
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          color: isHovering ? Colors.blue.shade50 : Colors.grey.shade100,
          child: NodeFlowEditor<VyuhNodeData>(
            controller: _controller,
            behavior: NodeFlowBehavior.design,
            theme: _editorTheme,
            nodeBuilder: (context, node) => _buildNodeWidget(node),
            events: NodeFlowEvents(
              connection: ConnectionEvents(
                onCreated: (conn) => setState(() => _isDirty = true),
                onDeleted: (conn) => setState(() => _isDirty = true),
              ),
              node: NodeEvents(
                onDragStop: (node) => setState(() => _isDirty = true),
                onDeleted: (node) => setState(() => _isDirty = true),
                onContextMenu: _showNodeContextMenu,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 显示节点右键菜单
  void _showNodeContextMenu(Node<VyuhNodeData> node, Offset position) {
    final deleteShortcut = Platform.isMacOS ? '⌫' : 'Delete';
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem<String>(
          value: 'duplicate',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('复制'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete, size: 18, color: Colors.red),
              const SizedBox(width: 8),
              const Text('删除', style: TextStyle(color: Colors.red)),
              const Spacer(),
              Text(deleteShortcut, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'duplicate') {
        _duplicateNode(node);
      } else if (value == 'delete') {
        _controller.removeNode(node.id);
        setState(() => _isDirty = true);
      }
    });
  }

  /// 复制单个节点
  void _duplicateNode(Node<VyuhNodeData> node) {
    final newNode = _adapter.duplicateNode(node);
    if (newNode != null) {
      _controller.addNode(newNode);
      _controller.selectNode(newNode.id);
      setState(() => _isDirty = true);
    }
  }

  /// 在指定位置添加节点
  void _addNodeAtPosition(NodeTypeDefinition typeDef, Offset position) {
    final node = _adapter.createNewNode(typeDef, position: position);
    _controller.addNode(node);
    setState(() => _isDirty = true);
  }

  Widget _buildNodeWidget(Node<VyuhNodeData> node) {
    final data = node.data;
    final color = data.color ?? Colors.blue;
    final icon = data.icon ?? Icons.extension;
    final name = data.name ?? data.typeId;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏（固定高度）
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600, 
                      fontSize: 11,
                      color: color.computeLuminance() > 0.5 
                          ? Colors.black87 
                          : color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 端口区域（占据剩余空间，不渲染内容，只是占位）
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  /// 打开流程
  Future<void> _openFlow() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dir = Directory('$home/.svn_flow/flows');
    
    if (!dir.existsSync()) {
      _showError('没有已保存的流程');
      return;
    }

    final files = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.flow.json'))
        .toList();

    if (files.isEmpty) {
      _showError('没有已保存的流程');
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开流程'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final name = file.path.split('/').last.replaceAll('.flow.json', '');
              return ListTile(
                leading: const Icon(Icons.account_tree),
                title: Text(name),
                subtitle: Text(file.statSync().modified.toString().split('.').first),
                onTap: () => Navigator.of(context).pop(file.path),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selected != null) {
      if (_isDirty) {
        final save = await _showConfirmDialog('未保存的更改', '是否保存当前流程？');
        if (save == true) {
          await _saveFlow();
        } else if (save == null) {
          return;
        }
      }
      _currentFilePath = selected;
      await _loadFlow(selected);
    }
  }

  Future<String?> _showNameDialog() async {
    final controller = TextEditingController(text: _flowName);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('流程名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入流程名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
}
