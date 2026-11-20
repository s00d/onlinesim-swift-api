import Foundation

/// Every error thrown by the SDK.
///
/// ```swift
/// do {
///     _ = try await client.numbers.get("google", country: 44)
/// } catch OnlineSimError.noNumber {
///     // try another country or later
/// } catch let error as OnlineSimError where error.code != nil {
///     print(error.code ?? "", error.message) // e.g. WARNING_LOW_BALANCE
/// }
/// ```
public enum OnlineSimError: Error, Sendable, Hashable {
    /// The API answered with an error code in `response` (also a wrong key, HTTP 456, and the rate limit,
    /// HTTP 429 `TRY_AGAIN_LATER`).
    ///
    /// `message` is the server's text when it sends one, otherwise ``messages``[code], otherwise the code itself.
    case api(code: String, message: String)

    /// No number is available right now (`NO_NUMBER`). Retry later or pick another country.
    ///
    /// An API error too: ``code`` and ``message`` are set as for ``api(code:message:)``.
    case noNumber(code: String, message: String)

    /// Network failure, request timeout, or a response that is not the expected JSON.
    ///
    /// `status` is `nil` when no response arrived; `body` holds the first 500 characters of the response body.
    case transport(message: String, status: Int?, body: String)

    /// ``NumbersAPI/waitCode(_:interval:timeout:keepOpen:fullMessage:since:clock:)`` got no code within `timeout` seconds.
    case waitTimeout(tzid: Int, timeout: TimeInterval)

    /// ``parseWebhook(_:)-(Data)`` got input that is not a JSON object.
    case invalidPayload(message: String)

    /// The API error code for ``api(code:message:)`` and ``noNumber(code:message:)``, `nil` for the other cases.
    public var code: String? {
        switch self {
        case .api(let code, _), .noNumber(let code, _): return code
        default: return nil
        }
    }

    /// A readable description of the error.
    public var message: String {
        switch self {
        case .api(_, let message), .noNumber(_, let message), .transport(let message, _, _),
            .invalidPayload(let message):
            return message
        case .waitTimeout(let tzid, let timeout):
            return "No code for operation \(tzid) within \(seconds(timeout))"
        }
    }

    /// An API error for `code`, ``noNumber(code:message:)`` for the no-number codes.
    /// An empty `message` falls back to ``messages``, then to the code.
    public static func api(_ code: String, message: String? = nil) -> OnlineSimError {
        let text = message.flatMap { $0.isEmpty ? nil : $0 } ?? messages[code] ?? code
        if code == "NO_NUMBER" { return .noNumber(code: code, message: text) }
        return .api(code: code, message: text)
    }

    /// Fallback messages for error codes the server sends without a `message`.
    public static let messages: [String: String] = [
        "ACCOUNT_BLOCKED": "Account is blocked",
        "ACCOUNT_CLEANED": "Account was deleted",
        "USER_NOT_ACTIVATED": "Account email is not confirmed",
        "ERROR_WRONG_KEY": "Wrong or missing API key",
        "ERROR_NO_SERVICE": "Service is not specified",
        "API_ACCESS_DISABLED": "API access is disabled in the profile",
        "API_ACCESS_IP": "API access from this IP is not allowed in the profile",
        "ERROR_NO_TZID": "tzid is not specified",
        "ERROR_WRONG_TZID": "Wrong tzid",
        "ERROR_NO_OPERATIONS": "No operations",
        "ERROR_UNDEFINED": "Unexpected server error, try again",
        "NO_NUMBER": "No numbers available for this service right now",
        "NO_COUNTRY": "Country not found",
        "UNDEFINED_COUNTRY": "Unknown country",
        "WARNING_LOW_BALANCE": "Not enough balance",
        "EXCEEDED_CONCURRENT_OPERATIONS": "Too many concurrent operations for this account",
        "INTERVAL_CONCURRENT_REQUESTS_ERROR": "Too many concurrent requests, try again in a few seconds",
        "TRY_AGAIN_LATER": "Rate limit exceeded or temporary error, try again later",
        "FORWARD_NOT_SUPPORTED": "Number forwarding is no longer available",
        "ERROR_PARAMS": "Wrong parameters",
        "NO_COMPLETE_TZID": "The operation cannot be closed yet",
        "NO_CLOSE_RENT_US": "US rent numbers cannot be closed early",
        "UNDEFINED_DAYS": "Unknown rent period",
        "VALIDATION_ERROR": "Validation failed",
        "0": "Ban not applied: the operation already has an SMS",
        "TZ_OVER_OK": "Operation finished without a new code",
        "ERROR_NO_ITEMS": "Operation failed",
    ]
}

extension OnlineSimError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { message }

    public var description: String {
        switch self {
        case .api(let code, let message), .noNumber(let code, let message): return "\(code): \(message)"
        default: return message
        }
    }
}

/// `30 s`, `0.5 s`.
func seconds(_ interval: TimeInterval) -> String {
    interval == interval.rounded() && abs(interval) < 1e15 ? "\(Int(interval)) s" : "\(interval) s"
}
