import Combine
import Foundation

struct VehicleProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var fuelType: FuelType
    var tankCapacityLitres: Double
    var averageConsumptionLitresPer100Km: Double
    var obdAdapterUUID: String?
    var licensePlate: String? = nil
    var preferredFuelType: String = FuelType.unleaded91.rawValue

    static let defaultProfile = VehicleProfile(
        name: "My Car",
        fuelType: .unleaded91,
        tankCapacityLitres: 51,
        averageConsumptionLitresPer100Km: 7,
        obdAdapterUUID: nil,
        licensePlate: nil,
        preferredFuelType: FuelType.unleaded91.rawValue
    )

    private enum CodingKeys: String, CodingKey {
        case id, name, fuelType, tankCapacityLitres, averageConsumptionLitresPer100Km, obdAdapterUUID, licensePlate, preferredFuelType
    }

    init(id: UUID = UUID(), name: String, fuelType: FuelType, tankCapacityLitres: Double, averageConsumptionLitresPer100Km: Double, obdAdapterUUID: String?, licensePlate: String? = nil, preferredFuelType: String = FuelType.unleaded91.rawValue) {
        self.id = id
        self.name = name
        self.fuelType = fuelType
        self.tankCapacityLitres = tankCapacityLitres
        self.averageConsumptionLitresPer100Km = averageConsumptionLitresPer100Km
        self.obdAdapterUUID = obdAdapterUUID
        self.licensePlate = licensePlate
        self.preferredFuelType = preferredFuelType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        fuelType = try container.decode(FuelType.self, forKey: .fuelType)
        tankCapacityLitres = try container.decode(Double.self, forKey: .tankCapacityLitres)
        averageConsumptionLitresPer100Km = try container.decode(Double.self, forKey: .averageConsumptionLitresPer100Km)
        obdAdapterUUID = try container.decodeIfPresent(String.self, forKey: .obdAdapterUUID)
        licensePlate = try container.decodeIfPresent(String.self, forKey: .licensePlate)
        preferredFuelType = try container.decodeIfPresent(String.self, forKey: .preferredFuelType) ?? FuelType.unleaded91.rawValue
    }
}

@MainActor
final class VehicleProfileStore: ObservableObject {
    @Published private(set) var profiles: [VehicleProfile] = []
    @Published private(set) var activeProfileID: UUID
    private let profilesKey = "CoastFuel.vehicleProfiles"
    private let activeKey = "CoastFuel.activeVehicleProfileID"

    var activeProfile: VehicleProfile {
        profiles.first(where: { $0.id == activeProfileID }) ?? profiles[0]
    }

    init(defaults: UserDefaults = .standard) {
        let key = "CoastFuel.vehicleProfiles"
        let activeKey = "CoastFuel.activeVehicleProfileID"
        let decoded = defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([VehicleProfile].self, from: $0)
        }
        let loadedProfiles = (decoded?.isEmpty == false) ? decoded! : [.defaultProfile]
        let savedID = defaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
        let loadedActiveID = savedID.flatMap { id in
            loadedProfiles.contains(where: { $0.id == id }) ? id : nil
        } ?? loadedProfiles[0].id

        self.profiles = loadedProfiles
        self.activeProfileID = loadedActiveID

        if let data = try? JSONEncoder().encode(loadedProfiles) {
            defaults.set(data, forKey: key)
        }
        defaults.set(loadedActiveID.uuidString, forKey: activeKey)
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        persist()
    }

    func add(_ profile: VehicleProfile) {
        profiles.append(profile)
        activeProfileID = profile.id
        persist()
    }

    func update(_ profile: VehicleProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    func delete(_ id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if activeProfileID == id { activeProfileID = profiles[0].id }
        persist()
    }

    private func persist(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
        defaults.set(activeProfileID.uuidString, forKey: activeKey)
    }
}
