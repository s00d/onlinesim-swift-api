import Foundation

/// The mock's routes: endpoint path (relative to `/api/`) → handler. A handler gets the request and returns the
/// JSON body the real backend would send (HTTP 200). Shapes follow the OpenAPI spec and the live captures:
/// `response` as int or string per endpoint, decimal-string money, `[]` for empty maps.
/// Auth, queued failures, 456 and 404 are the transport's job (``MockOnlineSim``), not the handlers'.
extension MockState {
    /// Endpoints that answer without a key.
    static let publicPaths: Set<String> = ["getNumbersStats.php", "rent/tariffsRent.php", "getFreeList"]

    /// Whether `path` is a known endpoint.
    static func routes(_ path: String) -> Bool { route(path) != nil }

    private static func route(_ path: String) -> ((inout MockState, MockRequest) -> JSONValue)? {
        switch path {
        case "getPrice.php": return { $0.getPrice($1) }
        case "getNum.php": return { $0.getNum($1) }
        case "getState.php": return { $0.getState($1) }
        case "setOperationRevise.php": return { $0.setOperationRevise($1) }
        case "setOperationOk.php": return { $0.setOperationOk($1) }
        case "getNumbersStats.php": return { $0.getNumbersStats($1) }
        case "rent/getRentNum.php": return { $0.getRentNum($1) }
        case "rent/getRentState.php": return { $0.getRentState($1) }
        case "rent/extendRentState.php": return { $0.extendRentState($1) }
        case "rent/closeRentNum.php": return { $0.closeRentNum($1) }
        case "rent/tariffsRent.php": return { $0.tariffsRent($1) }
        case "getBalance.php": return { $0.getBalance($1) }
        case "getProfile.php": return { $0.getProfile($1) }
        case "profile.php": return { $0.profile($1) }
        case "webhook-logs": return { $0.webhookLogsPage($1) }
        case "getPaymentHistory.php": return { $0.getPaymentHistory($1) }
        case "getFreeList": return { $0.getFreeList($1) }
        default: return nil
        }
    }

    /// The body for a known endpoint, `nil` for an unknown one.
    mutating func handle(_ req: MockRequest) -> JSONValue? {
        guard let handler = Self.route(req.path) else { return nil }
        return handler(&self, req)
    }

    // MARK: - numbers

    private func operationView(_ op: MockOperation, _ req: MockRequest) -> JSONValue {
        let toCode = req.flag("message_to_code")
        let open = op.status != .tzOverOk
        var view: [String: JSONValue] = [
            "country": .int(op.country),
            "sum": .double(op.sum),
            "service": .string(op.service),
            "number": .string(op.number),
            "subscription_package_id": nil,
            "webhook_url": webhookURL.map(JSONValue.string) ?? .null,
            "response": .string(op.status.rawValue),
            "tzid": .int(op.tzid),
            "time": .int(open ? operationTime : 0),
            "form": "index",
        ]
        func msg(_ sms: MockSms) -> JSONValue { .string(toCode ? sms.code ?? sms.text : sms.text) }
        if req.flag("msg_list") {
            if !op.messages.isEmpty {
                view["msg"] = .array(op.messages.map { ["service": .string($0.service), "msg": msg($0)] })
            }
        } else if op.cursor < op.messages.count {
            view["msg"] = msg(op.messages[op.cursor])
        }
        if req.query["number"] != nil {
            view["guard_interval_remaining_seconds"] = .int(open && op.messages.isEmpty ? guardInterval : 0)
        }
        return .object(view)
    }

    mutating func getPrice(_ req: MockRequest) -> JSONValue {
        guard let prices = prices[req.int("country", 7)] else { return error("UNDEFINED_COUNTRY") }
        return ["response": "1", "price": prices[req.query["service"] ?? ""].map(JSONValue.double) ?? .null]
    }

    mutating func getNum(_ req: MockRequest) -> JSONValue {
        let country = req.int("country", 7)
        let service = req.query["service"] ?? ""
        guard let prices = prices[country] else { return error("UNDEFINED_COUNTRY") }
        guard let price = prices[service] else { return error("ERROR_NO_SERVICE") }
        let cost = toMills(price)
        if available < cost { return error("WARNING_LOW_BALANCE") }

        let number = "+\(country)\(Self.shortNumber(peekID))"
        let reject = (req.query["reject"] ?? "").split(separator: ",").map(String.init)
        if reject.contains(where: { number.dropFirst().hasPrefix($0) }) { return error("NO_NUMBER") }

        let tzid = nextID()
        frozen += cost
        operations[tzid] = MockOperation(
            tzid: tzid, service: service, country: country, number: number, sum: price, status: .tzNumWait,
            messages: [], cursor: 0)
        if req.query["number"] == nil { return ["response": 1, "tzid": .int(tzid)] }
        return [
            "response": 1, "tzid": .int(tzid), "number": .string(number), "country": .int(country),
            "time": .int(operationTime), "service": .string(service), "title": .string(service),
            "response_text": "Waiting for SMS", "guard_interval_remaining_seconds": .int(guardInterval),
        ]
    }

    mutating func getState(_ req: MockRequest) -> JSONValue {
        let ids =
            req.query["tzid"] == nil
            ? operations.keys.sorted() : [req.int("tzid", -1)].filter { operations[$0] != nil }
        for id in ids { poll(id) }
        if ids.isEmpty { return error("ERROR_NO_OPERATIONS") }
        let ordered = req.query["orderby"] == "desc" ? ids.sorted(by: >) : ids.sorted()
        return .array(ordered.compactMap { operations[$0] }.map { operationView($0, req) })
    }

    mutating func setOperationRevise(_ req: MockRequest) -> JSONValue {
        let tzid = req.int("tzid", 0)
        if tzid == 0 { return error("ERROR_NO_TZID") }
        guard var op = operations[tzid] else { return error("ERROR_WRONG_TZID") }
        if op.status != .tzOverOk {
            op.cursor = op.messages.count
            op.status = .tzNumWait
            operations[tzid] = op
        }
        return ["tzid": .string(String(tzid)), "response": "1"]
    }

    mutating func setOperationOk(_ req: MockRequest) -> JSONValue {
        let tzid = req.int("tzid", 0)
        if tzid == 0 { return error("ERROR_NO_TZID") }
        guard var op = operations[tzid], op.status != .tzOverOk else { return error("ERROR_WRONG_TZID") }
        let received = !op.messages.isEmpty
        if req.flag("ban") && received { return ["response": "0"] }
        if !received && guardInterval > 0 { return error("NO_COMPLETE_TZID") }
        let cost = toMills(op.sum)
        frozen -= cost
        if received { balance -= cost }
        op.status = .tzOverOk
        operations[tzid] = op
        return ["response": 1, "tzid": .int(tzid)]
    }

    private func countryStat(_ code: Int) -> JSONValue {
        let (name, locale) = countryName(code)
        var services: [String: JSONValue] = [:]
        // Slugs in alphabetical order: ids are deterministic.
        for (i, (slug, price)) in (prices[code] ?? [:]).sorted(by: { $0.key < $1.key }).enumerated() {
            services["service_\(slug)"] = [
                "count": 100, "popular": false, "code": .int(code), "price": .double(price), "id": .int(i + 1),
                "service": .string(slug), "slug": .string(slug),
            ]
        }
        return [
            "name": .string(name), "position": .int(code), "code": .int(code), "other": false, "new": false,
            "enabled": true, "services": services.isEmpty ? [] : .object(services), "locale_name": .string(locale),
        ]
    }

    mutating func getNumbersStats(_ req: MockRequest) -> JSONValue {
        if req.query["country"] == "all" {
            let all = Dictionary(uniqueKeysWithValues: prices.keys.map { (String($0), countryStat($0)) })
            return all.isEmpty ? [] : .object(all)
        }
        let code = req.int("country", 7)
        return prices[code] == nil ? error("NO_COUNTRY") : countryStat(code)
    }

    // MARK: - rent

    /// A rent as the backend sends it. `sum` is a number in getRentNum/extendRentState and a 2-decimal string in
    /// getRentState (`stringSum`). An unconfirmed rent (`status` 0) waits 20 minutes for its first SMS.
    private func rentItem(_ rent: MockRent, _ req: MockRequest, stringSum: Bool = false) -> JSONValue {
        let tariff = rentTariffs[rent.country]
        let extendable = rent.isExtendable && tariff?.extend == 1
        let confirmed = rent.status == 1
        let start = rent.tzid
        let minutes = confirmed ? rent.days * 24 * 60 : rentFirstSmsMinutes
        var item: [String: JSONValue] = [
            "status": .int(rent.status),
            "extension": .int(rent.isExtendable ? 1 : 0),
            "messages": .array(
                rent.messages.reversed().map {
                    [
                        "id": .int($0.id), "service": .string($0.service), "text": .string($0.text),
                        // A notice about a prohibited sender carries the integer 0, other SMS a string ("" without
                        // a code).
                        "code": $0.service == notifySender ? 0 : .string($0.code ?? ""),
                        "created_at": .string($0.createdAt),
                    ]
                }),
            "webhook_url": webhookURL.map(JSONValue.string) ?? .null,
            "sum": stringSum ? .string(decimal(toMills(rent.sum), digits: 2)) : .double(rent.sum),
            "country": .int(rent.country),
            "start_time": .string(stamp(start)),
            "stop_time": .string(stamp(start + minutes * 60)),
            "checked_time": .string(stamp(start)),
            "number": .string(rent.number),
            "days_autoextend": .int(rent.initialDays),
            "rent": .int(rent.days),
            "tzid": .int(rent.tzid),
            "time": .int(minutes),
            "days": .int(confirmed ? rent.days : 0),
            "hours": .int(confirmed ? rent.days * 24 : 0),
            "extend": extendable ? daysObject(tariff?.days ?? [:], JSONValue.double) : [],
            "checked": .bool(confirmed),
            "reload": rent.country == 7 ? 0 : nil,
            "day_extend": .double(extendable ? tariff?.days[1] ?? 0 : 0),
            "m_ext": false,
            "freeze": false,
        ]
        if req.query["number"] != nil {
            item["time_seconds"] = .int(minutes * 60)
            item["guard_interval_remaining_seconds"] = .int(!confirmed && rent.messages.isEmpty ? guardInterval : 0)
        }
        return .object(item)
    }

    mutating func getRentNum(_ req: MockRequest) -> JSONValue {
        let country = req.int("country", 7)
        guard let tariff = rentTariffs[country] else { return error("UNDEFINED_COUNTRY") }
        let days = req.int("days", 1)
        guard let price = tariff.days[days] else { return error("UNDEFINED_DAYS") }
        if available < toMills(price) { return error("WARNING_LOW_BALANCE") }
        let tzid = nextID()
        // Reserved, not charged: the first SMS that is not `notify` confirms the rent and charges it.
        frozen += toMills(price)
        // `extension` defaults to 1 on the server; `0` makes the rent non-extendable for good.
        let rent = MockRent(
            tzid: tzid, country: country, number: Self.shortNumber(tzid), days: days, initialDays: days, status: 0,
            sum: price, isExtendable: req.query["extension"] != "0", messages: [])
        rents[tzid] = rent
        return ["response": 1, "item": rentItem(rent, req)]
    }

    mutating func getRentState(_ req: MockRequest) -> JSONValue {
        let ids = req.query["tzid"] == nil ? rents.keys.sorted() : [req.int("tzid", -1)].filter { rents[$0] != nil }
        for id in ids { poll(id) }
        return ["response": 1, "list": .array(ids.compactMap { rents[$0] }.map { rentItem($0, req, stringSum: true) })]
    }

    mutating func extendRentState(_ req: MockRequest) -> JSONValue {
        // Every refusal is TRY_AGAIN_LATER, like the backend: unknown tzid, unconfirmed rent, not extendable,
        // unknown days.
        guard var rent = rents[req.int("tzid", 0)], let tariff = rentTariffs[rent.country], rent.status == 1,
            rent.isExtendable, tariff.extend == 1, let price = tariff.days[req.int("days", 1)]
        else { return error("TRY_AGAIN_LATER") }
        if available < toMills(price) { return error("WARNING_LOW_BALANCE") }
        balance -= toMills(price)
        rent.days += req.int("days", 1)
        rent.sum = fromMills(toMills(rent.sum) + toMills(price))
        rents[rent.tzid] = rent
        return ["response": 1, "item": rentItem(rent, req)]
    }

    mutating func closeRentNum(_ req: MockRequest) -> JSONValue {
        let tzid = req.int("tzid", 0)
        guard let rent = rents[tzid] else { return error("ERROR_NO_OPERATIONS") }
        if rent.status == 0 {
            // `guardInterval` stands in for the backend's first 120 s, during which a rent without any SMS stays open.
            if rent.messages.isEmpty && guardInterval > 0 { return error("NO_COMPLETE_TZID") }
            // Unconfirmed (no SMS or only `notify`): the reservation is released.
            frozen -= toMills(rent.sum)
        }
        // A confirmed rent closes without a refund.
        rents[tzid] = nil
        scheduled[tzid] = nil
        return ["response": "1"]
    }

    mutating func tariffsRent(_ req: MockRequest) -> JSONValue {
        func tariff(_ code: Int) -> JSONValue {
            guard let t = rentTariffs[code] else { return [] }
            let count = daysObject(t.days) { _ in 100 }
            return [
                "code": .int(code), "enabled": true, "name": .string(countryName(code).0), "new": false,
                "position": .int(code), "count": count, "days": daysObject(t.days, JSONValue.double),
                "extend": .int(t.extend), "confirm": false, "ext_counts": count,
            ]
        }
        if req.query["country"] != nil { return tariff(req.int("country", 0)) }
        let all = Dictionary(uniqueKeysWithValues: rentTariffs.keys.map { (String($0), tariff($0)) })
        return all.isEmpty ? [] : .object(all)
    }

    // MARK: - user

    mutating func getBalance(_ req: MockRequest) -> JSONValue {
        var res: [String: JSONValue] = [
            "response": "1", "balance": .string(decimal(balance, digits: 3)), "zbalance": .double(fromMills(frozen)),
        ]
        if req.query["income"] != nil {
            res["income"] = 0
            res["income_usd"] = "0.000"
        }
        return .object(res)
    }

    mutating func getProfile(_ req: MockRequest) -> JSONValue {
        [
            "response": "1",
            "profile": [
                "id": .int(mockUserID), "hash_id": "mock", "name": "mock@example.com",
                "username": "mock@example.com", "email": "mock@example.com", "email_verified_at": .string(stamp()),
                "active": "true", "apikey": .string(apiKey), "api_access": true, "is_api": true, "number": nil,
                "country": nil, "locale": "en", "currency": "USD", "number_region": nil, "number_country": nil,
                "number_reject": [], "ugroup": 1, "verify": 0, "block": 0, "resetCount": nil,
                "created_at": .string(stamp()), "notification_at": nil, "first_login": false, "sub": 0,
                "disable": false, "webhook_url": webhookURL.map(JSONValue.string) ?? .null,
                "is_project_subscription": false,
            ],
        ]
    }

    mutating func profile(_ req: MockRequest) -> JSONValue {
        guard req.method == "POST", case .object(let profile)? = req.body?["profile"] else {
            return error("ERROR_PARAMS")
        }
        if let url = profile["webhook_url"] {
            switch url {
            case .null: webhookURL = nil
            case .string(let s) where isURL(s): webhookURL = s
            default: return ["response": ["webhook_url": ["The webhook url must be a valid URL."]]]
            }
        }
        return [
            "response": "1",
            "user": ["id": .int(mockUserID), "webhook_url": webhookURL.map(JSONValue.string) ?? .null],
        ]
    }

    mutating func webhookLogsPage(_ req: MockRequest) -> JSONValue {
        [
            "response": "1",
            "data": paginate(webhookLogs.reversed(), page: req.int("page", 1), perPage: 10, path: "webhook-logs"),
        ]
    }

    mutating func getPaymentHistory(_ req: MockRequest) -> JSONValue {
        [
            "response": "1",
            "orders": paginate([], page: req.int("page", 1), perPage: 10, path: "getPaymentHistory.php"),
            "paylist": [], "domains": ["onlinesim.io"], "forms": ["1": "Card"], "currency": ["USD": 1],
            "buttons": ["USD": [5, 10, 20]],
        ]
    }

    // MARK: - free

    private static let free: [Int: (name: String, text: String, numbers: [(String, [(String, String)])])] = [
        44: (
            "united_kingdom", "United Kingdom",
            [
                (
                    "7459608320",
                    [
                        ("Amazon", "Amazon: Use 195895 to reset your password."),
                        ("Microsoft", "Microsoft access code: 2991"),
                    ]
                )
            ]
        ),
        7: ("russia", "Russia", [("9001234567", [("Telegram", "Telegram code: 51423")])]),
    ]

    /// `ignore` of getFreeList: a note about prohibited services and their ids.
    private static let freeIgnore = "<p>Messages from these services are not shown:</p><p>1,2,3</p>"

    mutating func getFreeList(_ req: MockRequest) -> JSONValue {
        let codes = [44, 7]  // the backend lists 44 first
        let wanted = req.int("country", 44)
        let country = Self.free[wanted] == nil ? codes[0] : wanted
        let data = Self.free[country]!
        var numbers: [String: JSONValue] = [:]
        for (number, _) in data.numbers {
            numbers[number] = [
                "country": .int(country), "country_original": .string(data.name), "data_humans": "1 day ago",
                "full_number": .string("\(country)\(number)"), "is_archive": false,
            ]
        }
        let selected = data.numbers.first { $0.0 == req.query["number"] } ?? data.numbers[0]
        let messages: [JSONValue] = selected.1.enumerated().map { i, sms in
            [
                "id": .int(i + 1), "text": .string(sms.1), "in_number": .string(sms.0),
                "my_number": .string(selected.0),
                "created_at": .string(iso(i)), "data_humans": "1 day ago",
                "code": .string(extractCode(sms.1) ?? "-"),
            ]
        }
        guard
            case .object(var page) = paginate(
                messages, page: max(1, req.int("page", 1)), perPage: min(500, max(10, req.int("count", 10))),
                path: "getFreeList")
        else { return error("ERROR_PARAMS") }
        page["number"] = .string(selected.0)
        page["country"] = .int(country)
        return [
            "response": 1,
            "countries": .array(
                codes.map {
                    [
                        "country": .int($0), "country_text": .string(Self.free[$0]!.text),
                        "country_original": .string(Self.free[$0]!.name),
                    ]
                }),
            "numbers": .object(numbers),
            "messages": .object(page),
            "ignore": .string(Self.freeIgnore),
            "content": nil,
        ]
    }

    // MARK: - helpers

    private func error(_ code: String) -> JSONValue { ["response": .string(code)] }

    private func countryName(_ code: Int) -> (String, String) {
        switch code {
        case 7: return ("russia", "Russia")
        case 44: return ("united_kingdom", "United Kingdom")
        default: return ("country_\(code)", "Country \(code)")
        }
    }

    private func daysObject(_ days: [Int: Double], _ value: (Double) -> JSONValue) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: days.map { (String($0.key), value($0.value)) }))
    }

    /// Laravel paginator over `items`.
    private func paginate(_ items: [JSONValue], page: Int, perPage: Int, path: String) -> JSONValue {
        let total = items.count
        let lastPage = max(1, (total + perPage - 1) / max(perPage, 1))
        let lower = min(max(0, (page - 1) * perPage), total)
        let data = Array(items[lower..<min(lower + perPage, total)])
        func url(_ p: Int) -> JSONValue { .string("https://onlinesim.host/api/\(path)?page=\(p)") }
        return [
            "current_page": .int(page),
            "data": .array(data),
            "first_page_url": url(1),
            "from": data.isEmpty ? nil : .int(lower + 1),
            "last_page": .int(lastPage),
            "last_page_url": url(lastPage),
            "links": [],
            "next_page_url": page < lastPage ? url(page + 1) : nil,
            "path": .string("https://onlinesim.host/api/\(path)"),
            "per_page": .int(perPage),
            "prev_page_url": page > 1 ? url(page - 1) : nil,
            "to": data.isEmpty ? nil : .int(lower + data.count),
            "total": .int(total),
        ]
    }

    /// USD with `digits` decimals (3 or 2), as the backend sends `balance` and rent `sum`.
    private func decimal(_ mills: Int, digits: Int) -> String {
        let sign = mills < 0 ? "-" : ""
        let value = abs(mills)
        if digits == 2 {
            let cents = (value + 5) / 10
            let frac = cents % 100
            return "\(sign)\(cents / 100).\(frac < 10 ? "0" : "")\(frac)"
        }
        let frac = String(value % 1000)
        return "\(sign)\(value / 1000).\(String(repeating: "0", count: 3 - frac.count))\(frac)"
    }

    /// The backend accepts any `scheme://…` URL.
    private func isURL(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://\S+$"#, options: .regularExpression) != nil
    }

    /// `YYYY-MM-DDTHH:MM:SS.000000Z`, the ISO-8601 form getFreeList sends.
    private func iso(_ seconds: Int) -> String {
        stamp(seconds).replacingOccurrences(of: " ", with: "T") + ".000000Z"
    }
}

extension MockRequest {
    /// A query flag is set when present and not `0`.
    func flag(_ key: String) -> Bool { query[key] != nil && query[key] != "0" }

    func int(_ key: String, _ fallback: Int) -> Int { query[key].flatMap { Int($0) } ?? fallback }
}
