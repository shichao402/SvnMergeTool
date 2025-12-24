/// Pipeline 执行面板
///
/// 显示 Pipeline 执行状态、用户输入和控制指令
library;

import 'package:flutter/material.dart';
import '../../pipeline/engine/engine.dart';
import '../../models/merge_job.dart';

/// Pipeline 执行面板
/// 
/// 整合了：
/// - 执行状态显示
/// - 用户输入区域
/// - 流程控制指令（暂停、恢复、取消、跳过）
class PipelinePanel extends StatefulWidget {
  /// 执行状态
  final ExecutorStatus status;
  
  /// 当前节点 ID
  final String? currentNodeId;
  
  /// 当前节点名称
  final String? currentNodeName;
  
  /// 暂停的任务
  final MergeJob? pausedJob;
  
  /// 是否等待用户输入
  final bool isWaitingInput;
  
  /// 用户输入配置（当 isWaitingInput 为 true 时有效）
  final UserInputConfig? inputConfig;
  
  /// 恢复回调
  final VoidCallback onResume;
  
  /// 跳过回调
  final VoidCallback onSkip;
  
  /// 取消回调
  final VoidCallback onCancel;
  
  /// 提交输入回调
  final void Function(String value)? onSubmitInput;

  const PipelinePanel({
    super.key,
    required this.status,
    this.currentNodeId,
    this.currentNodeName,
    required this.pausedJob,
    required this.isWaitingInput,
    this.inputConfig,
    required this.onResume,
    required this.onSkip,
    required this.onCancel,
    this.onSubmitInput,
  });

  @override
  State<PipelinePanel> createState() => _PipelinePanelState();
}

class _PipelinePanelState extends State<PipelinePanel> {
  final _inputController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PipelinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当输入配置变化时，清空输入框
    if (widget.inputConfig != oldWidget.inputConfig) {
      _inputController.clear();
      _validationError = null;
    }
  }

  void _submitInput() {
    final value = _inputController.text.trim();
    
    // 验证必填
    if (widget.inputConfig?.required == true && value.isEmpty) {
      setState(() => _validationError = '此字段为必填项');
      return;
    }
    
    // 验证正则
    final regex = widget.inputConfig?.validationRegex;
    if (regex != null && value.isNotEmpty) {
      if (!RegExp(regex).hasMatch(value)) {
        setState(() => _validationError = '输入格式不正确');
        return;
      }
    }
    
    _validationError = null;
    widget.onSubmitInput?.call(value);
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          _buildHeader(),
          const Divider(height: 1),
          
          // 主内容区
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 执行状态
                  _buildStatusSection(),
                  
                  // 进度信息
                  if (widget.pausedJob != null) ...[
                    const SizedBox(height: 16),
                    _buildProgressSection(),
                  ],
                  
                  // 用户输入区域
                  if (widget.isWaitingInput && widget.inputConfig != null) ...[
                    const SizedBox(height: 20),
                    _buildInputSection(),
                  ],
                ],
              ),
            ),
          ),
          
          // 底部控制区
          _buildControlSection(),
        ],
      ),
    );
  }

  /// 标题栏
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _getStatusColor().withValues(alpha: 0.1),
      child: Row(
        children: [
          _StatusIcon(status: widget.status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusTitle(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.currentNodeName != null)
                  Text(
                    widget.currentNodeName!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 状态区域
  Widget _buildStatusSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getStatusIcon(),
                size: 20,
                color: _getStatusColor(),
              ),
              const SizedBox(width: 8),
              Text(
                _getStatusMessage(),
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: _getStatusColor(),
                ),
              ),
            ],
          ),
          if (widget.currentNodeId != null) ...[
            const SizedBox(height: 8),
            Text(
              '节点: ${widget.currentNodeId}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 进度区域
  Widget _buildProgressSection() {
    final job = widget.pausedJob!;
    final progress = job.completedIndex / job.revisions.length;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '执行进度',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                '${job.completedIndex}/${job.revisions.length}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前: r${job.currentRevision}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          if (job.pauseReason.isNotEmpty && !job.pauseReason.startsWith('等待输入')) ...[
            const SizedBox(height: 4),
            Text(
              '原因: ${job.pauseReason}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 用户输入区域
  Widget _buildInputSection() {
    final config = widget.inputConfig!;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  config.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
              if (config.required)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '必填',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
            ],
          ),
          if (config.hint != null) ...[
            const SizedBox(height: 8),
            Text(
              config.hint!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _inputController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '请输入...',
              errorText: _validationError,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (_) => _submitInput(),
            onChanged: (_) {
              if (_validationError != null) {
                setState(() => _validationError = null);
              }
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitInput,
              icon: const Icon(Icons.send, size: 18),
              label: const Text('提交'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 控制区域
  Widget _buildControlSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 主要操作
          if (widget.status == ExecutorStatus.paused && !widget.isWaitingInput)
            ElevatedButton.icon(
              onPressed: widget.onResume,
              icon: const Icon(Icons.play_arrow),
              label: const Text('继续执行'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          
          const SizedBox(height: 8),
          
          // 次要操作
          Row(
            children: [
              // 跳过按钮
              if (widget.pausedJob != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onSkip,
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: Text('跳过 r${widget.pausedJob!.currentRevision}'),
                  ),
                ),
              
              if (widget.pausedJob != null)
                const SizedBox(width: 8),
              
              // 取消按钮
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('终止流程'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          
          // 提示信息
          if (widget.status == ExecutorStatus.running) ...[
            const SizedBox(height: 8),
            Text(
              '终止指令将在当前节点执行完成后生效',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusTitle() {
    switch (widget.status) {
      case ExecutorStatus.idle:
        return '等待执行';
      case ExecutorStatus.running:
        return '执行中';
      case ExecutorStatus.paused:
        return widget.isWaitingInput ? '等待输入' : '已暂停';
      case ExecutorStatus.completed:
        return '执行完成';
      case ExecutorStatus.failed:
        return '执行失败';
      case ExecutorStatus.cancelled:
        return '已取消';
    }
  }

  IconData _getStatusIcon() {
    switch (widget.status) {
      case ExecutorStatus.idle:
        return Icons.schedule;
      case ExecutorStatus.running:
        return Icons.play_circle;
      case ExecutorStatus.paused:
        return widget.isWaitingInput ? Icons.edit : Icons.pause_circle;
      case ExecutorStatus.completed:
        return Icons.check_circle;
      case ExecutorStatus.failed:
        return Icons.error;
      case ExecutorStatus.cancelled:
        return Icons.cancel;
    }
  }

  Color _getStatusColor() {
    switch (widget.status) {
      case ExecutorStatus.idle:
        return Colors.grey;
      case ExecutorStatus.running:
        return Colors.blue;
      case ExecutorStatus.paused:
        return widget.isWaitingInput ? Colors.blue : Colors.orange;
      case ExecutorStatus.completed:
        return Colors.green;
      case ExecutorStatus.failed:
        return Colors.red;
      case ExecutorStatus.cancelled:
        return Colors.grey;
    }
  }

  String _getStatusMessage() {
    switch (widget.status) {
      case ExecutorStatus.idle:
        return '等待开始';
      case ExecutorStatus.running:
        return '正在执行...';
      case ExecutorStatus.paused:
        return widget.isWaitingInput ? '需要用户输入' : '已暂停';
      case ExecutorStatus.completed:
        return '执行完成';
      case ExecutorStatus.failed:
        return '执行失败';
      case ExecutorStatus.cancelled:
        return '已取消';
    }
  }
}

/// 状态图标
class _StatusIcon extends StatelessWidget {
  final ExecutorStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (status) {
      case ExecutorStatus.running:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        );
      case ExecutorStatus.paused:
        icon = Icons.pause_circle;
        color = Colors.orange;
      case ExecutorStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
      case ExecutorStatus.failed:
        icon = Icons.error;
        color = Colors.red;
      case ExecutorStatus.cancelled:
        icon = Icons.cancel;
        color = Colors.grey;
      case ExecutorStatus.idle:
        icon = Icons.schedule;
        color = Colors.grey;
    }

    return Icon(icon, size: 24, color: color);
  }
}
