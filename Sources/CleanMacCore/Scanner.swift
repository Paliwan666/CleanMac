import Foundation

public enum Scanner {
    public struct SearchLocation: Sendable {
        public let path: String
        public let category: String
        public let matchByName: Bool
        public let namePrefixMatch: Bool

        public init(path: String, category: String, matchByName: Bool, namePrefixMatch: Bool = false) {
            self.path = path
            self.category = category
            self.matchByName = matchByName
            self.namePrefixMatch = namePrefixMatch
        }
    }

    /// 逆向 App Cleaner 10 二进制提取的残留文件搜索目录
    public static let searchLocations: [SearchLocation] = [
        SearchLocation(path: "Library/Application Support", category: "应用支持", matchByName: true),
        SearchLocation(path: "Library/Application Support/CrashReporter", category: "崩溃报告", matchByName: true, namePrefixMatch: true),
        SearchLocation(path: "Library/Caches", category: "缓存", matchByName: true),
        SearchLocation(path: "Library/Containers", category: "容器数据", matchByName: false),
        SearchLocation(path: "Library/Group Containers", category: "组容器", matchByName: true),
        SearchLocation(path: "Library/Cookies", category: "Cookie", matchByName: false),
        SearchLocation(path: "Library/HTTPStorages", category: "网站数据", matchByName: false),
        SearchLocation(path: "Library/WebKit", category: "网站数据", matchByName: false),
        SearchLocation(path: "Library/Application Scripts", category: "应用脚本", matchByName: false),
        SearchLocation(path: "Library/Preferences", category: "偏好设置", matchByName: false),
        SearchLocation(path: "Library/Preferences/ByHost", category: "偏好设置", matchByName: false),
        SearchLocation(path: "Library/Saved Application State", category: "窗口状态", matchByName: false),
        SearchLocation(path: "Library/Logs", category: "日志", matchByName: true),
        SearchLocation(path: "Library/Logs/DiagnosticReports", category: "崩溃报告", matchByName: true, namePrefixMatch: true),
        SearchLocation(path: "Library/LaunchAgents", category: "启动项", matchByName: false),
        SearchLocation(path: "Library/Autosave Information", category: "自动保存", matchByName: false),
    ]

    public static let selfBundleID = "com.cleanmac.app"

    /// 已知的跨应用共享组件，永不判定为残留
    static let sharedComponentPrefixes = [
        "com.google.keystone",
        "com.microsoft.autoupdate",
        "com.microsoft.update",
    ]

    /// Apple 旧版/非 com.apple 前缀的系统组件（Workflow=快捷指令前身、TV 服务）
    static let appleLegacyPrefixes = [
        "is.workflow",
        "tvappservices",
    ]

    static let stripExtensions: Set<String> = ["plist", "savedstate", "binarycookies", "ips", "crash", "diag"]

    public static func normalized(_ name: String) -> String {
        var n = name
        let ext = (n as NSString).pathExtension.lowercased()
        if stripExtensions.contains(ext) {
            n = (n as NSString).deletingPathExtension
        }
        return n.lowercased()
    }

    public static func isProtected(_ name: String) -> Bool {
        var n = normalized(name)
        if n.hasPrefix("group.") { n = String(n.dropFirst("group.".count)) }
        if n == selfBundleID { return true }
        if n.hasPrefix("com.apple") || n.contains(".apple.") { return true }
        for prefix in sharedComponentPrefixes where n.hasPrefix(prefix) { return true }
        for prefix in appleLegacyPrefixes where n.hasPrefix(prefix) { return true }
        return false
    }

    /// 按点分组件做精确包含匹配：com.foo.bar 能匹配 group.com.foo.bar、TEAMID.com.foo.bar、com.foo.bar.helper，但不会误伤 com.foo.barbaz
    public static func containsBundleID(_ name: String, _ bundleID: String) -> Bool {
        let n = normalized(name)
        let b = bundleID.lowercased()
        if n == b { return true }
        let np = n.split(separator: ".").map(String.init)
        let bp = b.split(separator: ".").map(String.init)
        guard bp.count >= 2, np.count > bp.count else { return false }
        for i in 0...(np.count - bp.count) where Array(np[i..<(i + bp.count)]) == bp {
            return true
        }
        return false
    }

    static func nameMatches(_ itemName: String, appName: String, prefixOK: Bool) -> Bool {
        let a = appName.lowercased()
        guard a.count >= 4 else { return false }
        let n = normalized(itemName)
        if n == a { return true }
        if n.hasPrefix(a + " ") { return true }
        if prefixOK && (n.hasPrefix(a + "_") || n.hasPrefix(a + "-")) { return true }
        return false
    }

    public static func matches(_ itemName: String, location: SearchLocation, appName: String, bundleID: String) -> Bool {
        guard !isProtected(itemName) else { return false }
        if containsBundleID(itemName, bundleID) { return true }
        if location.matchByName && nameMatches(itemName, appName: appName, prefixOK: location.namePrefixMatch) { return true }
        return false
    }

    public static func scanInstalledApps(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraDirs: [URL]? = nil
    ) -> [InstalledApp] {
        let dirs = extraDirs ?? [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
        var apps: [InstalledApp] = []
        var seenBundleIDs = Set<String>()
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items where item.pathExtension == "app" {
                guard let bundle = Bundle(url: item),
                      let info = bundle.infoDictionary,
                      let bid = info["CFBundleIdentifier"] as? String,
                      !bid.isEmpty,
                      !isProtected(bid),
                      bid.lowercased() != selfBundleID
                else { continue }
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? item.deletingPathExtension().lastPathComponent
                let version = (info["CFBundleShortVersionString"] as? String) ?? ""
                var app = InstalledApp(url: item, name: name, bundleID: bid, version: version)
                let usage = UsageMetadata.appUsage(url: item)
                app.lastUsed = usage.lastUsed
                app.useCount = usage.useCount
                app.modified = UsageMetadata.modificationDate(of: item)
                if seenBundleIDs.insert(bid).inserted {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func findRelatedFiles(for app: InstalledApp, home: URL) -> [RelatedFile] {
        var result: [RelatedFile] = []
        for loc in searchLocations {
            let dir = home.appendingPathComponent(loc.path)
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for item in items where matches(item, location: loc, appName: app.name, bundleID: app.bundleID) {
                let url = dir.appendingPathComponent(item)
                result.append(RelatedFile(
                    url: url,
                    category: loc.category,
                    size: allocatedSize(of: url),
                    modified: UsageMetadata.modificationDate(of: url)
                ))
            }
        }
        return result
    }

    /// 判断文件名是否形如反向域名（com.xxx.yyy），用于残留判定
    public static func looksLikeBundleID(_ name: String) -> Bool {
        let n = normalized(name)
        guard n.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }) else { return false }
        let parts = n.split(separator: ".")
        guard parts.count >= 3 else { return false }
        let first = String(parts[0])
        let knownPrefixes: Set<String> = ["com", "org", "net", "io", "me", "app", "dev", "co", "cn", "jp", "de", "fr", "uk", "gg", "im", "fm", "sh", "so", "to", "cc", "xyz", "tech", "team", "group", "live", "cloud", "run", "info", "biz", "us", "eu", "ai", "tv", "pro", "one"]
        guard knownPrefixes.contains(first) || first.count <= 3 else { return false }
        return true
    }

    public static func scanLeftovers(home: URL, installedBundleIDs: Set<String>) -> [LeftoverGroup] {
        let installed = installedBundleIDs.map { $0.lowercased() }
        // 已安装应用的"公司前缀"（如 com.nektony），其下的 helper/服务条目不算残留，
        // 避免误删正在运行的应用主程序之外的配套进程数据
        func companyPrefix(_ norm: String) -> String {
            var parts = norm.split(separator: ".").map(String.init)
            if parts.first == "group" { parts.removeFirst() }
            return parts.prefix(2).joined(separator: ".")
        }
        let companyPrefixes = Set(installed.map { companyPrefix($0) })
        var groups: [LeftoverGroup] = []
        for loc in searchLocations {
            let dir = home.appendingPathComponent(loc.path)
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            var found: [LeftoverItem] = []
            for item in items {
                guard looksLikeBundleID(item), !isProtected(item) else { continue }
                let company = companyPrefix(normalized(item))
                let alive = companyPrefixes.contains(company)
                    || installed.contains { containsBundleID(item, $0) || containsBundleID($0, item) }
                guard !alive else { continue }
                let url = dir.appendingPathComponent(item)
                found.append(LeftoverItem(
                    url: url,
                    size: allocatedSize(of: url),
                    selected: false,
                    modified: UsageMetadata.modificationDate(of: url)
                ))
            }
            if !found.isEmpty {
                groups.append(LeftoverGroup(category: loc.category, path: loc.path, items: found.sorted { $0.size > $1.size }))
            }
        }
        return groups.sorted { $0.totalSize > $1.totalSize }
    }

    public static func allocatedSize(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            return Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
