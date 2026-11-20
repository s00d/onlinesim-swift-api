# Rent

> Rent a number for days and receive every SMS sent to it — client.rent.

A rent keeps a number for `days` days. Its SMS come in `RentItem.messages`, newest first.

`get` reserves the price (it shows in `zbalance`): the rent starts with `status` `0` and `checked` `false` and waits up to 20 minutes for its first SMS. The first SMS that is not a `notify` notice confirms it (`status` `1`) and charges the price; without one the rent closes and the reservation is released. Some countries (`confirm` in `tariffs`, e.g. US numbers) are confirmed and charged at once.

`RentItem`: `tzid`, `status`, `number`, `country`, `sum`, `days`, `hours`, `time`, `timeSeconds?`, `extension`, `extend`, `messages`, `startTime`, `stopTime`, `dayExtend?`, … —
`sum` is the cost in USD incl. extensions (a `Double`; the server sends a number, or a decimal string in `state`), `time` minutes left, `timeSeconds` seconds left,
`extension` `0` not extendable / `1` extendable / `2` auto-extension, `extend` maps days to the extension price (`[Int: Double]`, empty when not extendable),
`messages` is `[RentSms]`: `id`, `service`, `text`, `code`, `createdAt` — `code` is `""` when no code was found and `"0"` for a `notify` SMS (a prohibited sender; the server sends the integer `0`).

## get

Rent a number. The price is reserved; the first SMS charges it.

```swift
func get(country: Int = 7, days: Int = 1, extension: Bool = true) async throws -> RentItem
```

<table>
<thead>
  <tr>
    <th>
      Param
    </th>
    
    <th>
      Type
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
        country
      </code>
    </td>
    
    <td>
      <code>
        Int
      </code>
    </td>
    
    <td>
      <code>
        7
      </code>
    </td>
    
    <td>
      Country code.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        days
      </code>
    </td>
    
    <td>
      <code>
        Int
      </code>
    </td>
    
    <td>
      <code>
        1
      </code>
    </td>
    
    <td>
      One of the tariff's <code>
        days
      </code>
      
       keys.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        extension
      </code>
    </td>
    
    <td>
      <code>
        Bool
      </code>
    </td>
    
    <td>
      <code>
        true
      </code>
    </td>
    
    <td>
      <code>
        false
      </code>
      
       makes the rent non-extendable for good.
    </td>
  </tr>
</tbody>
</table>

```swift
let rent = try await client.rent.get(country: 7, days: 7)
print(rent.tzid, rent.number, rent.sum)
```

Errors: `.noNumber`; `.api` `UNDEFINED_DAYS`, `UNDEFINED_COUNTRY`, `WARNING_LOW_BALANCE`, `INTERVAL_CONCURRENT_REQUESTS_ERROR`, `TRY_AGAIN_LATER`.

## state

All rents of the account.

```swift
func state() async throws -> [RentItem]
```

```swift
for rent in try await client.rent.state() {
    print(rent.number, rent.messages.first?.code ?? "-")
}
```

## stateOne

One rent.

```swift
func stateOne(_ tzid: Int) async throws -> RentItem
```

```swift
let messages = try await client.rent.stateOne(tzid).messages
```

Errors: `.api` `ERROR_NO_OPERATIONS` for an unknown tzid.

## extend

Extend a rent by `days` days and charge the balance at once. Only confirmed rents (`status` `1` or `4`) created with `extension: true`.

```swift
func extend(_ tzid: Int, days: Int = 1) async throws -> RentItem
```

```swift
let rent = try await client.rent.extend(tzid, days: 3)
print(rent.stopTime)
```

Errors: `.api` `TRY_AGAIN_LATER` (unknown tzid, not confirmed yet or closed, not extendable, unknown period, a repeat within 10 s), `WARNING_LOW_BALANCE`.

## close

Return the number before the period ends. A rent that is not confirmed yet (`status` `0`) and has no SMS can be closed only after 120 s; then, or with only `notify` SMS, the reservation is released. With a real SMS the rent is confirmed (charged) and closed. A confirmed rent closes without a refund. US numbers cannot be closed early.

```swift
func close(_ tzid: Int) async throws
```

```swift
try await client.rent.close(tzid)
```

Errors: `.api` `ERROR_NO_OPERATIONS`, `NO_COMPLETE_TZID`, `NO_CLOSE_RENT_US`, `TRY_AGAIN_LATER`.

## tariffs

Rent prices of every country, keyed by country code. No API key needed.

```swift
func tariffs() async throws -> [Int: RentTariff]
```

`RentTariff`: `code`, `name`, `isEnabled`, `isNew`, `position`, `extend`, `confirm?`, `days`, `count`, `extCounts?` — `days` maps rent days to the price in USD, `count` to the numbers available.

```swift
let tariffs = try await client.rent.tariffs()
```

## tariffsOne

Rent prices of one country.

```swift
func tariffsOne(country: Int = 7) async throws -> RentTariff
```

```swift
let tariff = try await client.rent.tariffsOne(country: 7)
print(tariff.days[7] ?? 0) // price of 7 days
```

Errors: `.api` `NO_COUNTRY` for a country without rent.
