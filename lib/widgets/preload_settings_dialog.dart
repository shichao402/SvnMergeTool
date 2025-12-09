/// 预加载设置对话框
///
/// 用于配置后台预加载的各项参数

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';

class PreloadSettingsDialog extends StatefulWidget {
  /// 当前的预加载设置
  final PreloadSettings currentSettings;

  const PreloadSettingsDialog({
    super.key,
    required this.currentSettings,
  });

  @override
  State<PreloadSettingsDialog> createState() => _PreloadSettingsDialogState();

  /// 显示对话框并返回新的设置（如果用户保存了）
  static Future<PreloadSettings?> show(
    BuildContext context,
    PreloadSettings currentSettings,
  ) async {
    return showDialog<PreloadSettings>(
      context: context,
      builder: (context) => PreloadSettingsDialog(
        currentSettings: currentSettings,
      ),
    );
  }
}

class _PreloadSettingsDialogState extends State<PreloadSettingsDialog> {
  late bool _enabled;
  late bool _stopOnBranchPoint;
  late int _maxDays;
  late int _maxCount;
  late int _stopRevision;
  String? _stopDate;

  final _maxDaysController = TextEditingController();
  final _maxCountController = TextEditingController();
  final _stopRevisionController = TextEditingController();
  final _stopDateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    final settings = widget.currentSettings;
    _enabled = settings.enabled;
    _stopOnBranchPoint = settings.stopOnBranchPoint;
    _maxDays = settings.maxDays;
    _maxCount = settings.maxCount;
    _stopRevision = settings.stopRevision;
    _stopDate = settings.stopDate;

    _maxDaysController.text = _maxDays > 0 ? _maxDays.toString() : '';
    _maxCountController.text = _maxCount > 0 ? _maxCount.toString() : '';
    _stopRevisionController.text = _stopRevision > 0 ? _stopRevision.toString() : '';
    _stopDateController.text = _stopDate ?? '';
  }

  @override
  void dispose() {
    _maxDaysController.dispose();
    _maxCountController.dispose();
    _stopRevisionController.dispose();
    _stopDateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // 解析输入值
    final maxDays = int.tryParse(_maxDaysController.text.trim()) ?? 0;
    final maxCount = int.tryParse(_maxCountController.text.trim()) ?? 0;
    final stopRevision = int.tryParse(_stopRevisionController.text.trim()) ?? 0;
    final stopDate = _stopDateController.text.trim().isEmpty
        ? null
        : _stopDateController.text.trim();

    // 创建新的设置
    final newSettings = PreloadSettings(
      enabled: _enabled,
      stopOnBranchPoint: _stopOnBranchPoint,
      maxDays: maxDays,
      maxCount: maxCount,
      stopRevision: stopRevision,
      stopDate: stopDate,
    );

    // 保存到持久化存储
    try {
      final storageService = StorageService();
      await storageService.savePreloadSettings({
        'enabled': newSettings.enabled,
        'stop_on_branch_point': newSettings.stopOnBranchPoint,
        'max_days': newSettings.maxDays,
        'max_count': newSettings.maxCount,
        'stop_revision': newSettings.stopRevision,
        'stop_date': newSettings.stopDate,
      });
      AppLogger.ui.info('预加载设置已保存');
    } catch (e, stackTrace) {
      AppLogger.ui.error('保存预加载设置失败', e, stackTrace);
    }

    if (mounted) {
      Navigator.of(context).pop(newSettings);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _stopDate != null
        ? DateTime.tryParse(_stopDate!) ?? now.subtract(const Duration(days: 90))
        : now.subtract(const Duration(days: 90));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: '选择截止日期',
      cancelText: '取消',
      confirmText: '确定',
    );

    if (picked != null) {
      setState(() {
        _stopDate = picked.toIso8601String().split('T').first;
        _stopDateController.text = _stopDate!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          const Text('预加载设置'),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 启用开关
              SwitchListTile(
                title: const Text('启用后台预加载'),
                subtitle: const Text('应用启动后自动在后台加载更多日志'),
                value: _enabled,
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
              const Divider(),

              // 停止条件标题
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '停止条件（满足任一条件即停止预加载）',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),

              // 到达分支点
              CheckboxListTile(
                title: const Text('到达分支点时停止'),
                subtitle: const Text('加载到分支创建点即停止'),
                value: _stopOnBranchPoint,
                onChanged: _enabled
                    ? (value) {
                        setState(() {
                          _stopOnBranchPoint = value ?? true;
                        });
                      }
                    : null,
              ),

              // 天数限制
              ListTile(
                title: const Text('天数限制'),
                subtitle: const Text('加载最近 N 天的日志（0 表示不限制）'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _maxDaysController,
                    enabled: _enabled,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      suffixText: '天',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ),

              // 条数限制
              ListTile(
                title: const Text('条数限制'),
                subtitle: const Text('最多加载 N 条日志（0 表示不限制）'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _maxCountController,
                    enabled: _enabled,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      suffixText: '条',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ),

              // 指定版本
              ListTile(
                title: const Text('指定版本截止'),
                subtitle: const Text('加载到指定 revision 即停止（0 表示不限制）'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _stopRevisionController,
                    enabled: _enabled,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      prefixText: 'r',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ),

              // 指定日期
              ListTile(
                title: const Text('指定日期截止'),
                subtitle: const Text('加载到指定日期即停止'),
                trailing: SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _stopDateController,
                    enabled: _enabled,
                    readOnly: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      hintText: '点击选择',
                      suffixIcon: _stopDateController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: _enabled
                                  ? () {
                                      setState(() {
                                        _stopDate = null;
                                        _stopDateController.clear();
                                      });
                                    }
                                  : null,
                            )
                          : null,
                    ),
                    onTap: _enabled ? _pickDate : null,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 说明
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '预加载停止不影响手动翻页。您可以随时点击"加载全部"按钮加载更多日志。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
}
