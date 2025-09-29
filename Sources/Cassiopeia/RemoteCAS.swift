import Foundation
import SWBUtil

public struct RemoteCASConfiguration: Sendable {
    public let baseURL: URL
    public let session: URLSession
    public let defaultHeaders: [String: String]

    public init(
        baseURL: URL,
        session: URLSession = URLSession(configuration: .default),
        defaultHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.session = session
        self.defaultHeaders = defaultHeaders
    }
}

public enum RemoteCASError: Error, CustomStringConvertible {
    case invalidURL(String)
    case invalidResponse
    case decodingFailed
    case encodingFailed
    case serverError(status: Int, message: String?)
    case transportError(Error)

    public var description: String {
        switch self {
        case .invalidURL(let string):
            return "Invalid URL: \(string)"
        case .invalidResponse:
            return "Unexpected response from remote CAS"
        case .decodingFailed:
            return "Failed to decode remote CAS response"
        case .encodingFailed:
            return "Failed to encode request payload"
        case .serverError(let status, let message):
            if let message {
                return "Remote CAS responded with status \(status): \(message)"
            }
            return "Remote CAS responded with status \(status)"
        case .transportError(let error):
            return "Transport error while communicating with remote CAS: \(error)"
        }
    }
}

public actor RemoteCAS: CASProtocol, ActionCacheProtocol {
    public typealias Object = CASObject
    public typealias DataID = Object.DataID

    private let configuration: RemoteCASConfiguration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: RemoteCASConfiguration) {
        self.configuration = configuration
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    // MARK: - CASProtocol

    public func store(object: CASObject) async throws -> DataID {
        let payload = StoreObjectPayload(
            data: Data(object.data.bytes).base64EncodedString(),
            refs: object.refs.map(\.hash)
        )
        let data = try encodePayload(payload)
        let request = try makeRequest(
            method: "POST",
            path: "cas/objects",
            body: data,
            additionalHeaders: ["Content-Type": "application/json"]
        )
        let (responseData, response) = try await perform(request)
        try ensureSuccess(response, allowed: [200, 201])
        let decoded: StoreObjectResponse = try decode(responseData)
        return DataID(hash: decoded.id)
    }

    public func load(id: DataID) async throws -> CASObject? {
        let request = try makeRequest(method: "GET", path: "cas/objects/\(id.hash)")
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            let payload: ObjectPayload = try decode(data)
            guard let decodedData = Data(base64Encoded: payload.data) else {
                throw RemoteCASError.decodingFailed
            }
            let refs = payload.refs.map { DataID(hash: $0) }
            return CASObject(data: ByteString(decodedData), refs: refs)
        case 404:
            return nil
        default:
            throw RemoteCASError.serverError(status: response.statusCode, message: errorMessage(from: data))
        }
    }

    public func contains(id: DataID) async throws -> Bool {
        let request = try makeRequest(method: "HEAD", path: "cas/objects/\(id.hash)")
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            return true
        case 404:
            return false
        default:
            throw RemoteCASError.serverError(status: response.statusCode, message: nil)
        }
    }

    public func delete(id: DataID) async throws {
        let request = try makeRequest(method: "DELETE", path: "cas/objects/\(id.hash)")
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200, 204:
            return
        case 404:
            return
        default:
            throw RemoteCASError.serverError(status: response.statusCode, message: errorMessage(from: data))
        }
    }

    // MARK: - ActionCacheProtocol

    public func cache(objectID: DataID, forKeyID key: DataID) async throws {
        let payload = CacheValuePayload(objectID: objectID.hash)
        let body = try encodePayload(payload)
        let request = try makeRequest(
            method: "PUT",
            path: "cas/action-cache/\(key.hash)",
            body: body,
            additionalHeaders: ["Content-Type": "application/json"]
        )
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200, 204:
            return
        default:
            throw RemoteCASError.serverError(status: response.statusCode, message: errorMessage(from: data))
        }
    }

    public func lookupCachedObject(for keyID: DataID) async throws -> DataID? {
        let request = try makeRequest(method: "GET", path: "cas/action-cache/\(keyID.hash)")
        let (data, response) = try await perform(request)
        switch response.statusCode {
        case 200:
            let payload: CacheValuePayload = try decode(data)
            return DataID(hash: payload.objectID)
        case 404:
            return nil
        default:
            throw RemoteCASError.serverError(status: response.statusCode, message: errorMessage(from: data))
        }
    }

    // MARK: - Private helpers

    private func makeRequest(
        method: String,
        path: String,
        body: Data? = nil,
        additionalHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw RemoteCASError.invalidURL(configuration.baseURL.absoluteString)
        }
        var sanitizedPath = components.path
        if !sanitizedPath.hasSuffix("/") {
            sanitizedPath += "/"
        }
        sanitizedPath += path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = sanitizedPath
        guard let url = components.url else {
            throw RemoteCASError.invalidURL("\(configuration.baseURL.absoluteString)/\(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
        }
        let headers = configuration.defaultHeaders.merging(additionalHeaders) { _, new in new }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await configuration.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RemoteCASError.invalidResponse
            }
            return (data, http)
        } catch {
            throw RemoteCASError.transportError(error)
        }
    }

    private func ensureSuccess(_ response: HTTPURLResponse, allowed: [Int]) throws {
        guard allowed.contains(response.statusCode) else {
            throw RemoteCASError.serverError(status: response.statusCode, message: nil)
        }
    }

    private func encodePayload<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw RemoteCASError.encodingFailed
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RemoteCASError.decodingFailed
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct StoreObjectPayload: Codable {
    let data: String
    let refs: [String]
}

private struct StoreObjectResponse: Codable {
    let id: String
}

private struct ObjectPayload: Codable {
    let data: String
    let refs: [String]
}

private struct CacheValuePayload: Codable {
    let objectID: String

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
    }
}
