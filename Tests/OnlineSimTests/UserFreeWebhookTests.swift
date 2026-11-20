import Foundation
import XCTest

@testable import OnlineSim

final class UserTests: XCTestCase {
    func testBalanceSendsIncomeAndParsesDecimalString() async throws {
        let (client, transport) = fakeClient([.data(try fixture("getBalance"))])
        let balance = try await client.user.balance()
        XCTAssertEqual(balance, Balance(balance: 1442.33, zbalance: 1023.41, income: 9.78))
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getBalance.php")
        XCTAssertEqual(call.query, ["income": "1"])
    }

    func testBalanceWithoutIncome() async throws {
        let (client, _) = fakeClient([.json(["response": "1", "balance": "0.000", "zbalance": 0])])
        let balance = try await client.user.balance()
        XCTAssertEqual(balance, Balance(balance: 0, zbalance: 0))
    }

    func testProfile() async throws {
        let (client, transport) = fakeClient([.data(try fixture("getProfile"))])
        let profile = try await client.user.profile()
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getProfile.php")
        XCTAssertEqual(profile.id, 1)
        XCTAssertEqual(profile.webhookURL, "https://example.com/hook")
        XCTAssertEqual(profile.numberReject, ["333"])
        XCTAssertEqual(profile.apiAccess, .bool(true))
        XCTAssertEqual(profile.numberCountry, 1)
    }

    func testProfileDecodesNumberAsIntAndCountryAsString() async throws {
        let (client, _) = fakeClient([
            .json(["response": "1", "profile": ["id": 1, "number": 79_001_234_567, "country": "RU"]]),
            .json(["response": "1", "profile": ["id": 1, "number": nil, "country": nil]]),
        ])
        let profile = try await client.user.profile()
        XCTAssertEqual(profile.number, 79_001_234_567)
        XCTAssertEqual(profile.country, "RU")
        let empty = try await client.user.profile()
        XCTAssertNil(empty.number)
        XCTAssertNil(empty.country)
    }

    func testPaymentHistoryKeepsAnArrayPaylistAndNullableOrderFields() async throws {
        guard case .object(var body) = try JSONDecoder().decode(JSONValue.self, from: try fixture("getPaymentHistory")),
            case .object(var orders)? = body["orders"]
        else { throw URLError(.cannotDecodeContentData) }
        orders["data"] = [
            [
                "id": 1, "sum": "10.00", "currency": nil, "form_text": nil, "stat": 0,
                "created_at": "2026-06-14 09:12:12",
            ]
        ]
        body["orders"] = .object(orders)
        body["paylist"] = [["id": 0, "name": "Card"], ["id": 1, "name": "Crypto"]]
        let (client, _) = fakeClient([.json(.object(body))])
        let history = try await client.user.paymentHistory()
        XCTAssertEqual(history.paylist, ["0": ["id": 0, "name": "Card"], "1": ["id": 1, "name": "Crypto"]])
        let order = try XCTUnwrap(history.orders.data.first)
        XCTAssertNil(order.currency)
        XCTAssertNil(order.formText)
        XCTAssertEqual(order.sum, "10.00")
    }

    func testPaymentHistoryNormalisesEmptyPaylist() async throws {
        let (client, transport) = fakeClient([.data(try fixture("getPaymentHistory"))])
        let history = try await client.user.paymentHistory(page: 2)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getPaymentHistory.php")
        XCTAssertEqual(call.query, ["page": "2"])
        XCTAssertEqual(history.paylist, [:])
        XCTAssertEqual(history.orders.data.first?.id, 9462)
        XCTAssertEqual(history.orders.data.first?.sum, "89.00")
        XCTAssertEqual(history.orders.total, 106)
        XCTAssertEqual(history.currency, ["USD": 1])
    }

    func testSetWebhookURLPostsJSON() async throws {
        let (client, transport) = fakeClient([.json(["response": "1", "user": ["id": 2]])])
        try await client.user.setWebhookURL("https://example.com/hook")
        let call = try await transport.last()
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.path, "/api/profile.php")
        XCTAssertEqual(call.headers["Content-Type"], "application/json")
        XCTAssertEqual(call.headers["Authorization"], "Bearer test-key")
        XCTAssertEqual(call.json, ["profile": ["webhook_url": "https://example.com/hook"]])
    }

    func testClearWebhookURLPostsNull() async throws {
        let (client, transport) = fakeClient([.json(["response": "1", "user": ["id": 2]])])
        try await client.user.clearWebhookURL()
        let call = try await transport.last()
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.json, ["profile": ["webhook_url": nil]])
    }

    func testWebhookLogsReturnsThePaginator() async throws {
        let page: JSONValue = [
            "current_page": 1,
            "data": [
                [
                    "id": 7, "user_id": 2, "webhook_url": "https://example.com/hook", "type": "receiving_sms",
                    "params": ["webhook_type": "receiving_sms", "operation_id": 1520, "code": "195895"],
                    "status": "success", "error": nil, "created_at": "2026-11-19 10:00:01",
                    "updated_at": "2026-11-19 10:00:01",
                ]
            ],
            "from": 1, "to": 1, "last_page": 1, "per_page": 10, "total": 1,
        ]
        let (client, transport) = fakeClient([.json(["response": "1", "data": page])])
        let logs = try await client.user.webhookLogs()
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/webhook-logs")
        XCTAssertEqual(call.query, ["page": "1"])
        XCTAssertEqual(logs.total, 1)
        XCTAssertEqual(logs.data.first?.type, .receivingSms)
        XCTAssertEqual(logs.data.first?.params.operationID, 1520)
        XCTAssertEqual(logs.data.first?.params.code, "195895")
        XCTAssertNil(logs.data.first?.error)
    }
}

final class FreeTests: XCTestCase {
    func testListNoPhpSuffixOnlyTheSetParameters() async throws {
        let (client, transport) = fakeClient([.data(try fixture("getFreeList"))])
        let list = try await client.free.list(country: 44, number: "7459608320", count: 20)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getFreeList")
        XCTAssertEqual(call.query, ["country": "44", "number": "7459608320", "count": "20"])
        XCTAssertEqual(list.numbers["7459608320"]?.fullNumber, "447459608320")
        XCTAssertEqual(list.messages.data.first?.code, "195895")
        XCTAssertEqual(list.messages.number, "7459608320")
        XCTAssertEqual(list.messages.country, 44)
        XCTAssertEqual(list.messages.page.total, 426)
        XCTAssertEqual(list.countries.map(\.country), [44, 380])
    }

    func testListAcceptsNullCountryTexts() async throws {
        let (client, _) = fakeClient([
            .json([
                "response": 1, "countries": [["country": 999, "country_text": nil, "country_original": nil]],
                "numbers": [
                    "123": [
                        "country": 999, "country_original": nil, "full_number": "999123", "data_humans": "now",
                        "is_archive": false,
                    ]
                ],
                "messages": ["data": []],
            ])
        ])
        let list = try await client.free.list()
        XCTAssertEqual(list.countries.first?.country, 999)
        XCTAssertNil(list.countries.first?.countryText)
        XCTAssertNil(list.countries.first?.countryOriginal)
        XCTAssertNil(list.numbers["123"]?.countryOriginal)
    }

    func testListNormalisesEmptyNumbers() async throws {
        let (client, transport) = fakeClient([
            .json(["response": 1, "countries": [], "numbers": [], "messages": ["data": []]])
        ])
        let list = try await client.free.list()
        XCTAssertEqual(list.numbers, [:])
        let call = try await transport.last()
        XCTAssertEqual(call.query, [:])
    }
}

final class WebhookTests: XCTestCase {
    func testParsesReceivingSmsString() throws {
        let body = """
            {"webhook_type":"receiving_sms","operation_id":1520,"user_id":2,"country_code":7,"number":"+79001234567",
             "sender":"VK","message":"VK: 195895 is your code","code":"195895","time_start":"2026-11-19 10:00:00",
             "time_left":1100}
            """
        let hook = try parseWebhook(body)
        XCTAssertEqual(hook.webhookType, .receivingSms)
        XCTAssertEqual(hook.operationID, 1520)
        XCTAssertEqual(hook.userID, 2)
        XCTAssertEqual(hook.countryCode, 7)
        XCTAssertEqual(hook.number, "+79001234567")
        XCTAssertEqual(hook.sender, "VK")
        XCTAssertEqual(hook.message, "VK: 195895 is your code")
        XCTAssertEqual(hook.code, "195895")
        XCTAssertEqual(hook.timeStart, "2026-11-19 10:00:00")
        XCTAssertEqual(hook.timeLeft, 1100)
    }

    func testIsLenient() throws {
        let hook = try parseWebhook(
            Data(#"{"webhook_type":"rent_sms","operation_id":"430","code":2991,"time_left":"soon","extra":true}"#.utf8))
        XCTAssertEqual(hook.webhookType, .rentSms)
        XCTAssertEqual(hook.operationID, 430)
        XCTAssertNil(hook.userID)
        XCTAssertNil(hook.countryCode)
        XCTAssertNil(hook.number)
        XCTAssertNil(hook.sender)
        XCTAssertNil(hook.message)
        XCTAssertEqual(hook.code, "2991")
        XCTAssertNil(hook.timeStart)
        XCTAssertNil(hook.timeLeft)
        XCTAssertNil(try parseWebhook(#"{"webhook_type":"other"}"#).webhookType)
    }

    func testThrowsOnlyForInputThatIsNotAJSONObject() {
        XCTAssertThrowsError(try parseWebhook("not json")) {
            XCTAssertEqual($0 as? OnlineSimError, .invalidPayload(message: "Webhook payload is not valid JSON"))
        }
        XCTAssertThrowsError(try parseWebhook("[1,2]")) {
            XCTAssertEqual($0 as? OnlineSimError, .invalidPayload(message: "Webhook payload is not a JSON object"))
        }
        XCTAssertThrowsError(try parseWebhook("null"))
    }
}
