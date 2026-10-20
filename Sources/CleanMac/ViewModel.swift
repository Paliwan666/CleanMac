import AppKit
import CleanMacCore
import Foundation

func fmtSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// 相对时间：今天/昨天/N 天前/N 个月前/N 年前
func fmtRelative(_ date: Date) -> String {
    // 按日历日差计算，避免"10月19日（今天）"这种自相矛盾的显示
    let calendar = Calendar.current
    let days = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: date),
        to: calendar.startOfDay(for: Date())
    ).day ?? 0
    switch days {
    case ..<0: return "今天"
    case 0: return "今天"
    case 1: return "昨天"
    case 2..<30: return "\(days) 天前"
    case 30..<365: return "\(days / 30) 个月前"
    default: return "\(days / 365) 年前"
    }
}

func fmtDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

/// 超过该天数未使用视为"长期未用"，界面橙色提示
let staleThresholdDays = 90

func isStale(_ date: Date?) -> Bool {
    guard let date else { return false }
    let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    return days >= staleThresholdDays
}

@MainActor
final class CleanerViewModel: ObservableObject {
    enum Mode: String, CaseIterable {
        case apps = "应用卸载"
        case leftovers = "残留清理"
    }

    @Published var mode: Mode = .apps
    @Published var apps: [InstalledApp] = []
    @Published var leftovers: [LeftoverGroup] = []
    @Published var selectedAppID: String?
    @Published var selectedLeftoverPath: String?
    @Published var searchText = ""
    @Published var isScanning = false
    @Published var scanStatus = ""
    @Published var isCleaning = false
    @Published var hasFullDiskAccess = true
    @Published var showCleanConfirm = false
    @Published var cleanSummary: String?

    var busy: Bool { isScanning || isCleaning }

    var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }
    var selectedLeftover: LeftoverGroup? { leftovers.first { $0.path == selectedLeftoverPath } }

    var selectedTrashItems: [(url: URL, size: Int64)] {
        var items: [(URL, Int64)] = []
        for app in apps where app.isChecked {
            if app.includeAppBundle { items.append((app.url, app.appSize)) }
            for file in app.relatedFiles where file.selected { items.append((file.url, file.size)) }
        }
        for group in leftovers {
            for item in group.items where item.selected { items.append((item.url, item.size)) }
        }
        return items
    }

    var leftoverTotalCount: Int { leftovers.reduce(0) { $0 + $1.items.count } }
    var leftoverTotalSize: Int64 { leftovers.reduce(0) { $0 + $1.totalSize } }

    // MARK: - 扫描

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanStatus = "正在扫描已安装的应用…"
        hasFullDiskAccess = Self.checkFullDiskAccess()
        Task {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let found = await Task.detached(priority: .userInitiated) {
                Scanner.scanInstalledApps(home: home)
            }.value
            apps = found
            for i in apps.indices {
                apps[i].isRunning = !NSRunningApplication
                    .runningApplications(withBundleIdentifier: apps[i].bundleID).isEmpty
            }
            for i in apps.indices {
                let app = apps[i]
                scanStatus = "正在分析 \(app.name)…"
                let result = await Task.detached(priority: .userInitiated) {
                    (files: Scanner.findRelatedFiles(for: app, home: home),
                     appSize: Scanner.allocatedSize(of: app.url))
                }.value
                guard i < apps.count, apps[i].id == app.id else { break }
                apps[i].relatedFiles = result.files
                apps[i].appSize = result.appSize
            }
            scanStatus = "正在扫描残留文件…"
            let ids = Set(apps.map(\.bundleID))
            let found2 = await Task.detached(priority: .userInitiated) {
                Scanner.scanLeftovers(home: home, installedBundleIDs: ids)
            }.value
            leftovers = found2
            isScanning = false
            scanStatus = ""
            if selectedApp == nil { selectedAppID = apps.first?.id }
            if selectedLeftover == nil { selectedLeftoverPath = leftovers.first?.path }
        }
    }

    // MARK: - 勾选
    // 所有变更都按稳定 ID 现场查找再修改，不使用捕获的数组下标，
    // 避免重新扫描替换数组后 SwiftUI 绑定访问过期下标导致崩溃

    func toggleApp(_ id: String) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[i].isChecked.toggle()
        let on = apps[i].isChecked
        for j in apps[i].relatedFiles.indices {
            apps[i].relatedFiles[j].selected = on
        }
    }

    func toggleIncludeBundle(appID: String) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].includeAppBundle.toggle()
    }

    func toggleRelatedFile(appID: String, fileID: String) {
        guard let i = apps.firstIndex(where: { $0.id == appID }),
              let j = apps[i].relatedFiles.firstIndex(where: { $0.id == fileID }) else { return }
        apps[i].relatedFiles[j].selected.toggle()
    }

    func setAllFiles(appID: String, selected: Bool) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        for j in apps[i].relatedFiles.indices {
            apps[i].relatedFiles[j].selected = selected
        }
    }

    func toggleLeftoverItem(path: String, itemID: String) {
        guard let g = leftovers.firstIndex(where: { $0.path == path }),
              let j = leftovers[g].items.firstIndex(where: { $0.id == itemID }) else { return }
        leftovers[g].items[j].selected.toggle()
    }

    func setAllLeftovers(path: String, selected: Bool) {
        guard let g = leftovers.firstIndex(where: { $0.path == path }) else { return }
        for j in leftovers[g].items.indices {
            leftovers[g].items[j].selected = selected
        }
    }

    // MARK: - 清理

    func cleanSelected() {
        let items = selectedTrashItems
        guard !items.isEmpty else { return }
        showCleanConfirm = false
        isCleaning = true
        Task {
            let urls = items.map(\.url)
            let freed = items.reduce(Int64(0)) { $0 + $1.size }
            let result = await Task.detached(priority: .userInitiated) {
                Cleaner.trash(urls)
            }.value
            isCleaning = false
            var lines = ["已将 \(result.trashed.count) 个项目移到废纸篓，释放约 \(fmtSize(freed))。"]
            if !result.failures.isEmpty {
                lines.append("\n\(result.failures.count) 个项目删除失败：")
                lines += result.failures.prefix(5).map { "• \($0.url.lastPathComponent)：\($0.message)" }
                if result.failures.count > 5 { lines.append("…等共 \(result.failures.count) 项") }
                lines.append("\n提示：删除 /Applications 中由管理员安装的应用，可能需要先在“访达”中手动删除一次以授权。")
            }
            cleanSummary = lines.joined(separator: "\n")
            scan()
        }
    }

    // MARK: - 完全磁盘访问

    static func checkFullDiskAccess() -> Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari").path
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}
