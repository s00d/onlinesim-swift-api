import Foundation
import XCTest

@testable import OnlineSim

final class ClientTests: XCTestCase {
    func testSendsKeyAsBearerNeverInQueryPlusLang() async throws {
        let (client, transport) = fakeClient([.json(["response": "1", "price": 0.36])])
        _ = try await client.numbers.price("vkcom", country: 44)
        let call = try await transport.last()
        XCTAssertEqual(call.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(call.headers["Accept"], "application/json")
        XCTAssertEqual(call.method, "GET")
        XCTAssertNil(call.queryAll["apikey"])
        XCTAssertEqual(call.queryAll["lang"], "en")
        XCTAssertNil(call.queryAll["dev_id"])
        XCTAssertEqual(call.timeout, 30)
    }

    func testAppliesLangDevIDAndBaseURLWithoutTrailingSlash() async throws {
        let (client, transport) = fakeClient(
            [.json(["response": "1", "price": 1])], baseURL: "https://api.test/api", lang: "ru", devID: "42")
        _ = try await client.numbers.price("vkcom")
        let call = try await transport.last()
        XCTAssertTrue(call.url.absoluteString.hasPrefix("https://api.test/api/getPrice.php?"))
        XCTAssertEqual(call.queryAll["lang"], "ru")
        XCTAssertEqual(call.queryAll["dev_id"], "42")
    }

    func testNoAuthorizationHeaderWithoutKey() async throws {
        for key in [nil, ""] as [String?] {
            let (client, transport) = fakeClient([.json(["response": "1", "price": 1])], apiKey: key)
            _ = try await client.numbers.price("vkcom")
            let call = try await transport.last()
            XCTAssertNil(call.headers["Authorization"])
        }
    }

    func testDefaultBaseURL() async throws {
        let transport = FakeTransport([.json(["response": "1", "price": 1])])
        _ = try await OnlineSimClient(apiKey: "k", transport: transport).numbers.price("vkcom")
        let call = try await transport.last()
        XCTAssertTrue(call.url.absoluteString.hasPrefix("https://onlinesim.host/api/getPrice.php?"))
    }

    func testPlusInQueryValuesIsEncoded() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "tzid": 1])])
        _ = try await client.numbers.get("google", reject: ["+4470"])
        let call = try await transport.last()
        XCTAssertTrue(call.url.absoluteString.contains("reject=%2B4470"))
        XCTAssertEqual(call.query["reject"], "+4470")
    }

    // MARK: - response handling

    func testNoNumberMapsToNoNumber() async throws {
        let (client, _) = fakeClient([.json(["response": "NO_NUMBER"]), .json(["response": "FORWARD_NOT_SUPPORTED"])])
        let error = await caught { try await client.numbers.get("google", country: 44) }
        XCTAssertEqual(
            error as? OnlineSimError,
            .noNumber(code: "NO_NUMBER", message: "No numbers available for this service right now"))
        XCTAssertEqual((error as? OnlineSimError)?.code, "NO_NUMBER")
        // only NO_NUMBER is .noNumber
        let forward = await caught { try await client.numbers.get("google") }
        XCTAssertEqual(
            forward as? OnlineSimError,
            .api(code: "FORWARD_NOT_SUPPORTED", message: "Number forwarding is no longer available"))
    }

    func testHTTP456WrongKeyIsAnAPIErrorNotTransport() async throws {
        let (client, _) = fakeClient([.json(["response": "ERROR_WRONG_KEY"], status: 456)])
        let error = await caught { try await client.user.balance() }
        XCTAssertEqual(error as? OnlineSimError, .api(code: "ERROR_WRONG_KEY", message: "Wrong or missing API key"))
    }

    func testHTTP429TryAgainLaterIsAnAPIErrorNotTransport() async throws {
        let (client, _) = fakeClient([.json(["response": "TRY_AGAIN_LATER"], status: 429)])
        let error = await caught { try await client.numbers.state() }
        XCTAssertEqual(
            error as? OnlineSimError,
            .api(code: "TRY_AGAIN_LATER", message: "Rate limit exceeded or temporary error, try again later"))
    }

    func testMissingKeyHTTP200WrongKeyIsAnAPIError() async throws {
        let (client, _) = fakeClient([.json(["response": "ERROR_WRONG_KEY"])], apiKey: nil)
        let code = await apiCode { try await client.user.balance() }
        XCTAssertEqual(code, "ERROR_WRONG_KEY")
    }

    func testPrefersServerMessageButNotWhenItEchoesTheCode() async throws {
        let (client, _) = fakeClient([
            .json(["response": "TRY_AGAIN_LATER", "message": "Maintenance until 12:00"]),
            .json(["response": "UNDEFINED_COUNTRY", "message": "UNDEFINED_COUNTRY"]),
            .json(["response": "SOMETHING_NEW"]),
        ])
        var error = await caught { try await client.numbers.get("x") }
        XCTAssertEqual(error as? OnlineSimError, .api(code: "TRY_AGAIN_LATER", message: "Maintenance until 12:00"))
        error = await caught { try await client.numbers.get("x") }
        XCTAssertEqual(error as? OnlineSimError, .api(code: "UNDEFINED_COUNTRY", message: "Unknown country"))
        error = await caught { try await client.numbers.get("x") }
        XCTAssertEqual(error as? OnlineSimError, .api(code: "SOMETHING_NEW", message: "SOMETHING_NEW"))
    }

    func testValidationObjectMapsToValidationError() async throws {
        // Field messages are joined in key order (Swift dictionaries keep no insertion order).
        let (client, _) = fakeClient([
            .json([
                "response": [
                    "webhook_url": ["The webhook url must be a valid URL.", "Too long."], "name": ["Required."],
                ]
            ])
        ])
        let error = await caught { try await client.user.setWebhookURL("nope") }
        XCTAssertEqual(
            error as? OnlineSimError,
            .api(code: "VALIDATION_ERROR", message: "Required.; The webhook url must be a valid URL.; Too long."))
    }

    func testNonJSONBodyIsTransportErrorWithStatusAndExcerpt() async throws {
        let (client, _) = fakeClient([.raw("<html>Bad gateway</html>", status: 502)])
        let error = await caught { try await client.user.balance() }
        XCTAssertEqual(
            error as? OnlineSimError,
            .transport(message: "HTTP 502: response is not JSON", status: 502, body: "<html>Bad gateway</html>"))
    }

    func testBodyExcerptIsCutTo500Characters() async throws {
        let (client, _) = fakeClient([.raw(String(repeating: "x", count: 900), status: 500)])
        let error = await caught { try await client.user.balance() }
        guard case .transport(_, 500, let body)? = error as? OnlineSimError else { return XCTFail() }
        XCTAssertEqual(body.count, 500)
    }

    func testJSONErrorStatusWithoutResponseIsTransportError() async throws {
        let (client, _) = fakeClient([.json(["error": "boom"], status: 500)])
        let error = await caught { try await client.user.balance() }
        XCTAssertEqual(
            error as? OnlineSimError, .transport(message: "HTTP 500", status: 500, body: #"{"error":"boom"}"#))
    }

    func testNetworkFailureIsTransportErrorWithoutStatus() async throws {
        let (client, _) = fakeClient([.failure(URLError(.networkConnectionLost))])
        let error = await caught { try await client.user.balance() }
        guard case .transport(let message, nil, "")? = error as? OnlineSimError else {
            return XCTFail("\(String(describing: error))")
        }
        XCTAssertTrue(message.hasPrefix("Network error: "), message)
    }

    func testRequestTimeoutIsTransportError() async throws {
        let transport = FakeTransport([.failure(URLError(.timedOut))])
        let client = OnlineSimClient(apiKey: "k", timeout: 15, transport: transport)
        let error = await caught { try await client.user.balance() }
        XCTAssertEqual(
            error as? OnlineSimError, .transport(message: "Request timed out after 15 s", status: nil, body: ""))
        let timeout = await transport.calls.first?.timeout
        XCTAssertEqual(timeout, 15)
    }

    func testUnexpectedShapeIsTransportError() async throws {
        let (client, _) = fakeClient([.json(["response": 1, "tzid": "not a number"])])
        let error = await caught { try await client.numbers.get("google") }
        guard case .transport(let message, 200, _)? = error as? OnlineSimError else { return XCTFail() }
        XCTAssertTrue(message.hasPrefix("Unexpected response from getNum.php"), message)
    }

    func testBodiesWithoutResponseAreReturnedAsIs() async throws {
        let (client, _) = fakeClient([.json([])])
        let state = try await client.numbers.state()
        XCTAssertEqual(state, [])
    }

    func testErrorDescriptions() {
        XCTAssertEqual(OnlineSimError.api("NO_COUNTRY").localizedDescription, "Country not found")
        XCTAssertEqual(OnlineSimError.api("NO_COUNTRY").description, "NO_COUNTRY: Country not found")
        XCTAssertEqual(
            OnlineSimError.waitTimeout(tzid: 7, timeout: 600).message, "No code for operation 7 within 600 s")
        XCTAssertNil(OnlineSimError.waitTimeout(tzid: 7, timeout: 1).code)
    }
}
