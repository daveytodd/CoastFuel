import Foundation
import Combine
import CoreLocation

@MainActor
final class FuelDataService: ObservableObject {
    @Published private(set) var stations: [FuelStation] = []
    @Published var selectedState: AustralianState = .qld
    @Published private(set) var userLocation: CLLocation?

    private let defaults: [AustralianState: CLLocation] = [
        .qld: CLLocation(latitude: -27.967, longitude: 153.400), .nsw: CLLocation(latitude: -33.8688, longitude: 151.2093),
        .vic: CLLocation(latitude: -37.8136, longitude: 144.9631), .wa: CLLocation(latitude: -31.9505, longitude: 115.8605),
        .sa: CLLocation(latitude: -34.9285, longitude: 138.6007), .tas: CLLocation(latitude: -42.8821, longitude: 147.3272),
        .act: CLLocation(latitude: -35.2809, longitude: 149.1300), .nt: CLLocation(latitude: -12.4634, longitude: 130.8456)
    ]

    func setUserLocation(_ location: CLLocation?) {
        userLocation = location
        refreshStations()
    }

    func load() async { refreshStations() }

    func refreshStations() {
        let origin = userLocation ?? defaults[selectedState] ?? defaults[.qld]!
        stations = Self.fixtures.filter { $0.state == selectedState }.map { item in
            var station = item.station
            station.distanceKm = origin.distance(from: CLLocation(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)) / 1000
            return station
        }.sorted { $0.distanceKm < $1.distanceKm }
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
        .init(state: .qld, station: make("qld-hope-island", "Ampol Hope Island", "Hope Island Rd, Hope Island QLD 4212", -27.8704, 153.agext, 186.9)),
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
