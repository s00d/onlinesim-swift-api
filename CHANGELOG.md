# Changelog

## 1.0.0

First release of the Swift SDK for the OnlineSim API, on the same contract as the other OnlineSim SDKs (the JS SDK 2.1.0 is the reference). SwiftPM package `OnlineSim`, distributed by git tags.

### Added

- `OnlineSimClient(apiKey:baseURL:lang:devID:timeout:transport:)` (`baseURL` default `https://onlinesim.host/api/`, `timeout` in seconds) with the sections `numbers`, `rent`, `user`, `free`. Every method is `async throws`; the client and every model are `Sendable` (checked with complete strict concurrency, built in the Swift 6 language mode in CI).
- Swift 5.9+, macOS 12, iOS 15, tvOS 15, watchOS 8 and Linux (`FoundationNetworking`). Zero dependencies.
- The API key is sent as `Authorization: Bearer <key>`, never in the query string. Booleans as `1`/`0`, `reject` as a comma list, unset parameters omitted, `orderby` lowercase.
- `Transport` protocol (`send(_:) async throws -> TransportResponse`) with the default `URLSessionTransport` (your own `URLSession` for a proxy or custom TLS).
- Errors: one `OnlineSimError` enum — `.api(code:message:)`, `.noNumber(code:message:)`, `.transport(message:status:body:)`, `.waitTimeout(tzid:timeout:)`, `.invalidPayload(message:)` — with `code` and `message`. An HTTP 456 wrong-key answer is `.api`; profile validation errors are `.api(code: "VALIDATION_ERROR", …)`.
- `numbers`: `price`, `get`, `getWithNumber`, `state`, `stateOne`, `next`, `close`, `ban`, `tariffs`, `tariffsOne`, `waitCode` (`interval` / `timeout` in seconds, `keepOpen`, `fullMessage`, `since`, injectable `WaitClock`; retries transient transport errors).
- `rent`: `get` (extendable by default), `state`, `stateOne`, `extend`, `tariffs`, `tariffsOne`, `close`.
- `user`: `balance`, `profile`, `paymentHistory`, `setWebhookURL`, `clearWebhookURL`, `webhookLogs`.
- `free.list`.
- `parseWebhook(_:)` for inbound `receiving_sms` / `rent_sms` webhooks (lenient), from `Data` or `String`.
- Codable models with Swift names (`webhookURL`, `guardIntervalRemainingSeconds`, …). Normalisation of server quirks: decimal-string money (`balance`, rent `sum`) parsed to `Double`, empty PHP maps `[]` read as empty dictionaries, country codes and rent days as `Int` keys.
- `MockOnlineSim`: a built-in, in-process fake of the OnlineSim API for testing integrations offline — no network, key, money or clock. `mock.client()` returns a normal `OnlineSimClient` wired to it (the mock is the `Transport`). Test helpers: `addSms`, `addSmsAfter`, `failNext`, `failNextTransport`, `setBalance`, `balance`, `operations`, `rents`, `requests`, `reset`. See the [testing guide](https://s00d.github.io/onlinesim-swift-api/testing).
- DocC comments on the public API, `.spi.yml` for Swift Package Index.
- Offline XCTest suite (fake transport, fixtures, mock tests through the real client), docs examples compiled against the package, opt-in integration test, CI on macOS (latest Xcode, plus iOS/tvOS/watchOS builds) and Linux (Swift 5.9 and latest), `swift format lint --strict`, smoke test of the package from a clean copy, documentation site (Nuxt Content).
