import Foundation

/// Kind of operation a webhook is about.
public enum WebhookType: String, Sendable, Hashable, Codable {
    /// An SMS to a number operation.
    case receivingSms = "receiving_sms"
    /// An SMS to a rent.
    case rentSms = "rent_sms"
}

/// Inbound webhook body as normalised by ``parseWebhook(_:)-(Data)``: missing or malformed fields are `nil`.
public struct WebhookPayload: Sendable, Hashable, Codable {
    public var webhookType: WebhookType?
    /// `tzid` of the operation or rent.
    public var operationID: Int?
    public var userID: Int?
    public var countryCode: Int?
    /// Numbers: `+` and the full number (`+79001234567`), or `hidden`. Rent: the full number in digits without `+`
    /// (`79001234567`).
    public var number: String?
    /// Sender of the SMS, e.g. `VK`.
    public var sender: String?
    /// Full SMS text.
    public var message: String?
    /// Code extracted from the SMS; empty when none was found.
    public var code: String?
    /// Numbers: when the operation was ordered. Rent: when the SMS arrived. `YYYY-MM-DD HH:MM:SS`.
    public var timeStart: String?
    /// Time left: seconds for numbers, minutes for rent.
    public var timeLeft: Int?

    enum CodingKeys: String, CodingKey {
        case number, sender, message, code
        case webhookType = "webhook_type"
        case operationID = "operation_id"
        case userID = "user_id"
        case countryCode = "country_code"
        case timeStart = "time_start"
        case timeLeft = "time_left"
    }

    /// Lenient: numeric fields may be strings, numbers become strings where text is expected, unknown fields are dropped.
    init(_ object: [String: JSONValue]) {
        func string(_ key: CodingKeys) -> String? {
            switch object[key.rawValue] {
            case .string(let s)?: return s
            case .int(let i)?: return String(i)
            case .double(let d)?: return String(d)
            default: return nil
            }
        }
        webhookType = string(.webhookType).flatMap(WebhookType.init(rawValue:))
        operationID = object[CodingKeys.operationID.rawValue]?.intValue
        userID = object[CodingKeys.userID.rawValue]?.intValue
        countryCode = object[CodingKeys.countryCode.rawValue]?.intValue
        number = string(.number)
        sender = string(.sender)
        message = string(.message)
        code = string(.code)
        timeStart = string(.timeStart)
        timeLeft = object[CodingKeys.timeLeft.rawValue]?.intValue
    }

    public init(from decoder: Decoder) throws {
        guard case .object(let object) = try JSONValue(from: decoder) else {
            throw OnlineSimError.invalidPayload(message: "Webhook payload is not a JSON object")
        }
        self.init(object)
    }
}

/// Parses an inbound webhook body (`receiving_sms` or `rent_sms`).
///
/// Lenient: numeric fields may arrive as strings, missing or malformed fields become `nil`, unknown fields are
/// dropped. Throws ``OnlineSimError/invalidPayload(message:)`` only when the input is not a JSON object.
public func parseWebhook(_ payload: Data) throws -> WebhookPayload {
    guard let json = try? JSONDecoder().decode(JSONValue.self, from: payload) else {
        throw OnlineSimError.invalidPayload(message: "Webhook payload is not valid JSON")
    }
    guard case .object(let object) = json else {
        throw OnlineSimError.invalidPayload(message: "Webhook payload is not a JSON object")
    }
    return WebhookPayload(object)
}

/// Parses an inbound webhook body from a JSON string. See ``parseWebhook(_:)-(Data)``.
public func parseWebhook(_ payload: String) throws -> WebhookPayload {
    try parseWebhook(Data(payload.utf8))
}
