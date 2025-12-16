import Cocoa
import FlutterMacOS
import os.log

@main
class AppDelegate: FlutterAppDelegate {
  private let logger = OSLog(subsystem: "com.example.SvnMergeTool", category: "AppDelegate")
  
  override init() {
    // 忽略 SIGPIPE 信号，防止从 Finder 启动时因 stdout 关闭导致崩溃
    signal(SIGPIPE, SIG_IGN)
    super.init()
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    os_log("窗口已关闭，应用将退出（applicationShouldTerminateAfterLastWindowClosed = true）", log: logger, type: .info)
    return true
  }
  
  override func applicationWillTerminate(_ notification: Notification) {
    os_log("应用即将退出（applicationWillTerminate）", log: logger, type: .info)
  }
  
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    os_log("收到应用终止请求（applicationShouldTerminate）", log: logger, type: .info)
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
