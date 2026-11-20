import Foundation

/// Public free numbers: `client.free`. No key needed.
public struct FreeAPI: Sendable {
    let requester: Requester

    /// Countries, the numbers of the selected country and the SMS of the selected number, in one call.
    ///
    /// - Parameters:
    ///   - country: Country code (server default 44); an unknown one falls back to the first available.
    ///   - number: Number **without** the country code, as the keys of ``FreeList/numbers``.
    ///   - page: Page of ``FreeList/messages``.
    ///   - count: SMS per page, 10–500.
    public func list(country: Int? = nil, number: String? = nil, page: Int? = nil, count: Int? = nil)
        async throws -> FreeList
    {
        try await requester.call(
            "getFreeList",
            query: [
                ("country", country.map(String.init)), ("number", number), ("page", page.map(String.init)),
                ("count", count.map(String.init)),
            ])
    }
}

/// Result of ``FreeAPI/list(country:number:page:count:)``.
public struct FreeList: Sendable, Hashable, Codable {
    public var countries: [FreeCountry]
    /// Keyed by the number without the country code.
    public var numbers: [String: FreeNumber]
    /// SMS of the selected number.
    public var messages: FreeMessages

    enum CodingKeys: String, CodingKey { case countries, numbers, messages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        countries = try c.decodeIfPresent([FreeCountry].self, forKey: .countries) ?? []
        numbers = try c.phpMap(.numbers)
        messages = try c.decode(FreeMessages.self, forKey: .messages)
    }
}

/// A country with free numbers.
public struct FreeCountry: Sendable, Hashable, Codable {
    public var country: Int
    /// Display name; `nil` when the server has none.
    public var countryText: String?
    /// Slug, e.g. `united_kingdom`; `nil` when the server has none.
    public var countryOriginal: String?

    enum CodingKeys: String, CodingKey {
        case country
        case countryText = "country_text"
        case countryOriginal = "country_original"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = try c.lossyInt(.country) ?? c.decode(Int.self, forKey: .country)
        countryText = c.lossyString(.countryText)
        countryOriginal = c.lossyString(.countryOriginal)
    }
}

/// A free number.
public struct FreeNumber: Sendable, Hashable, Codable {
    public var country: Int
    /// Country slug; `nil` when the server has none.
    public var countryOriginal: String?
    /// With the country code, without `+`.
    public var fullNumber: String
    public var dataHumans: String
    public var isArchive: Bool

    enum CodingKeys: String, CodingKey {
        case country
        case countryOriginal = "country_original"
        case fullNumber = "full_number"
        case dataHumans = "data_humans"
        case isArchive = "is_archive"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = c.lossyInt(.country) ?? 0
        countryOriginal = c.lossyString(.countryOriginal)
        fullNumber = c.lossyString(.fullNumber) ?? ""
        dataHumans = c.lossyString(.dataHumans) ?? ""
        isArchive = (try? c.decodeIfPresent(Bool.self, forKey: .isArchive)) ?? false
    }
}

/// One SMS to a free number.
public struct FreeMessage: Sendable, Hashable, Codable {
    public var id: Int
    public var text: String
    /// Sender.
    public var inNumber: String
    public var myNumber: String
    /// `-` when no code was found.
    public var code: String
    public var createdAt: String
    public var dataHumans: String

    enum CodingKeys: String, CodingKey {
        case id, text, code
        case inNumber = "in_number"
        case myNumber = "my_number"
        case createdAt = "created_at"
        case dataHumans = "data_humans"
    }
}

/// A page of ``FreeMessage`` plus the selected number and country.
public struct FreeMessages: Sendable, Hashable, Codable {
    /// The paginator; ``data`` is a shortcut to its items.
    public var page: Paginator<FreeMessage>
    /// The selected number, without the country code.
    public var number: String?
    /// The selected country.
    public var country: Int

    /// The SMS of this page.
    public var data: [FreeMessage] { page.data }

    enum CodingKeys: String, CodingKey { case number, country }

    public init(from decoder: Decoder) throws {
        page = try Paginator(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decodeIfPresent(String.self, forKey: .number)
        country = c.lossyInt(.country) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        try page.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(number, forKey: .number)
        try c.encode(country, forKey: .country)
    }
}
