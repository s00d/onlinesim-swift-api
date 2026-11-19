/// Any JSON value.
///
/// Used where the API sends free-form data (`PaymentHistory.paylist`, `Profile.apiAccess`), for the bodies the
/// ``MockOnlineSim`` logs and answers, and internally to inspect the `response` field of every answer.
/// Integers and fractional numbers are kept apart so that `1520` stays an ``int(_:)``.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// The value of `key` when this is an object.
    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    /// The string, or `nil` when this is not a string.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// An integer from an integer, an integral double or a numeric string (`"430"`); `nil` otherwise.
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(exactly: d)
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            return Int(trimmed) ?? Double(trimmed).flatMap { Int(exactly: $0) }
        default: return nil
        }
    }

    /// A number from a number or a numeric string (`"1442.330"`); `nil` when missing or not numeric.
    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d.isFinite ? d : nil
        case .string(let s):
            guard let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite else { return nil }
            return d
        default: return nil
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
