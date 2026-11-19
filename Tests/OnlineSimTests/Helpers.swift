import Foundation
import XCTest

@testable import OnlineSim

/// A canned answer of the fake transport.
enum Reply: Sendable {
    case json(JSONValue, status: Int = 200)
    case data(Data, status: Int = 200)
    case raw(String, status: Int)
    case failure(URLError)
}

/// Transport that answers `replies` in order and records every request. An actor: its state has one owner.
actor FakeTransport: Transport {
    private var replies: [Reply]
    private(set) var calls: [TransportRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        calls.append(request)
        guard !replies.isEmpty else { throw URLError(.unsupportedURL) }
        switch replies.removeFirst() {
        case .json(let value, let status):
            return TransportResponse(status: status, body: try JSONEncoder().encode(value))
        case .data(let data, let status): return TransportResponse(status: status, body: data)
        case .raw(let text, let status): return TransportResponse(status: status, body: Data(text.utf8))
        case .failure(let error): throw error
        }
    }

    /// The only call made; throws when there were more or none.
    func last() throws -> TransportRequest {
        guard calls.count == 1, let call = calls.last else {
            throw URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: "expected 1 request, got \(calls.count)"])
        }
        return call
    }
}

func fakeClient(
    _ replies: [Reply], apiKey: String? = "test-key", baseURL: String = "https://api.test/api/", lang: String = "en",
    devID: String? = nil
) -> (OnlineSimClient, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = OnlineSimClient(
        apiKey: apiKey, baseURL: URL(string: baseURL)!, lang: lang, devID: devID, transport: transport)
    return (client, transport)
}

func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

extension TransportRequest {
    var path: String { url.path }

    /// Query without the `lang` every request carries.
    var query: [String: String] {
        var items = queryAll
        items["lang"] = nil
        return items
    }

    var queryAll: [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, b in b })
    }

    var json: JSONValue? { body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } }
}

/// The error `body` throws, `nil` (and a test failure) when it does not throw.
func caught<T>(
    _ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line
) async -> Error? {
    do {
        _ = try await body()
        XCTFail("expected an error", file: file, line: line)
        return nil
    } catch {
        return error
    }
}

/// The API error code `body` throws.
func apiCode<T>(_ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async -> String? {
    (await caught(body, file: file, line: line) as? OnlineSimError)?.code
}
