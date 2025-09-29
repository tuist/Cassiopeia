import Foundation

public enum Cassiopeia {
    public static func makeRemoteCAS(
        baseURL: URL,
        session: URLSession = URLSession(configuration: .default),
        headers: [String: String] = [:]
    ) -> RemoteCAS {
        let configuration = RemoteCASConfiguration(
            baseURL: baseURL,
            session: session,
            defaultHeaders: headers
        )
        return RemoteCAS(configuration: configuration)
    }

    public static func makeRemoteCASFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = URLSession(configuration: .default),
        headers: [String: String] = [:]
    ) throws -> RemoteCAS {
        guard let value = environment["COMPILATION_CACHE_REMOTE_SERVICE_PATH"], !value.isEmpty else {
            throw CassiopeiaFactoryError.missingRemoteServicePath
        }
        guard let url = URL(string: value), url.scheme?.hasPrefix("http") == true else {
            throw CassiopeiaFactoryError.invalidRemoteServiceURL(value)
        }
        return makeRemoteCAS(baseURL: url, session: session, headers: headers)
    }
}

public enum CassiopeiaFactoryError: Error, Equatable, CustomStringConvertible {
    case missingRemoteServicePath
    case invalidRemoteServiceURL(String)

    public var description: String {
        switch self {
        case .missingRemoteServicePath:
            return "Environment variable COMPILATION_CACHE_REMOTE_SERVICE_PATH is not set"
        case .invalidRemoteServiceURL(let value):
            return "Environment variable COMPILATION_CACHE_REMOTE_SERVICE_PATH does not contain a valid HTTP URL: \(value)"
        }
    }
}
