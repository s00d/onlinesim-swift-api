/// State of the mock backend. `MockState` is a value type holding everything the fake API remembers:
/// balance, operations, rents, the profile's webhook URL and its delivery log, scheduled SMS, the failure queue
/// and the request log. Its single owner is ``MockOnlineSim``, which keeps it behind one lock; the handlers
/// (`MockHandlers.swift`) change it only through `inout` access granted by that owner.
///
/// Deterministic: ids and numbers come from a counter, timestamps from a fixed epoch plus that counter.
/// Money is kept in integer thousandths of a USD ("mills") so sums never drift.

/// Rent tariff of one country for ``MockOnlineSim``.
public struct MockRentTariff: Sendable, Hashable {
    /// Rent days → USD.
    public var days: [Int: Double]
    /// `1`: rents can be extended; `0`: not.
    public var extend: Int

    public init(days: [Int: Double], extend: Int = 1) {
        self.days = days
        self.extend = extend
    }
}

/// One SMS received by a mock operation.
public struct MockSms: Sendable, Hashable {
    public internal(set) var service: String
    public internal(set) var text: String
    /// Code extracted from `text` (first run of 4–8 digits), `nil` when there is none.
    public internal(set) var code: String?
}

/// A number operation as the mock stores it.
public struct MockOperation: Sendable, Hashable {
    public internal(set) var tzid: Int
    public internal(set) var service: String
    public internal(set) var country: Int
    /// Full number with `+`.
    public internal(set) var number: String
    /// Price, USD. Frozen while open; spent on close after an SMS, refunded on close without one.
    public internal(set) var sum: Double
    /// ``OperationStatus/tzNumWait``, ``OperationStatus/tzNumAnswer`` or ``OperationStatus/tzOverOk``.
    public internal(set) var status: OperationStatus
    public internal(set) var messages: [MockSms]
    /// Index of the SMS shown in `msg`; ``NumbersAPI/next(_:)`` moves it past the last one.
    public internal(set) var cursor: Int
}

/// One SMS received by a mock rent.
public struct MockRentSms: Sendable, Hashable {
    public internal(set) var id: Int
    public internal(set) var service: String
    public internal(set) var text: String
    public internal(set) var code: String?
    public internal(set) var createdAt: String
}

/// A rent as the mock stores it. Closed rents are removed.
public struct MockRent: Sendable, Hashable {
    public internal(set) var tzid: Int
    public internal(set) var country: Int
    /// Number without the country code, as the backend sends it for rents.
    public internal(set) var number: String
    public internal(set) var days: Int
    /// Total paid, USD.
    public internal(set) var sum: Double
    /// Created with `extension: true`.
    public internal(set) var isExtendable: Bool
    /// Oldest first.
    public internal(set) var messages: [MockRentSms]
}

/// One request the mock received.
public struct MockRequest: Sendable, Hashable {
    /// `GET` or `POST`.
    public var method: String
    /// Path relative to `/api/`, e.g. `getNum.php`, `rent/getRentNum.php`, `getFreeList`.
    public var path: String
    public var query: [String: String]
    /// Parsed JSON body of a `POST`, `nil` for `GET`.
    public var body: JSONValue?

    public init(method: String, path: String, query: [String: String], body: JSONValue? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}

/// A queued failure: the next matching request answers `{"response": code}`, or a non-JSON HTTP `status`.
struct MockFailure {
    enum Kind {
        case code(String)
        case status(Int)
    }
    var kind: Kind
    var endpoint: String?
}

struct ScheduledSms {
    var text: String
    var service: String?
    /// getState/getRentState polls of this tzid still to pass before the SMS arrives.
    var polls: Int
}

let mockUserID = 1
/// Seconds an operation stays open, as reported in `time`. The mock has no clock, so it never runs down.
let operationTime = 1200

func toMills(_ usd: Double) -> Int { Int((usd * 1000).rounded()) }
func fromMills(_ mills: Int) -> Double { Double(mills) / 1000 }

/// `YYYY-MM-DD HH:MM:SS` at `seconds` after the fixed mock epoch 2026-01-01 00:00:00 UTC.
func stamp(_ seconds: Int = 0) -> String {
    let time = 1_767_225_600 + seconds
    let (days, rest) = (time / 86_400, time % 86_400)
    // Civil date from days since 1970-01-01 (H. Hinnant's algorithm).
    let z = days + 719_468
    let era = z / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    return "\(year)-\(pad(month))-\(pad(day)) \(pad(rest / 3600)):\(pad(rest % 3600 / 60)):\(pad(rest % 60))"
}

/// The code rule shared by every SDK mock: dashes/whitespace between digits are removed, then the first run of
/// 4–8 digits (not part of a longer run) is the code; `nil` when there is none.
func extractCode(_ text: String) -> String? {
    let chars = Array(text)
    func isDigit(_ c: Character) -> Bool { ("0"..."9").contains(c) }
    func isSeparator(_ c: Character) -> Bool { c == "-" || c.isWhitespace }

    var joined: [Character] = []
    var i = 0
    while i < chars.count {
        let c = chars[i]
        joined.append(c)
        i += 1
        if isDigit(c) {
            var j = i
            while j < chars.count, isSeparator(chars[j]) { j += 1 }
            if j > i, j < chars.count, isDigit(chars[j]) { i = j }
        }
    }

    var start = 0
    while start < joined.count {
        guard isDigit(joined[start]) else {
            start += 1
            continue
        }
        var end = start
        while end < joined.count, isDigit(joined[end]) { end += 1 }
        if (4...8).contains(end - start) { return String(joined[start..<end]) }
        start = end
    }
    return nil
}

struct MockState {
    let apiKey: String
    let guardInterval: Int
    let prices: [Int: [String: Double]]
    let rentTariffs: [Int: MockRentTariff]
    let startBalance: Int

    /// Total balance incl. the frozen part, mills.
    var balance = 0
    /// Frozen by open operations, mills.
    var frozen = 0
    var operations: [Int: MockOperation] = [:]
    var rents: [Int: MockRent] = [:]
    var webhookURL: String?
    var webhookLogs: [JSONValue] = []
    var requests: [MockRequest] = []
    var failures: [MockFailure] = []
    var scheduled: [Int: [ScheduledSms]] = [:]
    /// Source of tzids, numbers, message ids and timestamps.
    var seq = 0

    init(
        apiKey: String, balance: Double, prices: [Int: [String: Double]], rentTariffs: [Int: MockRentTariff],
        guardInterval: Int
    ) {
        self.apiKey = apiKey
        self.guardInterval = guardInterval
        self.prices = prices
        self.rentTariffs = rentTariffs
        startBalance = toMills(balance)
        self.balance = startBalance
    }

    /// Back to the constructor's state.
    mutating func reset() {
        self = MockState(
            apiKey: apiKey, balance: fromMills(startBalance), prices: prices, rentTariffs: rentTariffs,
            guardInterval: guardInterval)
    }

    /// Available balance (total minus frozen), mills.
    var available: Int { balance - frozen }

    /// The id the next operation/rent will get.
    var peekID: Int { seq + 1 }

    mutating func nextID() -> Int {
        seq += 1
        return seq
    }

    /// Short (country-less) number for an id: deterministic, 9 digits.
    static func shortNumber(_ id: Int) -> String { String(900_000_000 + id) }

    /// Removes and returns the first queued failure that applies to `path`.
    mutating func takeFailure(_ path: String) -> MockFailure? {
        guard let i = failures.firstIndex(where: { $0.endpoint == nil || $0.endpoint == path }) else { return nil }
        return failures.remove(at: i)
    }

    /// An SMS arrives at operation or rent `tzid` now. Returns `false` when there is no open one.
    mutating func deliver(_ tzid: Int, _ text: String, service: String?) -> Bool {
        let code = extractCode(text)
        if var op = operations[tzid], op.status != .tzOverOk {
            let sms = MockSms(service: service ?? op.service, text: text, code: code)
            op.messages.append(sms)
            op.status = .tzNumAnswer
            operations[tzid] = op
            webhook(.receivingSms, tzid: tzid, country: op.country, number: op.number, sms: sms)
            return true
        }
        if var rent = rents[tzid] {
            let sms = MockSms(service: service ?? "other", text: text, code: code)
            let id = nextID()
            rent.messages.append(
                MockRentSms(id: id, service: sms.service, text: text, code: code, createdAt: stamp(id)))
            rents[tzid] = rent
            webhook(.rentSms, tzid: tzid, country: rent.country, number: rent.number, sms: sms)
            return true
        }
        return false
    }

    mutating func schedule(_ tzid: Int, _ text: String, polls: Int, service: String?) {
        scheduled[tzid, default: []].append(ScheduledSms(text: text, service: service, polls: polls))
    }

    /// One state poll of `tzid`: delivers the scheduled SMS whose polls ran out, counts down the rest.
    mutating func poll(_ tzid: Int) {
        guard let list = scheduled[tzid] else { return }
        let due = list.filter { $0.polls <= 0 }
        let rest = list.filter { $0.polls > 0 }.map { sms -> ScheduledSms in
            var sms = sms
            sms.polls -= 1
            return sms
        }
        scheduled[tzid] = rest.isEmpty ? nil : rest
        // Dropped silently when the operation was closed meanwhile: a real SMS would not arrive either.
        for sms in due { _ = deliver(tzid, sms.text, service: sms.service) }
    }

    /// No HTTP call: the mock only records what the backend would have sent.
    private mutating func webhook(_ type: WebhookType, tzid: Int, country: Int, number: String, sms: MockSms) {
        guard let url = webhookURL else { return }
        let time = JSONValue.string(stamp(seq))
        webhookLogs.append([
            "id": .int(webhookLogs.count + 1),
            "user_id": .int(mockUserID),
            "webhook_url": .string(url),
            "type": .string(type.rawValue),
            "params": [
                "webhook_type": .string(type.rawValue),
                "operation_id": .int(tzid),
                "user_id": .int(mockUserID),
                "country_code": .int(country),
                "number": .string(number),
                "sender": .string(sms.service),
                "message": .string(sms.text),
                "code": sms.code.map(JSONValue.string) ?? .null,
                "time_start": time,
                "time_left": .int(operationTime),
            ],
            "status": "success",
            "error": nil,
            "created_at": time,
            "updated_at": time,
        ])
    }
}
