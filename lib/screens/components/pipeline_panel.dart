/// Pipeline 执行面板
///
/// 显示 Pipeline 执行状态、流程图和暂停任务信息

import 'package:flutter/material.dart';
import 'package:vyuh_node_flow/vyuh_node_flow.dart';
import '../../pipeline/pipeline.dart';
import '../../models/merge_job.dart';

/// Pipeline 执行面板
class PipelinePanel extends StatelessWidget {
  final GraphExecutorStatus status;
  final Node<StageData>? currentNode;
  final NodeFlowController<StageData>? controller;
  final MergeJob? pausedJob;
  final bool isWaitingInput;
  final VoidCallback onResume;
  final VoidCallback onSkip;
  final VoidCallback onCancel;
  final void Function(String value)? onSubmitInput;

  const PipelinePanel({
    super.key,
    required this.status,
    this.currentNode,
    this.controller,
    required this.pausedJob,
    required this.isWaitingInput,
    required this.onResume,
    required this.onSkip,
    required this.onCancel,
    this.onSubmitInput,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态标题和控制按钮
          _buildHeader(),
          const SizedBox(height: 16),
          // 流程图
          if (controller != null)
            Expanded(
              child: GraphFlowChart(
                controller: controller!,
                currentNodeId: currentNode?.id,
              ),
            ),
          // 暂停信息和操作
          if (pausedJob != null) ...[
            const SizedBox(height: 16),
            _PausedJobInfo(
              job: pausedJob!,
              isWaitingInput: isWaitingInput,
              onResume: onResume,
              onSkip: onSkip,
              onCancel: onCancel,
              onSubmitInput: onSubmitInput,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _StatusIcon(status: status),
        const SizedBox(width: 12),
        Text(
          currentNode?.data?.name ?? '任务执行中',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        if (pausedJob != null)
          Text(
            '${pausedJob!.completedIndex}/${pausedJob!.revisions.length}',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        // 运行时显示取消按钮
        if (status == GraphExecutorStatus.running && pausedJob == null) ...[
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('停止'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ],
    );
  }
}

/// 状态图标
class _StatusIcon extends StatelessWidget {
  final GraphExecutorStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (status) {
      case GraphExecutorStatus.running:
        icon = Icons.play_circle;
        color = Colors.blue;
        break;
      case GraphExecutorStatus.paused:
        icon = Icons.pause_circle;
        color = Colors.orange;
        break;
      case GraphExecutorStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case GraphExecutorStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case GraphExecutorStatus.cancelled:
        icon = Icons.cancel;
        color = Colors.grey;
        break;
      case GraphExecutorStatus.idle:
        icon = Icons.schedule;
        color = Colors.grey;
        break;
    }

    return Icon(icon, size: 28, color: color);
  }
}

/// 暂停任务信息
class _PausedJobInfo extends StatefulWidget {
  final MergeJob job;
  final bool isWaitingInput;
  final VoidCallback onResume;
  final VoidCallback onSkip;
  final VoidCallback onCancel;
  final void Function(String value)? onSubmitInput;

  const _PausedJobInfo({
    required this.job,
    required this.isWaitingInput,
    required this.onResume,
    required this.onSkip,
    required this.onCancel,
    this.onSubmitInput,
  });

  @override
  State<_PausedJobInfo> createState() => _PausedJobInfoState();
}

class _PausedJobInfoState extends State<_PausedJobInfo> {
  final _inputController = TextEditingController();
  
  /// 判断是否是"等待输入"类型的暂停
  bool get _isWaitingInputPause => widget.job.pauseReason.startsWith('等待输入');
  
  /// 提取输入字段名称
  String get _inputFieldName {
    final reason = widget.job.pauseReason;
    if (reason.startsWith('等待输入: ')) {
      return reason.substring('等待输入: '.length);
    }
    return '输入';
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _submitInput() {
    final value = _inputController.text.trim();
    if (value.isEmpty) return;
    widget.onSubmitInput?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isWaitingInputPause ? Colors.blue.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isWaitingInputPause ? Colors.blue.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isWaitingInputPause ? Icons.edit_note : Icons.warning_amber,
                color: _isWaitingInputPause ? Colors.blue.shade700 : Colors.orange.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isWaitingInputPause 
                      ? '需要输入: $_inputFieldName'
                      : '任务暂停: ${widget.job.pauseReason}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isWaitingInputPause ? Colors.blue.shade900 : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '进度: ${widget.job.completedIndex}/${widget.job.revisions.length} | 当前: r${widget.job.currentRevision}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          // 根据暂停类型显示不同的操作区域
          if (_isWaitingInputPause && widget.onSubmitInput != null)
            _buildInputSection()
          else
            _buildActionButtons(),
        ],
      ),
    );
  }

  /// 构建输入区域
  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '请输入 $_inputFieldName',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _submitInput(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _submitInput,
              child: const Text('提交'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.onSkip,
              icon: const Icon(Icons.skip_next, size: 18),
              label: Text('跳过 r${widget.job.currentRevision}'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.cancel, size: 18),
              label: const Text('取消任务'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      children: [
        if (!widget.isWaitingInput)
          ElevatedButton.icon(
            onPressed: widget.onResume,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('继续'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        OutlinedButton.icon(
          onPressed: widget.onSkip,
          icon: const Icon(Icons.skip_next, size: 18),
          label: Text('跳过 r${widget.job.currentRevision}'),
        ),
        OutlinedButton.icon(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.cancel, size: 18),
          label: const Text('取消'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }
}
