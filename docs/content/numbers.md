---
title: Numbers
description: Order a number, read its SMS, close it — client.numbers.
navigation:
  order: 1
---

An operation (`tzid`) is one ordered number. Order it with `get`/`getWithNumber`, read the SMS with `stateOne` or `waitCode`, finish it with `close` (or `ban`). Countries are phone codes (`7`, `44`, …), services are slugs (`google`, `vkcom`, …) as returned by `tariffs`. Every method is `async throws`.

## price

Price of one number, USD; `nil` when the country has no price for the service.

```swift
func price(_ service: String, country: Int = 7) async throws -> Double?
```

| Param | Type | Default | Description |
|---|---|---|---|
| `service` | `String` | — | Service slug. |
| `country` | `Int` | `7` | Country code. |

```swift
let usd = try await client.numbers.price("google", country: 44)
```

Errors: `.api` `ERROR_NO_SERVICE`, `UNDEFINED_COUNTRY`.

## get

Order a number; returns the operation id. Freezes the price on the balance.

```swift
func get(_ service: String, country: Int = 7, reject: [String] = []) async throws -> Int
```

| Param | Type | Default | Description |
|---|---|---|---|
| `service` | `String` | — | Service slug. |
| `country` | `Int` | `7` | Country code. |
| `reject` | `[String]` | profile list | Number prefixes to skip, e.g. `["4470"]`. |

```swift
let tzid = try await client.numbers.get("google", country: 44, reject: ["4470"])
```

Errors: `.noNumber`; `.api` `WARNING_LOW_BALANCE`, `ERROR_NO_SERVICE`, `UNDEFINED_COUNTRY`, `EXCEEDED_CONCURRENT_OPERATIONS`, `INTERVAL_CONCURRENT_REQUESTS_ERROR`, `TRY_AGAIN_LATER`.

## getWithNumber

Same as `get`, but returns the number right away.

```swift
func getWithNumber(_ service: String, country: Int = 7, reject: [String] = []) async throws -> NumberOrder
```

`NumberOrder`: `tzid`, `number` (with `+`), `country`, `time` (seconds left), `service`, `title?`, `guardIntervalRemainingSeconds?`.

```swift
let order = try await client.numbers.getWithNumber("google", country: 44)
print(order.tzid, order.number)
```

Errors: as `get`.

## state

All operations of the account; empty when there are none.

```swift
func state(messageToCode: Bool = true, orderBy: OrderBy = .asc, msgList: Bool = false) async throws -> [NumberOperation]
```

| Param | Type | Default | Description |
|---|---|---|---|
| `messageToCode` | `Bool` | `true` | `msg` is the code only; `false` — the full SMS text. |
| `orderBy` | `OrderBy` | `.asc` | Order of operations (`.asc`, `.desc`). |
| `msgList` | `Bool` | `false` | `msg` is a list of all SMS. |

`NumberOperation`: `tzid`, `response?`, `number?`, `service?`, `country?`, `sum?`, `time?`, `msg?`, `guardIntervalRemainingSeconds?`, …
`response` is an `OperationStatus` (`nil` when the server sends none: no number could be issued): `.tzInPool` (number being assigned), `.tzNumWait` (waiting for SMS), `.tzNumAnswer` (SMS arrived), `.tzOverOk` (finished), `.errorNoItems` (failed). `msg` is an `OperationMessage` — `.text(String)` by default, `.list([OperationSms])` with `msgList` — and `nil` until the first SMS. The server caches answers for a few seconds.

```swift
for op in try await client.numbers.state(orderBy: .desc) {
    print(op.tzid, op.response?.rawValue ?? "-", op.msg?.text ?? "-")
}
```

## stateOne

One operation.

```swift
func stateOne(_ tzid: Int, messageToCode: Bool = true, msgList: Bool = false) async throws -> NumberOperation
```

```swift
let op = try await client.numbers.stateOne(tzid)
if op.response == .tzNumAnswer { print(op.msg?.text ?? "") }
```

Errors: `.api` `ERROR_NO_OPERATIONS` when the operation does not exist (any more).

## waitCode

Poll the operation until a code arrives, then close it and return the code.

```swift
func waitCode(
    _ tzid: Int,
    interval: TimeInterval = 5,
    timeout: TimeInterval = 600,
    keepOpen: Bool = false,
    fullMessage: Bool = false,
    since: String? = nil,
    clock: WaitClock = .system
) async throws -> String
```

| Param | Type | Default | Description |
|---|---|---|---|
| `interval` | `TimeInterval` | `5` | Poll interval, seconds. |
| `timeout` | `TimeInterval` | `600` | Give up after, seconds. |
| `keepOpen` | `Bool` | `false` | Call `next(tzid)` instead of `close(tzid)`, to wait for another SMS. |
| `fullMessage` | `Bool` | `false` | Return the full SMS text instead of the code. |
| `since` | `String?` | `nil` | Ignore this value (the previous code). |
| `clock` | `WaitClock` | `.system` | `now` and `sleep`; inject a fake one in tests. |

Transient errors are retried until the timeout: `.transport`, and `.api` `TRY_AGAIN_LATER` (the HTTP 429 rate limit), `ERROR_UNDEFINED` and `INTERVAL_CONCURRENT_REQUESTS_ERROR`. Any other API error is thrown at once. Task cancellation stops the wait.

```swift
let first = try await client.numbers.waitCode(tzid, keepOpen: true)
let second = try await client.numbers.waitCode(tzid, since: first)
```

Errors: `.waitTimeout`; `.api` with code `TZ_OVER_OK` or `ERROR_NO_ITEMS` when the operation ended without a new code; any other API error from `stateOne`/`close`/`next`.

A fake clock for tests: nothing really waits.

```swift
import OnlineSim

let instant = WaitClock(now: { 0 }, sleep: { _ in })
let code = try await client.numbers.waitCode(tzid, clock: instant)
```

## next

Switch the operation to its next SMS and keep it open (for services that send several SMS).

```swift
func next(_ tzid: Int) async throws
```

```swift
try await client.numbers.next(tzid)
```

Errors: `.api` `ERROR_WRONG_TZID` (not an operation of your account), `ERROR_NO_TZID`.

## close

Finish the operation. An operation without SMS can be closed only after its guard interval (`guardIntervalRemainingSeconds`); every attempt locks the tzid for 5 s.

```swift
func close(_ tzid: Int) async throws
```

```swift
try await client.numbers.close(tzid)
```

Errors: `.api` `NO_COMPLETE_TZID`, `INTERVAL_CONCURRENT_REQUESTS_ERROR`, `ERROR_WRONG_TZID`.

## ban

Finish the operation and report the number as bad. Only before any SMS arrived.

```swift
func ban(_ tzid: Int) async throws
```

```swift
try await client.numbers.ban(tzid)
```

Errors: as `close`; `.api` with code `"0"` when the operation already has an SMS — nothing is changed then.

## tariffs

Services, prices and stock of every country, keyed by country code. No API key needed. The answer is large (a few MB); prefer `tariffsOne`.

```swift
func tariffs() async throws -> [Int: CountryStat]
```

`CountryStat`: `name`, `localeName?`, `position`, `code`, `other?`, `isNew`, `isEnabled`, `services`; `services` maps `service_<slug>` to `ServiceStat` (`count?`, `isPopular`, `code`, `price`, `id`, `service`, `slug`). `count` is `nil` when the server does not know the stock.

```swift
let all = try await client.numbers.tariffs()
print(all.count, "countries")
```

## tariffsOne

Services, prices and stock of one country.

```swift
func tariffsOne(country: Int = 7) async throws -> CountryStat
```

```swift
let uk = try await client.numbers.tariffsOne(country: 44)
for service in uk.services.values { print(service.slug, service.price, service.count ?? 0) }
```

Errors: `.api` `NO_COUNTRY`.
