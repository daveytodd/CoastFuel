import Combine
import Foundation

struct VehicleProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var fuelType: FuelType
    var tankCapacityLitres: Double
    var averageConsumptionLitresPer100Km: Double
    var obdAdapterUUID: String?
    static let defaultProfile = VehicleProfile(name: "My Car", fuelType: .unleaded91, tankCapacityLitres: 51, averageConsumptionLitresPer100Km: 7, obdAdapterUUID: nil)
}

@MainActor
final class VehicleProfileStore: ObservableObject {
    @Published private(set) var profiles: [VehicleProfile] = []
    @Published private(set) var activeProfileID: UUID
    private let profilesKey = "CoastFuel.vehicleProfiles"
    private let activeKey = "CoastFuel.activeVehicleProfileID"
    var activeProfile: VehicleProfile { profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0] }

    init(defaults: UserDefaults = .standard) {
        let decoded = defaults.data(forKey: profilesKey).flatMap { try? JSONDecoder().decode([VehicleProfile].self, from: $0) }
        profiles = (decoded?.isEmpty == false) ? decoded! : [.defaultProfile]
        if let text = defaults.string(forKey: activeKey), let id = UUID(uuidString: text), profiles.contains(where: { $0.id == id }) { activeProfileID = id }
        else { activeProfileID = profiles[0].id }
        persist(defaults)
    }
    func select(_ id: UUID) { guard profiles.contains(where: { $0.id == id }) else { return }; activeProfileID = id; persist() }
    func add(_ profile: VehicleProfile) { profiles.append(profile); activeProfileID = profile.id; persist() }
    func update(_ profile: VehicleProfile) { guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }; profiles[i] = profile; persist() }
    func delete(_ id: UUID) { guard profiles.count > 1 else { return }; profiles.removeAll { $0.id == id }; if activeProfileID == id { activeProfileID = profiles[0].id }; persist() }
    private func persist(_ defaults: UserDefaults = .standard) { if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: profilesKey) }; defaults.set(activeProfileID.uuidString, forKey: activeKey) }
}
