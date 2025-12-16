import Cocoa
import FlutterMacOS
import os.log

class MainFlutterWindow: NSWindow {
  private let logger = OSLog(subsystem: "com.example.SvnMergeTool", category: "MainFlutterWindow")
  
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    
    // 设置窗口标题
    self.title = "SVN 自动合并工具"
    
    // 设置窗口关闭代理
    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    
    os_log("窗口已初始化（awakeFromNib）", log: logger, type: .info)
  }
  
  override func close() {
    os_log("窗口 close() 方法被调用", log: logger, type: .info)
    super.close()
  }
}

extension MainFlutterWindow: NSWindowDelegate {
  func windowWillClose(_ notification: Notification) {
    os_log("窗口即将关闭（windowWillClose）", log: logger, type: .info)
  }
  
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    os_log("窗口关闭请求（windowShouldClose）", log: logger, type: .info)
    return true
  }
  
  func windowDidClose(_ notification: Notification) {
    os_log("窗口已关闭（windowDidClose）", log: logger, type: .info)
  }
}
