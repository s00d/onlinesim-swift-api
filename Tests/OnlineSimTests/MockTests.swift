import Foundation
import XCTest

@testable import OnlineSim

/// MockOnlineSim through the real client: every endpoint, every control helper.
final class MockAuthTests: XCTestCase {
    func testWrongOrMissingKeyAnswers456WrongKey() async throws {
        let mock = MockOnlineSim()
        for key in ["nope", ""] {
            let error = await caught { try await mock.client(apiKey: key).user.balance() }
            XCTAssertEqual(error as? OnlineSimError, .api(code: "ERROR_WRONG_KEY", message: "Wrong API key"))
        }
    }

    func testTariffsAndFreeNumbersNeedNoKey() async throws {
        let client = MockOnlineSim().client(apiKey: "")
        let uk = try await client.numbers.tariffsOne(country: 44)
        XCTAssertEqual(uk.code, 44)
        let ru = try await client.rent.tariffsOne(country: 7)
        XCTAssertEqual(ru.code, 7)
        let free = try await client.free.list()
        XCTAssertEqual(free.messages.country, 44)
    }

    func testTransportOfAClientBuiltByHandWithAnyBaseURL() async throws {
        let mock = MockOnlineSim(apiKey: "k", balance: 5)
        let client = OnlineSimClient(apiKey: "k", transport: mock.transport)
        let balance = try await client.user.balance()
        XCTAssertEqual(balance, Balance(balance: 5, zbalance: 0, income: 0))
        XCTAssertEqual(
            mock.requests, [MockRequest(method: "GET", path: "getBalance.php", query: ["income": "1", "lang": "en"])])
    }

    func testUnknownEndpointIsANonJSON404() async throws {
        let mock = MockOnlineSim()
        let request = TransportRequest(
            method: "GET", url: URL(string: "https://x.test/api/nope.php")!, headers: [:], body: nil, timeout: 1)
        let response = try await mock.send(request)
        XCTAssertEqual(response.status, 404)
    }
}

final class MockNumbersTests: XCTestCase {
    func testPrice() async throws {
        let client = MockOnlineSim().client()
        let telegram = try await client.numbers.price("telegram", country: 7)
        XCTAssertEqual(telegram, 1.2)
        let none = try await client.numbers.price("nope", country: 7)
        XCTAssertNil(none)
        let code = await apiCode { try await client.numbers.price("google", country: 999) }
        XCTAssertEqual(code, "UNDEFINED_COUNTRY")
    }

    func testGetFreezesThePriceNumbersAreDeterministic() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        let first = try await client.numbers.get("google", country: 44)
        XCTAssertEqual(first, 1)
        let order = try await client.numbers.getWithNumber("vkcom")
        XCTAssertEqual(order, NumberOrder(tzid: 2, number: "+7900000002", country: 7, time: 1200, service: "vkcom"))
        XCTAssertEqual(mock.requests.map { $0.query["number"] }, [nil, "1"])
        let balance = try await client.user.balance()
        XCTAssertEqual(balance, Balance(balance: 100, zbalance: 0.7, income: 0))
        XCTAssertEqual(mock.operations().map(\.number), ["+44900000001", "+7900000002"])
        XCTAssertEqual(mock.operations().map(\.status), [.tzNumWait, .tzNumWait])
    }

    func testGetErrors() async throws {
        let mock = MockOnlineSim(balance: 0.25)
        let client = mock.client()
        var code = await apiCode { try await client.numbers.get("google", country: 999) }
        XCTAssertEqual(code, "UNDEFINED_COUNTRY")
        code = await apiCode { try await client.numbers.get("nope", country: 7) }
        XCTAssertEqual(code, "ERROR_NO_SERVICE")
        code = await apiCode { try await client.numbers.get("google", country: 7) }
        XCTAssertEqual(code, "WARNING_LOW_BALANCE")
        let error = await caught { try await client.numbers.get("google", country: 44, reject: ["4490", "7"]) }
        guard case .noNumber? = error as? OnlineSimError else { return XCTFail("\(String(describing: error))") }
        XCTAssertEqual(mock.requests.last?.query["reject"], "4490,7")
        // a non-matching reject passes; the rejected attempt did not consume a number
        let order = try await client.numbers.getWithNumber("google", country: 44, reject: ["4480"])
        XCTAssertEqual(order.number, "+44900000001")
        // 0.25 - 0.2 frozen = 0.05 available
        code = await apiCode { try await client.numbers.get("google", country: 44) }
        XCTAssertEqual(code, "WARNING_LOW_BALANCE")
    }

    func testStateLifecycle() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        let empty = try await client.numbers.state()
        XCTAssertEqual(empty, [])
        let a = try await client.numbers.get("google", country: 44)
        let b = try await client.numbers.get("vkcom", country: 7)
        let one = try await client.numbers.stateOne(a)
        XCTAssertEqual(one.response, .tzNumWait)
        XCTAssertEqual(one.number, "+44900000001")
        XCTAssertEqual(one.sum, 0.2)
        XCTAssertEqual(one.guardIntervalRemainingSeconds, 0)
        XCTAssertNil(one.msg)

        try mock.addSms(a, "Your Google code is G-123 456. Do not share it.")
        let answered = try await client.numbers.stateOne(a)
        XCTAssertEqual(answered.response, .tzNumAnswer)
        XCTAssertEqual(answered.msg, .text("123456"))
        let full = try await client.numbers.stateOne(a, messageToCode: false)
        XCTAssertEqual(full.msg, .text("Your Google code is G-123 456. Do not share it."))
        let desc = try await client.numbers.state(orderBy: .desc)
        XCTAssertEqual(desc.map(\.tzid), [b, a])

        try await client.numbers.close(a)
        let closed = try await client.numbers.stateOne(a)
        XCTAssertEqual(closed.response, .tzOverOk)
        XCTAssertEqual(closed.time, 0)
        let code = await apiCode { try await client.numbers.stateOne(999) }
        XCTAssertEqual(code, "ERROR_NO_OPERATIONS")
    }

    func testTextWithoutCodeNextAndMsgList() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        let tzid = try await client.numbers.get("telegram")
        try mock.addSms(tzid, "Welcome!", service: "telegram")
        var op = try await client.numbers.stateOne(tzid)
        XCTAssertEqual(op.msg?.text, "Welcome!")
        try await client.numbers.next(tzid)
        op = try await client.numbers.stateOne(tzid)
        XCTAssertEqual(op.response, .tzNumWait)
        XCTAssertNil(op.msg)
        try mock.addSms(tzid, "code 98765")
        op = try await client.numbers.stateOne(tzid)
        XCTAssertEqual(op.msg?.text, "98765")
        op = try await client.numbers.stateOne(tzid, msgList: true)
        XCTAssertEqual(
            op.msg,
            .list([OperationSms(service: "telegram", msg: "Welcome!"), OperationSms(service: "telegram", msg: "98765")])
        )
        try await client.numbers.next(424_242)  // always succeeds, like the backend
    }

    func testCloseSpendsOrRefundsBanAfterSmsAnswersZero() async throws {
        let mock = MockOnlineSim(balance: 10)
        let client = mock.client()
        let paid = try await client.numbers.get("telegram")
        let empty = try await client.numbers.get("telegram")
        try mock.addSms(paid, "1111")
        var code = await apiCode { try await client.numbers.ban(paid) }
        XCTAssertEqual(code, "0")
        try await client.numbers.close(paid)
        try await client.numbers.close(empty)
        let balance = try await client.user.balance()
        XCTAssertEqual(balance.balance, 8.8)
        XCTAssertEqual(balance.zbalance, 0)
        XCTAssertEqual(mock.balance(), 8.8)
        code = await apiCode { try await client.numbers.close(paid) }
        XCTAssertEqual(code, "ERROR_WRONG_TZID")
        code = await apiCode { try await client.numbers.close(999) }
        XCTAssertEqual(code, "ERROR_WRONG_TZID")
        let banned = try await client.numbers.get("google")
        try await client.numbers.ban(banned)
        XCTAssertEqual(mock.operations().first { $0.tzid == banned }?.status, .tzOverOk)
    }

    func testGuardInterval() async throws {
        let mock = MockOnlineSim(guardInterval: 120)
        let client = mock.client()
        let tzid = try await client.numbers.get("google")
        var op = try await client.numbers.stateOne(tzid)
        XCTAssertEqual(op.guardIntervalRemainingSeconds, 120)
        let code = await apiCode { try await client.numbers.close(tzid) }
        XCTAssertEqual(code, "NO_COMPLETE_TZID")
        try mock.addSms(tzid, "5555")
        op = try await client.numbers.stateOne(tzid)
        XCTAssertEqual(op.guardIntervalRemainingSeconds, 0)
        try await client.numbers.close(tzid)
    }

    func testWaitCodeWithAddSmsAfterAndZeroInterval() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        let tzid = try await client.numbers.get("google", country: 44)
        try mock.addSmsAfter(tzid, "Your code: 4321", polls: 2)
        let code = try await client.numbers.waitCode(tzid, interval: 0)
        XCTAssertEqual(code, "4321")
        XCTAssertEqual(
            mock.requests.map(\.path),
            ["getNum.php", "getState.php", "getState.php", "getState.php", "setOperationOk.php"])
        XCTAssertEqual(mock.operations().first?.status, .tzOverOk)
    }

    func testWaitCodeKeepOpenSinceAndPollsListingAllOperations() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        let tzid = try await client.numbers.get("google", country: 44)
        try mock.addSmsAfter(tzid, "1111", polls: 0)
        let first = try await client.numbers.waitCode(tzid, interval: 0, keepOpen: true)
        try mock.addSmsAfter(tzid, "2222", polls: 1)
        _ = try await client.numbers.state()  // one poll of every operation
        let second = try await client.numbers.waitCode(tzid, interval: 0, since: first)
        XCTAssertEqual(second, "2222")
    }

    func testTariffsFromThePrices() async throws {
        let client = MockOnlineSim().client()
        let all = try await client.numbers.tariffs()
        XCTAssertEqual(all.keys.sorted(), [7, 44])
        let vk = try XCTUnwrap(all[44]?.services["service_vkcom"])
        XCTAssertEqual([vk.count, vk.code, vk.id], [100, 44, 2])
        XCTAssertEqual(vk.price, 0.36)
        XCTAssertEqual(vk.slug, "vkcom")
        XCTAssertFalse(vk.isPopular)
        let code = await apiCode { try await client.numbers.tariffsOne(country: 1) }
        XCTAssertEqual(code, "NO_COUNTRY")
        let empty = MockOnlineSim(prices: [1: [:]]).client()
        let one = try await empty.numbers.tariffsOne(country: 1)  // `[]` on the wire
        XCTAssertEqual(one.services, [:])
    }
}

final class MockRentTests: XCTestCase {
    func testGetStateExtendClose() async throws {
        let mock = MockOnlineSim(balance: 10)
        let client = mock.client()
        let rent = try await client.rent.get(country: 7, days: 3)
        XCTAssertEqual(rent.tzid, 1)
        XCTAssertEqual(rent.number, "900000001")
        XCTAssertEqual(rent.sum, 2.5)
        XCTAssertEqual(rent.days, 3)
        XCTAssertEqual(rent.time, 3 * 1440)
        XCTAssertEqual(rent.timeSeconds, 3 * 86400)
        XCTAssertEqual(rent.extension, 1)
        XCTAssertEqual(rent.messages, [])
        XCTAssertEqual(rent.extend, [1: 1, 3: 2.5, 7: 5])
        XCTAssertEqual(mock.balance(), 7.5)

        try mock.addSms(rent.tzid, "Bank: 777 888", service: "bank")
        try mock.addSms(rent.tzid, "no code here")
        let state = try await client.rent.stateOne(rent.tzid)
        XCTAssertEqual(state.messages.map(\.service), ["other", "bank"])  // newest first
        XCTAssertEqual(state.messages.map(\.code), ["", "777888"])

        let extended = try await client.rent.extend(rent.tzid, days: 1)
        XCTAssertEqual(extended.days, 4)
        XCTAssertEqual(extended.sum, 3.5)
        XCTAssertEqual(mock.balance(), 6.5)

        let fixed = try await client.rent.get(country: 7, days: 1, extension: false)
        XCTAssertEqual(fixed.extension, 0)
        XCTAssertEqual(fixed.extend, [:])
        var code = await apiCode { try await client.rent.extend(fixed.tzid) }
        XCTAssertEqual(code, "TRY_AGAIN_LATER")
        let all = try await client.rent.state()
        XCTAssertEqual(all.map(\.tzid), [rent.tzid, fixed.tzid])

        try await client.rent.close(fixed.tzid)
        XCTAssertEqual(mock.rents().map(\.tzid), [rent.tzid])
        code = await apiCode { try await client.rent.stateOne(fixed.tzid) }
        XCTAssertEqual(code, "ERROR_NO_OPERATIONS")
        code = await apiCode { try await client.rent.close(fixed.tzid) }
        XCTAssertEqual(code, "ERROR_WRONG_TZID")
    }

    func testRentErrors() async throws {
        let client = MockOnlineSim(balance: 1.5).client()
        var code = await apiCode { try await client.rent.get(country: 44) }
        XCTAssertEqual(code, "NO_COUNTRY")
        code = await apiCode { try await client.rent.get(country: 7, days: 2) }
        XCTAssertEqual(code, "UNDEFINED_DAYS")
        code = await apiCode { try await client.rent.get(country: 7, days: 3) }
        XCTAssertEqual(code, "WARNING_LOW_BALANCE")
    }

    func testAddSmsAfterForRentsTariffs() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        let tzid = try await client.rent.get().tzid
        try mock.addSmsAfter(tzid, "6060", polls: 1)
        let before = try await client.rent.stateOne(tzid)
        XCTAssertEqual(before.messages, [])
        let after = try await client.rent.state()
        XCTAssertEqual(after.first?.messages.first?.code, "6060")
        XCTAssertEqual(after.first?.messages.first?.service, "other")
        let tariffs = try await client.rent.tariffs()
        let ru = try XCTUnwrap(tariffs[7])
        XCTAssertEqual(tariffs.count, 1)
        XCTAssertEqual(ru.days, [1: 1, 3: 2.5, 7: 5])
        XCTAssertEqual(ru.count, [1: 100, 3: 100, 7: 100])
        XCTAssertEqual(ru.extCounts, [1: 100, 3: 100, 7: 100])
        XCTAssertEqual([ru.code, ru.position, ru.extend], [7, 7, 1])
        XCTAssertEqual(ru.name, "russia")
        XCTAssertEqual(ru.confirm, false)
        let code = await apiCode { try await client.rent.tariffsOne(country: 44) }
        XCTAssertEqual(code, "NO_COUNTRY")
    }
}

final class MockUserFreeTests: XCTestCase {
    func testProfileWebhookAndLogs() async throws {
        let mock = MockOnlineSim(apiKey: "secret")
        let client = mock.client()
        var profile = try await client.user.profile()
        XCTAssertEqual(profile.id, 1)
        XCTAssertEqual(profile.apikey, "secret")
        XCTAssertNil(profile.webhookURL)
        let error = await caught { try await client.user.setWebhookURL("ftp://x") }
        XCTAssertEqual(
            error as? OnlineSimError, .api(code: "VALIDATION_ERROR", message: "The webhook url must be a valid URL."))
        try await client.user.setWebhookURL("https://example.com/hook")
        let last = try XCTUnwrap(mock.requests.last)
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.path, "profile.php")
        XCTAssertEqual(last.body, ["profile": ["webhook_url": "https://example.com/hook"]])
        profile = try await client.user.profile()
        XCTAssertEqual(profile.webhookURL, "https://example.com/hook")

        let tzid = try await client.numbers.get("google", country: 44)
        try mock.addSms(tzid, "code 1234")
        let rent = try await client.rent.get()
        try mock.addSms(rent.tzid, "code 5678")
        let logs = try await client.user.webhookLogs()
        XCTAssertEqual([logs.total, logs.currentPage, logs.perPage], [2, 1, 10])
        XCTAssertEqual(logs.data.map(\.type), [.rentSms, .receivingSms])
        XCTAssertEqual(logs.data.map(\.params.operationID), [rent.tzid, tzid])
        XCTAssertEqual(logs.data.map(\.params.code), ["5678", "1234"])

        try await client.user.clearWebhookURL()
        profile = try await client.user.profile()
        XCTAssertNil(profile.webhookURL)
    }

    func testBalanceIncludesFrozenPaymentHistoryEmpty() async throws {
        let mock = MockOnlineSim(balance: 3)
        let client = mock.client()
        _ = try await client.numbers.get("telegram")
        let balance = try await client.user.balance()
        XCTAssertEqual(balance, Balance(balance: 3, zbalance: 1.2, income: 0))
        let history = try await client.user.paymentHistory()
        XCTAssertEqual(history.paylist, [:])
        XCTAssertEqual(history.orders.data, [])
        XCTAssertEqual(history.orders.total, 0)
        XCTAssertEqual(history.orders.currentPage, 1)
    }

    func testFreeList() async throws {
        let client = MockOnlineSim().client()
        let uk = try await client.free.list()
        XCTAssertEqual(uk.countries.map(\.country), [7, 44])
        XCTAssertEqual(Array(uk.numbers.keys), ["7459608320"])
        XCTAssertEqual(uk.messages.number, "7459608320")
        XCTAssertEqual(uk.messages.country, 44)
        XCTAssertEqual(uk.messages.page.total, 2)
        XCTAssertEqual(uk.messages.data.first?.code, "195895")
        let ru = try await client.free.list(country: 7)
        XCTAssertEqual(ru.messages.data.first?.code, "51423")
        XCTAssertEqual(ru.messages.data.first?.myNumber, "9001234567")
    }
}

final class MockControlTests: XCTestCase {
    func testFailNextOnceOptionallyForOneEndpoint() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        mock.failNext("NO_NUMBER", endpoint: "getNum.php")
        let balance = try await client.user.balance()  // other endpoint: untouched
        XCTAssertEqual(balance.balance, 100)
        let error = await caught { try await client.numbers.get("google") }
        guard case .noNumber? = error as? OnlineSimError else { return XCTFail() }
        let tzid = try await client.numbers.get("google")
        XCTAssertEqual(tzid, 1)
        mock.failNext("TRY_AGAIN_LATER")
        let code = await apiCode { try await client.user.profile() }
        XCTAssertEqual(code, "TRY_AGAIN_LATER")
    }

    func testFailNextTransportOnceWaitCodeRetriesIt() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()
        mock.failNextTransport()
        let error = await caught { try await client.user.balance() }
        guard case .transport(_, 502, _)? = error as? OnlineSimError else { return XCTFail() }

        let tzid = try await client.numbers.get("google")
        try mock.addSms(tzid, "3030")
        mock.failNextTransport(status: 503, endpoint: "getState.php")
        let code = try await client.numbers.waitCode(tzid, interval: 0)
        XCTAssertEqual(code, "3030")
    }

    func testUnknownIdsSetBalanceRequestsLogReset() async throws {
        let mock = MockOnlineSim(balance: 1)
        let client = mock.client(lang: "ru")
        XCTAssertThrowsError(try mock.addSms(5, "x")) {
            XCTAssertEqual(($0 as? MockOnlineSimError)?.message, "MockOnlineSim: no open operation or rent 5")
        }
        XCTAssertThrowsError(try mock.addSmsAfter(5, "x", polls: 1)) {
            XCTAssertEqual(($0 as? MockOnlineSimError)?.message, "MockOnlineSim: no operation or rent 5")
        }
        mock.setBalance(50)
        XCTAssertEqual(mock.balance(), 50)
        let tzid = try await client.numbers.get("telegram")
        try await client.numbers.close(tzid)
        XCTAssertThrowsError(try mock.addSms(tzid, "late"))  // closed
        XCTAssertEqual(
            mock.requests.first,
            MockRequest(
                method: "GET", path: "getNum.php", query: ["service": "telegram", "country": "7", "lang": "ru"]))

        mock.failNext("NO_NUMBER")
        mock.reset()
        XCTAssertEqual(mock.balance(), 1)
        XCTAssertEqual(mock.operations(), [])
        XCTAssertEqual(mock.rents(), [])
        XCTAssertEqual(mock.requests, [])
        let again = try await client.numbers.get("google", country: 44)  // ids restart, failure queue cleared
        XCTAssertEqual(again, 1)
    }

    func testConcurrentRequestsKeepTheStateConsistent() async throws {
        let mock = MockOnlineSim(balance: 1000)
        let client = mock.client()
        let ids = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<50 { group.addTask { try await client.numbers.get("google", country: 44) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(ids.sorted(), Array(1...50))
        let balance = try await client.user.balance()
        XCTAssertEqual(balance.zbalance, 10)
    }

    func testExtractCode() {
        XCTAssertEqual(extractCode("Your code: 123-456"), "123456")
        XCTAssertEqual(extractCode("G-123 456."), "123456")
        XCTAssertEqual(extractCode("1234567890 then 4321"), "4321")
        XCTAssertEqual(extractCode("abc 12 34"), "1234")
        XCTAssertNil(extractCode("Welcome!"))
        XCTAssertNil(extractCode("123"))
    }

    func testStampIsFixedEpochPlusSeconds() {
        XCTAssertEqual(stamp(), "2026-01-01 00:00:00")
        XCTAssertEqual(stamp(86_400 * 59 + 3661), "2026-03-01 01:01:01")
    }
}
