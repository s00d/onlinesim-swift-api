import Foundation

/// Sleep and clock of ``NumbersAPI/waitCode(_:interval:timeout:keepOpen:fullMessage:since:clock:)``.
/// Inject a fake one in tests so nothing really waits.
///
/// ```swift
/// // No real waiting: every sleep returns at once.
/// let instant = WaitClock(now: { 0 }, sleep: { _ in })
/// ```
public struct WaitClock: Sendable {
    /// Current time, seconds, from any fixed origin (monotonic).
    public var now: @Sendable () -> TimeInterval
    /// Sleeps for the given seconds.
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        now: @escaping @Sendable () -> TimeInterval,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void
    ) {
        self.now = now
        self.sleep = sleep
    }

    /// The real clock: `ProcessInfo.systemUptime` and `Task.sleep`.
    public static let system = WaitClock(
        now: { ProcessInfo.processInfo.systemUptime },
        sleep: { seconds in
            if seconds > 0 { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        }
    )
}

extension NumbersAPI {
    /// API error codes ``waitCode(_:interval:timeout:keepOpen:fullMessage:since:clock:)`` retries: the rate limit
    /// (HTTP 429), a transient server error, too many concurrent requests.
    static let retryable: Set<String> = ["TRY_AGAIN_LATER", "ERROR_UNDEFINED", "INTERVAL_CONCURRENT_REQUESTS_ERROR"]

    /// Polls the operation until an SMS code arrives, then closes it (or calls ``next(_:)`` with `keepOpen`) and
    /// returns the code.
    ///
    /// - Parameters:
    ///   - tzid: The operation id.
    ///   - interval: Poll interval, seconds.
    ///   - timeout: Give up after this many seconds.
    ///   - keepOpen: Call ``next(_:)`` instead of ``close(_:)`` after the code, to wait for another SMS.
    ///   - fullMessage: Return the full SMS text instead of the code.
    ///   - since: Ignore this value (the previous code when waiting for the next one).
    ///   - clock: Sleep and clock; inject a fake one in tests.
    ///
    /// Transient errors are retried until the timeout: ``OnlineSimError/transport(message:status:body:)``, and
    /// ``OnlineSimError/api(code:message:)`` `TRY_AGAIN_LATER` (the HTTP 429 rate limit), `ERROR_UNDEFINED` and
    /// `INTERVAL_CONCURRENT_REQUESTS_ERROR`. Any other API error is thrown at once. A finished operation (`TZ_OVER_OK`, `ERROR_NO_ITEMS`) without a new code throws
    /// ``OnlineSimError/api(code:message:)`` with that state as the code; running out of `timeout` throws
    /// ``OnlineSimError/waitTimeout(tzid:timeout:)``.
    public func waitCode(
        _ tzid: Int,
        interval: TimeInterval = 5,
        timeout: TimeInterval = 600,
        keepOpen: Bool = false,
        fullMessage: Bool = false,
        since: String? = nil,
        clock: WaitClock = .system
    ) async throws -> String {
        let deadline = clock.now() + timeout
        while true {
            var operation: NumberOperation?
            do {
                operation = try await stateOne(tzid, messageToCode: !fullMessage)
            } catch OnlineSimError.transport {
                // transient: retried until the deadline
            } catch OnlineSimError.api(let code, _) where Self.retryable.contains(code) {
                // rate limit or a transient server error: retried until the deadline
            }

            if let operation {
                if let code = operation.msg?.text, !code.isEmpty, code != since {
                    if keepOpen { try await next(tzid) } else { try await close(tzid) }
                    return code
                }
                if let state = operation.response, state == .tzOverOk || state == .errorNoItems {
                    throw OnlineSimError.api(state.rawValue)
                }
            }

            let left = deadline - clock.now()
            if left <= 0 { throw OnlineSimError.waitTimeout(tzid: tzid, timeout: timeout) }
            try await clock.sleep(min(interval, left))
        }
    }
}
