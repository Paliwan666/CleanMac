import AppKit
import SwiftUI

/// 单窗口工具类 App：关闭最后一个窗口即退出整个应用，
/// 避免窗口关闭后 Dock 图标残留且点击无响应的问题
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CleanMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1040, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
