import CleanMacCore
import Foundation

// CLT 无 XCTest，用轻量断言自测：任一断言失败即退出码 1
var failures = 0
func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS \(label)")
    } else {
        print("FAIL \(label)")
        failures += 1
    }
}

// containsBundleID
expect(Scanner.containsBundleID("com.foo.bar", "com.foo.bar"), "bid exact")
expect(Scanner.containsBundleID("com.foo.bar.plist", "com.foo.bar"), "bid plist ext")
expect(Scanner.containsBundleID("com.foo.bar.helper", "com.foo.bar"), "bid suffix")
expect(Scanner.containsBundleID("group.com.foo.bar", "com.foo.bar"), "bid group prefix")
expect(Scanner.containsBundleID("ABCDE12345.com.foo.bar", "com.foo.bar"), "bid team prefix")
expect(Scanner.containsBundleID("com.foo.bar.savedState", "com.foo.bar"), "bid savedState")
expect(!Scanner.containsBundleID("com.foo.barbaz", "com.foo.bar"), "bid no fuzzy")
expect(!Scanner.containsBundleID("com.other.thing", "com.foo.bar"), "bid unrelated")

// isProtected
expect(Scanner.isProtected("com.apple.Safari"), "protect apple")
expect(Scanner.isProtected("group.com.apple.notes"), "protect apple group")
expect(Scanner.isProtected("com.google.Keystone.Agent"), "protect keystone")
expect(!Scanner.isProtected("com.tencent.xinWeChat"), "no protect wechat")

// looksLikeBundleID
expect(Scanner.looksLikeBundleID("com.foo.bar"), "rdns basic")
expect(Scanner.looksLikeBundleID("com.foo.bar.plist"), "rdns plist")
expect(Scanner.looksLikeBundleID("group.com.foo.bar"), "rdns group")
expect(!Scanner.looksLikeBundleID("Code"), "rdns reject name")
expect(!Scanner.looksLikeBundleID("Google Chrome"), "rdns reject space")
expect(!Scanner.looksLikeBundleID("loginwindow"), "rdns reject single")

// name matching
let loc = Scanner.SearchLocation(path: "Library/Caches", category: "缓存", matchByName: true)
expect(Scanner.matches("foobar", location: loc, appName: "FooBar", bundleID: "com.none.x"), "name exact")
expect(!Scanner.matches("foo", location: loc, appName: "Foo", bundleID: "com.none.x"), "name too short")
expect(!Scanner.matches("Foobarista", location: loc, appName: "FooBar", bundleID: "com.none.x"), "name no fuzzy")

// 集成：临时目录里的关联文件 + 残留
func integrationTest() {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: home) }

    let dirs = [
        "Library/Application Support/FooBar",
        "Library/Application Support/Code",
        "Library/Caches/com.foo.bar",
        "Library/Caches/com.foo.helper",
        "Library/Caches/com.old.gone",
        "Library/Containers/com.foo.bar",
        "Library/Group Containers/group.com.foo.bar",
        "Library/Preferences",
    ]
    do {
        for d in dirs {
            try fm.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try "x".write(to: home.appendingPathComponent("Library/Preferences/com.foo.bar.plist"), atomically: true, encoding: .utf8)
        try "x".write(to: home.appendingPathComponent("Library/Preferences/com.apple.test.plist"), atomically: true, encoding: .utf8)
    } catch {
        expect(false, "integration setup: \(error.localizedDescription)")
        return
    }

    let app = InstalledApp(
        url: URL(fileURLWithPath: "/Applications/FooBar.app"),
        name: "FooBar",
        bundleID: "com.foo.bar",
        version: "1.0"
    )
    let files = Scanner.findRelatedFiles(for: app, home: home)
    let paths = files.map { $0.url.path }
    expect(paths.contains { $0.contains("Application Support/FooBar") }, "related app support")
    expect(paths.contains { $0.contains("Caches/com.foo.bar") }, "related caches")
    expect(paths.contains { $0.contains("com.foo.bar.plist") }, "related plist")
    expect(paths.contains { $0.contains("Containers/com.foo.bar") }, "related container")
    expect(paths.contains { $0.contains("Group Containers/group.com.foo.bar") }, "related group container")
    expect(!paths.contains { $0.contains("Application Support/Code") }, "related no other app")
    expect(!paths.contains { $0.contains("com.apple.test") }, "related no apple")

    let leftovers = Scanner.scanLeftovers(home: home, installedBundleIDs: ["com.foo.bar"])
    let leftoverPaths = leftovers.flatMap(\.items).map { $0.url.path }
    expect(leftoverPaths.contains { $0.contains("com.old.gone") }, "leftover found")
    expect(!leftoverPaths.contains { $0.contains("com.foo.bar") }, "leftover no installed")
    expect(!leftoverPaths.contains { $0.contains("com.foo.helper") }, "leftover no same-company helper")
    expect(!leftoverPaths.contains { $0.contains("com.apple") }, "leftover no apple")
}
integrationTest()

// 真机扫描探针：--real 扫描本机，验证深度扫描效果和误判率
if CommandLine.arguments.contains("--real") {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let apps = Scanner.scanInstalledApps(home: home)
    print("== 已安装应用: \(apps.count)")
    var withFiles = 0
    var totalFiles = 0
    var totalSize: Int64 = 0
    var samples: [String] = []
    for app in apps {
        let files = Scanner.findRelatedFiles(for: app, home: home)
        if !files.isEmpty {
            withFiles += 1
            if samples.count < 6 {
                samples.append("\(app.name) [\(app.bundleID)]: \(files.count) 个关联文件")
                samples += files.prefix(4).map { "    \($0.category) \($0.url.path)" }
            }
        }
        totalFiles += files.count
        totalSize += files.reduce(Int64(0)) { $0 + $1.size }
    }
    print("== 有关联文件的应用: \(withFiles)，关联文件总数: \(totalFiles)，总大小: \(totalSize / 1024 / 1024) MB")
    print(samples.joined(separator: "\n"))
    let groups = Scanner.scanLeftovers(home: home, installedBundleIDs: Set(apps.map(\.bundleID)))
    print("== 残留分组: \(groups.count)，残留总数: \(groups.reduce(0) { $0 + $1.items.count })")
    for g in groups {
        print("  [\(g.category)] \(g.items.count) 项, \(g.totalSize / 1024) KB")
        for item in g.items.prefix(6) {
            print("    \(item.url.path)")
        }
    }
    exit(0)
}

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
