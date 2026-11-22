import Foundation

nonisolated struct NBUBatch: Sendable {
    let day: String
    let rates: [String: Decimal]
}

nonisolated struct NBUClient: Sendable {
    // Official coverage for catalog fiat entries verified against the NBU list and public feed on 2026-11-21.
    static let supportedCodes: Set<String> = Set("AED AUD AZN BDT CAD CHF CNY CZK DKK DZD EGP EUR GBP GEL HKD HUF IDR ILS INR JPY KRW KZT LBP MDL MXN MYR NOK NZD PLN RON RSD SAR SEK SGD THB TND TRY USD VND XDR ZAR".split(separator: " ").map(String.init))
    static let maximumBytes = 2 * 1024 * 1024
    private struct Quote: Decodable {
        let cc: String
        let exchangedate: String
        let rate: Decimal
        let units: Int
        let rate_per_unit: Decimal
    }

    static func decode(_ data: Data, day: String) throws -> NBUBatch {
        try RateDates.validateDay(day)
        guard !data.isEmpty, data.count <= maximumBytes else { throw CurrencyRateError.response }
        let quotes = try JSONDecoder().decode([Quote].self, from: data)
        guard !quotes.isEmpty else { throw CurrencyRateError.response }
        var result: [String: Decimal] = [:]
        for quote in quotes {
            let parts = quote.exchangedate.split(separator: ".")
            guard parts.count == 3 else { throw CurrencyRateError.response }
            let effective = "\(parts[2])-\(parts[1])-\(parts[0])"
            guard effective == day, quote.cc.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil,
                  quote.cc != "UAH", quote.units > 0, quote.units <= 1_000_000,
                  quote.rate > 0, quote.rate_per_unit > 0, result[quote.cc] == nil else { throw CurrencyRateError.response }
            try MoneyCodec.validate(quote.rate)
            try MoneyCodec.validate(quote.rate_per_unit)
            guard try DecimalArithmetic.divide(quote.rate, Decimal(quote.units)) == quote.rate_per_unit else { throw CurrencyRateError.response }
            result[quote.cc] = quote.rate_per_unit
        }
        return NBUBatch(day: day, rates: result)
    }

    func fetch(day: String) async throws -> NBUBatch {
        try RateDates.validateDay(day)
        let compact = day.replacingOccurrences(of: "-", with: "")
        var components = URLComponents(string: "https://bank.gov.ua/NBU_Exchange/exchange_site")!
        components.queryItems = [URLQueryItem(name: "start", value: compact), URLQueryItem(name: "end", value: compact),
                                 URLQueryItem(name: "sort", value: "exchangedate"), URLQueryItem(name: "order", value: "desc"), URLQueryItem(name: "json", value: nil)]
        guard let url = components.url else { throw CurrencyRateError.response }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= Int64(Self.maximumBytes) else { throw CurrencyRateError.response }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumBytes else { throw CurrencyRateError.response }
            data.append(byte)
        }
        return try Self.decode(data, day: day)
    }
}
