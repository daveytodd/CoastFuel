import Foundation
import Combine

@MainActor
final class FuelDataService: ObservableObject {
    @Published private(set) var stations: [FuelStation] = []
    // Queensland Open Data fuel-price feed. The API can evolve; decoding failure intentionally falls back to fixtures.
    private let endpoint = URL(string: "https://www.data.qld.gov.au/api/3/action/package_show?id=queensland-fuel-price-reporting")!
    func load() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: endpoint)
            let decoded = try JSONDecoder().decode(QldPackageResponse.self, from: data)
            let resources = decoded.result.resources.compactMap { $0.url }.filter { $0.hasPrefix("https") }
            if let urlString = resources.first, let url = URL(string: urlString) {
                let (csv, _) = try await URLSession.shared.data(from: url)
                let parsed = Self.parseCSV(String(decoding: csv, as: UTF8.self))
                if !parsed.isEmpty { stations = parsed.sorted { $0.distanceKm < $1.distanceKm }; return }
            }
        } catch { /* Offline-first fallback below. */ }
        stations = Self.mockStations
    }
    private struct QldPackageResponse: Decodable { struct Result: Decodable { struct Resource: Decodable { let url: String? }; let resources: [Resource] }; let result: Result }
    private static func parseCSV(_ csv: String) -> [FuelStation] {
        let rows = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let header = rows.first?.lowercased().components(separatedBy: ",") else { return [] }
        func index(_ candidates: [String]) -> Int? { header.firstIndex { h in candidates.contains(where: h.contains) } }
        guard let name = index(["trading_name", "station_name", "name"]), let lat = index(["latitude"]), let lon = index(["longitude"]), let price = index(["price"]) else { return [] }
        return rows.dropFirst().compactMap { line in
            let cols = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            guard cols.count > max(name, lat, lon, price), let latitude = Double(cols[lat]), let longitude = Double(cols[lon]), let p = Double(cols[price]) else { return nil }
            return FuelStation(id: "qld-\(cols[name])-\(latitude)", name: cols[name], address: "Queensland", coordinate: .init(latitude: latitude, longitude: longitude), prices: [.unleaded91: p], amenities: [], distanceKm: 0, updatedAt: Date())
        }
    }
    static let mockStations: [FuelStation] = [
        .init(id:"s1",name:"CoastFuel Southport",address:"100 Scarborough St, Southport QLD",coordinate:.init(latitude:-27.9675,longitude:153.4143),prices:[.unleaded91:184.9,.premium95:198.9,.premium98:207.9,.diesel:189.9,.e10:181.9],amenities:["Air","Convenience store"],distanceKm:1.2,updatedAt:Date()),
        .init(id:"s2",name:"Metro Fuel Surfers Paradise",address:"Cavill Ave, Surfers Paradise QLD",coordinate:.init(latitude:-28.0027,longitude:153.4301),prices:[.unleaded91:189.9,.premium95:203.9,.premium98:212.9,.diesel:192.9,.e10:186.9],amenities:["24 hours","Air"],distanceKm:3.4,updatedAt:Date()),
        .init(id:"s3",name:"Pacific Petroleum Burleigh",address:"West Burleigh Rd, Burleigh Waters QLD",coordinate:.init(latitude:-28.0992,longitude:153.4384),prices:[.unleaded91:179.9,.premium95:194.9,.premium98:202.9,.diesel:187.9,.e10:176.9],amenities:["Cafe","Air"],distanceKm:9.8,updatedAt:Date()),
        .init(id:"s4",name:"Coastal Fuel Labrador",address:"Gold Coast Hwy, Labrador QLD",coordinate:.init(latitude:-27.9440,longitude:153.3995),prices:[.unleaded91:182.9,.premium95:196.9,.premium98:205.9,.diesel:188.9,.e10:179.9],amenities:["Convenience store"],distanceKm:4.1,updatedAt:Date())
    ]
}
