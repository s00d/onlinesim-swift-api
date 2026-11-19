---
title: Testing
description: Test your integration offline with MockOnlineSim — no network, key or money.
navigation:
  order: 6
---

`MockOnlineSim` is an in-process fake of the OnlineSim API that ships with the package. It is a `Transport` that answers like the real backend — same shapes, same error codes, HTTP 456 for a wrong key — and keeps a balance, operations and rents. Your code talks to a normal `OnlineSimClient`, so nothing in it changes for tests. It is deterministic: no randomness, no clock, numbers and ids come from a counter.

## Setup

```swift
import OnlineSim

let mock = MockOnlineSim(balance: 10)
let client = mock.client() // an OnlineSimClient wired to the mock
```

```swift
init(
    apiKey: String = "mock-key",
    balance: Double = 100,                                       // USD
    prices: [Int: [String: Double]] = MockOnlineSim.defaultPrices, // country → service → USD
    rentTariffs: [Int: MockRentTariff] = MockOnlineSim.defaultRentTariffs,
    guardInterval: Int = 0                                       // seconds
)
```

| Parameter | Default | Description |
|---|---|---|
| `apiKey` | `"mock-key"` | Key the mock accepts. `mock.client()` uses it; `mock.client(apiKey: "x")` tests a wrong key. |
| `balance` | `100` | Starting balance, USD. |
| `prices` | `[7: ["vkcom": 0.5, "telegram": 1.2, "google": 0.3], 44: ["google": 0.2, "vkcom": 0.36]]` | Number prices; replace the defaults. Also feed `numbers.tariffs()`. |
| `rentTariffs` | `[7: MockRentTariff(days: [1: 1, 3: 2.5, 7: 5], extend: 1)]` | Rent prices; `extend: 0` makes rents of that country non-extendable. |
| `guardInterval` | `0` | `> 0`: an operation without SMS cannot be closed (`NO_COMPLETE_TZID`). |

`mock.client(apiKey:lang:devID:timeout:)` takes the usual [client options](/#client-options) except `baseURL` and `transport`. To build the client yourself, pass `mock.transport` (the mock itself) as `transport`; any `baseURL` works:

```swift
import OnlineSim

let mock = MockOnlineSim()
let client = OnlineSimClient(apiKey: "mock-key", transport: mock.transport)
```

`MockOnlineSim` is a `Sendable` final class: its state is one value behind one lock, so the helpers below are synchronous and the mock can serve concurrent requests.

## A full example

Order a number, let an SMS arrive while `waitCode` polls, check the code and the money. `addSmsAfter` delivers the SMS after a number of polls instead of after some time, so `waitCode` runs with `interval: 0` and the test takes milliseconds.

```swift
import OnlineSim
import XCTest

final class SignUpTests: XCTestCase {
    func testReceivesTheCode() async throws {
        let mock = MockOnlineSim(balance: 10)
        let client = mock.client()

        let order = try await client.numbers.getWithNumber("google", country: 44)
        XCTAssertEqual(order.number, "+44900000001")

        try mock.addSmsAfter(order.tzid, "Your Google code: 123-456", polls: 2) // the third poll sees it
        let code = try await client.numbers.waitCode(order.tzid, interval: 0)

        XCTAssertEqual(code, "123456")
        XCTAssertEqual(mock.operations().first?.status, .tzOverOk) // waitCode closed it
        XCTAssertEqual(mock.balance(), 9.8) // the price is spent once an SMS arrived
    }
}
```

The `msg` of an operation is the code by default: the first run of 4–8 digits, with spaces and dashes between digits removed (`123-456` → `123456`); a text without such a run comes back whole. `messageToCode: false` (or `fullMessage` in `waitCode`) gives the full text.

## Errors

`failNext(_:endpoint:)` makes the next request answer `{"response": code}` — the client turns it into `OnlineSimError.api` (or `.noNumber`) exactly as for the real server. Pass `endpoint` to fail only that endpoint. `failNextTransport(status:endpoint:)` makes the next request fail with a non-JSON HTTP 502 (`.transport`).

```swift
import OnlineSim
import XCTest

final class FailureTests: XCTestCase {
    func testHandlesAMissingNumberAndANetworkHiccup() async throws {
        let mock = MockOnlineSim()
        let client = mock.client()

        mock.failNext("NO_NUMBER", endpoint: "getNum.php")
        do {
            _ = try await client.numbers.get("google")
            XCTFail("expected NO_NUMBER")
        } catch OnlineSimError.noNumber {}

        mock.failNextTransport(status: 503)
        do {
            _ = try await client.user.balance()
            XCTFail("expected a transport error")
        } catch OnlineSimError.transport(_, let status, _) {
            XCTAssertEqual(status, 503)
        }

        let balance = try await client.user.balance() // one-shot
        XCTAssertEqual(balance.balance, 100)
    }
}
```

The state itself produces the real error codes too: `WARNING_LOW_BALANCE` when the balance is short, `NO_NUMBER` when `reject` matches the next number, `UNDEFINED_COUNTRY` / `ERROR_NO_SERVICE` for unknown prices, `ERROR_WRONG_TZID` for an unknown or closed operation, `TRY_AGAIN_LATER` when extending a non-extendable rent, `ERROR_WRONG_KEY` (HTTP 456) for a wrong key.

## Inspecting requests

`mock.requests` lists every request received: `MockRequest(method:path:query:body:)`, `path` relative to `/api/`.

```swift
import OnlineSim
import XCTest

final class RequestTests: XCTestCase {
    func testSendsRejectAsACommaList() async throws {
        let mock = MockOnlineSim()
        _ = try await mock.client().numbers.get("google", country: 44, reject: ["4470", "4471"])

        XCTAssertEqual(mock.requests, [
            MockRequest(
                method: "GET", path: "getNum.php",
                query: ["service": "google", "country": "44", "reject": "4470,4471", "lang": "en"])
        ])
    }
}
```

## Control API

| Member | Description |
|---|---|
| `client(apiKey:lang:devID:timeout:)` | A normal `OnlineSimClient` wired to the mock. |
| `transport` | The fake `Transport` (the mock itself). |
| `addSms(_ tzid:_ text:service:) throws` | An SMS arrives now at a number operation or a rent (detected by `tzid`). Throws `MockOnlineSimError` for an unknown or closed one. |
| `addSmsAfter(_ tzid:_ text:polls:service:) throws` | The SMS arrives after `polls` state requests for `tzid` (`numbers.state`/`stateOne`, `rent.state`/`stateOne`). |
| `failNext(_ code:endpoint:)` | The next request (to `endpoint` only, e.g. `"getNum.php"`) answers `{"response": code}`. |
| `failNextTransport(status:endpoint:)` | The next request fails with a non-JSON body and HTTP `status` (default `502`). |
| `setBalance(_:)` / `balance()` | Set / read the total balance, USD (it includes the part frozen by open operations, as `user.balance()` reports it). |
| `operations()` / `rents()` | The current number operations / open rents (`[MockOperation]`, `[MockRent]` values), for assertions. |
| `requests` | Log of the requests received (`[MockRequest]`). |
| `reset()` | Back to the initializer's state. |

## What the mock does

- **Numbers**: `get` freezes the price; `close` after an SMS spends it, `close` without one refunds it; `ban` after an SMS answers `"0"`, like the server. Numbers are `+<country>9000000NN`, ids count from 1. `next` switches to the following SMS. The operation's `time` stays at 1200 s — there is no clock. Service ids in `tariffs` follow the alphabetical order of the slugs.
- **Rent**: `get` charges at once and keeps the `extension` flag; `extend` charges again; `close` removes the rent. SMS appear in `messages`, newest first.
- **User**: `balance` (frozen part included), a fixed profile, `setWebhookURL` validates `http(s)` URLs (`VALIDATION_ERROR` otherwise), `webhookLogs` lists the deliveries the mock *recorded* when an SMS arrived while a webhook URL was set — it makes no HTTP call. `paymentHistory` is empty.
- **Free**: `free.list` returns two fixed countries with one number and a few SMS each.
- Not imitated: the server's 5 s lock after `setOperationOk` (`INTERVAL_CONCURRENT_REQUESTS_ERROR`) and anything else that needs real time.
