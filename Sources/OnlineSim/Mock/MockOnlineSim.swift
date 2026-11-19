import Foundation

/// In-process fake OnlineSim API for tests: no network, no key, no money, no clock.
///
/// It is a ``Transport`` that answers like the real backend; ``client(apiKey:lang:devID:timeout:)`` returns a
/// normal ``OnlineSimClient`` wired to it. Test helpers add SMS, queue failures and expose the state.
///
/// ```swift
/// let mock = MockOnlineSim(balance: 10)
/// let client = mock.client()
/// let tzid = try await client.numbers.get("google", country: 44)
/// try mock.addSmsAfter(tzid, "Your code: 123-456", polls: 2)
/// let code = try await client.numbers.waitCode(tzid, interval: 0) // "123456"
/// ```
///
/// Thread-safe: the whole state is one value owned by this object behind one lock. Every request and every
/// helper takes the lock for its whole (short, never suspending) run, so the helpers stay synchronous — an actor
/// would make each of them `async`.
public final class MockOnlineSim: Transport, Sendable {
    /// Base URL of clients made by ``client(apiKey:lang:devID:timeout:)``. Never contacted.
    public static let baseURL = URL(string: "https://mock.onlinesim.invalid/api/")!

    /// Default number prices: country code → service slug → USD.
    public static let defaultPrices: [Int: [String: Double]] = [
        7: ["vkcom": 0.5, "telegram": 1.2, "google": 0.3],
        44: ["google": 0.2, "vkcom": 0.36],
    ]

    /// Default rent tariffs: country code → tariff.
    public static let defaultRentTariffs: [Int: MockRentTariff] = [
        7: MockRentTariff(days: [1: 1.0, 3: 2.5, 7: 5.0], extend: 1)
    ]

    private let state: Locked<MockState>

    /// Creates a mock.
    ///
    /// - Parameters:
    ///   - apiKey: Key the mock accepts as `Authorization: Bearer <apiKey>`.
    ///   - balance: Starting balance, USD.
    ///   - prices: Number prices; replace the defaults. Also feed ``NumbersAPI/tariffs()``.
    ///   - rentTariffs: Rent tariffs; replace the defaults. `extend: 0` makes rents of a country non-extendable.
    ///   - guardInterval: Guard interval of new operations, seconds. `> 0`: an operation without SMS cannot be
    ///     closed (`NO_COMPLETE_TZID`).
    public init(
        apiKey: String = "mock-key",
        balance: Double = 100,
        prices: [Int: [String: Double]] = MockOnlineSim.defaultPrices,
        rentTariffs: [Int: MockRentTariff] = MockOnlineSim.defaultRentTariffs,
        guardInterval: Int = 0
    ) {
        state = Locked(
            MockState(
                apiKey: apiKey, balance: balance, prices: prices, rentTariffs: rentTariffs,
                guardInterval: guardInterval))
    }

    /// The fake transport (this object); pass it as `transport` when you build the client yourself.
    /// Any base URL works.
    public var transport: any Transport { self }

    /// A normal client wired to the mock.
    ///
    /// - Parameters:
    ///   - apiKey: `nil`: the mock's key. Pass another one to test a wrong key, `""` for none.
    ///   - lang: Language of server texts (`lang` query parameter).
    ///   - devID: Partner developer id (`dev_id` query parameter), sent only when set.
    ///   - timeout: Per-request timeout, seconds.
    public func client(apiKey: String? = nil, lang: String = "en", devID: String? = nil, timeout: TimeInterval = 30)
        -> OnlineSimClient
    {
        OnlineSimClient(
            apiKey: apiKey ?? state.withLock { $0.apiKey }, baseURL: Self.baseURL, lang: lang, devID: devID,
            timeout: timeout, transport: self)
    }

    /// An SMS arrives now at number operation or rent `tzid`.
    /// Throws ``MockOnlineSimError`` when there is no open operation or rent with that id.
    public func addSms(_ tzid: Int, _ text: String, service: String? = nil) throws {
        guard state.withLock({ $0.deliver(tzid, text, service: service) }) else {
            throw MockOnlineSimError(message: "MockOnlineSim: no open operation or rent \(tzid)")
        }
    }

    /// The SMS arrives after `polls` state requests for `tzid` (getState / rent getRentState, listing it alone or
    /// with others): with `polls: 2` the third poll sees it. Lets `waitCode` run with `interval: 0`.
    /// Throws ``MockOnlineSimError`` for an unknown id.
    public func addSmsAfter(_ tzid: Int, _ text: String, polls: Int, service: String? = nil) throws {
        try state.withLock { state in
            guard state.operations[tzid] != nil || state.rents[tzid] != nil else {
                throw MockOnlineSimError(message: "MockOnlineSim: no operation or rent \(tzid)")
            }
            state.schedule(tzid, text, polls: polls, service: service)
        }
    }

    /// The next request (to `endpoint` only, e.g. `getNum.php`, when given) answers `{"response": code}`.
    public func failNext(_ code: String, endpoint: String? = nil) {
        state.withLock { $0.failures.append(MockFailure(kind: .code(code), endpoint: endpoint)) }
    }

    /// The next request (to `endpoint` only, when given) fails at transport level: a non-JSON body with HTTP `status`.
    public func failNextTransport(status: Int = 502, endpoint: String? = nil) {
        state.withLock { $0.failures.append(MockFailure(kind: .status(status), endpoint: endpoint)) }
    }

    /// Sets the total balance, USD.
    public func setBalance(_ usd: Double) {
        state.withLock { $0.balance = toMills(usd) }
    }

    /// Total balance, USD, including the part frozen by open operations (as ``UserAPI/balance()`` reports it).
    public func balance() -> Double {
        state.withLock { fromMills($0.balance) }
    }

    /// Number operations, oldest first.
    public func operations() -> [MockOperation] {
        state.withLock { s in s.operations.keys.sorted().compactMap { s.operations[$0] } }
    }

    /// Open rents, oldest first.
    public func rents() -> [MockRent] {
        state.withLock { s in s.rents.keys.sorted().compactMap { s.rents[$0] } }
    }

    /// Every request received, in order.
    public var requests: [MockRequest] {
        state.withLock { $0.requests }
    }

    /// Back to the initializer's state: balance, no operations, rents, logs, schedules or failures.
    public func reset() {
        state.withLock { $0.reset() }
    }

    /// ``Transport`` conformance: answers in-process.
    public func send(_ request: TransportRequest) async throws -> TransportResponse {
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? ""
        let req = MockRequest(
            method: request.method.uppercased(),
            path: path.range(of: "/api/").map { String(path[$0.upperBound...]) }
                ?? String(path.drop(while: { $0 == "/" })),
            query: Dictionary(
                (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last }
            ),
            body: request.body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        )
        let authorization = request.headers.first { $0.key.lowercased() == "authorization" }?.value

        return state.withLock { state in
            state.requests.append(req)
            if let failure = state.takeFailure(req.path) {
                switch failure.kind {
                case .code(let code): return json(["response": .string(code)])
                case .status(let status): return html(status, "Mock transport failure")
                }
            }
            guard MockState.routes(req.path) else { return html(404, "Not Found") }
            if !MockState.publicPaths.contains(req.path) && authorization != "Bearer \(state.apiKey)" {
                return json(["response": "ERROR_WRONG_KEY"], status: 456)
            }
            return json(state.handle(req) ?? .null)
        }
    }
}

/// Misuse of a ``MockOnlineSim`` helper, e.g. ``MockOnlineSim/addSms(_:_:service:)`` for an unknown id.
public struct MockOnlineSimError: Error, Sendable, Hashable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

private func json(_ body: JSONValue, status: Int = 200) -> TransportResponse {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return TransportResponse(status: status, body: (try? encoder.encode(body)) ?? Data("null".utf8))
}

private func html(_ status: Int, _ text: String) -> TransportResponse {
    TransportResponse(status: status, body: Data("<html><body>\(status) \(text)</body></html>".utf8))
}

/// A value behind a lock: the one place the mock's state is reached from any thread.
///
/// `@unchecked Sendable`: `value` is read and written only inside `withLock`, under `lock`.
/// (`Synchronization.Mutex` needs macOS 15 / iOS 18; the package supports macOS 12 / iOS 15.)
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
