---
title: User
description: Balance, profile, payments and the webhook URL — client.user.
navigation:
  order: 3
---

## balance

Balance in USD.

```swift
func balance() async throws -> Balance
```

`Balance`: `balance`, `zbalance`, `income?` (all `Double`). `balance` includes the sum frozen by numbers and unconfirmed rents in progress (`zbalance`, which may be negative): available = `balance − max(zbalance, 0)`. `income` is the partner income. The server caches the answer for 60 s.

```swift
let balance = try await client.user.balance()
let available = balance.balance - max(balance.zbalance, 0)
```

Errors: `.api` `ERROR_WRONG_KEY`, `ACCOUNT_BLOCKED`, `API_ACCESS_DISABLED`, `API_ACCESS_IP`.

## profile

The account profile.

```swift
func profile() async throws -> Profile
```

`Profile`: `id`, `name?`, `username?`, `email?`, `locale?`, `currency?`, `numberCountry?`, `numberReject`, `webhookURL?`, `number?` (`Int`), `country?` (`String`), `apiAccess?` (a `JSONValue`: `true` or a map of allowed IPs), …

```swift
let profile = try await client.user.profile()
print(profile.email ?? "", profile.webhookURL ?? "no webhook")
```

## paymentHistory

Top-up orders (paginated, newest first) and the available payment methods.

```swift
func paymentHistory(page: Int = 1) async throws -> PaymentHistory
```

`PaymentHistory`: `orders` (`Paginator<PaymentOrder>`), `paylist` (`[String: JSONValue]`), `domains?`, `forms?`, `currency?`, `buttons?`. `PaymentOrder.sum` stays a decimal string (`"89.00"`); `currency` and `formText` may be `nil`. `paylist` maps a group id to its payment methods; when the server sends a JSON array (ids 0, 1, 2…) its items are kept under the keys `"0"`, `"1"`, `"2"`…. `Paginator`: `currentPage`, `data`, `from?`, `to?`, `lastPage`, `perPage`, `total`, page URLs.

```swift
let orders = try await client.user.paymentHistory().orders
print("\(orders.total) orders, page \(orders.currentPage)/\(orders.lastPage)")
```

## setWebhookURL

Set the URL that receives SMS webhooks (see [Webhooks](/webhooks)).

```swift
func setWebhookURL(_ url: String) async throws
```

```swift
try await client.user.setWebhookURL("https://example.com/onlinesim-hook")
```

Errors: `.api` `VALIDATION_ERROR` for an invalid URL; `message` holds the server's field messages.

## clearWebhookURL

Remove the webhook URL, also from operations in progress.

```swift
func clearWebhookURL() async throws
```

```swift
try await client.user.clearWebhookURL()
```

## webhookLogs

Webhook delivery log, newest first, 10 per page.

```swift
func webhookLogs(page: Int = 1) async throws -> Paginator<WebhookLog>
```

`WebhookLog`: `id`, `userID`, `webhookURL`, `type`, `params`, `status`, `error?`, `createdAt`, `updatedAt` — `type` is `.receivingSms` or `.rentSms`, `status` is `success`, `fail` or `pending`, `params` the payload that was sent (a `WebhookPayload`).

```swift
let logs = try await client.user.webhookLogs()
for log in logs.data { print(log.createdAt, log.status, log.error ?? "") }
```
