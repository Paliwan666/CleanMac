import CoreServices
import Foundation

public enum UsageMetadata {
    /// 通过 Spotlight/LaunchServices 读取 App 的最后使用日期和使用次数（无需权限）
    public static func appUsage(url: URL) -> (lastUsed: Date?, useCount: Int?) {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return (nil, nil) }
        let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        // kMDItemUseCount 未在新版 SDK 公开头文件中导出，但 Spotlight 运行时仍填充该属性
        let useCount = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue
        return (lastUsed, useCount)
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
