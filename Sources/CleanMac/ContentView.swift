import AppKit
import CleanMacCore
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = CleanerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if !vm.hasFullDiskAccess {
                fullDiskAccessBanner
            }
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            Divider()
            footer
        }
        .frame(minWidth: 940, minHeight: 580)
        .navigationTitle("净 Mac")
        .onAppear { if vm.apps.isEmpty && !vm.isScanning { vm.scan() } }
        .alert("确认清理", isPresented: $vm.showCleanConfirm) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓") { vm.cleanSelected() }
        } message: {
            let items = vm.selectedTrashItems
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            Text("将把 \(items.count) 个项目（共 \(fmtSize(total))）移到废纸篓。如需恢复，可在废纸篓中放回原处。")
        }
        .alert("清理完成", isPresented: summaryPresented) {
            Button("好") { vm.cleanSummary = nil }
        } message: {
            Text(vm.cleanSummary ?? "")
        }
    }

    private var summaryPresented: Binding<Bool> {
        Binding(
            get: { vm.cleanSummary != nil },
            set: { if !$0 { vm.cleanSummary = nil } }
        )
    }

    // MARK: - 完全磁盘访问横幅

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            Text("未授予完全磁盘访问权限，部分位置（如 Safari 数据、崩溃报告）将无法扫描。")
                .font(.callout)
            Spacer()
            Button("打开系统设置") { CleanerViewModel.openFullDiskAccessSettings() }
            Button("重新检查") { vm.hasFullDiskAccess = CleanerViewModel.checkFullDiskAccess() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - 侧栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $vm.mode) {
                ForEach(CleanerViewModel.Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)

            switch vm.mode {
            case .apps: appList
            case .leftovers: leftoverList
            }
        }
        .frame(minWidth: 260)
    }

    private var appList: some View {
        List(selection: $vm.selectedAppID) {
            ForEach(vm.filteredApps) { app in
                AppRowView(
                    app: app,
                    isChecked: Binding(
                        get: { app.isChecked },
                        set: { _ in vm.toggleApp(app.id) }
                    )
                )
                .tag(app.id)
            }
        }
        .searchable(text: $vm.searchText, placement: .sidebar, prompt: "搜索应用")
    }

    private var leftoverList: some View {
        List(selection: $vm.selectedLeftoverPath) {
            ForEach(vm.leftovers) { group in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(
                        get: {
                            !group.items.isEmpty && group.items.allSatisfy(\.selected)
                        },
                        set: { vm.setAllLeftovers(path: group.path, selected: $0) }
                    )) {}
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help("勾选/取消整组")
                    CategoryIconView(category: group.category)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.category)
                            .lineLimit(1)
                        Text(subtitle(for: group))
                            .font(.caption)
                            .foregroundStyle(isStale(group.latestModified) ? .orange : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(fmtSize(group.totalSize))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("\(group.items.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .tag(group.path)
            }
        }
    }

    private func subtitle(for group: LeftoverGroup) -> String {
        if let latest = group.latestModified {
            return "最近修改：\(fmtRelative(latest))"
        }
        return "~/" + group.path
    }

    // MARK: - 明细

    @ViewBuilder
    private var detail: some View {
        switch vm.mode {
        case .apps:
            if let app = vm.selectedApp {
                AppDetailView(vm: vm, appID: app.id)
            } else {
                placeholder("选择一个应用查看关联文件")
            }
        case .leftovers:
            if let group = vm.selectedLeftover {
                LeftoverGroupDetailView(vm: vm, path: group.path)
            } else {
                placeholder(vm.leftovers.isEmpty ? "未发现残留文件" : "选择一个类别查看残留文件")
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部操作栏

    private var footer: some View {
        let items = vm.selectedTrashItems
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        return HStack(spacing: 12) {
            if vm.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text(vm.scanStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if vm.isCleaning {
                ProgressView()
                    .controlSize(.small)
                Text("正在移到废纸篓…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(vm.apps.count) 个应用 · 残留 \(vm.leftoverTotalCount) 项")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("已选 \(items.count) 项 · \(fmtSize(total))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("重新扫描") { vm.scan() }
                .disabled(vm.busy)
            Button("清理所选") { vm.showCleanConfirm = true }
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty || vm.busy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - 应用行

private struct AppRowView: View {
    let app: InstalledApp
    @Binding var isChecked: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isChecked) {}
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(app.isRunning)
                .help(app.isRunning ? "应用正在运行，退出后才能清理" : "")
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .lineLimit(1)
                    if app.isRunning {
                        Text("运行中")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    if isStale(app.lastUsed) {
                        Text("久未使用")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.relatedTotalSize > 0 {
                Text(fmtSize(app.relatedTotalSize))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [app.relatedFiles.isEmpty ? "无关联文件" : "\(app.relatedFiles.count) 个关联文件"]
        if let lastUsed = app.lastUsed {
            parts.append("\(fmtRelative(lastUsed))用过")
        } else if let modified = app.modified {
            parts.append("更新于 \(fmtRelative(modified))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 应用明细

private struct AppDetailView: View {
    @ObservedObject var vm: CleanerViewModel
    let appID: String

    var body: some View {
        if let app = vm.apps.first(where: { $0.id == appID }) {
            content(for: app)
        } else {
            Text("该应用已不在列表中")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(for app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.title3)
                    Text("\(app.bundleID) · 版本 \(app.version.isEmpty ? "未知" : app.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(usageLine(for: app))
                        .font(.caption)
                        .foregroundStyle(isStale(app.lastUsed) ? .orange : .secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle(isOn: Binding(
                    get: { app.includeAppBundle },
                    set: { _ in vm.toggleIncludeBundle(appID: app.id) }
                )) {
                    Text("同时删除 App 本体（\(fmtSize(app.appSize))）")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .disabled(!app.isChecked)
                Button("在访达中显示") { CleanerViewModel.revealInFinder(app.url) }
            }
            .padding(12)

            Divider()

            HStack {
                Text("关联文件（\(app.selectedCount)/\(app.relatedFiles.count) 项 · \(fmtSize(app.selectedRelatedSize))）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全选") { vm.setAllFiles(appID: app.id, selected: true) }
                    .controlSize(.small)
                Button("全不选") { vm.setAllFiles(appID: app.id, selected: false) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if app.relatedFiles.isEmpty {
                Text("该应用没有扫描到关联文件")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(app.relatedFiles) { file in
                        FileRowView(
                            file: file,
                            selected: Binding(
                                get: { file.selected },
                                set: { _ in vm.toggleRelatedFile(appID: app.id, fileID: file.id) }
                            )
                        )
                    }
                }
            }
        }
    }
}

// MARK: - 应用使用信息

private func usageLine(for app: InstalledApp) -> String {
    var parts: [String] = []
    if let lastUsed = app.lastUsed {
        parts.append("最后使用：\(fmtDate(lastUsed))（\(fmtRelative(lastUsed))）")
    } else {
        parts.append("最后使用：无记录")
    }
    if let useCount = app.useCount, useCount > 0 {
        parts.append("共使用 \(useCount) 次")
    }
    return parts.joined(separator: " · ")
}

// MARK: - 残留类别图标

private struct CategoryIconView: View {
    let category: String

    private var style: (symbol: String, color: Color) {
        switch category {
        case "缓存": return ("tray.full.fill", .teal)
        case "偏好设置": return ("gearshape.fill", .gray)
        case "容器数据": return ("shippingbox.fill", .blue)
        case "组容器": return ("cube.box.fill", .indigo)
        case "网站数据": return ("globe", .cyan)
        case "Cookie": return ("network", .mint)
        case "应用脚本": return ("chevron.left.forwardslash.chevron.right", .orange)
        case "日志": return ("doc.text.fill", .secondary)
        case "崩溃报告": return ("exclamationmark.triangle.fill", .red)
        case "启动项": return ("power", .green)
        case "窗口状态": return ("macwindow", .blue)
        case "自动保存": return ("arrow.clockwise", .teal)
        default: return ("folder.fill", .blue)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(style.color.gradient)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

// MARK: - 残留类别明细

private struct LeftoverGroupDetailView: View {
    @ObservedObject var vm: CleanerViewModel
    let path: String

    var body: some View {
        if let group = vm.leftovers.first(where: { $0.path == path }) {
            content(for: group)
        } else {
            Text("该类别已不在列表中")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(for group: LeftoverGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CategoryIconView(category: group.category)
                    .scaleEffect(1.7)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.category)
                        .font(.title3)
                    Text("~/" + group.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("已选 \(group.items.filter(\.selected).count)/\(group.items.count) 项 · \(fmtSize(group.selectedSize))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("全选") { vm.setAllLeftovers(path: group.path, selected: true) }
                    .controlSize(.small)
                Button("全不选") { vm.setAllLeftovers(path: group.path, selected: false) }
                    .controlSize(.small)
            }
            .padding(12)

            Divider()

            List {
                ForEach(group.items) { item in
                    LeftoverItemRowView(
                        item: item,
                        selected: Binding(
                            get: { item.selected },
                            set: { _ in vm.toggleLeftoverItem(path: group.path, itemID: item.id) }
                        )
                    )
                }
            }
        }
    }
}

// MARK: - 残留项目行

private struct LeftoverItemRowView: View {
    let item: LeftoverItem
    @Binding var selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $selected) {}
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                Text(CleanerViewModel.displayPath(item.url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let modified = item.modified {
                Text("\(fmtRelative(modified))修改")
                    .font(.caption)
                    .foregroundStyle(isStale(modified) ? .orange : .secondary)
            }
            Text(fmtSize(item.size))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
            Button {
                CleanerViewModel.revealInFinder(item.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("在访达中显示")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 文件行

private struct FileRowView: View {
    let file: RelatedFile
    @Binding var selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $selected) {}
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .lineLimit(1)
                Text(fileCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(file.category)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            Text(fmtSize(file.size))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
            Button {
                CleanerViewModel.revealInFinder(file.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("在访达中显示")
        }
        .padding(.vertical, 2)
    }

    private var fileCaption: String {
        var text = CleanerViewModel.displayPath(file.url)
        if let modified = file.modified {
            text += " · \(fmtRelative(modified))修改"
        }
        return text
    }
}
