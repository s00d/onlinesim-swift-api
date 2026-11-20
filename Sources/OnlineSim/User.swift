import Foundation

/// Account: `client.user`.
public struct UserAPI: Sendable {
    let requester: Requester

    /// Balance in USD. ``Balance/balance`` includes the frozen ``Balance/zbalance``:
    /// available = balance − max(zbalance, 0).
    ///
    /// Throws ``OnlineSimError/api(code:message:)`` `ERROR_WRONG_KEY`, `ACCOUNT_BLOCKED`, `API_ACCESS_DISABLED`, …
    public func balance() async throws -> Balance {
        try await requester.call("getBalance.php", query: [("income", "1")])
    }

    /// The account profile.
    public func profile() async throws -> Profile {
        struct Answer: Decodable { let profile: Profile }
        return try await requester.call(Answer.self, "getProfile.php").profile
    }

    /// Top-up orders (paginated, newest first) and the available payment methods.
    public func paymentHistory(page: Int = 1) async throws -> PaymentHistory {
        try await requester.call("getPaymentHistory.php", query: [("page", String(page))])
    }

    /// Sets the URL that receives SMS webhooks.
    /// Throws ``OnlineSimError/api(code:message:)`` `VALIDATION_ERROR` for an invalid URL.
    public func setWebhookURL(_ url: String) async throws {
        try await requester.send("profile.php", body: ["profile": ["webhook_url": .string(url)]])
    }

    /// Removes the webhook URL (also from operations in progress).
    public func clearWebhookURL() async throws {
        try await requester.send("profile.php", body: ["profile": ["webhook_url": nil]])
    }

    /// Webhook delivery log, newest first, 10 per page.
    public func webhookLogs(page: Int = 1) async throws -> Paginator<WebhookLog> {
        struct Answer: Decodable { let data: Paginator<WebhookLog> }
        return try await requester.call(Answer.self, "webhook-logs", query: [("page", String(page))]).data
    }
}

/// Balance in USD.
public struct Balance: Sendable, Hashable, Codable {
    /// Total balance. Includes ``zbalance``: available = balance − max(zbalance, 0).
    public var balance: Double
    /// Sum frozen by numbers and unconfirmed rents in progress; may be negative.
    public var zbalance: Double
    /// Partner income.
    public var income: Double?

    public init(balance: Double, zbalance: Double, income: Double? = nil) {
        self.balance = balance
        self.zbalance = zbalance
        self.income = income
    }

    enum CodingKeys: String, CodingKey { case balance, zbalance, income }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balance = c.lossyDouble(.balance) ?? 0
        zbalance = c.lossyDouble(.zbalance) ?? 0
        income = c.lossyDouble(.income)
    }
}

/// The account profile.
public struct Profile: Sendable, Hashable, Codable {
    public var id: Int
    public var hashID: String?
    public var name: String?
    public var username: String?
    public var email: String?
    public var emailVerifiedAt: String?
    public var apikey: String?
    /// `true`, or a map of allowed IPs.
    public var apiAccess: JSONValue?
    public var locale: String?
    public var currency: String?
    public var numberCountry: Int?
    /// Rejected number prefixes (the server sends a list or a map; the values are kept).
    public var numberReject: [String]
    public var webhookURL: String?
    /// The profile's phone number.
    public var number: Int?
    /// The profile's country.
    public var country: String?
    public var numberRegion: Int?
    public var isAPI: Bool?
    public var active: String?
    public var block: Int?
    public var disable: Bool?
    public var verify: Int?
    public var ugroup: Int?
    public var sub: Int?
    public var firstLogin: Bool?
    public var isProjectSubscription: Bool?
    public var createdAt: String?
    public var notificationAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, username, email, apikey, locale, currency, number, country, active, block, disable, verify,
            ugroup, sub
        case hashID = "hash_id"
        case emailVerifiedAt = "email_verified_at"
        case apiAccess = "api_access"
        case numberCountry = "number_country"
        case numberReject = "number_reject"
        case webhookURL = "webhook_url"
        case numberRegion = "number_region"
        case isAPI = "is_api"
        case firstLogin = "first_login"
        case isProjectSubscription = "is_project_subscription"
        case createdAt = "created_at"
        case notificationAt = "notification_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        hashID = try? c.decodeIfPresent(String.self, forKey: .hashID)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        username = try? c.decodeIfPresent(String.self, forKey: .username)
        email = try? c.decodeIfPresent(String.self, forKey: .email)
        emailVerifiedAt = try? c.decodeIfPresent(String.self, forKey: .emailVerifiedAt)
        apikey = try? c.decodeIfPresent(String.self, forKey: .apikey)
        apiAccess = try c.decodeIfPresent(JSONValue.self, forKey: .apiAccess)
        locale = try? c.decodeIfPresent(String.self, forKey: .locale)
        currency = try? c.decodeIfPresent(String.self, forKey: .currency)
        numberCountry = c.lossyInt(.numberCountry)
        switch try c.decodeIfPresent(JSONValue.self, forKey: .numberReject) {
        case .array(let list)?: numberReject = list.compactMap(\.stringValue)
        case .object(let map)?: numberReject = map.keys.sorted().compactMap { map[$0]?.stringValue }
        default: numberReject = []
        }
        webhookURL = try? c.decodeIfPresent(String.self, forKey: .webhookURL)
        number = c.lossyInt(.number)
        country = c.lossyString(.country)
        numberRegion = c.lossyInt(.numberRegion)
        isAPI = try? c.decodeIfPresent(Bool.self, forKey: .isAPI)
        active = try? c.decodeIfPresent(String.self, forKey: .active)
        block = c.lossyInt(.block)
        disable = try? c.decodeIfPresent(Bool.self, forKey: .disable)
        verify = c.lossyInt(.verify)
        ugroup = c.lossyInt(.ugroup)
        sub = c.lossyInt(.sub)
        firstLogin = try? c.decodeIfPresent(Bool.self, forKey: .firstLogin)
        isProjectSubscription = try? c.decodeIfPresent(Bool.self, forKey: .isProjectSubscription)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        notificationAt = try? c.decodeIfPresent(String.self, forKey: .notificationAt)
    }
}

/// A top-up order.
public struct PaymentOrder: Sendable, Hashable, Codable {
    public var id: Int
    /// Decimal string, e.g. `"89.00"`.
    public var sum: String
    public var currency: String?
    public var stat: Int
    public var formText: String?
    public var statusText: String?
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, sum, currency, stat
        case formText = "form_text"
        case statusText = "status_text"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.lossyInt(.id) ?? c.decode(Int.self, forKey: .id)
        sum = c.lossyString(.sum) ?? ""
        currency = c.lossyString(.currency)
        stat = c.lossyInt(.stat) ?? 0
        formText = c.lossyString(.formText)
        statusText = c.lossyString(.statusText)
        createdAt = c.lossyString(.createdAt) ?? ""
    }
}

/// Top-up orders and payment methods.
public struct PaymentHistory: Sendable, Hashable, Codable {
    public var orders: Paginator<PaymentOrder>
    /// Payment methods by group id. When the server sends a JSON array (ids 0, 1, 2…), its items are kept under
    /// the keys `"0"`, `"1"`, `"2"`…
    public var paylist: [String: JSONValue]
    public var domains: [String]?
    public var forms: [String: String]?
    public var currency: [String: Double]?
    public var buttons: [String: [Int]]?

    enum CodingKeys: String, CodingKey { case orders, paylist, domains, forms, currency, buttons }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orders = try c.decode(Paginator<PaymentOrder>.self, forKey: .orders)
        switch try c.decodeIfPresent(JSONValue.self, forKey: .paylist) {
        case .object(let map)?: paylist = map
        case .array(let list)?:
            paylist = Dictionary(uniqueKeysWithValues: list.enumerated().map { (String($0.offset), $0.element) })
        default: paylist = [:]
        }
        domains = try? c.decodeIfPresent([String].self, forKey: .domains)
        forms = try? c.decodeIfPresent([String: String].self, forKey: .forms)
        currency = try? c.decodeIfPresent([String: Double].self, forKey: .currency)
        buttons = try? c.decodeIfPresent([String: [Int]].self, forKey: .buttons)
    }
}

/// One webhook delivery attempt.
public struct WebhookLog: Sendable, Hashable, Codable {
    public var id: Int
    public var userID: Int
    public var webhookURL: String
    public var type: WebhookType
    /// The payload that was sent.
    public var params: WebhookPayload
    /// `success`, `fail` or `pending`.
    public var status: String
    public var error: String?
    public var createdAt: String
    public var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, params, status, error
        case userID = "user_id"
        case webhookURL = "webhook_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Laravel paginator.
public struct Paginator<Item: Codable & Sendable & Hashable>: Sendable, Hashable, Codable {
    public var currentPage: Int
    public var data: [Item]
    public var from: Int?
    public var to: Int?
    public var lastPage: Int
    public var perPage: Int
    public var total: Int
    public var firstPageURL: String?
    public var lastPageURL: String?
    public var nextPageURL: String?
    public var prevPageURL: String?
    public var path: String?

    enum CodingKeys: String, CodingKey {
        case data, from, to, total, path
        case currentPage = "current_page"
        case lastPage = "last_page"
        case perPage = "per_page"
        case firstPageURL = "first_page_url"
        case lastPageURL = "last_page_url"
        case nextPageURL = "next_page_url"
        case prevPageURL = "prev_page_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentPage = c.lossyInt(.currentPage) ?? 1
        data = try c.decodeIfPresent([Item].self, forKey: .data) ?? []
        from = c.lossyInt(.from)
        to = c.lossyInt(.to)
        lastPage = c.lossyInt(.lastPage) ?? 1
        perPage = c.lossyInt(.perPage) ?? data.count
        total = c.lossyInt(.total) ?? data.count
        firstPageURL = try? c.decodeIfPresent(String.self, forKey: .firstPageURL)
        lastPageURL = try? c.decodeIfPresent(String.self, forKey: .lastPageURL)
        nextPageURL = try? c.decodeIfPresent(String.self, forKey: .nextPageURL)
        prevPageURL = try? c.decodeIfPresent(String.self, forKey: .prevPageURL)
        path = try? c.decodeIfPresent(String.self, forKey: .path)
    }
}
