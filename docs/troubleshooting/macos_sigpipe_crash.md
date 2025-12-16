# macOS 应用从 Finder 启动时 SIGPIPE 崩溃问题

## 问题现象

- Flutter macOS 应用从**终端命令行**启动正常
- 从 **Finder 双击**或 **Dock 点击**启动时，应用立即退出（约 1-3 秒后）
- 没有明显的崩溃报告

## 诊断方法

### 1. 检查系统日志

```bash
log show --predicate 'process == "YourAppName"' --last 5m --style compact
```

### 2. 关键错误特征

在日志中查找 `SIGPIPE` 关键字：

```bash
log show --predicate 'eventMessage CONTAINS "YourAppName" AND eventMessage CONTAINS[c] "SIGPIPE"' --last 5m --style compact
```

典型错误日志：
```
exited due to SIGPIPE | sent by YourAppName[PID], ran for 1809ms
```

## 根本原因

1. 当 macOS 应用从 Finder 双击启动时，**没有终端连接**
2. 应用的 stdout/stderr 是**关闭的管道**
3. Flutter 的 `print()` 语句或其他写入 stdout 的操作会触发 **SIGPIPE** 信号
4. SIGPIPE 的默认行为是**终止进程**

## 解决方案

在 `macos/Runner/AppDelegate.swift` 的 `init()` 方法中忽略 SIGPIPE 信号：

```swift
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  
  override init() {
    // 忽略 SIGPIPE 信号，防止从 Finder 启动时因 stdout 关闭导致崩溃
    signal(SIGPIPE, SIG_IGN)
    super.init()
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
```

## 额外建议

1. **避免在 Swift 原生代码中使用 `print()`**：使用 `os_log` 替代，它不会写入 stdout
2. **Flutter/Dart 的 `print()` 通常安全**：因为 Flutter 引擎会处理，但在引擎初始化前的原生代码需要注意
3. **始终添加 SIGPIPE 忽略**：作为 macOS 应用的最佳实践

## 相关问题

- 代码签名破坏也可能导致类似问题（应用无法启动）
- 检查方法：`codesign -vvv /path/to/YourApp.app`

## 参考

- SIGPIPE 信号：当进程向已关闭的管道写入数据时产生
- macOS 应用生命周期：从 Finder 启动时没有 TTY 连接
