import Foundation
import SWBUtil

public actor FileSystemCAS: CASProtocol {
    public typealias Object = CASObject

    private let rootPath: URL
    private let metadataPath: URL

    public init(path: String) {
        self.rootPath = URL(fileURLWithPath: path)
        self.metadataPath = rootPath.appendingPathComponent("metadata")
        Task {
            await createDirectoriesIfNeeded()
        }
    }

    private func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: rootPath, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: metadataPath, withIntermediateDirectories: true, attributes: nil)
    }

    private func objectPath(for id: DataID) -> URL {
        let prefix = String(id.hash.prefix(2))
        let dir = rootPath.appendingPathComponent("objects").appendingPathComponent(prefix)
        return dir.appendingPathComponent(id.hash)
    }

    private func metadataFilePath(for id: DataID) -> URL {
        let prefix = String(id.hash.prefix(2))
        let dir = metadataPath.appendingPathComponent(prefix)
        return dir.appendingPathComponent("\(id.hash).json")
    }

    public func store(object: Object) async throws -> DataID {
        let id = object.id
        let objectFile = objectPath(for: id)
        let metadataFile = metadataFilePath(for: id)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: objectFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: metadataFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        if !fileManager.fileExists(atPath: objectFile.path) {
            try Data(object.data.bytes).write(to: objectFile)
        }

        let metadata = ObjectMetadata(refs: object.refs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataFile)

        return id
    }

    public func load(id: DataID) async throws -> Object? {
        let objectFile = objectPath(for: id)
        let metadataFile = metadataFilePath(for: id)

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: objectFile.path) else {
            return nil
        }

        let data = try Data(contentsOf: objectFile)
        let refs: [DataID]

        if fileManager.fileExists(atPath: metadataFile.path) {
            let metadataData = try Data(contentsOf: metadataFile)
            let metadata = try JSONDecoder().decode(ObjectMetadata.self, from: metadataData)
            refs = metadata.refs
        } else {
            refs = []
        }

        return Object(data: ByteString(data), refs: refs)
    }

    public func contains(id: DataID) async throws -> Bool {
        let objectFile = objectPath(for: id)
        return FileManager.default.fileExists(atPath: objectFile.path)
    }

    public func delete(id: DataID) async throws {
        let objectFile = objectPath(for: id)
        let metadataFile = metadataFilePath(for: id)

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: objectFile)
        try? fileManager.removeItem(at: metadataFile)
    }

    public func listObjects() async throws -> [DataID] {
        let objectsPath = rootPath.appendingPathComponent("objects")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: objectsPath.path) else {
            return []
        }

        var objects: [DataID] = []

        if let prefixDirs = try? fileManager.contentsOfDirectory(atPath: objectsPath.path) {
            for prefix in prefixDirs {
                let prefixPath = objectsPath.appendingPathComponent(prefix)
                if let files = try? fileManager.contentsOfDirectory(atPath: prefixPath.path) {
                    for file in files {
                        objects.append(DataID(hash: file))
                    }
                }
            }
        }

        return objects
    }

    public func size() async throws -> Int64 {
        let objectsPath = rootPath.appendingPathComponent("objects")
        return try calculateDirectorySize(at: objectsPath)
    }

    private func calculateDirectorySize(at url: URL) throws -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let fileAttributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(fileAttributes.fileSize ?? 0)
            }
        }

        return totalSize
    }
}

private struct ObjectMetadata: Codable {
    let refs: [DataID]
}