---
title: Free numbers
description: Public numbers and their SMS — client.free. No API key needed.
navigation:
  order: 4
---

## list

Countries, the numbers of the selected country and the SMS of the selected number, in one call.

```swift
func list(country: Int? = nil, number: String? = nil, page: Int? = nil, count: Int? = nil) async throws -> FreeList
```

| Param | Type | Default | Description |
|---|---|---|---|
| `country` | `Int?` | `44` (server) | Country code; an unknown one falls back to the first available. |
| `number` | `String?` | first number | Number **without** the country code, as the keys of `numbers`. |
| `page` | `Int?` | `1` | Page of `messages`. |
| `count` | `Int?` | server default | SMS per page, 10–500. |

`FreeList`:

- `countries`: `[FreeCountry]` — `country`, `countryText?`, `countryOriginal?` (`nil` when the server has none)
- `numbers`: `[String: FreeNumber]` — `country`, `countryOriginal?`, `fullNumber`, `dataHumans`, `isArchive`; keyed by the short number
- `messages`: `FreeMessages` — `page` (a `Paginator<FreeMessage>`), `data` (its items), `number`, `country`; `FreeMessage` has `id`, `text`, `inNumber`, `myNumber`, `code`, `createdAt`, `dataHumans`; `code` is `-` when no code was found

```swift
let numbers = try await client.free.list(country: 44).numbers
if let short = numbers.keys.sorted().first {
    let messages = try await client.free.list(country: 44, number: short, count: 20).messages
    for sms in messages.data { print(sms.inNumber, sms.code, sms.text) }
}
```
