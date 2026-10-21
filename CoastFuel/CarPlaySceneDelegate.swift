import CarPlay
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let service = CarPlayFuelStore()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        service.load { [weak self] stations in
            self?.showList(stations, on: interfaceController)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func showList(_ stations: [FuelStation], on controller: CPInterfaceController) {
        let selected = UserDefaults.standard.string(forKey: "stationRadius") ?? "tenKm"
        let limit: Double? = switch selected {
        case "fiveKm": 5
        case "tenKm": 10
        case "twentyFiveKm": 25
        case "fiftyKm": 50
        default: nil
        }

        let nearby = stations.filter { station in
            guard let limit else { return true }
            return station.distanceKm <= limit
        }
        let sortedStations = nearby.sorted { lhs, rhs in
            (lhs.prices[.unleaded91] ?? .infinity) < (rhs.prices[.unleaded91] ?? .infinity)
        }
        let items = sortedStations.map { station -> CPListItem in
            let distance = String(format: "%.1f", station.distanceKm)
            let price = station.prices[.unleaded91].map { price in
                String(format: "%.1f¢/L", price)
            } ?? "—"
            let item = CPListItem(text: station.name, detailText: "91: \(price) · \(distance) km")
            item.handler = { [weak self] _, completion in
                self?.showStation(station)
                completion()
            }
            return item
        }

        let title = limit.map { distance in "Nearby Fuel · \(Int(distance)) km" } ?? "Nearby Fuel · All"
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: title, sections: [section])
        controller.setRootTemplate(template, animated: true, completion: nil)
    }

    private func showStation(_ station: FuelStation) {
        guard let controller = interfaceController else { return }
        let prices = station.prices.map { entry in
            CPListItem(text: entry.key.rawValue, detailText: String(format: "%.1f¢ per litre", entry.value))
        }
        let amenities = station.amenities.map { amenity in
            CPListItem(text: amenity, detailText: "Amenity")
        }
        let section = CPListSection(items: prices + amenities)
        let template = CPListTemplate(title: station.name, sections: [section])
        controller.pushTemplate(template, animated: true)
    }
}

private final class CarPlayFuelStore {
    @MainActor
    func load(completion: @escaping ([FuelStation]) -> Void) {
        let service = FuelDataService()
        service.refreshStations()
        completion(service.stations)
    }
}
