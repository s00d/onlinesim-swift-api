import Foundation

/// Numbers for receiving SMS: `client.numbers`.
///
/// An operation (`tzid`) is one ordered number. Order it with ``get(_:country:reject:)`` or
/// ``getWithNumber(_:country:reject:)``, read the SMS with ``stateOne(_:messageToCode:msgList:)`` or
/// ``waitCode(_:interval:timeout:keepOpen:fullMessage:since:clock:)``, finish it with ``close(_:)`` (or ``ban(_:)``).
public struct NumbersAPI: Sendable {
    let requester: Requester

    /// Price (USD) of one number of `service` in `country`; `nil` when the country has no price for it.
    ///
    /// Throws ``OnlineSimError/api(code:message:)`` `ERROR_NO_SERVICE`, `UNDEFINED_COUNTRY`.
    public func price(_ service: String, country: Int = 7) async throws -> Double? {
        struct Price: Decodable { let price: Double? }
        return try await requester.call(
            Price.self, "getPrice.php", query: [("service", service), ("country", String(country))]
        ).price
    }

    /// Orders a number. Returns the operation id (`tzid`). Freezes the price on the balance.
    ///
    /// - Parameters:
    ///   - service: Service slug, e.g. `google`.
    ///   - country: Country code.
    ///   - reject: Number prefixes to skip, e.g. `["4470"]`; empty: the profile's list.
    ///
    /// Throws ``OnlineSimError/noNumber(code:message:)``; ``OnlineSimError/api(code:message:)``
    /// `WARNING_LOW_BALANCE`, `ERROR_NO_SERVICE`, `UNDEFINED_COUNTRY`, `EXCEEDED_CONCURRENT_OPERATIONS`, …
    public func get(_ service: String, country: Int = 7, reject: [String] = []) async throws -> Int {
        struct Order: Decodable { let tzid: Int }
        return try await requester.call(Order.self, "getNum.php", query: orderQuery(service, country, reject)).tzid
    }

    /// Orders a number and returns it right away together with the operation id.
    public func getWithNumber(_ service: String, country: Int = 7, reject: [String] = []) async throws -> NumberOrder {
        // `number` is a presence flag on getNum: sent here only.
        try await requester.call("getNum.php", query: orderQuery(service, country, reject) + [("number", "1")])
    }

    /// All operations of the account; empty when there are none.
    ///
    /// - Parameters:
    ///   - messageToCode: `true`: `msg` is the code only; `false`: the full SMS text.
    ///   - orderBy: Order of operations.
    ///   - msgList: `true`: `msg` is a list of all SMS.
    public func state(messageToCode: Bool = true, orderBy: OrderBy = .asc, msgList: Bool = false) async throws
        -> [NumberOperation]
    {
        do {
            return try await requester.call(
                "getState.php",
                query: [
                    ("message_to_code", flag(messageToCode)), ("orderby", orderBy.rawValue),
                    ("msg_list", flag(msgList)), ("number", "1"),
                ])
        } catch OnlineSimError.api(code: "ERROR_NO_OPERATIONS", _) {
            return []
        }
    }

    /// One operation. Throws ``OnlineSimError/api(code:message:)`` `ERROR_NO_OPERATIONS` when it does not exist (any more).
    public func stateOne(_ tzid: Int, messageToCode: Bool = true, msgList: Bool = false) async throws
        -> NumberOperation
    {
        let list: [NumberOperation] = try await requester.call(
            "getState.php",
            query: [
                ("tzid", String(tzid)), ("message_to_code", flag(messageToCode)), ("msg_list", flag(msgList)),
                ("number", "1"),
            ])
        guard let operation = list.first else { throw OnlineSimError.api("ERROR_NO_OPERATIONS") }
        return operation
    }

    /// Switches the operation to its next SMS and keeps it open.
    ///
    /// Throws ``OnlineSimError/api(code:message:)`` `ERROR_WRONG_TZID` (not an operation of your account),
    /// `ERROR_NO_TZID`.
    public func next(_ tzid: Int) async throws {
        try await requester.send("setOperationRevise.php", query: [("tzid", String(tzid))])
    }

    /// Finishes the operation.
    ///
    /// Throws ``OnlineSimError/api(code:message:)`` `NO_COMPLETE_TZID`, `INTERVAL_CONCURRENT_REQUESTS_ERROR`,
    /// `ERROR_WRONG_TZID`.
    public func close(_ tzid: Int) async throws {
        try await requester.send("setOperationOk.php", query: [("tzid", String(tzid))])
    }

    /// Finishes the operation and reports the number as bad (only before any SMS arrived).
    ///
    /// Throws as ``close(_:)``; ``OnlineSimError/api(code:message:)`` with code `"0"` when the operation already has
    /// an SMS — nothing is changed then.
    public func ban(_ tzid: Int) async throws {
        try await requester.send("setOperationOk.php", query: [("tzid", String(tzid)), ("ban", "1")])
    }

    /// Services, prices and stock of every country, keyed by country code. No key needed.
    public func tariffs() async throws -> [Int: CountryStat] {
        try await requester.call(PHPMap<Int, CountryStat>.self, "getNumbersStats.php", query: [("country", "all")])
            .map
    }

    /// Services, prices and stock of one country. No key needed. Throws ``OnlineSimError/api(code:message:)`` `NO_COUNTRY`.
    public func tariffsOne(country: Int = 7) async throws -> CountryStat {
        try await requester.call("getNumbersStats.php", query: [("country", String(country))])
    }

    private func orderQuery(_ service: String, _ country: Int, _ reject: [String]) -> Query {
        [("service", service), ("country", String(country)), ("reject", reject.joined(separator: ","))]
    }
}

/// Order of operations in ``NumbersAPI/state(messageToCode:orderBy:msgList:)``.
public enum OrderBy: String, Sendable, Hashable, Codable {
    case asc, desc
}

/// State of a number operation (``NumberOperation/response``). Unknown values are kept as they are.
public struct OperationStatus: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    /// The number is being assigned.
    public static let tzInPool = OperationStatus("TZ_INPOOL")
    /// Waiting for an SMS.
    public static let tzNumWait = OperationStatus("TZ_NUM_WAIT")
    /// An SMS arrived.
    public static let tzNumAnswer = OperationStatus("TZ_NUM_ANSWER")
    /// Finished.
    public static let tzOverOk = OperationStatus("TZ_OVER_OK")
    /// Failed.
    public static let errorNoItems = OperationStatus("ERROR_NO_ITEMS")

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One SMS of an operation when `msgList` is set.
public struct OperationSms: Sendable, Hashable, Codable {
    public var service: String
    public var msg: String?
    public var text: String?
    public var code: String?

    public init(service: String, msg: String? = nil, text: String? = nil, code: String? = nil) {
        self.service = service
        self.msg = msg
        self.text = text
        self.code = code
    }
}

/// `msg` of an operation: the code (or full text) by default, the list of all SMS with `msgList`.
public enum OperationMessage: Sendable, Hashable, Codable {
    case text(String)
    case list([OperationSms])

    /// The text of ``text(_:)``, `nil` for a list.
    public var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([OperationSms].self) {
            self = .list(list)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .list(let list): try container.encode(list)
        }
    }
}

/// A number operation (getState item).
///
/// Named `NumberOperation`, not `Operation`, to stay clear of Foundation's `Operation`.
public struct NumberOperation: Sendable, Hashable, Codable {
    public var tzid: Int
    /// The state: ``OperationStatus/tzNumWait``, ``OperationStatus/tzNumAnswer``, …; `nil` when the server sends
    /// none (no number could be issued).
    public var response: OperationStatus?
    /// Full number with `+`.
    public var number: String?
    public var service: String?
    public var country: Int?
    /// Price, USD.
    public var sum: Double?
    /// Seconds left.
    public var time: Int?
    public var form: String?
    public var subscriptionPackageID: Int?
    public var webhookURL: String?
    /// `nil` until an SMS arrives (the server's `false` too).
    public var msg: OperationMessage?
    public var extend: Int?
    /// Seconds until the operation may be closed.
    public var guardIntervalRemainingSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case tzid, response, number, service, country, sum, time, form, msg, extend
        case subscriptionPackageID = "subscription_package_id"
        case webhookURL = "webhook_url"
        case guardIntervalRemainingSeconds = "guard_interval_remaining_seconds"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tzid = try c.lossyInt(.tzid) ?? c.decode(Int.self, forKey: .tzid)
        response = (try? c.decodeIfPresent(OperationStatus.self, forKey: .response)) ?? nil
        number = try c.decodeIfPresent(String.self, forKey: .number)
        service = try c.decodeIfPresent(String.self, forKey: .service)
        country = c.lossyInt(.country)
        sum = c.lossyDouble(.sum)
        time = c.lossyInt(.time)
        form = try c.decodeIfPresent(String.self, forKey: .form)
        subscriptionPackageID = c.lossyInt(.subscriptionPackageID)
        webhookURL = try c.decodeIfPresent(String.self, forKey: .webhookURL)
        msg = try? c.decodeIfPresent(OperationMessage.self, forKey: .msg)
        extend = c.lossyInt(.extend)
        guardIntervalRemainingSeconds = c.lossyInt(.guardIntervalRemainingSeconds)
    }
}

/// Result of ``NumbersAPI/getWithNumber(_:country:reject:)``.
public struct NumberOrder: Sendable, Hashable, Codable {
    public var tzid: Int
    /// Full number with `+`, e.g. `+447459608320`.
    public var number: String
    public var country: Int
    /// Seconds left.
    public var time: Int
    public var service: String
    public var title: String?
    public var guardIntervalRemainingSeconds: Int?

    public init(
        tzid: Int, number: String, country: Int, time: Int, service: String, title: String? = nil,
        guardIntervalRemainingSeconds: Int? = nil
    ) {
        self.tzid = tzid
        self.number = number
        self.country = country
        self.time = time
        self.service = service
        self.title = title
        self.guardIntervalRemainingSeconds = guardIntervalRemainingSeconds
    }

    enum CodingKeys: String, CodingKey {
        case tzid, number, country, time, service, title
        case guardIntervalRemainingSeconds = "guard_interval_remaining_seconds"
    }
}

/// A service of a country in ``CountryStat/services``.
public struct ServiceStat: Sendable, Hashable, Codable {
    /// Numbers in stock; `nil` when the server does not know (`"?"`).
    public var count: Int?
    public var isPopular: Bool
    public var code: Int
    /// USD.
    public var price: Double
    public var id: Int
    /// Display name.
    public var service: String
    /// Service id for ``NumbersAPI/get(_:country:reject:)`` and ``NumbersAPI/price(_:country:)``.
    public var slug: String

    enum CodingKeys: String, CodingKey {
        case count, code, price, id, service, slug
        case isPopular = "popular"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.lossyInt(.count)
        isPopular = (try? c.decodeIfPresent(Bool.self, forKey: .isPopular)) ?? false
        code = try c.decode(Int.self, forKey: .code)
        price = c.lossyDouble(.price) ?? 0
        id = try c.decode(Int.self, forKey: .id)
        service = try c.decode(String.self, forKey: .service)
        slug = try (try? c.decode(String.self, forKey: .slug)) ?? String(c.decode(Int.self, forKey: .slug))
    }
}

/// Services, prices and stock of one country.
public struct CountryStat: Sendable, Hashable, Codable {
    public var name: String
    public var localeName: String?
    public var position: Int
    public var code: Int
    /// Price of other services; `nil` when not set (the server's `false`).
    public var other: Double?
    public var isNew: Bool
    public var isEnabled: Bool
    /// `service_<slug>` → service.
    public var services: [String: ServiceStat]

    enum CodingKeys: String, CodingKey {
        case name, position, code, other, services
        case localeName = "locale_name"
        case isNew = "new"
        case isEnabled = "enabled"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        localeName = try c.decodeIfPresent(String.self, forKey: .localeName)
        position = c.lossyInt(.position) ?? 0
        code = try c.decode(Int.self, forKey: .code)
        other = c.lossyDouble(.other)
        isNew = (try? c.decodeIfPresent(Bool.self, forKey: .isNew)) ?? false
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        services = try c.phpMap(.services)
    }
}
