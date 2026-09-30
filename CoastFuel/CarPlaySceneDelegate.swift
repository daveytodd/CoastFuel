import CarPlay
import MapKit
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let service = CarPlayFuelStore()

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        service.load { [weak self] stations in self?.showList(stations, on: interfaceController) }
    }
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) { self.interfaceController = nil }

    private func showList(_ stations: [FuelStation], on controller: CPInterfaceController) {
        let selected = UserDefaults.standard.string(forKey: "stationRadius") ?? "tenKm"
        let limit: Double? = switch selected { case "fiveKm": 5; case "tenKm": 10; case "twentyFiveKm": 25; case "fiftyKm": 50; default: nil }
        let nearby = stations.filter { limit.map { $0 >= $0 } ?? true }
        let items = nearby.sorted { ($0.prices[.unleaded91] ?? .infinity) < ($1.prices[.unleaded91] ?? .infinity) }.map { station -> CPListItem in
            let distance = String(format: "%.1f", station.distanceKm)
            let price = station.prices[.unleaded91].map { String(format: "%.1f¢/L", $0) } ?? "—"
            let item = CPListItem(text: station.name, detailText: "91: \(price) · \(distance) km")
            item.handler = { [weak self] _, completion in self?.showStation(station); completion() }
            return item
        }
        let title = limit.map { "Nearby Fuel · \(Int($0)) km" } ?? "Nearby Fuel · All"
        controller.setRootTemplate(CPListTemplate(title: title, sections: [CPListSection(items: items)]), animated: true, completion: nil)
    }
    private func showStation(_ station: FuelStation) {
        guard let controller = interfaceController else { return }
        let prices = station.prices.map { CPListItem(text: $0.key.rawValue, detailText: String(format: "%.1f¢ per litre", $0.value)) }
        let amenities = station.amenities.map { CPListItem(text: $0, detailText: "Amenity") }
        controller.pushTemplate(CPListTemplate(title: station.name, sections: [CPListSection(items: prices + amenities)]), animated: true)
    }
}

private final class CarPlayFuelStore {
    func load(completion: @escaping ([FuelStation]) -> Void) { completion(FuelDataService.mockStations) }
}
