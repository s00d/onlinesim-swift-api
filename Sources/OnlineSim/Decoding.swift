/// Client-side normalisation of server quirks, shared by the models and ``parseWebhook(_:)-(Data)``.

/// A map the server may send as an empty PHP array `[]` (or `null`): decodes to an empty map then.
/// Keys are converted from the JSON object's string keys (`Int` for country codes and rent days); keys that do
/// not convert are dropped.
struct PHPMap<Key: LosslessStringConvertible & Hashable, Value: Decodable>: Decodable {
    let map: [Key: Value]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() || (try? container.decode([JSONValue].self)) != nil {
            map = [:]
            return
        }
        let raw = try container.decode([String: Value].self)
        map = Dictionary(raw.compactMap { key, value in Key(key).map { ($0, value) } }, uniquingKeysWith: { a, _ in a })
    }
}

extension KeyedDecodingContainer {
    /// A number or a numeric string (`"1442.330"`); `nil` when missing or not numeric.
    func lossyDouble(_ key: Key) -> Double? {
        ((try? decodeIfPresent(JSONValue.self, forKey: key)) ?? nil)?.doubleValue
    }

    /// An integer or a numeric string (`"1520"`); `nil` when missing or not an integer.
    func lossyInt(_ key: Key) -> Int? {
        ((try? decodeIfPresent(JSONValue.self, forKey: key)) ?? nil)?.intValue
    }

    /// A string, or a number in its JSON form (`79001234567`); `nil` when missing, `null` or not a scalar.
    func lossyString(_ key: Key) -> String? {
        let value: JSONValue? = (try? decodeIfPresent(JSONValue.self, forKey: key)) ?? nil
        switch value {
        case .string(let s)?: return s
        case .int(let i)?: return String(i)
        case .double(let d)?: return String(d)
        default: return nil
        }
    }

    /// A map that may arrive as `[]`; empty when missing.
    func phpMap<MapKey: LosslessStringConvertible & Hashable, V: Decodable>(_ key: Key) throws -> [MapKey: V] {
        try decodeIfPresent(PHPMap<MapKey, V>.self, forKey: key)?.map ?? [:]
    }
}
