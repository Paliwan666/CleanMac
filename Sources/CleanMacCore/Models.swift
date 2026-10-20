import Foundation

public struct RelatedFile: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let category: String
    public var size: Int64
    public var selected: Bool
    public var modified: Date?

    public init(url: URL, category: String, size: Int64, selected: Bool = true, modified: Date? = nil) {
        self.url = url
        self.category = category
        self.size = size
        self.selected = selected
        self.modified = modified
    }
}

public struct InstalledApp: Identifiable, Hashable {
    /// 用 bundleID 做稳定身份：重新扫描后选择状态不丢失，SwiftUI 也不会索引错位
    public var id: String { bundleID }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String
    public var isRunning: Bool = false
    public var isChecked: Bool = false
    public var includeAppBundle: Bool = true
    public var appSize: Int64 = 0
    public var lastUsed: Date?
    public var useCount: Int?
    public var modified: Date?
    public var relatedFiles: [RelatedFile] = []

    public var relatedTotalSize: Int64 { relatedFiles.reduce(0) { $0 + $1.size } }
    public var selectedRelatedSize: Int64 { relatedFiles.filter(\.selected).reduce(0) { $0 + $1.size } }
    public var selectedCount: Int { relatedFiles.filter(\.selected).count }

    public init(url: URL, name: String, bundleID: String, version: String) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
    }
}

public struct LeftoverItem: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public var size: Int64
    public var selected: Bool
    public var modified: Date?

    public init(url: URL, size: Int64, selected: Bool = true, modified: Date? = nil) {
        self.url = url
        self.size = size
        self.selected = selected
        self.modified = modified
    }
}

public struct LeftoverGroup: Identifiable, Hashable {
    public var id: String { path }
    public let category: String
    public let path: String
    public var items: [LeftoverItem]

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    /// 组内最新修改时间：最新文件都很久没动说明整组都是死数据
    public var latestModified: Date? { items.compactMap(\.modified).max() }

    public init(category: String, path: String, items: [LeftoverItem]) {
        self.category = category
        self.path = path
        self.items = items
    }
}
