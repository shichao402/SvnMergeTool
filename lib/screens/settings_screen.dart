/// 全屏设置界面
///
/// 整合所有设置项，包括：
/// - 预加载设置
/// - 最大重试次数
/// - 其他设置

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';

/// 设置界面返回的结果
class SettingsResult {
  final PreloadSettings preloadSettings;
  final int maxRetries;

  const SettingsResult({
    required this.preloadSettings,
    required this.maxRetries,
  });
}

class SettingsScreen extends StatefulWidget {
  /// 当前的预加载设置
  final PreloadSettings currentPreloadSettings;
  
  /// 当前的最大重试次数
  final int currentMaxRetries;

  const SettingsScreen({
    super.key,
    required this.currentPreloadSettings,
    required this.currentMaxRetries,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();

  /// 显示设置界面并返回新的设置（如果用户保存了）
  static Future<SettingsResult?> show(
    BuildContext context, {
    required PreloadSettings currentPreloadSettings,
    required int currentMaxRetries,
  }) async {
    return Navigator.of(context).push<SettingsResult>(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          currentPreloadSettings: currentPreloadSettings,
          currentMaxRetries: currentMaxRetries,
        ),
      ),
    );
  }
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 预加载设置
  late bool _preloadEnabled;
  late bool _stopOnBranchPoint;
  late int _maxDays;
  late int _maxCount;
  late int _stopRevision;
  String? _stopDate;

  // 合并设置
  late int _maxRetries;

  // 控制器
  final _maxDaysController = TextEditingController();
  final _maxCountController = TextEditingController();
  final _stopRevisionController = TextEditingController();
  final _stopDateController = TextEditingController();
  final _maxRetriesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    // 加载预加载设置
    final preloadSettings = widget.currentPreloadSettings;
    _preloadEnabled = preloadSettings.enabled;
    _stopOnBranchPoint = preloadSettings.stopOnBranchPoint;
    _maxDays = preloadSettings.maxDays;
    _maxCount = preloadSettings.maxCount;
    _stopRevision = preloadSettings.stopRevision;
    _stopDate = preloadSettings.stopDate;

    _maxDaysController.text = _maxDays > 0 ? _maxDays.toString() : '';
    _maxCountController.text = _maxCount > 0 ? _maxCount.toString() : '';
    _stopRevisionController.text = _stopRevision > 0 ? _stopRevision.toString() : '';
    _stopDateController.text = _stopDate ?? '';

    // 加载合并设置
    _maxRetries = widget.currentMaxRetries;
    _maxRetriesController.text = _maxRetries.toString();
  }

  @override
  void dispose() {
    _maxDaysController.dispose();
    _maxCountController.dispose();
    _stopRevisionController.dispose();
    _stopDateController.dispose();
    _maxRetriesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // 解析预加载设置
    final maxDays = int.tryParse(_maxDaysController.text.trim()) ?? 0;
    final maxCount = int.tryParse(_maxCountController.text.trim()) ?? 0;
    final stopRevision = int.tryParse(_stopRevisionController.text.trim()) ?? 0;
    final stopDate = _stopDateController.text.trim().isEmpty
        ? null
        : _stopDateController.text.trim();

    // 解析合并设置
    final maxRetries = int.tryParse(_maxRetriesController.text.trim()) ?? 5;

    // 创建新的预加载设置
    final newPreloadSettings = PreloadSettings(
      enabled: _preloadEnabled,
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
        'enabled': newPreloadSettings.enabled,
        'stop_on_branch_point': newPreloadSettings.stopOnBranchPoint,
        'max_days': newPreloadSettings.maxDays,
        'max_count': newPreloadSettings.maxCount,
        'stop_revision': newPreloadSettings.stopRevision,
        'stop_date': newPreloadSettings.stopDate,
      });
      await storageService.saveDefaultMaxRetries(maxRetries);
      AppLogger.ui.info('设置已保存');
    } catch (e, stackTrace) {
      AppLogger.ui.error('保存设置失败', e, stackTrace);
    }

    if (mounted) {
      Navigator.of(context).pop(SettingsResult(
        preloadSettings: newPreloadSettings,
        maxRetries: maxRetries,
      ));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '取消',
        ),
        actions: [
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 合并设置组
            _buildSectionTitle('合并设置', Icons.merge_type),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 最大重试次数
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('最大重试次数'),
                      subtitle: const Text('合并失败时的最大重试次数（out-of-date 错误）'),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _maxRetriesController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            suffixText: '次',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 预加载设置组
            _buildSectionTitle('预加载设置', Icons.download),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 启用开关
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用后台预加载'),
                      subtitle: const Text('应用启动后自动在后台加载更多日志'),
                      value: _preloadEnabled,
                      onChanged: (value) {
                        setState(() {
                          _preloadEnabled = value;
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
                      contentPadding: EdgeInsets.zero,
                      title: const Text('到达分支点时停止'),
                      subtitle: const Text('加载到分支创建点即停止'),
                      value: _stopOnBranchPoint,
                      onChanged: _preloadEnabled
                          ? (value) {
                              setState(() {
                                _stopOnBranchPoint = value ?? true;
                              });
                            }
                          : null,
                    ),

                    // 天数限制
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('天数限制'),
                      subtitle: const Text('加载最近 N 天的日志（0 表示不限制）'),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _maxDaysController,
                          enabled: _preloadEnabled,
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
                      contentPadding: EdgeInsets.zero,
                      title: const Text('条数限制'),
                      subtitle: const Text('最多加载 N 条日志（0 表示不限制）'),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _maxCountController,
                          enabled: _preloadEnabled,
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
                      contentPadding: EdgeInsets.zero,
                      title: const Text('指定版本截止'),
                      subtitle: const Text('加载到指定 revision 即停止（0 表示不限制）'),
                      trailing: SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _stopRevisionController,
                          enabled: _preloadEnabled,
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
                      contentPadding: EdgeInsets.zero,
                      title: const Text('指定日期截止'),
                      subtitle: const Text('加载到指定日期即停止'),
                      trailing: SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _stopDateController,
                          enabled: _preloadEnabled,
                          readOnly: true,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            hintText: '点击选择',
                            suffixIcon: _stopDateController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: _preloadEnabled
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
                          onTap: _preloadEnabled ? _pickDate : null,
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
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
