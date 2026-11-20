# Free numbers

> Public numbers and their SMS — client.free. No API key needed.

## list

Countries, the numbers of the selected country and the SMS of the selected number, in one call.

```swift
func list(country: Int? = nil, number: String? = nil, page: Int? = nil, count: Int? = nil) async throws -> FreeList
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
        Int?
      </code>
    </td>
    
    <td>
      <code>
        44
      </code>
      
       (server)
    </td>
    
    <td>
      Country code; an unknown one falls back to the first available.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        number
      </code>
    </td>
    
    <td>
      <code>
        String?
      </code>
    </td>
    
    <td>
      first number
    </td>
    
    <td>
      Number <strong>
        without
      </strong>
      
       the country code, as the keys of <code>
        numbers
      </code>
      
      .
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        page
      </code>
    </td>
    
    <td>
      <code>
        Int?
      </code>
    </td>
    
    <td>
      <code>
        1
      </code>
    </td>
    
    <td>
      Page of <code>
        messages
      </code>
      
      .
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        count
      </code>
    </td>
    
    <td>
      <code>
        Int?
      </code>
    </td>
    
    <td>
      server default
    </td>
    
    <td>
      SMS per page, 10–500.
    </td>
  </tr>
</tbody>
</table>

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
