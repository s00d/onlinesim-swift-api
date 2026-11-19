---
title: Webhooks
description: Receive SMS as HTTP callbacks and parse them with parseWebhook.
navigation:
  order: 5
---

Set a URL with [`client.user.setWebhookURL`](/user#setwebhookurl). For each SMS the server POSTs a JSON body to it: `webhook_type` `receiving_sms` for numbers, `rent_sms` for rents. Delivery attempts are listed by [`client.user.webhookLogs`](/user#webhooklogs).

## parseWebhook

Parse an inbound webhook body from the raw request body or a JSON string.

```swift
func parseWebhook(_ payload: Data) throws -> WebhookPayload
func parseWebhook(_ payload: String) throws -> WebhookPayload
```

Lenient: numeric fields may arrive as strings, missing or malformed fields become `nil`, unknown fields are dropped. It throws `OnlineSimError.invalidPayload` only when the input is not a JSON object.

Call it from the request handler of your HTTP server (Vapor, Hummingbird, …) with the body bytes:

```swift
import Foundation
import OnlineSim

func handleOnlineSimHook(body: Data) throws {
    let hook = try parseWebhook(body)
    if hook.webhookType == .receivingSms, let tzid = hook.operationID {
        print(tzid, hook.code ?? "no code")
    }
}
```

## Payload fields

| Field | JSON key | Type | Description |
|---|---|---|---|
| `webhookType` | `webhook_type` | `WebhookType?` | `.receivingSms` or `.rentSms`. |
| `operationID` | `operation_id` | `Int?` | `tzid` of the operation or rent. |
| `userID` | `user_id` | `Int?` | Account id. |
| `countryCode` | `country_code` | `Int?` | Country code of the number. |
| `number` | `number` | `String?` | The number, e.g. `+79001234567`. |
| `sender` | `sender` | `String?` | Sender of the SMS, e.g. `VK`. |
| `message` | `message` | `String?` | Full SMS text. |
| `code` | `code` | `String?` | Code extracted from the SMS. |
| `timeStart` | `time_start` | `String?` | Start of the operation. |
| `timeLeft` | `time_left` | `Int?` | Time left. |
