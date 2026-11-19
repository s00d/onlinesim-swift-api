// Opt-in integration test against a LOCAL backend. Skipped unless both are set:
//   ONLINESIM_IT_BASE=https://on.test/api/  ONLINESIM_IT_KEY=<apikey>
// With ONLINESIM_IT_MOCK=1 it also runs the number lifecycle on the provider-free `test` driver
// (`spec/verify/backend_mock.php setup` first, a key of a user without webhook_url, teardown after).
import Foundation
import XCTest

@testable import OnlineSim

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class IntegrationTests: XCTestCase {
    private struct Env {
        let base: URL
        let key: String
        let mock: Bool
    }

    private func env() throws -> Env {
        let vars = ProcessInfo.processInfo.environment
        guard let base = vars["ONLINESIM_IT_BASE"].flatMap(URL.init(string:)), let key = vars["ONLINESIM_IT_KEY"],
            !key.isEmpty
        else { throw XCTSkip("ONLINESIM_IT_BASE / ONLINESIM_IT_KEY not set") }
        let host = base.host ?? ""
        guard host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".test") || host.hasSuffix(".localhost")
        else { throw XCTSkip("refusing non-local integration host \(host)") }
        return Env(base: base, key: key, mock: vars["ONLINESIM_IT_MOCK"] == "1")
    }

    private func client(_ env: Env, key: String? = nil) -> OnlineSimClient {
        OnlineSimClient(apiKey: key ?? env.key, baseURL: env.base, transport: insecureTransport)
    }

    func testReadOnly() async throws {
        let env = try env()
        let client = client(env)

        let balance = try await client.user.balance()
        XCTAssertGreaterThanOrEqual(balance.balance, balance.zbalance)
        let profile = try await client.user.profile()
        XCTAssertGreaterThan(profile.id, 0)
        let uk = try await client.numbers.tariffsOne(country: 44)
        XCTAssertEqual(uk.code, 44)
        _ = try await client.numbers.state()
        let ru = try await client.rent.tariffsOne(country: 7)
        XCTAssertEqual(ru.code, 7)
        for rent in try await client.rent.state() { XCTAssertGreaterThan(rent.tzid, 0) }
        _ = try await client.user.paymentHistory()
        _ = try await client.user.webhookLogs()
        _ = try await client.free.list()

        let code = await apiCode { try await self.client(env, key: "wrong-key").user.balance() }
        XCTAssertEqual(code, "ERROR_WRONG_KEY")
    }

    func testNumberLifecycleOnTheTestDriver() async throws {
        let env = try env()
        guard env.mock else { throw XCTSkip("ONLINESIM_IT_MOCK=1 not set") }
        let client = client(env)
        let (country, service) = (44, "google")

        let price = try await client.numbers.price(service, country: country)
        XCTAssertNotNil(price)
        let tzid = try await client.numbers.get(service, country: country)
        let order = try await client.numbers.getWithNumber(service, country: country)
        XCTAssertTrue(order.number.hasPrefix("+44") || order.number.hasPrefix("44"), order.number)
        XCTAssertEqual(order.country, country)

        let ids = try await client.numbers.state().map(\.tzid)
        XCTAssertTrue(ids.contains(tzid) && ids.contains(order.tzid))
        let one = try await client.numbers.stateOne(tzid)
        XCTAssertTrue(one.response.rawValue.hasPrefix("TZ_"))

        // The test driver answers NO_NUMBER to any reject list: proves `reject` is sent.
        let rejected = await caught { try await client.numbers.get(service, country: country, reject: ["4470"]) }
        guard case .noNumber? = rejected as? OnlineSimError else { return XCTFail("\(String(describing: rejected))") }

        // No SMS yet: the guard interval keeps it open.
        let early = await apiCode { try await client.numbers.close(order.tzid) }
        XCTAssertEqual(early, "NO_COMPLETE_TZID")

        // Inject an SMS through the test driver callback (local backends only, no auth).
        let inject = TransportRequest(
            method: "POST", url: URL(string: "sms_in_getaways/test", relativeTo: env.base)!.absoluteURL,
            headers: ["Content-Type": "application/json", "Accept": "application/json"],
            body: try JSONEncoder().encode(
                ["id": .int(tzid), "phoneFrom": "VK", "text": "VK: 195895 is your code"] as JSONValue),
            timeout: 30)
        let injected = try await insecureTransport.send(inject)
        XCTAssertEqual(injected.status, 200)
        let code = try await client.numbers.waitCode(tzid, interval: 1, timeout: 30)
        XCTAssertEqual(code, "195895")

        try await client.user.setWebhookURL("https://example.com/hook")
        var profile = try await client.user.profile()
        XCTAssertEqual(profile.webhookURL, "https://example.com/hook")
        let invalid = await apiCode { try await client.user.setWebhookURL("not a url") }
        XCTAssertEqual(invalid, "VALIDATION_ERROR")
        try await client.user.clearWebhookURL()
        profile = try await client.user.profile()
        XCTAssertNil(profile.webhookURL)
    }
}

/// Test-only transport: local backends use a self-signed certificate. Not part of the SDK API.
/// On Linux (no `SecTrust`) it is the default transport, so the local certificate must be trusted there.
private let insecureTransport: any Transport = {
    #if canImport(Security)
        URLSessionTransport(
            session: URLSession(configuration: .ephemeral, delegate: TrustAllDelegate(), delegateQueue: nil))
    #else
        URLSessionTransport()
    #endif
}()

#if canImport(Security)
    private final class TrustAllDelegate: NSObject, URLSessionDelegate, Sendable {
        func urlSession(
            _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
#endif
