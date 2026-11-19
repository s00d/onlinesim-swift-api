#if canImport(FoundationNetworking)
    // corelibs-foundation of Swift 5.9 does not mark `URL` as `Sendable` yet.
    @preconcurrency import Foundation
#else
    import Foundation
#endif

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One HTTP request the client asks a ``Transport`` to send.
public struct TransportRequest: Sendable, Hashable {
    /// `GET` or `POST`.
    public var method: String
    /// Full URL, query included.
    public var url: URL
    /// Request headers (`Accept`, `Authorization`, `Content-Type`).
    public var headers: [String: String]
    /// JSON body of a `POST`, `nil` for `GET`.
    public var body: Data?
    /// Per-request timeout, seconds.
    public var timeout: TimeInterval

    public init(method: String, url: URL, headers: [String: String], body: Data?, timeout: TimeInterval) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// The HTTP answer a ``Transport`` returns: any status, the raw body.
public struct TransportResponse: Sendable, Hashable {
    /// HTTP status code.
    public var status: Int
    /// Raw response body.
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Sends HTTP requests for ``OnlineSimClient``.
///
/// The default is ``URLSessionTransport``. Implement it for a custom stack, a proxy, or a fake in tests
/// (``MockOnlineSim`` is one). Return every HTTP status as a ``TransportResponse``; throw only when no response
/// arrived. A thrown `URLError(.timedOut)` is reported as a request timeout.
public protocol Transport: Sendable {
    func send(_ request: TransportRequest) async throws -> TransportResponse
}

/// The default ``Transport``: `URLSession` with async/await. Pass your own session for a proxy or custom TLS.
///
/// `@unchecked Sendable`: its only stored property is an immutable `URLSession`, which is thread-safe, but
/// corelibs-foundation of older toolchains (Linux, Swift 5.9) does not mark `URLSession` as `Sendable`.
public struct URLSessionTransport: Transport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: TransportRequest) async throws -> TransportResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }

        #if canImport(FoundationNetworking)
            // corelibs-foundation: no async `data(for:)` on every supported toolchain.
            let session = self.session
            let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
                session.dataTask(with: urlRequest) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response {
                        continuation.resume(returning: (data ?? Data(), response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }.resume()
            }
        #else
            let (data, response) = try await session.data(for: urlRequest)
        #endif
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return TransportResponse(status: http.statusCode, body: data)
    }
}
