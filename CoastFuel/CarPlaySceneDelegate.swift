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
        let items = stations.sorted { ($0.prices[.unleaded91] ?? .infinity) < ($1.prices[.unleaded91] ?? .infinity) }.map { station -> CPListItem in
            let distance = String(format: "%.1f", station.distanceKm)
            let item = CPListItem(text: station.name, detailText: "91: \(station.prices[.unleaded91].map { String(format:"%.1f¢/L",$0) } ?? "—") · \(distance) km")
            item.handler = { [weak self] _, completion in self?.showStation(station); completion() }
            return item
        }
        controller.setRootTemplate(CPListTemplate(title: "Nearby Fuel", sections: [CPListSection(items: items)]), animated: true)
        if #available(iOS 14.0, *) {
            let pois = stations.map { station -> CPPointOfInterest in
                let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate.location))
                mapItem.name = station.name
                let poi = CPPointOfInterest(location: mapItem, title: station.name, subtitle: station.address, summary: station.priceText, detailTitle: station.name, detailSubtitle: station.address, detailSummary: station.prices.map { "\($0.key.rawValue): \(String(format:"%.1f¢/L",$0.value))" }.sorted().joined(separator:" · "), pinImage: UIImage(systemName:"fuelpump.fill"))
                poi.subtitle = station.priceText
                poi.primaryButton = CPButton(title: "Navigate", image: UIImage(systemName:"arrow.turn.up.right")) { _ in mapItem.openInMaps(launchOptions:[MKLaunchOptionsDirectionsModeKey:MKLaunchOptionsDirectionsModeDriving]) }
                return poi
            }
            let poiTemplate = CPPointOfInterestTemplate(title: "Fuel Map", pointsOfInterest: pois, selectedIndex: 0)
            _ = poiTemplate
        }
    }
    private func showStation(_ station: FuelStation) {
        guard let controller = interfaceController else { return }
        let prices = station.prices.map { CPListItem(text:$0.key.rawValue, detailText:String(format:"%.1f¢ per litre",$0.value)) }
        let section = CPListSection(items: prices + station.amenities.map { CPListItem(text:$0, detailText:"Amenity") })
        controller.pushTemplate(CPListTemplate(title: station.name, sections:[section]), animated:true)
    }
}

private final class CarPlayFuelStore {
    func load(completion: @escaping ([FuelStation]) -> Void) { completion(FuelDataService.mockStations) }
}
