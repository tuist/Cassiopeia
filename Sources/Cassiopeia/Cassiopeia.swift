import Foundation
import SWBUtil

public enum Cassiopeia {
    public static func createFileSystemCAS(at path: String) -> FileSystemCAS {
        FileSystemCAS(path: path)
    }

    public static func createFileSystemActionCache(at path: String) -> FileSystemActionCache {
        FileSystemActionCache(path: path)
    }
}