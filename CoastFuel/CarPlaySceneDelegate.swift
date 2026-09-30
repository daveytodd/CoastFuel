import CarPlay
import MapKit
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let service = CarPlayFuelStore()

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        service.load { [weak self] stations in
            let radius = UserDefaults.standard.integer(forKey: "stationRadiusKm")
            let filtered = stations.filter { radius == 0 || $0.distanceKm <= Double(radius) }
            self?.showList(filtered, on: interfaceController, radius: radius)
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }

    private func showList(_ stations: [FuelStation], on controller: CPInterfaceController, radius: Int) {
        let items = stations.sorted {
            ($0.prices[.unleaded91] ?? .infinity) < ($1.prices[.unleaded91] ?? .infinity)
        }.map { station -> CPListItem in
            let distance = String(format: "%.1f", station.distanceKm)
            let price = station.prices[.unleaded91].map { String(format: "%.1f¢/L", $0) } ?? "—"
            let item = CPListItem(text: station.name, detailText: "91: \(price) · \(distance) km")
            item.handler = { [weak self] _, completion in
                self?.showStation(station)
                completion()
            }
            return item
        }
        let radiusText = radius == 0 ? "All" : "\(radius) km"
        let template = CPListTemplate(title: "Nearby Fuel (\(radiusText))", sections: [CPListSection(items: items)])
        controller.setRootTemplate(template, animated: true, completion: nil)
    }

    private func showStation(_ station: FuelStation) {
        guard let controller = interfaceController else { return }
        let prices = station.prices.map {
            CPListItem(text: $0.key.rawValue, detailText: String(format: "%.1f¢ per litre", $0.value))
        }
        let amenities = station.amenities.map { CPListItem(text: $0, detailText: "Amenity") }
        let section = CPListSection(items: prices + amenities)
        controller.pushTemplate(CPListTemplate(title: station.name, sections: [section]), animated: true)
    }
}

private final class CarPlayFuelStore {
    func load(completion: @escaping ([FuelStation]) -> Void) {
        completion(FuelDataService.mockStations)
    }
}
