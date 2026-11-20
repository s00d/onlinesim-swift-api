import Foundation

/// Rented numbers: `client.rent`. A rent keeps a number for `days` days; its SMS come in ``RentItem/messages``.
public struct RentAPI: Sendable {
    let requester: Requester

    // Always sent: flat `messages` list and `time_seconds`.
    private static let detail: Query = [("pagination", "0"), ("number", "1")]

    private struct ItemAnswer: Decodable { let item: RentItem }
    private struct ListAnswer: Decodable { let list: [RentItem] }

    /// Rents a number for `days` days. The price is reserved (it shows in ``Balance/zbalance``): the rent starts
    /// with ``RentItem/status`` `0` and waits up to 20 minutes for its first SMS; the first SMS that is not a
    /// `notify` notice confirms it (`status` `1`) and charges the price. Without one the rent closes and the
    /// reservation is released.
    ///
    /// - Parameters:
    ///   - country: Country code.
    ///   - days: One of the tariff's ``RentTariff/days`` keys.
    ///   - extendable: `false` makes the rent non-extendable for good (`extension=0`).
    ///
    /// Throws ``OnlineSimError/noNumber(code:message:)``; ``OnlineSimError/api(code:message:)`` `UNDEFINED_DAYS`,
    /// `UNDEFINED_COUNTRY`, `WARNING_LOW_BALANCE`, `TRY_AGAIN_LATER`.
    public func get(country: Int = 7, days: Int = 1, extension extendable: Bool = true) async throws -> RentItem {
        try await requester.call(
            ItemAnswer.self, "rent/getRentNum.php",
            query: [("country", String(country)), ("days", String(days)), ("extension", flag(extendable))]
                + Self.detail
        ).item
    }

    /// All rents of the account.
    public func state() async throws -> [RentItem] {
        try await requester.call(ListAnswer.self, "rent/getRentState.php", query: Self.detail).list
    }

    /// One rent. Throws ``OnlineSimError/api(code:message:)`` `ERROR_NO_OPERATIONS` when it does not exist.
    public func stateOne(_ tzid: Int) async throws -> RentItem {
        let list = try await requester.call(
            ListAnswer.self, "rent/getRentState.php", query: [("tzid", String(tzid))] + Self.detail
        ).list
        guard let item = list.first else { throw OnlineSimError.api("ERROR_NO_OPERATIONS") }
        return item
    }

    /// Extends a rent by `days` days and charges the balance at once. Only confirmed rents (`status` `1` or `4`)
    /// created with `extension: true`.
    ///
    /// Throws ``OnlineSimError/api(code:message:)`` `TRY_AGAIN_LATER` (unknown tzid, not confirmed yet or closed,
    /// not extendable, unknown period, a repeat within 10 s), `WARNING_LOW_BALANCE`.
    public func extend(_ tzid: Int, days: Int = 1) async throws -> RentItem {
        try await requester.call(
            ItemAnswer.self, "rent/extendRentState.php",
            query: [("tzid", String(tzid)), ("days", String(days))] + Self.detail
        ).item
    }

    /// Rent prices of every country, keyed by country code. No key needed.
    public func tariffs() async throws -> [Int: RentTariff] {
        try await requester.call(PHPMap<Int, RentTariff>.self, "rent/tariffsRent.php").map
    }

    /// Rent prices of one country. No key needed.
    /// Throws ``OnlineSimError/api(code:message:)`` `NO_COUNTRY` for a country without rent.
    public func tariffsOne(country: Int = 7) async throws -> RentTariff {
        // An unknown country answers `[]`.
        guard
            let tariff = try await requester.call(
                OneTariff.self, "rent/tariffsRent.php", query: [("country", String(country))]
            ).tariff
        else { throw OnlineSimError.api("NO_COUNTRY") }
        return tariff
    }

    /// Returns the number before the rent period ends. A rent that is not confirmed yet (`status` `0`) and has no
    /// SMS can be closed only after 120 s; then, or with only `notify` SMS, the reservation is released. With a real
    /// SMS the rent is confirmed (charged) and closed. A confirmed rent closes without a refund.
    ///
    /// Throws ``OnlineSimError/api(code:message:)`` `ERROR_NO_OPERATIONS`, `NO_COMPLETE_TZID`, `NO_CLOSE_RENT_US`.
    public func close(_ tzid: Int) async throws {
        try await requester.send("rent/closeRentNum.php", query: [("tzid", String(tzid))])
    }

    /// A tariff, or `nil` for the `[]` answer.
    private struct OneTariff: Decodable {
        let tariff: RentTariff?
        init(from decoder: Decoder) throws {
            tariff =
                (try? decoder.singleValueContainer().decode([JSONValue].self)) != nil
                ? nil : try RentTariff(from: decoder)
        }
    }
}

/// One SMS of a rent.
public struct RentSms: Sendable, Hashable, Codable {
    public var id: Int
    /// Sender. `notify`: a notice about a prohibited sender (does not confirm the rent); `init`: record of a rent
    /// confirmed at once.
    public var service: String
    public var text: String
    /// Code extracted from the SMS; empty when none. The server's integer `0` of a `notify` SMS becomes `"0"`.
    public var code: String
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, service, text, code
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        service = try c.decodeIfPresent(String.self, forKey: .service) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        code = (try? c.decodeIfPresent(String.self, forKey: .code)) ?? c.lossyInt(.code).map(String.init) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

/// A rent operation.
public struct RentItem: Sendable, Hashable, Codable {
    public var tzid: Int
    /// `0`: reserved, waiting for the first SMS; `1`: active (confirmed), charged; `4`: frozen.
    public var status: Int
    /// Number without the country code.
    public var number: String
    public var country: Int
    /// Cost of the rent incl. extensions, USD (the server sends a number, or a decimal string in
    /// ``RentAPI/state()``). Reserved while ``status`` is `0`, charged once confirmed.
    public var sum: Double
    public var days: Int
    public var hours: Int
    /// Minutes left.
    public var time: Int
    /// Seconds left.
    public var timeSeconds: Int?
    public var guardIntervalRemainingSeconds: Int?
    /// `0` not extendable, `1` extendable, `2` auto-extension.
    public var `extension`: Int
    public var daysAutoextend: Int?
    public var rent: Int?
    public var startTime: String
    public var stopTime: String
    public var checkedTime: String?
    public var checked: Bool?
    public var freeze: Bool?
    public var reload: Int?
    public var mExt: Bool?
    /// Price of one day of extension; 0 when not configured.
    public var dayExtend: Double?
    /// Days → extension price, USD; empty when not extendable.
    public var extend: [Int: Double]
    public var webhookURL: String?
    /// SMS, newest first.
    public var messages: [RentSms]

    enum CodingKeys: String, CodingKey {
        case tzid, status, number, country, sum, days, hours, time, `extension`, rent, checked, freeze, reload,
            extend, messages
        case timeSeconds = "time_seconds"
        case guardIntervalRemainingSeconds = "guard_interval_remaining_seconds"
        case daysAutoextend = "days_autoextend"
        case startTime = "start_time"
        case stopTime = "stop_time"
        case checkedTime = "checked_time"
        case mExt = "m_ext"
        case dayExtend = "day_extend"
        case webhookURL = "webhook_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tzid = try c.lossyInt(.tzid) ?? c.decode(Int.self, forKey: .tzid)
        status = c.lossyInt(.status) ?? 0
        number = try (try? c.decode(String.self, forKey: .number)) ?? String(c.decode(Int.self, forKey: .number))
        country = c.lossyInt(.country) ?? 0
        sum = c.lossyDouble(.sum) ?? 0
        days = c.lossyInt(.days) ?? 0
        hours = c.lossyInt(.hours) ?? 0
        time = c.lossyInt(.time) ?? 0
        timeSeconds = c.lossyInt(.timeSeconds)
        guardIntervalRemainingSeconds = c.lossyInt(.guardIntervalRemainingSeconds)
        `extension` = c.lossyInt(.extension) ?? 0
        daysAutoextend = c.lossyInt(.daysAutoextend)
        rent = c.lossyInt(.rent)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        stopTime = try c.decodeIfPresent(String.self, forKey: .stopTime) ?? ""
        checkedTime = try? c.decodeIfPresent(String.self, forKey: .checkedTime)
        checked = try? c.decodeIfPresent(Bool.self, forKey: .checked)
        freeze = try? c.decodeIfPresent(Bool.self, forKey: .freeze)
        reload = c.lossyInt(.reload)
        mExt = try? c.decodeIfPresent(Bool.self, forKey: .mExt)
        dayExtend = c.lossyDouble(.dayExtend)
        extend = try c.phpMap(.extend)
        webhookURL = try? c.decodeIfPresent(String.self, forKey: .webhookURL)
        messages = (try? c.decodeIfPresent([RentSms].self, forKey: .messages)) ?? []
    }
}

/// Rent prices of one country.
public struct RentTariff: Sendable, Hashable, Codable {
    public var code: Int
    public var name: String
    public var isEnabled: Bool
    public var isNew: Bool
    public var position: Int
    /// `1`: rents can be extended.
    public var extend: Int
    public var confirm: Bool?
    /// Rent days → price, USD.
    public var days: [Int: Double]
    /// Rent days → numbers available.
    public var count: [Int: Int]
    public var extCounts: [Int: Int]?

    enum CodingKeys: String, CodingKey {
        case code, name, position, extend, confirm, days, count
        case isEnabled = "enabled"
        case isNew = "new"
        case extCounts = "ext_counts"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(Int.self, forKey: .code)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        isNew = (try? c.decodeIfPresent(Bool.self, forKey: .isNew)) ?? false
        position = c.lossyInt(.position) ?? 0
        extend = c.lossyInt(.extend) ?? 0
        confirm = try? c.decodeIfPresent(Bool.self, forKey: .confirm)
        days = try c.phpMap(.days)
        count = try c.phpMap(.count)
        extCounts = c.contains(.extCounts) ? try c.phpMap(.extCounts) : nil
    }
}
