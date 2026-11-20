# Testing

> Test your integration offline with MockOnlineSim — no network, key or money.

`MockOnlineSim` is an in-process fake of the OnlineSim API that ships with the package. It is a `Transport` that answers like the real backend — same shapes, same error codes, HTTP 456 for a wrong key (HTTP 200 `ERROR_WRONG_KEY` for none) — and keeps a balance, operations and rents. Your code talks to a normal `OnlineSimClient`, so nothing in it changes for tests. It is deterministic: no randomness, no clock, numbers and ids come from a counter.

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

<table>
<thead>
  <tr>
    <th>
      Parameter
    </th>
    
    <th>
      Default
    </th>
    
    <th>
      Description
    </th>
  </tr>
</thead>

<tbody>
  <tr>
    <td>
      <code>
        apiKey
      </code>
    </td>
    
    <td>
      <code>
        "mock-key"
      </code>
    </td>
    
    <td>
      Key the mock accepts. <code>
        mock.client()
      </code>
      
       uses it; <code>
        mock.client(apiKey: "x")
      </code>
      
       tests a wrong key.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        balance
      </code>
    </td>
    
    <td>
      <code>
        100
      </code>
    </td>
    
    <td>
      Starting balance, USD.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        prices
      </code>
    </td>
    
    <td>
      <code>
        [7: ["vkcom": 0.5, "telegram": 1.2, "google": 0.3], 44: ["google": 0.2, "vkcom": 0.36]]
      </code>
    </td>
    
    <td>
      Number prices; replace the defaults. Also feed <code>
        numbers.tariffs()
      </code>
      
      .
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        rentTariffs
      </code>
    </td>
    
    <td>
      <code>
        [7: MockRentTariff(days: [1: 1, 3: 2.5, 7: 5], extend: 1)]
      </code>
    </td>
    
    <td>
      Rent prices; <code>
        extend: 0
      </code>
      
       makes rents of that country non-extendable.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        guardInterval
      </code>
    </td>
    
    <td>
      <code>
        0
      </code>
    </td>
    
    <td>
      <code>
        > 0
      </code>
      
      : an operation without SMS, or an unconfirmed rent without any SMS, cannot be closed (<code>
        NO_COMPLETE_TZID
      </code>
      
      ).
    </td>
  </tr>
</tbody>
</table>

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

The state itself produces the real error codes too: `WARNING_LOW_BALANCE` when the balance is short, `NO_NUMBER` when `reject` matches the next number, `UNDEFINED_COUNTRY` / `ERROR_NO_SERVICE` for unknown prices, `ERROR_WRONG_TZID` for an unknown or closed operation (`next` too; `ERROR_NO_TZID` for tzid `0`), `UNDEFINED_COUNTRY` / `UNDEFINED_DAYS` for an unknown rent country or period, `TRY_AGAIN_LATER` for every refused `rent.extend`, `ERROR_NO_OPERATIONS` for an unknown rent in `rent.close`, `ERROR_WRONG_KEY` for a wrong key (HTTP 456) or no key (HTTP 200).

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

<table>
<thead>
  <tr>
    <th>
      Member
    </th>
    
    <th>
      Description
    </th>
  </tr>
</thead>

<tbody>
  <tr>
    <td>
      <code>
        client(apiKey:lang:devID:timeout:)
      </code>
    </td>
    
    <td>
      A normal <code>
        OnlineSimClient
      </code>
      
       wired to the mock.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        transport
      </code>
    </td>
    
    <td>
      The fake <code>
        Transport
      </code>
      
       (the mock itself).
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        addSms(_ tzid:_ text:service:) throws
      </code>
    </td>
    
    <td>
      An SMS arrives now at a number operation or a rent (detected by <code>
        tzid
      </code>
      
      ). Throws <code>
        MockOnlineSimError
      </code>
      
       for an unknown or closed one.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        addSmsAfter(_ tzid:_ text:polls:service:) throws
      </code>
    </td>
    
    <td>
      The SMS arrives after <code>
        polls
      </code>
      
       state requests for <code>
        tzid
      </code>
      
       (<code>
        numbers.state
      </code>
      
      /<code>
        stateOne
      </code>
      
      , <code>
        rent.state
      </code>
      
      /<code>
        stateOne
      </code>
      
      ).
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        failNext(_ code:endpoint:)
      </code>
    </td>
    
    <td>
      The next request (to <code>
        endpoint
      </code>
      
       only, e.g. <code>
        "getNum.php"
      </code>
      
      ) answers <code>
        {"response": code}
      </code>
      
      .
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        failNextTransport(status:endpoint:)
      </code>
    </td>
    
    <td>
      The next request fails with a non-JSON body and HTTP <code>
        status
      </code>
      
       (default <code>
        502
      </code>
      
      ).
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        setBalance(_:)
      </code>
      
       / <code>
        balance()
      </code>
    </td>
    
    <td>
      Set / read the total balance, USD (it includes the part frozen by open operations, as <code>
        user.balance()
      </code>
      
       reports it).
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        operations()
      </code>
      
       / <code>
        rents()
      </code>
    </td>
    
    <td>
      The current number operations / open rents (<code>
        [MockOperation]
      </code>
      
      , <code>
        [MockRent]
      </code>
      
       values), for assertions.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        requests
      </code>
    </td>
    
    <td>
      Log of the requests received (<code>
        [MockRequest]
      </code>
      
      ).
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        reset()
      </code>
    </td>
    
    <td>
      Back to the initializer's state.
    </td>
  </tr>
</tbody>
</table>

## What the mock does

- **Numbers**: `get` freezes the price; `close` after an SMS spends it, `close` without one refunds it; `ban` after an SMS answers `"0"`, like the server. Numbers are `+<country>9000000NN`, ids count from 1. `next` switches to the following SMS. The operation's `time` stays at 1200 s — there is no clock. Service ids in `tariffs` follow the alphabetical order of the slugs.
- **Rent**: `get` reserves the price (`status` `0`, `checked` `false`) and keeps the `extension` flag; the first SMS that is not `notify` confirms the rent (`status` `1`) and charges it — `addSms(tzid, text, service: "notify")` adds a notice with `code` `0` (`"0"` in `RentSms.code`) that confirms nothing. `extend` works on a confirmed rent and charges at once. `close` releases the reservation of an unconfirmed rent and gives no refund for a confirmed one. `sum` is a number in `get`/`extend` and a decimal string on the wire of `state`, like the server. SMS appear in `messages`, newest first.
- **User**: `balance` (frozen part included), a fixed profile, `setWebhookURL` accepts any `scheme://…` URL (`VALIDATION_ERROR` otherwise), `webhookLogs` lists the deliveries the mock *recorded* when an SMS arrived while a webhook URL was set — it makes no HTTP call; their `params` follow the real payload (`code` `""` without a code, rent `number` in digits without `+`, rent `timeLeft` in minutes). `paymentHistory` has no orders.
- **Free**: `free.list` returns two fixed countries (44 first) with one number and a few SMS each.
- Not imitated: anything that needs real time — the 5 s lock after `setOperationOk` (`INTERVAL_CONCURRENT_REQUESTS_ERROR`), the 10 s lock of `rent.extend`, the 120 s before an unconfirmed rent may be closed and its 20-minute wait for the first SMS. `guardInterval > 0` stands in for "too early to close".
