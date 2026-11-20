---
title: onlinesim-swift-api
description: Swift client for the OnlineSim API — SMS numbers, rent, account and free numbers. async/await, Sendable, zero dependencies.
---

## Install

Swift 5.9 or newer; macOS 12, iOS 15, tvOS 15, watchOS 8 or Linux. The client uses `URLSession` and has no dependencies. Add the package with Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/s00d/onlinesim-swift-api.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "OnlineSim", package: "onlinesim-swift-api")]),
]
```

In Xcode: **File → Add Package Dependencies…**, enter `https://github.com/s00d/onlinesim-swift-api.git`, add the `OnlineSim` library.

## Quick start

Check the balance, order a number, wait for the SMS code.

```swift
import OnlineSim

let client = OnlineSimClient(apiKey: "your-api-key")

let balance = try await client.user.balance()
print("available: \(balance.balance - max(balance.zbalance, 0)) USD")

let order = try await client.numbers.getWithNumber("google", country: 44)
print("enter \(order.number) in the app")

// Polls every 5 s for up to 10 min, then closes the operation.
let code = try await client.numbers.waitCode(order.tzid)
print("code: \(code)")
```

## Client options

```swift
import OnlineSim

let client = OnlineSimClient(
    apiKey: "your-api-key",
    lang: "en",
    timeout: 15
)
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `apiKey` | `String?` | `nil` | Sent as `Authorization: Bearer <apiKey>`, never in the URL. Not needed for tariffs and free numbers. |
| `baseURL` | `URL` | `https://onlinesim.host/api/` | API base; trailing slash optional. |
| `lang` | `String` | `"en"` | Language of server texts (`lang` query parameter). |
| `devID` | `String?` | `nil` | Partner developer id (`dev_id`), sent only when set. |
| `timeout` | `TimeInterval` | `30` | Per-request timeout, seconds. |
| `transport` | `any Transport` | `URLSessionTransport()` | Sends the HTTP requests: your own `URLSession` (proxy, custom TLS), or a fake in tests. |

`OnlineSimClient` is an immutable `Sendable` struct: create it once and share it between tasks. Sections: [`client.numbers`](/numbers), [`client.rent`](/rent), [`client.user`](/user), [`client.free`](/free). Webhook bodies are parsed by the standalone [`parseWebhook`](/webhooks).

Models are `Codable`, `Sendable` and `Hashable` structs with Swift names (`webhookURL`, `guardIntervalRemainingSeconds`). Server quirks are normalised: money that arrives as a decimal string (`balance`, rent `sum` in `rent.state`) becomes a `Double`, maps that arrive as an empty PHP array `[]` become empty dictionaries (`paymentHistory().paylist` sent as a JSON array keeps its items under the keys `"0"`, `"1"`…), and country codes and rent days are `Int` keys.

### Transport

Implement `Transport` to send the requests yourself:

```swift
public protocol Transport: Sendable {
    func send(_ request: TransportRequest) async throws -> TransportResponse
}
```

`TransportRequest` carries `method`, `url`, `headers`, `body` and `timeout`; return every HTTP status as a `TransportResponse(status:body:)` and throw only when no response arrived (`URLError(.timedOut)` is reported as a request timeout).

```swift
import Foundation
import OnlineSim

let configuration = URLSessionConfiguration.ephemeral
configuration.connectionProxyDictionary = [:] // your proxy settings
let client = OnlineSimClient(
    apiKey: "your-api-key",
    transport: URLSessionTransport(session: URLSession(configuration: configuration))
)
```

## Error handling

Every error is an `OnlineSimError`:

| Case | When |
|---|---|
| `.api(code:message:)` | The API answered with an error code (also a wrong key, HTTP 456, and the rate limit, HTTP 429 `TRY_AGAIN_LATER`). |
| `.noNumber(code:message:)` | `NO_NUMBER`: no number right now. An API error too. |
| `.transport(message:status:body:)` | Network error, request timeout, or a body that is not the expected JSON. `status` is `nil` without a response, `body` holds the first 500 characters. |
| `.waitTimeout(tzid:timeout:)` | `waitCode` got no code within its `timeout`. |
| `.invalidPayload(message:)` | `parseWebhook` got input that is not a JSON object. |

`error.code` is the API code for `.api` and `.noNumber` (`nil` otherwise); `error.message` is readable text for every case.

```swift
import OnlineSim

do {
    _ = try await client.numbers.get("google", country: 44)
} catch OnlineSimError.noNumber {
    // try another country or later
} catch let error as OnlineSimError {
    switch error {
    case .api(let code, let message): print(code, message) // e.g. WARNING_LOW_BALANCE
    case .transport(_, let status, let body): print("network", status ?? 0, body)
    default: throw error
    }
}
```

`message` is the server's text when it sends one, otherwise a short English description of the code (`OnlineSimError.messages`), otherwise the code itself. Profile validation failures become `.api` with code `VALIDATION_ERROR`.
