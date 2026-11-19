---
title: Changelog
description: Release notes of onlinesim-swift-api.
navigation:
  order: 7
---

The full history is in [CHANGELOG.md](https://github.com/s00d/onlinesim-swift-api/blob/main/CHANGELOG.md).

## 1.0.0

First release of the Swift SDK, on the same contract as the other OnlineSim SDKs (JS 2.1.0, PHP, Python, Go, Rust, Java, Ruby, .NET).

- `OnlineSimClient` with `numbers`, `rent`, `user` and `free` sections; `async throws` methods; `Sendable` everywhere (Swift 6 language mode ready).
- Swift 5.9+, macOS 12, iOS 15, tvOS 15, watchOS 8, Linux; zero dependencies (`URLSession`).
- The key is sent as a Bearer header, never in the URL; injectable `Transport` (your own `URLSession`).
- One error enum, `OnlineSimError`: `.api`, `.noNumber`, `.transport`, `.waitTimeout`, `.invalidPayload`.
- `numbers.waitCode`: interval and timeout in seconds, `keepOpen`, `since`, retries network errors, injectable `WaitClock`.
- `parseWebhook` for inbound webhooks; webhook URL set / clear / logs.
- `MockOnlineSim`: an offline fake of the API for your tests — see [Testing](/testing).
