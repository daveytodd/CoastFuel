import Foundation
import CoreLocation

enum FuelType: String, CaseIterable, Identifiable, Codable {
    case unleaded91 = "Unleaded 91", premium95 = "Premium 95", premium98 = "Premium 98", diesel = "Diesel", e10 = "E10"
    var id: String { rawValue }
}

struct FuelCoordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct FuelStation: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var address: String
    var coordinate: FuelCoordinate
    var prices: [FuelType: Double]
    var amenities: [String]
    var distanceKm: Double
    var updatedAt: Date
    var priceText: String { prices[.unleaded91].map { String(format: "%.1f¢/L", $0) } ?? "Price unavailable" }
}
