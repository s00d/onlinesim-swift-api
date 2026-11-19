#if canImport(FoundationNetworking)
    // corelibs-foundation of Swift 5.9 does not mark `URL` as `Sendable` yet.
    @preconcurrency import Foundation
#else
    import Foundation
#endif

/// OnlineSim API client.
///
/// ```swift
/// let client = OnlineSimClient(apiKey: "your-api-key")
/// let balance = try await client.user.balance()
/// ```
///
/// Immutable and `Sendable`: share one client between tasks.
public struct OnlineSimClient: Sendable {
    /// `https://onlinesim.host/api/`.
    public static let defaultBaseURL = URL(string: "https://onlinesim.host/api/")!

    /// Numbers for receiving SMS.
    public let numbers: NumbersAPI
    /// Rented numbers.
    public let rent: RentAPI
    /// Account: balance, profile, payments, webhook URL.
    public let user: UserAPI
    /// Public free numbers. No key needed.
    public let free: FreeAPI

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - apiKey: Sent as `Authorization: Bearer <apiKey>`, never in the URL. Not needed for tariffs and free
    ///     numbers. `nil` or empty: no header.
    ///   - baseURL: API base; trailing slash optional.
    ///   - lang: Language of server texts (`lang` query parameter).
    ///   - devID: Partner developer id (`dev_id` query parameter), sent only when set.
    ///   - timeout: Per-request timeout, seconds.
    ///   - transport: Sends the HTTP requests. Default: ``URLSessionTransport`` on `URLSession.shared`.
    public init(
        apiKey: String? = nil,
        baseURL: URL = OnlineSimClient.defaultBaseURL,
        lang: String = "en",
        devID: String? = nil,
        timeout: TimeInterval = 30,
        transport: any Transport = URLSessionTransport()
    ) {
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL : URL(string: baseURL.absoluteString + "/")!
        let requester = Requester(
            apiKey: apiKey.flatMap { $0.isEmpty ? nil : $0 },
            baseURL: base,
            lang: lang,
            devID: devID.flatMap { $0.isEmpty ? nil : $0 },
            timeout: timeout,
            transport: transport
        )
        numbers = NumbersAPI(requester: requester)
        rent = RentAPI(requester: requester)
        user = UserAPI(requester: requester)
        free = FreeAPI(requester: requester)
    }
}

/// Query parameters in order; `nil` values are omitted.
typealias Query = [(String, String?)]

/// `1`/`0`, as the API expects booleans.
func flag(_ value: Bool) -> String { value ? "1" : "0" }

/// The one request function every section calls: builds the request, sends it, maps errors, decodes the answer.
struct Requester: Sendable {
    static let bodyExcerpt = 500

    let apiKey: String?
    let baseURL: URL
    let lang: String
    let devID: String?
    let timeout: TimeInterval
    let transport: any Transport

    /// Sends the request and decodes the answer as `T` (the `response` field, if any, is ignored by the decoder).
    func call<T: Decodable>(_ endpoint: String, query: Query = [], body: JSONValue? = nil) async throws -> T {
        try await call(T.self, endpoint, query: query, body: body)
    }

    /// ``call(_:query:body:)`` with the answer type spelled out.
    func call<T: Decodable>(_ type: T.Type, _ endpoint: String, query: Query = [], body: JSONValue? = nil)
        async throws -> T
    {
        let (data, status) = try await send(endpoint, query: query, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw OnlineSimError.transport(
                message: "Unexpected response from \(endpoint): \(error)", status: status, body: excerpt(data))
        }
    }

    /// Sends the request; returns the body once it passed the error checks.
    @discardableResult
    func send(_ endpoint: String, query: Query = [], body: JSONValue? = nil) async throws -> (Data, Int) {
        let request = try build(endpoint, query: query, body: body)
        let response: TransportResponse
        do {
            response = try await transport.send(request)
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw OnlineSimError.transport(
                message: "Request timed out after \(seconds(timeout))", status: nil, body: "")
        } catch {
            throw OnlineSimError.transport(
                message: "Network error: \(error.localizedDescription)", status: nil, body: "")
        }
        try Self.check(response.body, status: response.status)
        return (response.body, response.status)
    }

    func build(_ endpoint: String, query: Query, body: JSONValue?) throws -> TransportRequest {
        guard let url = URL(string: endpoint, relativeTo: baseURL)?.absoluteURL,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw OnlineSimError.transport(message: "Invalid URL for \(endpoint)", status: nil, body: "")
        }
        let items = (query + [("lang", lang), ("dev_id", devID)]).compactMap { name, value in
            value.flatMap { $0.isEmpty ? nil : URLQueryItem(name: name, value: $0) }
        }
        components.queryItems = items.isEmpty ? nil : items
        // URLComponents leaves `+` as is, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let full = components.url else {
            throw OnlineSimError.transport(message: "Invalid URL for \(endpoint)", status: nil, body: "")
        }

        var headers = ["Accept": "application/json"]
        if let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }
        var data: Data?
        if let body {
            headers["Content-Type"] = "application/json"
            data = try JSONEncoder().encode(body)
        }
        return TransportRequest(
            method: body == nil ? "GET" : "POST", url: full, headers: headers, body: data, timeout: timeout)
    }

    /// Response handling shared by every call. The JSON body is checked before the HTTP status:
    /// a wrong key is HTTP 456 with `{"response":"ERROR_WRONG_KEY"}`, an ``OnlineSimError/api(code:message:)``.
    static func check(_ data: Data, status: Int) throws {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw OnlineSimError.transport(
                message: "HTTP \(status): response is not JSON", status: status, body: excerpt(data))
        }
        if case .object(let object) = json, let response = object["response"] {
            switch response {
            case .int(1), .string("1"):
                return
            case .object(let fields):
                // profile.php validation errors: {"response":{"webhook_url":["The webhook url must be a valid URL."]}}
                let messages = fields.keys.sorted().flatMap { key -> [String] in
                    switch fields[key] {
                    case .array(let list)?: return list.map(text)
                    case let value?: return [text(value)]
                    case nil: return []
                    }
                }
                throw OnlineSimError.api("VALIDATION_ERROR", message: messages.joined(separator: "; "))
            default:
                let code = text(response)
                // Debug backends echo the code as `message`; prefer the readable fallback then.
                let message = object["message"]?.stringValue.flatMap { $0 == code ? nil : $0 }
                throw OnlineSimError.api(code, message: message)
            }
        }
        guard (200..<300).contains(status) else {
            throw OnlineSimError.transport(message: "HTTP \(status)", status: status, body: excerpt(data))
        }
    }
}

/// The first 500 characters of a body.
func excerpt(_ data: Data) -> String {
    String(String(decoding: data, as: UTF8.self).prefix(Requester.bodyExcerpt))
}

/// A JSON scalar as text: strings as they are, numbers and booleans in their JSON form.
private func text(_ value: JSONValue) -> String {
    switch value {
    case .string(let s): return s
    case .int(let i): return String(i)
    case .double(let d): return String(d)
    case .bool(let b): return String(b)
    case .null: return "null"
    case .array, .object:
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
