import Foundation
import XCTest

@testable import OnlineSim

final class RentTests: XCTestCase {
    private let detail = ["pagination": "0", "number": "1"]

    private func items() throws -> [JSONValue] {
        let state = try JSONDecoder().decode(JSONValue.self, from: try fixture("rent_getRentState"))
        guard case .array(let list)? = state["list"] else { throw URLError(.cannotDecodeContentData) }
        return list
    }

    func testGetSendsExtensionExplicitlyPaginationAndNumberParsesSum() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "item": try items()[0]])])
        let rent = try await client.rent.get(country: 7, days: 3)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/rent/getRentNum.php")
        XCTAssertEqual(call.query, ["country": "7", "days": "3", "extension": "1"].merging(detail) { a, _ in a })
        XCTAssertEqual(rent.sum, 5.14)
        XCTAssertEqual(rent.extend, [1: 14.7, 3: 25.3, 7: 51])
        XCTAssertEqual(rent.messages.first?.code, "195895")
        XCTAssertEqual(rent.number, "781746533")
        XCTAssertEqual(rent.timeSeconds, 18_034_680)
        XCTAssertEqual(rent.extension, 1)
    }

    func testGetWithExtensionFalseSendsZero() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "item": try items()[1]])])
        _ = try await client.rent.get(country: 7, days: 1, extension: false)
        let call = try await transport.last()
        XCTAssertEqual(call.query["extension"], "0")
    }

    func testStateNormalisesSumAndEmptyExtendMap() async throws {
        let (client, transport) = fakeClient([.data(try fixture("rent_getRentState"))])
        let list = try await client.rent.state()
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/rent/getRentState.php")
        XCTAssertEqual(call.query, detail)
        XCTAssertEqual(list.map(\.sum), [5.14, 0])
        XCTAssertEqual(list[1].extend, [:])
    }

    func testStateOne() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "list": [try items()[0]]])])
        let rent = try await client.rent.stateOne(430)
        XCTAssertEqual(rent.tzid, 430)
        XCTAssertEqual(rent.sum, 5.14)
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["tzid": "430"].merging(detail) { a, _ in a })
    }

    func testStateOneRaisesErrorNoOperationsForEmptyList() async throws {
        let (client, _) = fakeClient([.json(["response": 1, "list": []])])
        let code = await apiCode { try await client.rent.stateOne(1) }
        XCTAssertEqual(code, "ERROR_NO_OPERATIONS")
    }

    func testExtend() async throws {
        let (client, transport) = fakeClient([.json(["response": 1, "item": try items()[0]])])
        let rent = try await client.rent.extend(430, days: 3)
        XCTAssertEqual(rent.tzid, 430)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/rent/extendRentState.php")
        XCTAssertEqual(call.query, ["tzid": "430", "days": "3"].merging(detail) { a, _ in a })
    }

    func testTariffs() async throws {
        let (client, transport) = fakeClient([.data(try fixture("rent_tariffsRent"))])
        let tariffs = try await client.rent.tariffs()
        XCTAssertEqual(tariffs.keys.sorted(), [7, 380])
        XCTAssertEqual(tariffs[7]?.days, [3: 5.14, 7: 9.11, 15: 16.07, 30: 24.11])
        XCTAssertEqual(tariffs[7]?.extCounts?[30], 1)
        XCTAssertNil(tariffs[380]?.extCounts)
        XCTAssertEqual(tariffs[380]?.isEnabled, false)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/rent/tariffsRent.php")
        XCTAssertEqual(call.query, [:])
    }

    func testTariffsOne() async throws {
        let all = try JSONDecoder().decode(JSONValue.self, from: try fixture("rent_tariffsRent"))
        let (client, transport) = fakeClient([.json(try XCTUnwrap(all["7"]))])
        let ru = try await client.rent.tariffsOne()
        XCTAssertEqual(ru.code, 7)
        XCTAssertEqual(ru.name, "russia")
        XCTAssertEqual(ru.count[3], 1)
        let call = try await transport.last()
        XCTAssertEqual(call.query, ["country": "7"])
    }

    func testTariffsOneRaisesNoCountryForEmptyArray() async throws {
        let (client, _) = fakeClient([.json([])])
        let code = await apiCode { try await client.rent.tariffsOne(country: 999) }
        XCTAssertEqual(code, "NO_COUNTRY")
    }

    func testClose() async throws {
        let (client, transport) = fakeClient([.json(["response": "1"])])
        try await client.rent.close(430)
        let call = try await transport.last()
        XCTAssertEqual(call.path, "/api/rent/closeRentNum.php")
        XCTAssertEqual(call.query, ["tzid": "430"])
    }

    func testCloseSurfacesNoCloseRentUS() async throws {
        let (client, _) = fakeClient([.json(["response": "NO_CLOSE_RENT_US"])])
        let code = await apiCode { try await client.rent.close(1) }
        XCTAssertEqual(code, "NO_CLOSE_RENT_US")
    }

    func testDecodesSumAsNumberOrStringAndNotifyCodeZero() async throws {
        guard case .object(var item) = try items()[0] else { throw URLError(.cannotDecodeContentData) }
        item["status"] = 0
        item["checked"] = false
        item["sum"] = 1.5
        item["messages"] = [
            [
                "id": 2, "service": "notify", "text": "Messages from this sender are not accepted", "code": 0,
                "created_at": "2026-11-19 10:01:12",
            ],
            ["id": 1, "service": "Google", "text": "G-070051", "code": "070051", "created_at": "2026-11-19 10:01:00"],
        ]
        var listed = item
        listed["sum"] = "2.40"
        let (client, _) = fakeClient([
            .json(["response": 1, "item": .object(item)]), .json(["response": 1, "list": [.object(listed)]]),
        ])
        let rent = try await client.rent.get(country: 7, days: 3)
        XCTAssertEqual(rent.status, 0)
        XCTAssertEqual(rent.checked, false)
        XCTAssertEqual(rent.sum, 1.5)
        XCTAssertEqual(rent.messages.map(\.code), ["0", "070051"])
        let state = try await client.rent.stateOne(rent.tzid)
        XCTAssertEqual(state.sum, 2.4)
    }
}
