/// SVN 鉴权门禁服务（单点实现）。
///
/// 本应用不存储 SVN 用户名/密码；鉴权完全依赖 Subversion 客户端及其
/// 系统凭据存储（`~/.subversion/auth/` 等，macOS 部分构建还会写入钥匙串）。
///
/// 职责：
/// - 远端 URL 操作前探测鉴权是否可用（`svn info`，默认 `--non-interactive`）
/// - 引导用户通过 SVN 客户端完成交互式鉴权（不加 `--non-interactive`）
/// - 移除鉴权（委托 [SvnAuthClearService]）
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'logger_service.dart';
import 'svn_auth_clear_service.dart';
import 'svn_auth_exceptions.dart';
import 'svn_service.dart';

/// 鉴权探针结果状态。
enum AuthProbeStatus {
  /// 可访问（已缓存凭据或匿名可读）。
  ok,

  /// 需要用户提供凭据。
  needsAuth,

  /// 其它错误（网络、URL 无效等）。
  error,
}

/// 单次 `svn info` 探针结果。
class AuthProbeResult {
  final String url;
  final AuthProbeStatus status;
  final String? message;

  const AuthProbeResult({
    required this.url,
    required this.status,
    this.message,
  });
}

/// 设置页鉴权按钮应展示的状态。
enum SvnAuthUiState {
  hasAuth,
  needsAuth,
}

/// 交互式添加鉴权结果。
class AddAuthResult {
  final bool success;
  final String? message;

  const AddAuthResult({required this.success, this.message});
}

/// 根据 `svn info` 探针的退出码与输出分类鉴权状态。
@visibleForTesting
AuthProbeStatus classifyAuthProbe({
  required int exitCode,
  required String output,
}) {
  if (exitCode == 0) {
    return AuthProbeStatus.ok;
  }
  if (svnOutputNeedsAuth(output)) {
    return AuthProbeStatus.needsAuth;
  }
  return AuthProbeStatus.error;
}

/// 收集设置页用于鉴权引导的 URL 列表（去重、去空白）。
@visibleForTesting
List<String> collectAuthGuideUrls({
  String? sourceUrl,
  String? targetUrl,
}) {
  final urls = <String>[];
  void add(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return;
    }
    if (!urls.contains(trimmed)) {
      urls.add(trimmed);
    }
  }

  add(sourceUrl);
  if (targetUrl != null && isSvnRepositoryUrl(targetUrl.trim())) {
    add(targetUrl);
  }
  return urls;
}

/// 生成终端鉴权命令（供用户复制到 Terminal / CMD）。
@visibleForTesting
String formatSvnAuthTerminalCommand({
  required String svnExecutable,
  required String url,
}) {
  final exe = svnExecutable.trim().isEmpty ? 'svn' : svnExecutable.trim();
  return '$exe info $url';
}

/// 设置页「添加鉴权」推荐路径说明正文（默认展示）。
@visibleForTesting
String buildSvnAuthAddDialogText({
  required String operatingSystem,
  required List<String> urls,
  required List<String> terminalCommands,
}) {
  final buffer = StringBuffer(
    '【推荐】自行配置鉴权\n'
    '本应用不保存 SVN 密码。请通过 Subversion 客户端完成鉴权，凭据将写入 '
    'Subversion 的 auth 目录（本机 ~/.subversion/auth/ 或 Windows 下 '
    '%APPDATA%\\Subversion\\auth\\）。\n\n',
  );

  if (urls.isEmpty) {
    buffer.writeln(
      '请先在主界面配置源 URL（及精简模式下的目标 SVN URL），再返回此处添加鉴权。',
    );
  } else {
    buffer.writeln('将对以下地址尝试鉴权：');
    for (final url in urls) {
      buffer.writeln('  • $url');
    }
    buffer.writeln();
    buffer.writeln('步骤一：复制下方命令到终端执行，按提示输入用户名和密码：');
    for (final cmd in terminalCommands) {
      buffer.writeln('  $cmd');
    }
    buffer.writeln();
    buffer.writeln(
      '步骤二（可选）：点击下方「尝试在此完成鉴权」，本应用将运行一次可交互的 svn info '
      '（不加 --non-interactive）。部分环境下可能弹出系统凭据窗口；若 GUI 应用'
      '无法弹窗，请改用终端命令。',
    );
  }

  final platformNote = switch (operatingSystem) {
    'macos' =>
      '\n\nmacOS 说明：部分 SVN 构建会把密码写入系统钥匙串；本应用无法检测或清理'
      '钥匙串中的孤立条目。若清理 auth 文件后仍能访问，可能是钥匙串仍保留凭据。',
    'windows' =>
      '\n\nWindows 说明：部分 SVN 发行版可能额外使用 Windows 凭据管理器；'
      '本应用主要清理 Subversion auth 目录。',
    _ => '',
  };
  buffer.write(platformNote);
  return buffer.toString();
}

/// 用户名密码路径的提示文案（展开后展示）。
@visibleForTesting
String buildSvnAuthCredentialsHintText() =>
    '仅当您希望用账号密码登录时填写；否则请使用上方推荐方式。'
    '用户名和密码仅用于本次鉴权，关闭对话框后即丢弃，不会写入本应用存储。';

/// 校验用户名密码输入；通过返回 null，否则返回用户可见错误。
@visibleForTesting
String? validateSvnAuthCredentialsInput({
  required String username,
  required String password,
}) {
  if (username.trim().isEmpty) {
    return '请输入用户名';
  }
  if (password.isEmpty) {
    return '请输入密码';
  }
  return null;
}

/// 从 SVN 输出中移除可能回显的密码片段。
@visibleForTesting
String sanitizeSvnAuthErrorMessage(String message, {String? password}) {
  if (password == null || password.isEmpty) {
    return message;
  }
  return message.replaceAll(password, '****');
}

/// 设置页「添加鉴权」对话框用户选择。
enum SvnAddAuthDialogChoice {
  cancelled,
  tryInteractive,
  useCredentials,
}

/// 设置页「添加鉴权」对话框关闭结果。
class SvnAddAuthDialogResult {
  final SvnAddAuthDialogChoice choice;
  final String username;
  final String password;

  const SvnAddAuthDialogResult({
    required this.choice,
    this.username = '',
    this.password = '',
  });
}

/// 设置页「移除鉴权」确认对话框正文（复用清理范围说明）。
@visibleForTesting
String buildSvnAuthRemoveDialogText({
  required String operatingSystem,
  String? authDirPath,
  String? svnConfigDirEnv,
}) {
  return buildSvnAuthClearDialogText(
    operatingSystem: operatingSystem,
    authDirPath: authDirPath,
    svnConfigDirEnv: svnConfigDirEnv,
  );
}

/// 日志同步等场景：判断是否鉴权缺失错误。
@visibleForTesting
bool isSvnAuthRequiredError(Object error) {
  if (error is SvnAuthRequiredException) {
    return true;
  }
  return error is SvnException && error.needsAuth;
}

/// 将 SVN 异常规范化为 [SvnAuthRequiredException]（若适用）。
@visibleForTesting
Object normalizeSvnAuthError(Object error, {required String url}) {
  if (error is SvnAuthRequiredException) {
    return error;
  }
  if (error is SvnException && error.needsAuth) {
    return SvnAuthRequiredException(url: url, message: error.message);
  }
  return error;
}

/// 日志同步失败时的用户提示（鉴权缺失）。
@visibleForTesting
String formatLogSyncAuthFailureMessage() =>
    '同步失败：需要 SVN 鉴权，请在设置中添加鉴权信息';

/// SVN 鉴权门禁（IO 入口，单例）。
class SvnAuthGateService {
  static final SvnAuthGateService _instance = SvnAuthGateService._internal();
  factory SvnAuthGateService() => _instance;
  SvnAuthGateService._internal() {
    svnService.registerAuthEnsurer(ensureAuthForUrl);
  }

  @visibleForTesting
  SvnAuthClearService clearService = SvnAuthClearService();

  @visibleForTesting
  SvnService svnService = SvnService();

  @visibleForTesting
  String operatingSystem = Platform.operatingSystem;

  @visibleForTesting
  String? homeDir = Platform.environment['HOME'];

  @visibleForTesting
  String? appDataDir = Platform.environment['APPDATA'];

  @visibleForTesting
  String? svnConfigDirEnv = Platform.environment['SVN_CONFIG_DIR'];

  SvnAuthClearService get _clear => clearService;
  SvnService get _svn => svnService;

  /// 是否 auth 目录下存在已缓存条目（不保证对特定 URL 有效）。
  Future<bool> hasAnyCachedAuth() async {
    final authPath = resolveSubversionAuthDir(
      operatingSystem: operatingSystem,
      homeDir: homeDir,
      appDataDir: appDataDir,
      svnConfigDirEnv: svnConfigDirEnv,
    );
    if (authPath == null) {
      return false;
    }
    final authDir = Directory(authPath);
    if (!await authDir.exists()) {
      return false;
    }
    final counts = await countSubversionAuthEntries(authDir);
    return counts.fileCount > 0;
  }

  /// 对 [url] 执行 `svn info` 探针（非交互）。
  Future<AuthProbeResult> probeAuth(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const AuthProbeResult(
        url: '',
        status: AuthProbeStatus.error,
        message: 'URL 为空',
      );
    }

    AppLogger.credential.info('探测 SVN 鉴权: $trimmed');
    try {
      final result = await _svn.runInfoProbeRaw(trimmed, interactive: false);
      final output = '${result.stdout}${result.stderr}';
      final status = classifyAuthProbe(
        exitCode: result.exitCode,
        output: output,
      );
      if (status == AuthProbeStatus.ok) {
        AppLogger.credential.info('鉴权探针通过: $trimmed');
        return AuthProbeResult(url: trimmed, status: status);
      }
      AppLogger.credential.warn(
        '鉴权探针未通过: $trimmed status=$status',
      );
      return AuthProbeResult(
        url: trimmed,
        status: status,
        message: output.trim().isEmpty ? 'svn info 失败' : output.trim(),
      );
    } catch (e, stackTrace) {
      AppLogger.credential.error('鉴权探针异常: $trimmed', e, stackTrace);
      return AuthProbeResult(
        url: trimmed,
        status: AuthProbeStatus.error,
        message: '$e',
      );
    }
  }

  /// 探针通过或存在可用缓存时视为「有鉴权」。
  Future<bool> hasAuthForUrl(String url) async {
    final probe = await probeAuth(url);
    if (probe.status == AuthProbeStatus.ok) {
      return true;
    }
    return hasAnyCachedAuth();
  }

  /// 远端操作前调用：缺鉴权时抛出 [SvnAuthRequiredException]。
  Future<void> ensureAuthForUrl(String url) async {
    if (!isSvnRepositoryUrl(url.trim())) {
      return;
    }
    final probe = await probeAuth(url);
    if (probe.status == AuthProbeStatus.needsAuth) {
      AppLogger.credential.warn('门禁拦截：缺少 SVN 鉴权 url=$url');
      throw SvnAuthRequiredException(
        url: url.trim(),
        message: '需要 SVN 鉴权才能访问 $url',
      );
    }
  }

  /// 运行一次可交互的 `svn info`，引导用户完成鉴权。
  Future<AddAuthResult> addAuthForUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const AddAuthResult(success: false, message: 'URL 为空');
    }

    AppLogger.credential.info('尝试交互式 SVN 鉴权: $trimmed');
    try {
      final result = await _svn.runInfoProbeRaw(trimmed, interactive: true);
      final output = '${result.stdout}${result.stderr}';
      final status = classifyAuthProbe(
        exitCode: result.exitCode,
        output: output,
      );
      if (status == AuthProbeStatus.ok) {
        AppLogger.credential.info('交互式鉴权成功: $trimmed');
        return const AddAuthResult(success: true);
      }
      if (status == AuthProbeStatus.needsAuth) {
        return AddAuthResult(
          success: false,
          message: '仍无法完成鉴权。请复制终端命令在 Terminal 中执行，'
              '或检查用户名/密码是否正确。',
        );
      }
      return AddAuthResult(
        success: false,
        message: output.trim().isEmpty
            ? 'svn info 失败（退出码 ${result.exitCode}）'
            : output.trim(),
      );
    } catch (e, stackTrace) {
      AppLogger.credential.error('交互式鉴权异常: $trimmed', e, stackTrace);
      return AddAuthResult(success: false, message: '$e');
    }
  }

  /// 使用一次性用户名/密码运行 `svn info`，由 Subversion 客户端写入 auth 缓存。
  Future<AddAuthResult> addAuthForUrlWithCredentials(
    String url, {
    required String username,
    required String password,
  }) async {
    final trimmed = url.trim();
    final validationError = validateSvnAuthCredentialsInput(
      username: username,
      password: password,
    );
    if (validationError != null) {
      return AddAuthResult(success: false, message: validationError);
    }
    if (trimmed.isEmpty) {
      return const AddAuthResult(success: false, message: 'URL 为空');
    }

    final user = username.trim();
    AppLogger.credential.info('尝试用户名密码 SVN 鉴权: $trimmed user=$user');
    try {
      final result = await _svn.runInfoProbeRaw(
        trimmed,
        interactive: true,
        username: user,
        password: password,
      );
      final output = sanitizeSvnAuthErrorMessage(
        '${result.stdout}${result.stderr}',
        password: password,
      );
      final status = classifyAuthProbe(
        exitCode: result.exitCode,
        output: output,
      );
      if (status == AuthProbeStatus.ok) {
        AppLogger.credential.info('用户名密码鉴权成功: $trimmed');
        return const AddAuthResult(success: true);
      }
      if (status == AuthProbeStatus.needsAuth) {
        return const AddAuthResult(
          success: false,
          message: '鉴权失败：用户名或密码不正确，或服务器拒绝访问。',
        );
      }
      return AddAuthResult(
        success: false,
        message: output.trim().isEmpty
            ? 'svn info 失败（退出码 ${result.exitCode}）'
            : output.trim(),
      );
    } catch (e, stackTrace) {
      AppLogger.credential.error('用户名密码鉴权异常: $trimmed', e, stackTrace);
      return AddAuthResult(
        success: false,
        message: sanitizeSvnAuthErrorMessage('$e', password: password),
      );
    }
  }

  /// 对配置的源/目标 URL 依次尝试用户名密码鉴权。
  Future<AddAuthResult> addAuthForConfiguredUrlsWithCredentials({
    String? sourceUrl,
    String? targetUrl,
    required String username,
    required String password,
  }) async {
    final urls = collectAuthGuideUrls(
      sourceUrl: sourceUrl,
      targetUrl: targetUrl,
    );
    if (urls.isEmpty) {
      return const AddAuthResult(
        success: false,
        message: '请先在主界面配置源 URL',
      );
    }

    var lastError = '';
    for (final url in urls) {
      final result = await addAuthForUrlWithCredentials(
        url,
        username: username,
        password: password,
      );
      if (result.success) {
        return result;
      }
      lastError = result.message ?? lastError;
    }
    return AddAuthResult(
      success: false,
      message: lastError.isEmpty ? '鉴权未完成' : lastError,
    );
  }

  /// 对配置的源/目标 URL 依次尝试交互式鉴权。
  Future<AddAuthResult> addAuthForConfiguredUrls({
    String? sourceUrl,
    String? targetUrl,
  }) async {
    final urls = collectAuthGuideUrls(
      sourceUrl: sourceUrl,
      targetUrl: targetUrl,
    );
    if (urls.isEmpty) {
      return const AddAuthResult(
        success: false,
        message: '请先在主界面配置源 URL',
      );
    }

    var lastError = '';
    for (final url in urls) {
      final result = await addAuthForUrl(url);
      if (result.success) {
        return result;
      }
      lastError = result.message ?? lastError;
    }
    return AddAuthResult(
      success: false,
      message: lastError.isEmpty ? '鉴权未完成' : lastError,
    );
  }

  /// 解析设置页按钮状态。
  Future<SvnAuthUiState> resolveAuthUiState({
    String? sourceUrl,
    String? targetUrl,
  }) async {
    final urls = collectAuthGuideUrls(
      sourceUrl: sourceUrl,
      targetUrl: targetUrl,
    );

    for (final url in urls) {
      final probe = await probeAuth(url);
      if (probe.status == AuthProbeStatus.ok) {
        return SvnAuthUiState.hasAuth;
      }
    }

    if (await hasAnyCachedAuth()) {
      return SvnAuthUiState.hasAuth;
    }

    return SvnAuthUiState.needsAuth;
  }

  /// 移除 Subversion 鉴权缓存（委托清理服务）。
  Future<SvnAuthClearResult> removeAuth() => _clear.clearAuthCache();
}
