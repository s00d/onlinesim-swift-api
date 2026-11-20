# onlinesim-swift-api

[![CI](https://github.com/s00d/onlinesim-swift-api/actions/workflows/ci.yml/badge.svg)](https://github.com/s00d/onlinesim-swift-api/actions/workflows/ci.yml)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fs00d%2Fonlinesim-swift-api%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/s00d/onlinesim-swift-api)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fs00d%2Fonlinesim-swift-api%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/s00d/onlinesim-swift-api)

Swift client for the [OnlineSim](https://onlinesim.io) API: SMS numbers, rent, account and free numbers.
async/await, `Sendable`, zero dependencies (`URLSession`). Swift 5.9+, macOS 12, iOS 15, tvOS 15, watchOS 8, Linux.

```swift
// Package.swift
.package(url: "https://github.com/s00d/onlinesim-swift-api.git", from: "1.0.0"),
// target dependencies
.product(name: "OnlineSim", package: "onlinesim-swift-api"),
```

```swift
import OnlineSim

let client = OnlineSimClient(apiKey: "your-api-key")

let balance = try await client.user.balance()
print("available: \(balance.balance - max(balance.zbalance, 0)) USD")

let order = try await client.numbers.getWithNumber("google", country: 44)
print("enter \(order.number) in the app")
print("code:", try await client.numbers.waitCode(order.tzid))
```

## Testing

`MockOnlineSim` is a built-in offline fake of the API: test your integration without network, key or money.
More in the [testing guide](https://s00d.github.io/onlinesim-swift-api/testing).

```swift
import OnlineSim

let mock = MockOnlineSim(balance: 10)
let client = mock.client()

let tzid = try await client.numbers.get("google", country: 44)
try mock.addSmsAfter(tzid, "Your code: 123-456", polls: 2) // arrives on the third poll
let code = try await client.numbers.waitCode(tzid, interval: 0)
precondition(code == "123456")
precondition(mock.balance() == 9.8)
```

Documentation: **https://s00d.github.io/onlinesim-swift-api/** · API reference: [Swift Package Index](https://swiftpackageindex.com/s00d/onlinesim-swift-api/documentation/onlinesim) · Changes: [CHANGELOG.md](CHANGELOG.md) · License: Apache-2.0
