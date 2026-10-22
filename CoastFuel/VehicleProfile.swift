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
        let key = "CoastFuel.vehicleProfiles"
        let activeKey = "CoastFuel.activeVehicleProfileID"
        let decoded = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([VehicleProfile].self, from: $0) }
        let loadedProfiles = (decoded?.isEmpty == false) ? decoded! : [.defaultProfile]
        let savedID = defaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        let loadedActiveID = savedID.flatMap { id in loadedProfiles.contains(where: { $0.id == id }) ? id : nil } ?? loadedProfiles[0].id
        self.profiles = loadedProfiles
        self.activeProfileID = loadedActiveID
        if let data = try? JSONEncoder().encode(loadedProfiles) { defaults.set(data, forKey: key) }
        defaults.set(loadedActiveID.uuidString, forKey: activeKey)
    }
    func select(_ id: UUID) { guard profiles.contains(where: { $0.id == id }) else { return }; activeProfileID = id; persist() }
    func add(_ profile: VehicleProfile) { profiles.append(profile); activeProfileID = profile.id; persist() }
    func update(_ profile: VehicleProfile) { guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }; profiles[i] = profile; persist() }
    func delete(_ id: UUID) { guard profiles.count > 1 else { return }; profiles.removeAll { $0.id == id }; if activeProfileID == id { activeProfileID = profiles[0].id }; persist() }
    private func persist(_ defaults: UserDefaults = .standard) { if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: profilesKey) }; defaults.set(activeProfileID.uuidString, forKey: activeKey) }
}
