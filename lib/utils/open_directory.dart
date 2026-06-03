/// 跨平台「打开本地目录」命令解析。
///
/// 提供跨库共享的 [OpenDirectoryCommand] 值类型 + [resolveOpenDirectoryCommand]
/// 解析函数。`settings_screen` / `main_screen_v3` 等多处需要打开系统文件管理器，
/// 此处单点维护映射规则，避免散落多套实现。
///
/// 实际 `Process.run` 调用由 caller 负责——本模块只做命令组装，不依赖 `dart:io`，
/// 便于跨平台单元测试。
library;

/// 「打开本地目录」用的命令描述：可执行文件名 + 参数列表。
class OpenDirectoryCommand {
  final String executable;
  final List<String> args;

  const OpenDirectoryCommand({required this.executable, required this.args});

  @override
  bool operator ==(Object other) {
    if (other is! OpenDirectoryCommand) return false;
    if (other.executable != executable) return false;
    if (other.args.length != args.length) return false;
    for (var i = 0; i < args.length; i++) {
      if (other.args[i] != args[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(executable, Object.hashAll(args));

  @override
  String toString() => 'OpenDirectoryCommand($executable ${args.join(' ')})';
}

/// 把 `Platform.operatingSystem` 翻译成"打开本地目录"的命令。
///
/// 已知映射：
/// - `'macos'`   → `open <path>`
/// - `'windows'` → `explorer <path>`
/// - `'linux'`   → `xdg-open <path>`
///
/// 其它平台（`'android'` / `'ios'` / `'fuchsia'` / 任何未知字符串）→ 返回 `null`，
/// 调用方应据此走"不支持的平台"分支（提示用户路径）。
///
/// `path` 原样透传到 `args`，不做引号 / 转义 / 反斜杠归一化——交给底层 `Process.run`
/// 处理。
OpenDirectoryCommand? resolveOpenDirectoryCommand({
  required String platform,
  required String path,
}) {
  switch (platform) {
    case 'macos':
      return OpenDirectoryCommand(executable: 'open', args: [path]);
    case 'windows':
      return OpenDirectoryCommand(executable: 'explorer', args: [path]);
    case 'linux':
      return OpenDirectoryCommand(executable: 'xdg-open', args: [path]);
    default:
      return null;
  }
}

/// 把 `Platform.operatingSystem` 翻译成"用系统默认应用打开文件"的命令。
///
/// 与 [resolveOpenDirectoryCommand] **复用同一种 [OpenDirectoryCommand] 值类型**——
/// 这两个动作在 macOS / Linux 上用的是同一个可执行命令（`open` / `xdg-open`），
/// 只是参数从"目录路径"换成"文件路径"，OS 自身根据 path 类型决定行为。
///
/// 已知映射：
/// - `'macos'`   → `open <path>`
/// - `'windows'` → `cmd /c start "" <path>`
///   - 走 `cmd /c start` 而非 `explorer`：`explorer <file.txt>` 在 Windows 会
///     "在文件管理器中选中"（不打开），而 `start "" path` 会用关联程序打开文件本身；
///   - `start` 第一个引号参数 `""` 是 cmd `start` 命令的"窗口标题"占位（必填，
///     否则 `start "C:\path with space\foo.txt"` 会被当作标题），见
///     <https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/start>。
/// - `'linux'`   → `xdg-open <path>`
///
/// 其它平台（`'android'` / `'ios'` / `'fuchsia'` / 任何未知字符串）→ 返回 `null`，
/// 调用方应据此走"不支持的平台"分支（提示用户路径）。
///
/// `path` 原样透传到 `args`，不做引号 / 转义 / 反斜杠归一化——交给底层 `Process.run`
/// 处理。
OpenDirectoryCommand? resolveOpenFileCommand({
  required String platform,
  required String path,
}) {
  switch (platform) {
    case 'macos':
      return OpenDirectoryCommand(executable: 'open', args: [path]);
    case 'windows':
      return OpenDirectoryCommand(
        executable: 'cmd',
        args: ['/c', 'start', '', path],
      );
    case 'linux':
      return OpenDirectoryCommand(executable: 'xdg-open', args: [path]);
    default:
      return null;
  }
}
