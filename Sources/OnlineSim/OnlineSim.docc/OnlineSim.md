# ``OnlineSim``

Swift client for the OnlineSim API: SMS numbers, rent, account and free numbers.

## Overview

```swift
import OnlineSim

let client = OnlineSimClient(apiKey: "your-api-key")
let order = try await client.numbers.getWithNumber("google", country: 44)
let code = try await client.numbers.waitCode(order.tzid)
```

Test your integration offline with ``MockOnlineSim``. Guides: <https://s00d.github.io/onlinesim-swift-api/>.

## Topics

### Client

- ``OnlineSimClient``
- ``NumbersAPI``
- ``RentAPI``
- ``UserAPI``
- ``FreeAPI``
- ``WaitClock``
- ``OnlineSimError``

### Transport

- ``Transport``
- ``TransportRequest``
- ``TransportResponse``
- ``URLSessionTransport``

### Webhooks

- ``parseWebhook(_:)-(Data)``
- ``parseWebhook(_:)-(String)``
- ``WebhookPayload``
- ``WebhookType``

### Testing

- ``MockOnlineSim``
- ``MockOnlineSimError``
- ``MockRequest``
- ``MockOperation``
- ``MockRent``
- ``MockRentTariff``
