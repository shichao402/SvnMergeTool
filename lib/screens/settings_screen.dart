/// 全屏设置界面
///
/// 整合所有设置项，包括：
/// - 预加载设置
/// - 最大重试次数
/// - 其他设置
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config.dart';
import '../services/storage_service.dart';
import '../services/logger_service.dart';
import '../services/svn_auth_clear_service.dart';
import '../services/svn_auth_gate_service.dart';
import '../services/svn_service.dart';
import '../utils/open_directory.dart';
import '../utils/app_banner.dart';

/// 设置界面返回的结果
class SettingsResult {
  final PreloadSettings preloadSettings;
  final int maxRetries;
  final String? mergeValidationScriptPath;

  const SettingsResult({
    required this.preloadSettings,
    required this.maxRetries,
    this.mergeValidationScriptPath,
  });
}

/// 把"正整数 → 文本框文案"的规则统一成一行：值 `<= 0` 时显示空字符串，
/// 否则显示十进制数字。
///
/// `_loadSettings` 在初始化 maxDays / maxCount / stopRevision 三个数字输入框时
/// 用了同一条规则——抽出来既消重又便于测试 0/负数边界。
@visibleForTesting
String formatPositiveIntForField(int value) {
  return value > 0 ? value.toString() : '';
}

/// 把 `DateTime` 渲染成 `yyyy-MM-dd`（截掉 `toIso8601String()` 的时间段）。
///
/// `_pickDate` 在用户确认日期后用同样的方式存入 `_stopDate` / `_stopDateController`。
@visibleForTesting
String formatStopDate(DateTime date) {
  return date.toIso8601String().split('T').first;
}

/// 计算"指定日期截止"日期选择器初次展示时定位到的日期。
///
/// 规则（与原 `_pickDate` 完全一致）：
/// 1. `stopDate` 非空且能 `DateTime.parse` 成功 → 用 parse 出的日期。
/// 2. `stopDate` 为空 / 无法 parse → 回落到 `now - 90 天`。
///
/// 注：`DateTime.tryParse` 对 `'invalid-date'` 之类返回 null；空串也返回 null，
/// 因此第二条覆盖"用户首次打开（stopDate=null）"和"已存的字符串损坏"两种情况。
@visibleForTesting
DateTime resolveStopDatePickerInitialDate({
  required String? stopDate,
  required DateTime now,
}) {
  final fallback = now.subtract(const Duration(days: 90));
  if (stopDate == null) {
    return fallback;
  }
  return DateTime.tryParse(stopDate) ?? fallback;
}

/// 把"设置界面表单输入"翻译成 [SettingsResult]。
///
/// 行为契约（与原 `_save` 完全一致）：
/// - **数字字段**：`maxDays` / `maxCount` / `stopRevision` 的文本经 `trim` 后
///   `int.tryParse`，失败 / 空串 → `0`（与 `PreloadSettings` 中"0 表示不限制"约定一致）。
/// - **maxRetries**：同样 `trim + int.tryParse`，失败 / 空串 → [kDefaultMaxRetries]（默认重试次数，定义在 `models/app_config.dart`）。
///   注意这里默认值是 [kDefaultMaxRetries]，**不是** 0——和上面三个字段不一样，单测会显式覆盖这条。
/// - **stopDate**：`trim` 后若为空则结果为 `null`，否则保留 trim 后的字符串
///   （不再做日期格式校验——保留原行为，由调用方负责确保日期串合法）。
/// - **mergeValidationScriptPath**：空白回落到默认 `Tools/check.py`，路径保存为 `/` 风格相对路径。
/// - 布尔字段 `preloadEnabled` / `stopOnBranchPoint` 直出，不做转换。
///
/// 不修改入参，返回新对象。
@visibleForTesting
SettingsResult parseSettingsFormInputs({
  required String maxDaysText,
  required String maxCountText,
  required String stopRevisionText,
  required String stopDateText,
  required String maxRetriesText,
  required String mergeValidationScriptPathText,
  required bool preloadEnabled,
  required bool stopOnBranchPoint,
}) {
  final maxDays = int.tryParse(maxDaysText.trim()) ?? 0;
  final maxCount = int.tryParse(maxCountText.trim()) ?? 0;
  final stopRevision = int.tryParse(stopRevisionText.trim()) ?? 0;
  final trimmedStopDate = stopDateText.trim();
  final stopDate = trimmedStopDate.isEmpty ? null : trimmedStopDate;
  final maxRetries = int.tryParse(maxRetriesText.trim()) ?? kDefaultMaxRetries;
  final validationScript =
      normalizeMergeValidationScriptPath(mergeValidationScriptPathText);

  return SettingsResult(
    preloadSettings: PreloadSettings(
      enabled: preloadEnabled,
      stopOnBranchPoint: stopOnBranchPoint,
      maxDays: maxDays,
      maxCount: maxCount,
      stopRevision: stopRevision,
      stopDate: stopDate,
    ),
    maxRetries: maxRetries,
    mergeValidationScriptPath: validationScript,
  );
}

/// 「打开本地目录」用的命令描述与解析函数已抽到 `lib/utils/open_directory.dart`，
/// 跨库共享（settings_screen 打开日志目录、main_screen_v3 打开工作副本目录）。

/// 比较"用户当前编辑的表单结果"与"打开设置页时传入的基线"，判断是否有未保存修改。
///
/// 真 bug 场景：用户在设置页改了 5 个数字 / 1 个日期 / 2 个 toggle，点 AppBar
/// 左上 X 按钮，原 `Navigator.of(context).pop()` 直连，所有未保存输入静默丢失。
/// 现用此函数做 dirty 检测 → 弹"丢弃修改？"确认 dialog。
///
/// 行为契约：
/// - PreloadSettings 7 字段（enabled / stopOnBranchPoint / maxDays / maxCount /
///   stopRevision / stopDate / maxRetries）任一与基线不等 → 返回 `true`。
/// - PreloadSettings 没有 `operator ==`，所以**逐字段对比**——不能用引用相等。
/// - stopDate 是 nullable String，用 `==` 直接比较即可（Dart String == 是值相等）。
/// - 数字字段对比的是已经 parse 过的整数（由 `parseSettingsFormInputs` 处理），
///   所以 "0" 与 "" 视为同一个 0、不算 dirty——和 `_save` 的解释保持一致。
@visibleForTesting
bool isSettingsFormDirty({
  required SettingsResult current,
  required PreloadSettings baselinePreload,
  required int baselineMaxRetries,
  required String? baselineMergeValidationScriptPath,
}) {
  if (current.maxRetries != baselineMaxRetries) return true;
  if (normalizeMergeValidationScriptPath(current.mergeValidationScriptPath) !=
      normalizeMergeValidationScriptPath(baselineMergeValidationScriptPath)) {
    return true;
  }
  final p = current.preloadSettings;
  if (p.enabled != baselinePreload.enabled) return true;
  if (p.stopOnBranchPoint != baselinePreload.stopOnBranchPoint) return true;
  if (p.maxDays != baselinePreload.maxDays) return true;
  if (p.maxCount != baselinePreload.maxCount) return true;
  if (p.stopRevision != baselinePreload.stopRevision) return true;
  if (p.stopDate != baselinePreload.stopDate) return true;
  return false;
}

class SettingsScreen extends StatefulWidget {
  /// 当前的预加载设置
  final PreloadSettings currentPreloadSettings;

  /// 当前的最大重试次数
  final int currentMaxRetries;

  /// 当前的合并校验脚本路径
  final String? currentMergeValidationScriptPath;

  /// 当前源 URL（用于鉴权引导，可选）
  final String? sourceUrl;

  /// 当前目标 SVN URL（精简模式，可选）
  final String? targetUrl;

  const SettingsScreen({
    super.key,
    required this.currentPreloadSettings,
    required this.currentMaxRetries,
    this.currentMergeValidationScriptPath,
    this.sourceUrl,
    this.targetUrl,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();

  /// 显示设置界面并返回新的设置（如果用户保存了）
  static Future<SettingsResult?> show(
    BuildContext context, {
    required PreloadSettings currentPreloadSettings,
    required int currentMaxRetries,
    String? currentMergeValidationScriptPath,
    String? sourceUrl,
    String? targetUrl,
  }) async {
    return Navigator.of(context).push<SettingsResult>(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          currentPreloadSettings: currentPreloadSettings,
          currentMaxRetries: currentMaxRetries,
          currentMergeValidationScriptPath: currentMergeValidationScriptPath,
          sourceUrl: sourceUrl,
          targetUrl: targetUrl,
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
  String? _mergeValidationScriptPath;

  // 控制器
  final _maxDaysController = TextEditingController();
  final _maxCountController = TextEditingController();
  final _stopRevisionController = TextEditingController();
  final _stopDateController = TextEditingController();
  final _maxRetriesController = TextEditingController();
  final _mergeValidationScriptPathController = TextEditingController();

  SvnAuthUiState? _authUiState;
  bool _authStatusLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshAuthStatus();
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

    _maxDaysController.text = formatPositiveIntForField(_maxDays);
    _maxCountController.text = formatPositiveIntForField(_maxCount);
    _stopRevisionController.text = formatPositiveIntForField(_stopRevision);
    _stopDateController.text = _stopDate ?? '';

    // 加载合并设置
    _maxRetries = widget.currentMaxRetries;
    _maxRetriesController.text = _maxRetries.toString();
    _mergeValidationScriptPath = normalizeMergeValidationScriptPath(
      widget.currentMergeValidationScriptPath,
    );
    _mergeValidationScriptPathController.text = _mergeValidationScriptPath!;
  }

  /// **R129 widget lifecycle dispose 维度审计 — 档 3 stateful + owned Disposable
  /// 同框架对照 `main_screen_v3.dart:_MainScreenV3State`**：
  ///
  /// 6 个 TextEditingController declaration → 6 个 dispose 调用 → super.dispose()
  /// 末位。同 main_screen_v3 共享跨档不变量 I1（super 末位）/ I2（每 controller
  /// 先释放）/ I3（1:1 owned-vs-disposed parity）/ I4（同序释放，无内部顺序约束）。
  /// 详细三档框架说明见 `main_screen_v3.dart:dispose` 处 doc。
  ///
  /// **同形锁（R59 helper-vs-inline 在 widget lifecycle 维度的扩展）**：本类与
  /// `_MainScreenV3State.dispose` 形态完全同形——controllers 同序逐个 dispose
  /// + super.dispose 末位。如未来引入 ScrollController / FocusNode 等额外资源，
  /// 两类必须**同时改**才不破同形（双类共享同模板）。
  @override
  void dispose() {
    _maxDaysController.dispose();
    _maxCountController.dispose();
    _stopRevisionController.dispose();
    _stopDateController.dispose();
    _maxRetriesController.dispose();
    _mergeValidationScriptPathController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // 把表单文本翻译成结构化结果（纯函数）
    final result = parseSettingsFormInputs(
      maxDaysText: _maxDaysController.text,
      maxCountText: _maxCountController.text,
      stopRevisionText: _stopRevisionController.text,
      stopDateText: _stopDateController.text,
      maxRetriesText: _maxRetriesController.text,
      mergeValidationScriptPathText: _mergeValidationScriptPathController.text,
      preloadEnabled: _preloadEnabled,
      stopOnBranchPoint: _stopOnBranchPoint,
    );
    final newPreloadSettings = result.preloadSettings;
    final maxRetries = result.maxRetries;
    final validationScriptPath = result.mergeValidationScriptPath;

    // 保存到持久化存储
    try {
      final storageService = StorageService();
      // 直接复用 PreloadSettings.toJson()——与 SharedPreferences 扁平化存储约定的
      // 6 个 snake_case 键完全一致（已比对 app_config.g.dart 中的 _$PreloadSettingsToJson）。
      // 之前手动列举每个字段，每加一个新字段都要在 settings_screen 和 storage_service 两边改。
      await storageService.savePreloadSettings(newPreloadSettings.toJson());
      await storageService.saveDefaultMaxRetries(maxRetries);
      await storageService.saveMergeValidationScriptPath(validationScriptPath);
      AppLogger.ui.info('设置已保存');
    } catch (e, stackTrace) {
      // 真 bug 修复：原 catch 仅写日志却仍 pop(result)，UI 显示"保存成功"实际未持久化，
      // 下次启动配置丢失（磁盘满 / 权限拒绝 / SharedPreferences 写入失败时触发）。
      // 现改为：弹 SnackBar 显示具体错误 + 提前 return（不 pop），让用户感知失败可重试或手动取消。
      AppLogger.ui.error('保存设置失败', e, stackTrace);
      if (mounted) {
        AppBanner.showContext(
          context,
          message: '保存设置失败：$e',
          kind: AppBannerKind.error,
        );
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  /// 用户点击 AppBar 左上 X 关闭按钮时，先做 dirty 检测，dirty 时弹确认 dialog。
  ///
  /// 真 bug 修复：原 X 按钮 `onPressed: () => Navigator.of(context).pop()` 直连，
  /// 用户编辑后误点 X，所有未保存输入静默丢失。现改为：dirty → 弹"丢弃修改？"
  /// 确认 dialog，用户选"丢弃"才 pop，选"取消"留在设置页继续编辑或保存。
  Future<void> _onClosePressed() async {
    final current = parseSettingsFormInputs(
      maxDaysText: _maxDaysController.text,
      maxCountText: _maxCountController.text,
      stopRevisionText: _stopRevisionController.text,
      stopDateText: _stopDateController.text,
      maxRetriesText: _maxRetriesController.text,
      mergeValidationScriptPathText: _mergeValidationScriptPathController.text,
      preloadEnabled: _preloadEnabled,
      stopOnBranchPoint: _stopOnBranchPoint,
    );
    final dirty = isSettingsFormDirty(
      current: current,
      baselinePreload: widget.currentPreloadSettings,
      baselineMaxRetries: widget.currentMaxRetries,
      baselineMergeValidationScriptPath:
          widget.currentMergeValidationScriptPath,
    );
    if (!dirty) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('丢弃未保存的修改？'),
        content: const Text('设置页有未保存的修改，关闭后将丢失。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('丢弃'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = resolveStopDatePickerInitialDate(
      stopDate: _stopDate,
      now: now,
    );

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
      if (!mounted) return;
      setState(() {
        _stopDate = formatStopDate(picked);
        _stopDateController.text = _stopDate!;
      });
    }
  }

  Future<void> _refreshAuthStatus() async {
    setState(() => _authStatusLoading = true);
    try {
      final state = await SvnAuthGateService().resolveAuthUiState(
        sourceUrl: widget.sourceUrl,
        targetUrl: widget.targetUrl,
      );
      if (!mounted) return;
      setState(() {
        _authUiState = state;
        _authStatusLoading = false;
      });
    } catch (e, stackTrace) {
      AppLogger.credential.error('刷新 SVN 鉴权状态失败', e, stackTrace);
      if (!mounted) return;
      setState(() {
        _authUiState = SvnAuthUiState.needsAuth;
        _authStatusLoading = false;
      });
    }
  }

  Future<void> _confirmRemoveSvnAuth() async {
    final authDirPath = resolveSubversionAuthDir(
      operatingSystem: Platform.operatingSystem,
      homeDir: Platform.environment['HOME'],
      appDataDir: Platform.environment['APPDATA'],
      svnConfigDirEnv: Platform.environment['SVN_CONFIG_DIR'],
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除 SVN 鉴权信息？'),
        content: SingleChildScrollView(
          child: Text(
            buildSvnAuthClearDialogText(
              operatingSystem: Platform.operatingSystem,
              authDirPath: authDirPath,
              svnConfigDirEnv: Platform.environment['SVN_CONFIG_DIR'],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final result = await SvnAuthGateService().removeAuth();
      AppLogger.credential.info(
        '用户从设置页移除 SVN 鉴权缓存: ${result.authDirPath}',
      );
      if (!mounted) return;
      await _refreshAuthStatus();
      if (!mounted) return;
      AppBanner.showContext(
        context,
        message: formatSvnAuthClearSnackBar(result),
      );
    } catch (e, stackTrace) {
      AppLogger.credential.error('移除 SVN 鉴权缓存失败', e, stackTrace);
      if (!mounted) return;
      AppBanner.showContext(
        context,
        message: '移除 SVN 鉴权信息失败：$e',
        kind: AppBannerKind.error,
      );
    }
  }

  Future<void> _showAddSvnAuthGuide() async {
    final urls = collectAuthGuideUrls(
      sourceUrl: widget.sourceUrl,
      targetUrl: widget.targetUrl,
    );
    final svnPath = SvnService().svnExecutablePath;
    final commands = urls
        .map(
          (url) => formatSvnAuthTerminalCommand(
            svnExecutable: svnPath,
            url: url,
          ),
        )
        .toList();

    final dialogResult = await showDialog<SvnAddAuthDialogResult>(
      context: context,
      builder: (ctx) => SvnAddAuthDialog(
        operatingSystem: Platform.operatingSystem,
        urls: urls,
        terminalCommands: commands,
      ),
    );
    if (dialogResult == null ||
        dialogResult.choice == SvnAddAuthDialogChoice.cancelled ||
        !mounted) {
      return;
    }

    try {
      final AddAuthResult result;
      if (dialogResult.choice == SvnAddAuthDialogChoice.tryInteractive) {
        result = await SvnAuthGateService().addAuthForConfiguredUrls(
          sourceUrl: widget.sourceUrl,
          targetUrl: widget.targetUrl,
        );
      } else {
        result =
            await SvnAuthGateService().addAuthForConfiguredUrlsWithCredentials(
          sourceUrl: widget.sourceUrl,
          targetUrl: widget.targetUrl,
          username: dialogResult.username,
          password: dialogResult.password,
        );
      }
      if (!mounted) return;
      await _refreshAuthStatus();
      if (!mounted) return;
      if (result.success) {
        AppBanner.showContext(
          context,
          message: 'SVN 鉴权已完成，可返回主界面同步日志',
          kind: AppBannerKind.success,
        );
      } else {
        AppBanner.showContext(
          context,
          message: result.message ?? '鉴权未完成',
          kind: AppBannerKind.warning,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.credential.error('添加 SVN 鉴权失败', e, stackTrace);
      if (!mounted) return;
      AppBanner.showContext(
        context,
        message: '添加鉴权失败：$e',
        kind: AppBannerKind.error,
      );
    }
  }

  Widget _buildSvnAuthListTile() {
    if (_authStatusLoading) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.vpn_key),
        title: Text('SVN 鉴权'),
        subtitle: Text('正在检测鉴权状态…'),
        trailing: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final hasAuth = _authUiState == SvnAuthUiState.hasAuth;
    if (hasAuth) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.vpn_key_off),
        title: const Text('移除鉴权'),
        subtitle: const Text(
          '清除 Subversion auth 缓存；不影响本应用已缓存的日志列表',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _confirmRemoveSvnAuth,
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.vpn_key),
      title: const Text('添加鉴权信息'),
      subtitle: const Text(
        '通过 SVN 客户端完成鉴权；本应用不保存密码',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _showAddSvnAuthGuide,
    );
  }

  Future<void> _openLogDirectory() async {
    try {
      final logDir = await logger.getLogDirectory();
      final dir = Directory(logDir);

      // 确保目录存在
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 使用系统命令打开目录
      final command = resolveOpenDirectoryCommand(
        platform: Platform.operatingSystem,
        path: logDir,
      );
      if (command != null) {
        await Process.run(command.executable, command.args);
      } else {
        if (mounted) {
          AppBanner.showContext(
            context,
            message: '不支持的平台，日志目录: $logDir',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppBanner.showContext(
          context,
          message: '打开日志目录失败: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _onClosePressed,
          tooltip: '取消',
        ),
        actions: [
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存'),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_tree),
                      title: const Text('执行步骤'),
                      subtitle: const Text(
                        '执行流程：准备 -> 更新 -> 合并 -> 校验 -> 提交',
                      ),
                    ),
                    const Divider(),
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            suffixText: '次',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('合并校验脚本'),
                      subtitle: const Text(
                        '相对目标工作副本的 / 风格路径。默认 Tools/check.py；支持 .sh / .bat / .py。',
                      ),
                    ),
                    TextField(
                      controller: _mergeValidationScriptPathController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: kDefaultMergeValidationScriptPath,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 其他设置组
            _buildSectionTitle('其他', Icons.settings),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_open),
                      title: const Text('打开日志目录'),
                      subtitle: const Text('查看程序运行日志文件'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openLogDirectory,
                    ),
                    const Divider(),
                    _buildSvnAuthListTile(),
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            suffixText: '天',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            suffixText: '条',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
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
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            prefixText: 'r',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
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
                          Icon(Icons.info_outline,
                              color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '预加载停止不影响日志浏览。您可以随时在主界面点击"同步最新"或"加载更多"继续获取日志。',
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

/// 设置页「添加鉴权」对话框：推荐自行配置 + 可选用户名密码路径。
class SvnAddAuthDialog extends StatefulWidget {
  final String operatingSystem;
  final List<String> urls;
  final List<String> terminalCommands;

  const SvnAddAuthDialog({
    super.key,
    required this.operatingSystem,
    required this.urls,
    required this.terminalCommands,
  });

  @override
  State<SvnAddAuthDialog> createState() => _SvnAddAuthDialogState();
}

class _SvnAddAuthDialogState extends State<SvnAddAuthDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _credentialsError;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _copyCommands(BuildContext ctx) {
    Clipboard.setData(ClipboardData(text: widget.terminalCommands.join('\n')));
    AppBanner.showContext(ctx, message: '已复制终端命令');
  }

  void _submitCredentials() {
    final username = _usernameController.text;
    final password = _passwordController.text;
    final validationError = validateSvnAuthCredentialsInput(
      username: username,
      password: password,
    );
    if (validationError != null) {
      setState(() => _credentialsError = validationError);
      return;
    }
    Navigator.of(context).pop(
      SvnAddAuthDialogResult(
        choice: SvnAddAuthDialogChoice.useCredentials,
        username: username.trim(),
        password: password,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUrls = widget.urls.isNotEmpty;
    return AlertDialog(
      title: const Text('添加 SVN 鉴权信息'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              buildSvnAuthAddDialogText(
                operatingSystem: widget.operatingSystem,
                urls: widget.urls,
                terminalCommands: widget.terminalCommands,
              ),
            ),
            if (hasUrls) ...[
              const SizedBox(height: 16),
              const Divider(),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('使用用户名和密码登录'),
                subtitle: Text(
                  buildSvnAuthCredentialsHintText(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                initiallyExpanded: false,
                onExpansionChanged: (expanded) {
                  if (!expanded) {
                    setState(() => _credentialsError = null);
                  }
                },
                children: [
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _submitCredentials(),
                  ),
                  if (_credentialsError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _credentialsError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _submitCredentials,
                      child: const Text('使用账号密码登录'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.terminalCommands.isNotEmpty)
          TextButton(
            onPressed: () => _copyCommands(context),
            child: const Text('复制命令'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const SvnAddAuthDialogResult(
              choice: SvnAddAuthDialogChoice.cancelled,
            ),
          ),
          child: const Text('取消'),
        ),
        if (hasUrls)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              const SvnAddAuthDialogResult(
                choice: SvnAddAuthDialogChoice.tryInteractive,
              ),
            ),
            child: const Text('尝试在此完成鉴权'),
          ),
      ],
    );
  }
}
