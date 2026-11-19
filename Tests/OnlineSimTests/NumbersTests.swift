import Foundation
import XCTest

@testable import OnlineSim

final class NumbersTests: XCTestCase {
    func testPrice() async throws {
        let (client, transport) = fakeClient([.json(["response": "1", "price": 0.36])])
        let price = try await client.numbers.price("vkcom", country: 44)
        XCTAssertEqual(price, 0.36)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getPrice.php")
        XCTAssertEqual(call.query, ["service": "vkcom", "country": "44"])
    }

    func testPriceIsNilWhenTheServerHasNone() async throws {
        let (client, _) = fakeClient([.json(["response": "1", "price": nil])])
        let price = try await client.numbers.price("vkcom")
        XCTAssertNil(price)
    }

    func testGetSendsNoNumberFlagAndRejectAsCommaList() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "tzid": 1520])])
        let tzid = try await client.numbers.get("google", country: 44, reject: ["4470", "4471"])
        XCTAssertEqual(tzid, 1520)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getNum.php")
        XCTAssertEqual(call.query, ["service": "google", "country": "44", "reject": "4470,4471"])
    }

    func testGetDefaultsToCountry7AndOmitsEmptyReject() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "tzid": 1])])
        _ = try await client.numbers.get("google", reject: [])
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["service": "google", "country": "7"])
    }

    func testGetWithNumberSendsNumberFlag() async throws {
        let (client, transport) = fakeClient([
            .json([
                "response": 1, "tzid": 1520, "number": "+447459608320", "country": 44, "time": 1200,
                "service": "google",
            ])
        ])
        let order = try await client.numbers.getWithNumber("google", country: 44)
        XCTAssertEqual(
            order, NumberOrder(tzid: 1520, number: "+447459608320", country: 44, time: 1200, service: "google"))
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["service": "google", "country": "44", "number": "1"])
    }

    func testStateSendsBooleansAs10LowercaseOrderbyAndNumberFlag() async throws {
        let (client, transport) = fakeClient([.data(try fixture("getState"))])
        let ops = try await client.numbers.state(orderBy: .desc, msgList: true)
        XCTAssertEqual(ops.map(\.tzid), [594, 593])
        XCTAssertEqual(ops[0].msg, .text("195895"))
        XCTAssertEqual(ops[0].response, .tzNumAnswer)
        XCTAssertEqual(ops[0].number, "+77781746533")
        XCTAssertEqual(ops[0].sum, 0.3)
        XCTAssertNil(ops[1].msg)
        XCTAssertEqual(ops[1].guardIntervalRemainingSeconds, 120)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getState.php")
        XCTAssertEqual(call.query, ["message_to_code": "1", "orderby": "desc", "msg_list": "1", "number": "1"])
    }

    func testStateDefaults() async throws {
        let (client, transport) = fakeClient([.json([])])
        _ = try await client.numbers.state()
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["message_to_code": "1", "orderby": "asc", "msg_list": "0", "number": "1"])
    }

    func testStateReturnsEmptyOnErrorNoOperations() async throws {
        let (client, _) = fakeClient([.json(["response": "ERROR_NO_OPERATIONS"])])
        let ops = try await client.numbers.state()
        XCTAssertEqual(ops, [])
    }

    func testStateDecodesMsgListAndFalse() async throws {
        let (client, _) = fakeClient([
            .json([
                ["tzid": 1, "response": "TZ_NUM_ANSWER", "msg": [["service": "vk", "msg": "1234"]]],
                ["tzid": "2", "response": "TZ_NUM_WAIT", "msg": false],
            ])
        ])
        let ops = try await client.numbers.state()
        XCTAssertEqual(ops[0].msg, .list([OperationSms(service: "vk", msg: "1234")]))
        XCTAssertNil(ops[0].msg?.text)
        XCTAssertEqual(ops[1].tzid, 2)
        XCTAssertNil(ops[1].msg)
    }

    func testStateOneReturnsTheOperation() async throws {
        let (client, transport) = fakeClient([
            .json([["tzid": 594, "response": "TZ_NUM_ANSWER", "msg": "VK: 195895 is your code"]])
        ])
        let op = try await client.numbers.stateOne(594, messageToCode: false)
        XCTAssertEqual(op.msg?.text, "VK: 195895 is your code")
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["tzid": "594", "message_to_code": "0", "msg_list": "0", "number": "1"])
    }

    func testStateOneRaisesErrorNoOperations() async throws {
        let (client, _) = fakeClient([.json(["response": "ERROR_NO_OPERATIONS"]), .json([])])
        let first = await apiCode { try await client.numbers.stateOne(1) }
        XCTAssertEqual(first, "ERROR_NO_OPERATIONS")
        let second = await apiCode { try await client.numbers.stateOne(1) }
        XCTAssertEqual(second, "ERROR_NO_OPERATIONS")
    }

    func testNext() async throws {
        let (client, transport) = fakeClient([.json(["response": "1", "tzid": "1520"])])
        try await client.numbers.next(1520)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/setOperationRevise.php")
        XCTAssertEqual(call.query, ["tzid": "1520"])
    }

    func testClose() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "tzid": 1520])])
        try await client.numbers.close(1520)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/setOperationOk.php")
        XCTAssertEqual(call.query, ["tzid": "1520"])
    }

    func testBan() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "tzid": 1520])])
        try await client.numbers.ban(1520)
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["tzid": "1520", "ban": "1"])
    }

    func testCloseSurfacesNoCompleteTzid() async throws {
        let (client, _) = fakeClient([.json(["response": "NO_COMPLETE_TZID"])])
        let code = await apiCode { try await client.numbers.close(1) }
        XCTAssertEqual(code, "NO_COMPLETE_TZID")
    }

    func testTariffsRequestsCountryAllAndNormalisesEmptyServices() async throws {
        let uk = try JSONDecoder().decode(JSONValue.self, from: try fixture("getNumbersStats_44"))
        guard case .object(var ru) = uk else { return XCTFail() }
        ru["code"] = 7
        ru["services"] = []
        let (client, transport) = fakeClient([.json(["44": uk, "7": .object(ru)])])
        let all = try await client.numbers.tariffs()
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/getNumbersStats.php")
        XCTAssertEqual(call.query, ["country": "all"])
        XCTAssertEqual(all[44]?.services["service_vkcom"]?.slug, "vkcom")
        XCTAssertEqual(all[7]?.services, [:])
    }

    func testTariffsOne() async throws {
        let (client, transport) = fakeClient([.data(try fixture("getNumbersStats_44"))])
        let uk = try await client.numbers.tariffsOne(country: 44)
        XCTAssertEqual(uk.code, 44)
        XCTAssertEqual(uk.localeName, "United Kingdom")
        XCTAssertEqual(uk.other, 0.63)
        XCTAssertEqual(uk.services["service_3223"]?.slug, "3223")
        XCTAssertEqual(uk.services["service_vkcom"]?.count, 363)
        XCTAssertEqual(uk.services["service_vkcom"]?.price, 0.36)
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["country": "44"])
    }

    func testTariffsOneRaisesNoCountry() async throws {
        let (client, _) = fakeClient([.json(["response": "NO_COUNTRY"])])
        let code = await apiCode { try await client.numbers.tariffsOne(country: 999) }
        XCTAssertEqual(code, "NO_COUNTRY")
    }
}
