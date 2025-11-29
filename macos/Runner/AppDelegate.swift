import Cocoa
import FlutterMacOS
import os.log

@main
class AppDelegate: FlutterAppDelegate {
  private let logger = OSLog(subsystem: "com.example.SvnMergeTool", category: "AppDelegate")
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 记录窗口关闭事件
    os_log("窗口已关闭，应用将退出（applicationShouldTerminateAfterLastWindowClosed = true）", log: logger, type: .info)
    print("[APP] 窗口已关闭，应用将退出")
    return true
  }
  
  override func applicationWillTerminate(_ notification: Notification) {
    // 记录应用即将退出
    os_log("应用即将退出（applicationWillTerminate）", log: logger, type: .info)
    print("[APP] 应用即将退出")
  }
  
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // 记录应用终止请求
    os_log("收到应用终止请求（applicationShouldTerminate）", log: logger, type: .info)
    print("[APP] 收到应用终止请求")
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
