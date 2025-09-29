import Foundation
import Testing
@testable import Cassiopeia

typealias RemoteRequestHandler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

@Suite(.serialized)
struct RemoteCASTests {
    @Test func remoteCASStoreSendsExpectedPayload() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/cas/objects")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            guard let body = bodyData(from: request),
                  let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                Issue.record("Missing JSON body in store request")
                throw RemoteCASError.invalidResponse
            }
            #expect(json["refs"] as? [String] == ["ref1"])
            if let dataString = json["data"] as? String,
               let decoded = Data(base64Encoded: dataString) {
                #expect(String(decoding: decoded, as: UTF8.self) == "hello")
            } else {
                Issue.record("Unexpected data payload in store request")
            }
            let responseData = try JSONSerialization.data(withJSONObject: ["id": "stored-id"])
            return (MockURLProtocol.makeResponse(for: request.url!, status: 201), responseData)
        }

        let cas = makeTestCAS()
        let object = CASObject(string: "hello", refs: [DataID(hash: "ref1")])
        let id = try await cas.store(object: object)
        #expect(id.hash == "stored-id")
    }

    @Test func remoteCASLoadAndContains() async throws {
        MockURLProtocol.reset()
        let storedData = Data("cached".utf8).base64EncodedString()
        let objectResponse = try JSONSerialization.data(withJSONObject: [
            "data": storedData,
            "refs": [String]()
        ])

        MockURLProtocol.enqueue { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/cas/objects/object-id")
            return (MockURLProtocol.makeResponse(for: request.url!, status: 200), objectResponse)
        }

        MockURLProtocol.enqueue { request in
            #expect(request.httpMethod == "HEAD")
            #expect(request.url?.path == "/api/cas/objects/object-id")
            return (MockURLProtocol.makeResponse(for: request.url!, status: 200), Data())
        }

        let cas = makeTestCAS()
        let id = DataID(hash: "object-id")
        let loaded = try await cas.load(id: id)
        #expect(loaded != nil)
        #expect(loaded?.data.stringValue == "cached")

        let exists = try await cas.contains(id: id)
        #expect(exists)
    }

    @Test func remoteCASActionCacheRoundTrip() async throws {
        MockURLProtocol.reset()

        MockURLProtocol.enqueue { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/api/cas/action-cache/key-id")
            return (MockURLProtocol.makeResponse(for: request.url!, status: 204), Data())
        }

        let responsePayload = try JSONSerialization.data(withJSONObject: ["object_id": "value-id"])

        MockURLProtocol.enqueue { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/cas/action-cache/key-id")
            return (MockURLProtocol.makeResponse(for: request.url!, status: 200), responsePayload)
        }

        let cas = makeTestCAS()
        let key = DataID(hash: "key-id")
        let value = DataID(hash: "value-id")

        try await cas.cache(objectID: value, forKeyID: key)
        let cached = try await cas.lookupCachedObject(for: key)
        #expect(cached?.hash == value.hash)
    }

    @Test func cassiopeiaFactoryReadsEnvironment() async throws {
        let env = ["COMPILATION_CACHE_REMOTE_SERVICE_PATH": "https://example.com/api"]
        let cas = try Cassiopeia.makeRemoteCASFromEnvironment(environment: env)
        _ = cas

        #expect(throws: CassiopeiaFactoryError.missingRemoteServicePath) {
            _ = try Cassiopeia.makeRemoteCASFromEnvironment(environment: [:])
        }

        #expect(throws: CassiopeiaFactoryError.invalidRemoteServiceURL("not-a-url")) {
            _ = try Cassiopeia.makeRemoteCASFromEnvironment(environment: ["COMPILATION_CACHE_REMOTE_SERVICE_PATH": "not-a-url"])
        }
    }
}

// MARK: - Test Utilities

private func makeTestCAS() -> RemoteCAS {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return RemoteCAS(configuration: RemoteCASConfiguration(
        baseURL: URL(string: "https://example.com/api")!,
        session: session
    ))
}

private func bodyData(from request: URLRequest) -> Data? {
    if let data = request.httpBody {
        return data
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }

    var data = Data()
    let chunkSize = 1024
    var buffer = [UInt8](repeating: 0, count: chunkSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: chunkSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

final class MockURLProtocol: URLProtocol {
    private static let handlers = Locked<[RemoteRequestHandler]>([])

    static func enqueue(_ handler: @escaping RemoteRequestHandler) {
        handlers.with { $0.append(handler) }
    }

    static func reset() {
        handlers.with { $0.removeAll() }
    }

    private static func dequeue() -> RemoteRequestHandler? {
        handlers.with { storage in
            guard !storage.isEmpty else { return nil }
            return storage.removeFirst()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.dequeue() else {
            Issue.record("No handler registered for request: \(request)")
            client?.urlProtocol(self, didFailWithError: RemoteCASError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeResponse(for url: URL, status: Int, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func with<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(&value)
    }
}
