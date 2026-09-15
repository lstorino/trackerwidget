import Foundation

// MARK: - API model (shared shape — all three backends serve this)

struct PricesPayload: Decodable {
  let generatedAt: String
  let totalHistoryRows: Int
  let markets: [Market]
  let spark: [String: [Double]]?

  enum CodingKeys: String, CodingKey {
    case generatedAt = "generated_at"
    case totalHistoryRows = "total_history_rows"
    case markets
    case spark
  }
}

struct Market: Decodable, Identifiable {
  let marketId: Int
  let priceDate: String
  let scrapedAt: String
  let price: Double
  let currency: String
  let unit: String
  let usdPerKg: Double?
  let reference: String
  let variation: String?
  let delta: String?
  let deltaClass: String?
  let country: String
  let flag: String
  let region: String
  let category: String

  var id: Int { marketId }

  enum CodingKeys: String, CodingKey {
    case marketId = "market_id"
    case priceDate = "price_date"
    case scrapedAt = "scraped_at"
    case price, currency, unit
    case usdPerKg = "usd_per_kg"
    case reference, variation, delta
    case deltaClass = "delta_class"
    case country, flag, region, category
  }

  var variationPercent: Double? {
    guard let variation,
          let digits = variation.split(separator: "%").first.map(String.init),
          let v = Double(digits) else { return nil }
    return v
  }

  var wentDown: Bool { deltaClass?.contains("down") == true }
  var wentUp: Bool { deltaClass?.contains("up") == true }

  /// pig333's own variation can glitch (|v| >= 50% is almost surely their
  /// delta/current bug) — gray those out on the pig tab.
  var variationSuspect: Bool {
    guard let v = variationPercent else { return false }
    return abs(v) >= 50
  }
}

// MARK: - Loader (one fetch per tracker)

enum Tracker {
  case pig, shrimp, grains, chemicals

  var base: String {
    switch self {
    case .pig: return ProcessInfo.processInfo.environment["PIG_API_BASE"] ?? Secrets.pigBase
    case .shrimp: return ProcessInfo.processInfo.environment["SHRIMP_API_BASE"] ?? Secrets.shrimpBase
    case .grains: return ProcessInfo.processInfo.environment["GRAINS_API_BASE"] ?? Secrets.grainsBase
    // Chemicals ride the grains backend (same ComexStat pipeline).
    case .chemicals: return ProcessInfo.processInfo.environment["GRAINS_API_BASE"] ?? Secrets.grainsBase
    }
  }

  var token: String {
    switch self {
    case .pig: return Secrets.pigToken
    case .shrimp: return Secrets.shrimpToken
    case .grains: return Secrets.grainsToken
    case .chemicals: return Secrets.grainsToken
    }
  }

  var logTag: String {
    switch self {
    case .pig: return "Pig"
    case .shrimp: return "Shrimp"
    case .grains: return "Grains"
    case .chemicals: return "Chemicals"
    }
  }
}

enum PricesLoader {
  static func fetch(_ tracker: Tracker,
                    completion: @escaping (Result<PricesPayload, Error>) -> Void) {
    let url = URL(string: "\(tracker.base)/prices.json?token=\(tracker.token)")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error {
        NSLog("[TrackerWidget:\(tracker.logTag)] transport error: \(error.localizedDescription)")
        return completion(.failure(error))
      }
      guard let data else {
        NSLog("[TrackerWidget:\(tracker.logTag)] empty response")
        return completion(.failure(NSError(domain: "TrackerWidget", code: 2,
                                           userInfo: [NSLocalizedDescriptionKey: "empty response"])))
      }
      do {
        let payload = try JSONDecoder().decode(PricesPayload.self, from: data)
        completion(.success(payload))
      } catch {
        NSLog("[TrackerWidget:\(tracker.logTag)] decode error: \(error)")
        if let http = response as? HTTPURLResponse {
          NSLog("[TrackerWidget:\(tracker.logTag)] http \(http.statusCode), body: \(String(data: data, encoding: .utf8) ?? "<binary>")")
        }
        completion(.failure(error))
      }
    }.resume()
  }
}
