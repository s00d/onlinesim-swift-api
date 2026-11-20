# Webhooks

> Receive SMS as HTTP callbacks and parse them with parseWebhook.

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

<table>
<thead>
  <tr>
    <th>
      Field
    </th>
    
    <th>
      JSON key
    </th>
    
    <th>
      Type
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
        webhookType
      </code>
    </td>
    
    <td>
      <code>
        webhook_type
      </code>
    </td>
    
    <td>
      <code>
        WebhookType?
      </code>
    </td>
    
    <td>
      <code>
        .receivingSms
      </code>
      
       or <code>
        .rentSms
      </code>
      
      .
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        operationID
      </code>
    </td>
    
    <td>
      <code>
        operation_id
      </code>
    </td>
    
    <td>
      <code>
        Int?
      </code>
    </td>
    
    <td>
      <code>
        tzid
      </code>
      
       of the operation or rent.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        userID
      </code>
    </td>
    
    <td>
      <code>
        user_id
      </code>
    </td>
    
    <td>
      <code>
        Int?
      </code>
    </td>
    
    <td>
      Account id.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        countryCode
      </code>
    </td>
    
    <td>
      <code>
        country_code
      </code>
    </td>
    
    <td>
      <code>
        Int?
      </code>
    </td>
    
    <td>
      Country code of the number.
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
        number
      </code>
    </td>
    
    <td>
      <code>
        String?
      </code>
    </td>
    
    <td>
      Numbers: <code>
        +
      </code>
      
       and the full number (<code>
        +79001234567
      </code>
      
      ), or <code>
        hidden
      </code>
      
      . Rent: the full number in digits without <code>
        +
      </code>
      
       (<code>
        79001234567
      </code>
      
      ).
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        sender
      </code>
    </td>
    
    <td>
      <code>
        sender
      </code>
    </td>
    
    <td>
      <code>
        String?
      </code>
    </td>
    
    <td>
      Sender of the SMS, e.g. <code>
        VK
      </code>
      
      .
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        message
      </code>
    </td>
    
    <td>
      <code>
        message
      </code>
    </td>
    
    <td>
      <code>
        String?
      </code>
    </td>
    
    <td>
      Full SMS text.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        code
      </code>
    </td>
    
    <td>
      <code>
        code
      </code>
    </td>
    
    <td>
      <code>
        String?
      </code>
    </td>
    
    <td>
      Code extracted from the SMS; <code>
        ""
      </code>
      
       when none was found.
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        timeStart
      </code>
    </td>
    
    <td>
      <code>
        time_start
      </code>
    </td>
    
    <td>
      <code>
        String?
      </code>
    </td>
    
    <td>
      Numbers: when the operation was ordered. Rent: when the SMS arrived. <code>
        YYYY-MM-DD HH:MM:SS
      </code>
      
      .
    </td>
  </tr>
  
  <tr>
    <td>
      <code>
        timeLeft
      </code>
    </td>
    
    <td>
      <code>
        time_left
      </code>
    </td>
    
    <td>
      <code>
        Int?
      </code>
    </td>
    
    <td>
      Time left: seconds for numbers, minutes for rent.
    </td>
  </tr>
</tbody>
</table>
