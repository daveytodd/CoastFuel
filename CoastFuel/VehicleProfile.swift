import Foundation

struct VehicleProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var fuelType: FuelType
    var tankCapacityLitres: Double
    var averageConsumptionLitresPer100Km: Double
    var obdAdapterUUID: String?

    static let defaultProfile = VehicleProfile(
        name: "My Car", fuelType: .unleaded91,
        tankCapacityLitres: 51, averageConsumptionLitresPer100Km: 7,
        obdAdapterUUID: nil
    )
}

/// UserDefaults-backed persistent vehicle profiles and active selection.
@MainActor
final class VehicleProfileStore: ObservableObject {
    @Published private(set) var profiles: [VehicleProfile] = []
    @Published private(set) var activeProfileID: UUID
    private let profilesKey = "CoastFuel.vehicleProfiles"
    private let activeProfileKey = "CoastFuel.activeVehicleProfileID"

    var activeProfile: VehicleProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    init(defaults: UserDefaults = .standard) {
        let saved = defaults.data(forKey: profilesKey).flatMap { try? JSONDecoder().decode([VehicleProfile].self, from: $0) }
        let loaded = saved?.isEmpty == false ? saved! : [.defaultProfile]
        profiles = loaded
        if let idString = defaults.string(forKey: activeProfileKey), let id = UUID(uuidString: idString), loaded.contains(where: { $0.id == id }) {
            activeProfileID = id
        } else {
            activeProfileID = loaded[0].id
        }
        persist(defaults: defaults)
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
    }

    func add(_ profile: VehicleProfile) {
        profiles.append(profile); persist()
        select(profile.id)
    }

    func update(_ profile: VehicleProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile; persist()
    }

    func delete(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = profiles[0].id }
        persist()
    }

    private func persist(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: profilesKey) }
        defaults.set(activeProfileID.uuidString, forKey: activeProfileKey)
    }
}
