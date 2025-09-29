import Foundation
import SWBUtil

public actor FileSystemActionCache: ActionCacheProtocol {
    public typealias DataID = DataID

    private let cachePath: URL

    public init(path: String) {
        self.cachePath = URL(fileURLWithPath: path).appendingPathComponent("action_cache")
        Task {
            await createDirectoriesIfNeeded()
        }
    }

    private func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: cachePath, withIntermediateDirectories: true, attributes: nil)
    }

    private func cacheFilePath(for keyID: DataID) -> URL {
        let prefix = String(keyID.hash.prefix(2))
        let dir = cachePath.appendingPathComponent(prefix)
        return dir.appendingPathComponent("\(keyID.hash).json")
    }

    public func cache(objectID: DataID, forKeyID key: DataID) async throws {
        let cacheFile = cacheFilePath(for: key)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        let cacheEntry = CacheEntry(objectID: objectID, timestamp: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cacheEntry)
        try data.write(to: cacheFile)
    }

    public func lookupCachedObject(for keyID: DataID) async throws -> DataID? {
        let cacheFile = cacheFilePath(for: keyID)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: cacheFile.path) else {
            return nil
        }

        let data = try Data(contentsOf: cacheFile)
        let cacheEntry = try JSONDecoder().decode(CacheEntry.self, from: data)
        return cacheEntry.objectID
    }

    public func clear() async throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: cachePath)
        createDirectoriesIfNeeded()
    }
}

private struct CacheEntry: Codable {
    let objectID: DataID
    let timestamp: Date
}