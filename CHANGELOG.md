# Changelog

## 1.0.1

Aligned with the regenerated backend API spec.

### Fixed

- Decoding: `NumberOperation.response` is optional (absent when no number could be issued; a getState item without it no longer fails to decode, which made `waitCode` poll until its timeout); `PaymentOrder.currency`/`formText`, `FreeCountry.countryText`/`countryOriginal` and `FreeNumber.countryOriginal` accept `null` (`String?`); `Profile.number` is `Int?` and `Profile.country` is `String?` (they were swapped). The changed models decode leniently.
- `RentSms.code`: the integer `0` of a `notify` SMS is normalised to `"0"`; rent `sum` is read from a number or a decimal string.
- `user.paymentHistory()` no longer drops `paylist` when the server sends it as a JSON array (ids 0, 1, 2…): its items are kept under the keys `"0"`, `"1"`, `"2"`…
- `numbers.waitCode` retries `.api` `TRY_AGAIN_LATER` (HTTP 429 rate limit), `ERROR_UNDEFINED` and `INTERVAL_CONCURRENT_REQUESTS_ERROR` until its timeout instead of throwing at once.
- Error messages: `"0"` (ban not applied, the operation already has an SMS), `ACCOUNT_CLEANED`, `USER_NOT_ACTIVATED`, `ERROR_UNDEFINED`, `FORWARD_NOT_SUPPORTED` added; `ERROR_NO_KEY`, `NO_NUMBER_FOR_FORWARD`, `ACCOUNT_IDENTIFICATION_REQUIRED`, `API_DISABLED` (no longer sent) removed; `.noNumber` only for `NO_NUMBER`; `ERROR_WRONG_KEY` reads "Wrong or missing API key".
- `MockOnlineSim` follows the backend: `setOperationRevise` answers `{"tzid":"N","response":"1"}` and `ERROR_WRONG_TZID` / `ERROR_NO_TZID`; `setOperationOk` tzid `0` → `ERROR_NO_TZID`; a missing key is HTTP 200 `ERROR_WRONG_KEY` (456 only for a wrong key, also on public endpoints); `getNum` with `number` adds `title`, `response_text`, `guard_interval_remaining_seconds`. Rent: `getRentNum` reserves the price (`status` 0) and the first non-`notify` SMS confirms and charges it, unknown country → `UNDEFINED_COUNTRY`, `sum` a number in getRentNum/extendRentState and a string in getRentState, `guard_interval_remaining_seconds` with `number`; `extendRentState` refusals are all `TRY_AGAIN_LATER`; `closeRentNum` unknown tzid → `ERROR_NO_OPERATIONS`, releases the reservation of an unconfirmed rent. `MockRent` gains `status` and `initialDays`. Webhook-log params: `code` `""` without a code, rent `number` in full digits, rent `time_left` in minutes, `time_start` per type. `profile.php` accepts any `scheme://…` URL. `getPaymentHistory` adds `forms`/`buttons`/`domains`; `getFreeList` lists 44 first, clamps `count` to 10..500, sends ISO-8601 `created_at` and `ignore`/`content`.
- Docs: rent reservation and `sum`, available = balance − max(zbalance, 0), `ban` answer `"0"`, `next` errors, webhook `number`/`timeLeft`/`timeStart`, the `waitCode` retry policy, the mock's behaviour.

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
