import CoreGraphics
import Foundation

// 列出指定进程名的屏幕窗口（windowID 与位置），供 screencapture -l 精确截取窗口
let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "CleanMac"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for window in list {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == target,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
    let pid = window[kCGWindowOwnerPID as String] as? Int ?? 0
    print("\(number) pid=\(pid) x=\(Int(bounds["X"] ?? 0)) y=\(Int(bounds["Y"] ?? 0)) w=\(Int(bounds["Width"] ?? 0)) h=\(Int(bounds["Height"] ?? 0))")
}
