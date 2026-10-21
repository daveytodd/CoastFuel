import Foundation
import Combine

@MainActor
final class FuelDataService: ObservableObject {
    @Published private(set) var stations: [FuelStation] = []
    // Queensland Open Data fuel-price feed. Keep fixtures available when the feed is offline or changes format.
    private let endpoint = URL(string: "https://www.data.qld.gov.au/api/3/action/package_show?id=queensland-fuel-price-reporting")!

    func load() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            try Self.validate(response)
            let decoded = try JSONDecoder().decode(QldPackageResponse.self, from: data)
            let urls = decoded.result.resources.compactMap { resource -> URL? in
                guard let value = resource.url, let url = URL(string: value), url.scheme == "https" else { return nil }
                return url
            }
            var lastResourceError: Error?
            for url in urls {
                do {
                    let (csvData, csvResponse) = try await URLSession.shared.data(from: url)
                    try Self.validate(csvResponse)
                    let parsed = Self.parseCSV(String(decoding: csvData, as: UTF8.self))
                    if !parsed.isEmpty {
                        stations = parsed.sorted { $0.distanceKm < $1.distanceKm }
                        return
                    }
                } catch {
                    lastResourceError = error
                }
            }
            if let lastResourceError {
                print("QLD fuel feed resources could not be loaded: \(lastResourceError). Using mock stations.")
            } else {
                print("QLD fuel feed returned no usable station rows across \(urls.count) HTTPS resources. Using mock stations.")
            }
        } catch {
            print("QLD fuel feed could not be loaded: \(error). Using mock stations.")
        }
        stations = Self.mockStations
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private struct QldPackageResponse: Decodable {
        struct Result: Decodable {
            struct Resource: Decodable { let url: String? }
            let resources: [Resource]
        }
        let result: Result
    }

    private static func parseCSV(_ csv: String) -> [FuelStation] {
        let records = csvRecords(csv)
        guard let rawHeader = records.first else { return [] }
        let header = rawHeader.enumerated().map { index, value in
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\u{feff}", with: "")
                .lowercased()
        }
        func index(_ candidates: [String]) -> Int? {
            header.firstIndex { value in candidates.contains(value) }
        }
        guard let nameIndex = index(["trading_name", "station_name", "name"]),
              let latitudeIndex = index(["latitude", "lat"]),
              let longitudeIndex = index(["longitude", "lon", "lng"]),
              let priceIndex = index(["price", "price_cpl", "price_cents_per_litre"]) else { return [] }

        return records.dropFirst().compactMap { columns in
            guard columns.count > max(max(nameIndex, latitudeIndex), max(longitudeIndex, priceIndex)) else { return nil }
            let name = columns[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let priceText = columns[priceIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "$", with: "")
            guard !name.isEmpty,
                  let latitude = Double(columns[latitudeIndex].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let longitude = Double(columns[longitudeIndex].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let price = Double(priceText),
                  (-90...90).contains(latitude), (-180...180).contains(longitude), price > 0 else { return nil }
            return FuelStation(id: "qld-\(name)-\(latitude)", name: name, address: "Queensland", coordinate: .init(latitude: latitude, longitude: longitude), prices: [.unleaded91: price], amenities: [], distanceKm: 0, updatedAt: Date())
        }
    }

    // CSV record scanner: supports escaped quotes, commas and newlines inside quoted fields.
    private static func csvRecords(_ csv: String) -> [[String]] {
        let chars = Array(csv)
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                    field.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                record.append(field)
                field = ""
            } else if (char == "\\n" || char == "\\r") && !inQuotes {
                if char == "\\r", i + 1 < chars.count, chars[i + 1] == "\\n" { i += 1 }
                record.append(field)
                if record.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { records.append(record) }
                record = []
                field = ""
            } else {
                field.append(char)
            }
            i += 1
        }
        record.append(field)
        if record.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { records.append(record) }
        return records
    }

    static let mockStations: [FuelStation] = [
        .init(id:"s1",name:"7-Eleven Southport",address:"138 Slatyer Ave, Southport QLD 4215",coordinate:.init(latitude:-27.9964,longitude:153.3997),prices:[.unleaded91:184.9,.premium95:198.9,.premium98:207.9,.diesel:189.9,.e10:181.9],amenities:["Air","Convenience store"],distanceKm:1.2,updatedAt:Date()),
        .init(id:"s2",name:"Ampol Surfers Paradise",address:"100 Ferny Ave, Surfers Paradise QLD 4217",coordinate:.init(latitude:-27.9956,longitude:153.4274),prices:[.unleaded91:189.9,.premium95:203.9,.premium98:212.9,.diesel:192.9,.e10:186.9],amenities:["24 hours","Air"],distanceKm:3.4,updatedAt:Date()),
        .init(id:"s3",name:"EG Ampol Robina",address:"Robina Town Centre Dr, Robina QLD 4230",coordinate:.init(latitude:-28.0757,longitude:153.3828),prices:[.unleaded91:179.9,.premium95:194.9,.premium98:202.9,.diesel:187.9,.e10:176.9],amenities:["Cafe","Air"],distanceKm:9.8,updatedAt:Date()),
        .init(id:"s4",name:"BP Helensvale",address:"Discovery Dr, Helensvale QLD 4212",coordinate:.init(latitude:-27.9185,longitude:153.3368),prices:[.unleaded91:182.9,.premium95:196.9,.premium98:205.9,.diesel:188.9,.e10:179.9],amenities:["Convenience store"],distanceKm:4.1,updatedAt:Date()),
        .init(id:"s5",name:"Shell Pacific Pines",address:"31 Pitcairn Way, Pacific Pines QLD 4211",coordinate:.init(latitude:-27.9462,longitude:153.3206),prices:[.unleaded91:186.9,.premium95:199.9,.premium98:209.9,.diesel:190.9,.e10:183.9],amenities:["24 hours","Convenience store"],distanceKm:5.2,updatedAt:Date()),
        .init(id:"s6",name:"Liberty Helensvale",address:"Old Pacific Highway, Helensvale QLD 4212",coordinate:.init(latitude:-27.9168,longitude:153.3337),prices:[.unleaded91:179.9,.premium95:193.9,.premium98:202.9,.diesel:186.9,.e10:176.9],amenities:["Air","Convenience store"],distanceKm:4.0,updatedAt:Date())
    ]
}
