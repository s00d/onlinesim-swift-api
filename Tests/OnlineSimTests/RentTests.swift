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
}
