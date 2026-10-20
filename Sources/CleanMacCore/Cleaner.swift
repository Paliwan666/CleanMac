import Foundation

public enum Cleaner {
    public struct TrashResult {
        public var trashed: [URL] = []
        public var failures: [(url: URL, message: String)] = []
        public init() {}
    }

    /// 移到废纸篓（可在 Finder 中恢复）
    public static func trash(_ urls: [URL]) -> TrashResult {
        var result = TrashResult()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.trashed.append(url)
            } catch {
                result.failures.append((url, error.localizedDescription))
            }
        }
        return result
    }
}
