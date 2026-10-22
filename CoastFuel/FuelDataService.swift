import Foundation
import Combine
import CoreLocation

@MainActor
final class FuelDataService: ObservableObject {
    @Published private(set) var stations: [FuelStation] = []
    @Published var selectedState: AustralianState = .qld {
        didSet { refreshStations() }
    }
    @Published private(set) var userLocation: CLLocation?

    private let defaults: [AustralianState: CLLocation] = [
        .qld: CLLocation(latitude: -27.967, longitude: 153.400), .nsw: CLLocation(latitude: -33.8688, longitude: 151.2093),
        .vic: CLLocation(latitude: -37.8136, longitude: 144.9631), .wa: CLLocation(latitude: -31.9505, longitude: 115.8605),
        .sa: CLLocation(latitude: -34.9285, longitude: 138.6007), .tas: CLLocation(latitude: -42.8821, longitude: 147.3272),
        .act: CLLocation(latitude: -35.2809, longitude: 149.1300), .nt: CLLocation(latitude: -12.4634, longitude: 130.8456)
    ]

    // Supply credentials through the app's secure configuration. Never commit API secrets.
    private let fuelCheckAPIKey = Bundle.main.object(forInfoDictionaryKey: "FuelCheckAPIKey") as? String ?? ""
    private let fuelCheckClientSecret = Bundle.main.object(forInfoDictionaryKey: "FuelCheckClientSecret") as? String ?? ""
    private let cacheKey = "FuelDataService.cachedNSWStations"
    private var cachedNSWStations: [FuelStation] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([FuelStation].self, from: data) {
            cachedNSWStations = cached
        }
    }

    func setUserLocation(_ location: CLLocation?) {
        userLocation = location
        refreshStations()
    }

    func load() async {
        if selectedState == .nsw {
            await refreshNSWStations()
        } else {
            refreshStations()
        }
    }

    /// Fetches the complete NSW prices feed. On any failure, cached or fixture stations remain available.
    func refreshNSWStations() async {
        guard !fuelCheckAPIKey.isEmpty, !fuelCheckClientSecret.isEmpty else {
            refreshStations()
            return
        }

        do {
            let token = try await fetchAccessToken()
            var request = URLRequest(url: URL(string: "https://api.onegov.nsw.gov.au/FuelPriceCheck/v1/fuel/prices")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 25
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(fuelCheckAPIKey, forHTTPHeaderField: "apikey")
            request.setValue(UUID().uuidString, forHTTPHeaderField: "transactionid")
            request.setValue(Self.requestTimestamp(), forHTTPHeaderField: "requesttimestamp")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONDecoder().decode(FuelCheckPricesResponse.self, from: data)
            let mapped = Self.map(payload)
            guard !mapped.isEmpty else { throw URLError(.cannotParseResponse) }

            cachedNSWStations = mapped
            if let encoded = try? JSONEncoder().encode(mapped) {
                UserDefaults.standard.set(encoded, forKey: cacheKey)
            }
            if selectedState == .nsw { publish(mapped) }
        } catch {
            // Keep the app usable offline; use cached live values when available, otherwise fixtures.
            if selectedState == .nsw, !cachedNSWStations.isEmpty {
                publish(cachedNSWStations)
            } else {
                refreshStations()
            }
        }
    }

    func refreshStations() {
        let origin = userLocation ?? defaults[selectedState] ?? defaults[.qld]!
        let source: [FuelStation]
        if selectedState == .nsw, !cachedNSWStations.isEmpty {
            source = cachedNSWStations
        } else {
            source = Self.fixtures.filter { $0.state == selectedState }.map(\.station)
        }
        stations = Self.sorted(source, from: origin)
    }

    private func publish(_ values: [FuelStation]) {
        let origin = userLocation ?? defaults[.nsw]!
        stations = Self.sorted(values, from: origin)
    }

    private static func sorted(_ values: [FuelStation], from origin: CLLocation) -> [FuelStation] {
        values.map { value in
            var station = value
            station.distanceKm = origin.distance(from: CLLocation(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)) / 1000
            return station
        }.sorted { $0.distanceKm < $1.distanceKm }
    }

    private func fetchAccessToken() async throws -> String {
        var components = URLComponents(string: "https://api.onegov.nsw.gov.au/oauth/client_credential/accesstoken")!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "client_credentials")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        let clientID = Bundle.main.object(forInfoDictionaryKey: "FuelCheckClientID") as? String ?? fuelCheckAPIKey
        let credentials = Data("\(clientID):\(fuelCheckClientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue(fuelCheckAPIKey, forHTTPHeaderField: "apikey")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "transactionid")
        request.setValue(Self.requestTimestamp(), forHTTPHeaderField: "requesttimestamp")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.userAuthenticationRequired)
        }
        let token = try JSONDecoder().decode(FuelCheckTokenResponse.self, from: data)
        guard !token.accessToken.isEmpty else { throw URLError(.userAuthenticationRequired) }
        return token.accessToken
    }

    private static func requestTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private struct FuelCheckTokenResponse: Decodable {
        let accessToken: String
        enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
    }

    // Accepts the API's JSON feed without relying on a single casing convention.
    private struct FuelCheckPricesResponse: Decodable {
        let stations: [FuelCheckStation]
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let direct = try? container.decode([FuelCheckStation].self) {
                stations = direct
                return
            }
            let object = try container.decode([String: AnyCodable].self)
            let list = object.first { ["stations", "prices", "fuelprices"].contains($0.key.lowercased()) }?.value
            stations = (try? JSONDecoder().decode([FuelCheckStation].self, from: JSONEncoder().encode(list))) ?? []
        }
    }

    private struct FuelCheckStation: Decodable {
        let stationCode: String?
        let name: String?
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let fuelType: String?
        let price: Double?
        let updated: String?

        private enum CodingKeys: String, CodingKey {
            case stationCode, stationcode, code, name, brand, address, addressLine, latitude, lat, longitude, lon
            case fuelType, fueltype, fuel, price, priceInCents, lastUpdated, updated
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stationCode = try c.decodeIfPresent(String.self, forKey: .stationCode) ?? c.decodeIfPresent(String.self, forKey: .stationcode) ?? c.decodeIfPresent(String.self, forKey: .code)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .brand)
            address = try c.decodeIfPresent(String.self, forKey: .address) ?? c.decodeIfPresent(String.self, forKey: .addressLine)
            latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? c.decodeIfPresent(Double.self, forKey: .lat)
            longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? c.decodeIfPresent(Double.self, forKey: .lon)
            fuelType = try c.decodeIfPresent(String.self, forKey: .fuelType) ?? c.decodeIfPresent(String.self, forKey: .fueltype) ?? c.decodeIfPresent(String.self, forKey: .fuel)
            price = try c.decodeIfPresent(Double.self, forKey: .price) ?? c.decodeIfPresent(Double.self, forKey: .priceInCents)
            updated = try c.decodeIfPresent(String.self, forKey: .lastUpdated) ?? c.decodeIfPresent(String.self, forKey: .updated)
        }
    }

    private struct AnyCodable: Codable {
        let value: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(String.self) { value = v }
            else if let v = try? c.decode([String: AnyCodable].self) { value = v }
            else if let v = try? c.decode([AnyCodable].self) { value = v }
            else if let v = try? c.decode(Double.self) { value = v }
            else if let v = try? c.decode(Bool.self) { value = v }
            else { value = NSNull() }
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            if let v = value as? String { try c.encode(v) }
            else if let v = value as? Double { try c.encode(v) }
            else if let v = value as? Bool { try c.encode(v) }
            else if let v = value as? [String: AnyCodable] { try c.encode(v) }
            else if let v = value as? [AnyCodable] { try c.encode(v) }
            else { try c.encodeNil() }
        }
    }

    private static func map(_ response: FuelCheckPricesResponse) -> [FuelStation] {
        struct Accumulator {
            var name: String
            var address: String
            var latitude: Double
            var longitude: Double
            var prices: [FuelType: Double] = [:]
            var updatedAt = Date()
        }
        var grouped: [String: Accumulator] = [:]
        for item in response.stations {
            guard let code = item.stationCode, let lat = item.latitude, let lon = item.longitude,
                  let rawPrice = item.price, let rawFuel = item.fuelType else { continue }
            let price = rawPrice > 1000 ? rawPrice / 10 : rawPrice
            let normalized = rawFuel.lowercased().filter { $0.isLetter || $0.isNumber }
            let fuel: FuelType?
            switch normalized {
            case "ulp91", "unleaded91", "e91", "91": fuel = .unleaded91
            case "ulp95", "premium95", "p95", "95": fuel = .premium95
            case "ulp98", "premium98", "p98", "98": fuel = .premium98
            case "diesel", "diesel": fuel = .diesel
            case "e10": fuel = .e10
            default: fuel = nil
            }
            guard let fuel else { continue }
            let date = item.updated.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            var current = grouped[code] ?? Accumulator(name: item.name ?? "Fuel station", address: item.address ?? "NSW", latitude: lat, longitude: lon)
            current.prices[fuel] = price
            current.updatedAt = max(current.updatedAt, date)
            grouped[code] = current
        }
        return grouped.map { key, value in
            FuelStation(id: "nsw-\(key)", name: value.name, address: value.address,
                        coordinate: FuelCoordinate(latitude: value.latitude, longitude: value.longitude),
                        prices: value.prices, amenities: [], distanceKm: 0, updatedAt: value.updatedAt)
        }
    }

    private struct Fixture {
        let state: AustralianState
        let station: FuelStation
    }

    private static func make(_ id: String, _ name: String, _ address: String, _ lat: Double, _ lon: Double, _ price: Double) -> FuelStation {
        FuelStation(id: id, name: name, address: address, coordinate: FuelCoordinate(latitude: lat, longitude: lon), prices: [.unleaded91: price, .premium95: price + 14, .premium98: price + 23, .diesel: price + 5, .e10: price - 3], amenities: ["Air", "Convenience store"], distanceKm: 0, updatedAt: Date())
    }

    private static let fixtures: [Fixture] = [
        .init(state: .qld, station: make("qld-southport", "7-Eleven Southport", "138 Slatyer Ave, Southport QLD 4215", -27.9964, 153.3997, 184.9)),
        .init(state: .qld, station: make("qld-helensvale", "BP Helensvale", "Discovery Dr, Helensvale QLD 4212", -27.9185, 153.3368, 182.9)),
        .init(state: .qld, station: make("qld-liberty-helensvale", "Liberty Helensvale", "21 Millennium Circuit, Helensvale QLD 4212", -27.915, 153.332, 176.9)),
        .init(state: .qld, station: make("qld-hope-island", "Ampol Hope Island", "Hope Island Rd, Hope Island QLD 4212", -27.8704, 153.3670, 186.9)),
        .init(state: .qld, station: make("qld-oxenford", "Shell Oxenford", "Old Pacific Hwy, Oxenford QLD 4210", -27.8900, 153.3140, 180.9)),
        .init(state: .qld, station: make("qld-coomera", "7-Eleven Coomera", "Days Rd, Coomera QLD 4209", -27.8557, 153.3158, 183.9)),
        .init(state: .qld, station: make("qld-robina", "EG Ampol Robina", "Robina Town Centre Dr, Robina QLD 4230", -28.0757, 153.3828, 179.9)),
        .init(state: .qld, station: make("qld-surfers", "Ampol Surfers Paradise", "100 Ferny Ave, Surfers Paradise QLD 4217", -27.9956, 153.4274, 189.9)),
        .init(state: .qld, station: make("qld-pacific-pines", "Shell Pacific Pines", "31 Pitcairn Way, Pacific Pines QLD 4211", -27.9462, 153.3206, 186.9)),
        .init(state: .nsw, station: make("nsw-tweed", "Ampol Tweed Heads", "Wharf St, Tweed Heads NSW 2485", -28.1780, 153.5420, 187.9)),
        .init(state: .nsw, station: make("nsw-kingscliff", "Caltex Kingscliff", "Tweed Coast Rd, Kingscliff NSW 2487", -28.2550, 153.5780, 185.9)),
        .init(state: .nsw, station: make("nsw-murwillumbah", "Shell Murwillumbah", "Main St, Murwillumbah NSW 2484", -28.3270, 153.3940, 183.9)),
        .init(state: .nsw, station: make("nsw-byron", "BP Byron Bay", "Ewingsdale Rd, Byron Bay NSW 2481", -28.6470, 153.6120, 191.9))
    ]
}
