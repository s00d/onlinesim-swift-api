import Foundation
import XCTest

@testable import OnlineSim

/// Fake clock: `sleep` only moves `now` and records the duration; nothing really waits.
///
/// `@unchecked Sendable`: `time` and `sleeps` are touched only under `lock` (`now` must be synchronous, so an
/// actor cannot own them).
private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 0
    private var recorded: [TimeInterval] = []

    var sleeps: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return recorded }
    var current: TimeInterval { lock.lock(); defer { lock.unlock() }; return time }

    var clock: WaitClock {
        WaitClock(
            now: { self.current },
            sleep: { seconds in self.advance(seconds) })
    }

    private func advance(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(seconds)
        time += seconds
    }
}

final class WaitCodeTests: XCTestCase {
    private func op(_ status: String = "TZ_NUM_WAIT", msg: String? = nil) -> Reply {
        var view: [String: JSONValue] = ["tzid": 7, "response": .string(status)]
        if let msg { view["msg"] = .string(msg) }
        return .json([.object(view)])
    }

    private let ok = Reply.json(["response": 1, "tzid": 7])

    private func log(_ transport: FakeTransport) async -> [String] {
        await transport.calls.map { call in
            call.path == "/api/getState.php" ? "state code=\(call.query["message_to_code"] ?? "")" : call.path
        }
    }

    func testReturnsTheCodeOnceItArrivesAndClosesTheOperation() async throws {
        let fake = FakeClock()
        let (client, transport) = fakeClient([op(), op(), op("TZ_NUM_ANSWER", msg: "195895"), ok])
        let code = try await client.numbers.waitCode(7, clock: fake.clock)
        XCTAssertEqual(code, "195895")
        XCTAssertEqual(fake.sleeps, [5, 5])
        let calls = await log(transport)
        XCTAssertEqual(calls, ["state code=1", "state code=1", "state code=1", "/api/setOperationOk.php"])
    }

    func testKeepOpenSinceAndFullMessage() async throws {
        let fake = FakeClock()
        let (client, transport) = fakeClient([op(msg: "old"), op(msg: "Your code is 2991"), ok])
        let code = try await client.numbers.waitCode(
            7, interval: 1, keepOpen: true, fullMessage: true, since: "old", clock: fake.clock)
        XCTAssertEqual(code, "Your code is 2991")
        XCTAssertEqual(fake.sleeps, [1])
        let calls = await log(transport)
        XCTAssertEqual(calls, ["state code=0", "state code=0", "/api/setOperationRevise.php"])
    }

    func testFinishedOperationRaisesAtOnce() async throws {
        for status in ["TZ_OVER_OK", "ERROR_NO_ITEMS"] {
            let fake = FakeClock()
            let (client, transport) = fakeClient([op(status)])
            let code = await apiCode { try await client.numbers.waitCode(7, clock: fake.clock) }
            XCTAssertEqual(code, status)
            let count = await transport.calls.count
            XCTAssertEqual(count, 1)
            XCTAssertEqual(fake.sleeps, [])
        }
    }

    func testFinishedOperationThatStillCarriesANewCodeReturnsIt() async throws {
        let (client, _) = fakeClient([op("TZ_OVER_OK", msg: "1234"), ok])
        let code = try await client.numbers.waitCode(7, clock: FakeClock().clock)
        XCTAssertEqual(code, "1234")
    }

    func testTimeoutWithTheLastSleepCutToTheDeadline() async throws {
        let fake = FakeClock()
        let (client, transport) = fakeClient(Array(repeating: op(), count: 4))
        let error = await caught { try await client.numbers.waitCode(7, interval: 4, timeout: 10, clock: fake.clock) }
        XCTAssertEqual(error as? OnlineSimError, .waitTimeout(tzid: 7, timeout: 10))
        XCTAssertEqual(fake.sleeps, [4, 4, 2])
        let count = await transport.calls.count
        XCTAssertEqual(count, 4)
        XCTAssertEqual(fake.current, 10)
    }

    func testRetriesATransientTransportError() async throws {
        let fake = FakeClock()
        let (client, transport) = fakeClient([
            .failure(URLError(.networkConnectionLost)), .raw("<html>502</html>", status: 502), op(msg: "42"), ok,
        ])
        let code = try await client.numbers.waitCode(7, clock: fake.clock)
        XCTAssertEqual(code, "42")
        XCTAssertEqual(fake.sleeps, [5, 5])
        let calls = await log(transport)
        XCTAssertEqual(calls, ["state code=1", "state code=1", "state code=1", "/api/setOperationOk.php"])
    }

    func testRetriesTransientAPIErrorsUntilTheCodeArrives() async throws {
        for code in ["TRY_AGAIN_LATER", "ERROR_UNDEFINED", "INTERVAL_CONCURRENT_REQUESTS_ERROR"] {
            let fake = FakeClock()
            let status = code == "TRY_AGAIN_LATER" ? 429 : 200
            let (client, transport) = fakeClient([
                .json(["response": .string(code)], status: status), op(msg: "42"), ok,
            ])
            let result = try await client.numbers.waitCode(7, clock: fake.clock)
            XCTAssertEqual(result, "42")
            XCTAssertEqual(fake.sleeps, [5])
            let calls = await log(transport)
            XCTAssertEqual(calls, ["state code=1", "state code=1", "/api/setOperationOk.php"])
        }
    }

    func testARetryableAPIErrorStillEndsInTimeoutAtTheDeadline() async throws {
        let fake = FakeClock()
        let (client, _) = fakeClient(Array(repeating: .json(["response": "TRY_AGAIN_LATER"], status: 429), count: 3))
        let error = await caught { try await client.numbers.waitCode(7, interval: 5, timeout: 10, clock: fake.clock) }
        XCTAssertEqual(error as? OnlineSimError, .waitTimeout(tzid: 7, timeout: 10))
        XCTAssertEqual(fake.sleeps, [5, 5])
    }

    func testAnOperationWithoutResponseKeepsPolling() async throws {
        let fake = FakeClock()
        let (client, _) = fakeClient([.json([["tzid": 7]]), op(msg: "77"), ok])
        let code = try await client.numbers.waitCode(7, clock: fake.clock)
        XCTAssertEqual(code, "77")
    }

    func testRaisesAnyOtherAPIErrorAtOnce() async throws {
        let fake = FakeClock()
        let (client, transport) = fakeClient([.json(["response": "ERROR_NO_OPERATIONS"])])
        let code = await apiCode { try await client.numbers.waitCode(7, clock: fake.clock) }
        XCTAssertEqual(code, "ERROR_NO_OPERATIONS")
        let count = await transport.calls.count
        XCTAssertEqual(count, 1)
    }

    func testSystemClockSleepsZeroWithoutWaiting() async throws {
        let (client, _) = fakeClient([op(), op(msg: "555"), ok])
        let code = try await client.numbers.waitCode(7, interval: 0)
        XCTAssertEqual(code, "555")
    }
}
