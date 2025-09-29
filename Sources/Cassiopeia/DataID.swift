import Foundation
import Crypto
import SWBUtil

public struct DataID: Equatable, Hashable, Sendable {
    public let hash: String

    public init(hash: String) {
        self.hash = hash
    }

    public init(from data: ByteString) {
        let digest = SHA256.hash(data: data.bytes)
        self.hash = digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    public var shortID: String {
        String(hash.prefix(12))
    }
}

extension DataID: CustomStringConvertible {
    public var description: String {
        hash
    }
}

extension DataID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.hash = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hash)
    }
}